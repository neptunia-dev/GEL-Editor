extends RefCounted
class_name RuntimePackageWriter

## Runtime Package 的磁盘发布边界。
##
## 编译器只返回纯 DTO 和 Lua 文本；本类将它们先写进目标目录旁的 staging
## 目录，再替换发布目录。这样写失败不会把旧 manifest 与新脚本混在一起。
## 第一版允许 caller 指定目录，但会拒绝 project 资源树和符号链接路径；默认
## UI 仅使用 user://runtime-package。正式发布宿主应额外提供已授权的发布根。

func write(compiled: Dictionary, destination: String) -> Dictionary:
	var diagnostics: Array = _validate_compiled(compiled)
	if destination.strip_edges().is_empty():
		diagnostics.append(_error("invalid_destination", "Runtime Package destination must not be empty."))
	if not diagnostics.is_empty():
		return _failure(diagnostics)

	var absolute_destination := ProjectSettings.globalize_path(destination).simplify_path()
	if not _is_safe_destination(absolute_destination, diagnostics):
		return _failure(diagnostics)
	var staging := absolute_destination + ".gel-staging-" + str(Time.get_ticks_usec())
	if DirAccess.dir_exists_absolute(staging):
		_remove_tree(staging)
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		diagnostics.append(_error("write_failed", "Could not create Runtime Package staging directory."))
		return _failure(diagnostics)

	if not _write_compiled_to_directory(compiled, staging, diagnostics):
		_remove_tree(staging)
		return _failure(diagnostics)
	if not _publish_staging(staging, absolute_destination, diagnostics):
		_remove_tree(staging)
		return _failure(diagnostics)

	return {
		"ok": true,
		"diagnostics": [],
		"directory": absolute_destination,
		"manifest_path": absolute_destination.path_join("manifest.json"),
	}

func _write_compiled_to_directory(compiled: Dictionary, directory: String, diagnostics: Array) -> bool:
	var scripts: Dictionary = compiled.scripts
	for logical_path in _sorted_keys(scripts):
		var script_path := directory.path_join(logical_path)
		if DirAccess.make_dir_recursive_absolute(script_path.get_base_dir()) != OK:
			diagnostics.append(_error("write_failed", "Could not create script directory for '" + logical_path + "'."))
			return false
		if not _write_text(script_path, str(scripts[logical_path])):
			diagnostics.append(_error("write_failed", "Could not write script '" + logical_path + "'."))
			return false
	var manifest_text := JSON.stringify(compiled.manifest, "  ") + "\n"
	if not _write_text(directory.path_join("manifest.json"), manifest_text):
		diagnostics.append(_error("write_failed", "Could not write manifest.json."))
		return false
	return true

func _publish_staging(staging: String, destination: String, diagnostics: Array) -> bool:
	var backup := destination + ".gel-backup-" + str(Time.get_ticks_usec())
	var had_destination := DirAccess.dir_exists_absolute(destination)
	if had_destination and not _is_safe_directory(destination):
		diagnostics.append(_error("unsafe_destination", "Runtime Package destination must not be a symbolic link."))
		return false
	if had_destination:
		if DirAccess.rename_absolute(destination, backup) != OK:
			diagnostics.append(_error("publish_failed", "Could not prepare the existing Runtime Package for replacement."))
			return false
	if DirAccess.rename_absolute(staging, destination) != OK:
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		diagnostics.append(_error("publish_failed", "Could not publish the completed Runtime Package."))
		return false
	if had_destination:
		_remove_tree(backup)
	return true

func _is_safe_destination(destination: String, diagnostics: Array) -> bool:
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	if _is_within(destination, project_root):
		diagnostics.append(_error("unsafe_destination", "Runtime Package destination must not be inside the editor project resource tree."))
		return false
	if DirAccess.dir_exists_absolute(destination) and not _is_safe_directory(destination):
		diagnostics.append(_error("unsafe_destination", "Runtime Package destination must not be a symbolic link."))
		return false
	return true

func _is_safe_directory(path: String) -> bool:
	var parent := path.get_base_dir()
	var name := path.get_file()
	var parent_access := DirAccess.open(parent)
	return parent_access == null or not parent_access.is_link(name)

func _is_within(path: String, root: String) -> bool:
	return path == root or path.begins_with(root.path_join(""))

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := path.path_join(name)
		if directory.current_is_dir() and not directory.is_link(name):
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)

func _validate_compiled(compiled: Variant) -> Array:
	var diagnostics: Array = []
	if not compiled is Dictionary or not bool(compiled.get("ok", false)):
		diagnostics.append(_error("invalid_compiled_package", "Writer requires a successful NodeMapCompiler result."))
		return diagnostics
	var manifest: Variant = compiled.get("manifest", null)
	var scripts: Variant = compiled.get("scripts", null)
	if not manifest is Dictionary or not scripts is Dictionary:
		diagnostics.append(_error("invalid_compiled_package", "Compiled package must contain a manifest dictionary and scripts dictionary."))
		return diagnostics
	for path in scripts:
		if not path is String or not _is_script_path(path) or not scripts[path] is String:
			diagnostics.append(_error("invalid_compiled_package", "Compiled scripts must use safe scenes/<scene-id>/main.lua paths and string content."))
	if not manifest.has_all(["formatVersion", "packageId", "packageVersion", "saveSchemaVersion", "entryScene", "assets", "characters", "variables", "scenes", "routes"]):
		diagnostics.append(_error("invalid_compiled_package", "Compiled manifest is missing a required Runtime Package field."))
	return diagnostics

func _is_script_path(path: String) -> bool:
	if path.begins_with("/") or path.begins_with("\\") or path.contains("\\") or path.contains("..") or not path.begins_with("scenes/") or not path.ends_with("/main.lua"):
		return false
	var parts := path.split("/", false)
	return parts.size() == 3 and not parts[1].is_empty()

func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	var failed := file.get_error() != OK
	file.close()
	return not failed

func _sorted_keys(values: Dictionary) -> Array:
	var keys: Array = values.keys()
	keys.sort()
	return keys

func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "severity": "error", "graph_id": "", "node_id": "", "port_id": "", "link_id": ""}

func _failure(diagnostics: Array) -> Dictionary:
	return {"ok": false, "diagnostics": diagnostics, "directory": "", "manifest_path": ""}
