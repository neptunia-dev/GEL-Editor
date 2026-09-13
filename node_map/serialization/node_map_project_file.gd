extends RefCounted
class_name NodeMapProjectFile

## 编辑器工程文件的磁盘边界。
##
## ProjectFileCodec 负责纯容器编解码，本类只负责物理路径、原子写入和把
## 已解码快照恢复到一个临时 NodeMapDocument。加载失败不会触碰调用方当前文档。

const CODEC := preload("res://node_map/serialization/project_file_codec.gd")
const DOCUMENT := preload("res://node_map/model/node_map_document.gd")

const DEFAULT_EXTENSION := ".gelproj"
const MAX_PROJECT_FILE_BYTES := 32 * 1024 * 1024

static func save(document: Variant, metadata: Dictionary, path: Variant, editor_state: Dictionary = {}) -> Dictionary:
	var encoded: Dictionary = CODEC.encode_json(document, metadata, editor_state)
	if not bool(encoded.get("ok", false)):
		return _failure(encoded.get("diagnostics", []), path)
	if str(encoded.text).to_utf8_buffer().size() > MAX_PROJECT_FILE_BYTES:
		return _failure([_error("project_file_too_large", "Project file exceeds the maximum supported size.")], path)
	var diagnostics: Array = []
	var absolute := _absolute_file_path(path, diagnostics)
	if absolute.is_empty():
		return _failure(diagnostics, path)
	if not _is_safe_project_path(absolute):
		return _failure([_error("unsafe_project_path", "Project file destination must not pass through a symbolic link or junction.")], path)
	var parent := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent) != OK:
		return _failure([_error("project_write_failed", "Could not create the project file directory.")], path)
	# Recheck after directory creation because a host process can change an
	# ancestor while the save operation is in progress.
	if not _is_safe_project_path(absolute):
		return _failure([_error("unsafe_project_path", "Project file destination became a symbolic link or junction during save.")], path)
	if DirAccess.dir_exists_absolute(absolute):
		return _failure([_error("project_write_failed", "Project file destination is a directory.")], path)

	var temporary := absolute + ".gel-tmp-" + str(Time.get_ticks_usec())
	if _path_occupied(temporary):
		return _failure([_error("project_write_failed", "Temporary project file path is already occupied.")], path)
	if not _write_text(temporary, str(encoded.text)):
		_remove_file(temporary)
		return _failure([_error("project_write_failed", "Could not write the temporary project file.")], path)

	var backup := absolute + ".gel-backup-" + str(Time.get_ticks_usec())
	if _path_occupied(backup):
		_remove_file(temporary)
		return _failure([_error("project_publish_failed", "Backup project file path is already occupied.")], path)
	# Avoid publishing over a link introduced after the staging file was written.
	if not _is_safe_project_path(absolute):
		_remove_file(temporary)
		return _failure([_error("unsafe_project_path", "Project file destination became unsafe during save.")], path)
	var had_file := FileAccess.file_exists(absolute)
	if had_file:
		if DirAccess.rename_absolute(absolute, backup) != OK:
			_remove_file(temporary)
			return _failure([_error("project_publish_failed", "Could not prepare the existing project file for replacement.")], path)
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		if had_file:
			var recovery_error := DirAccess.rename_absolute(backup, absolute)
			if recovery_error != OK:
				# Keep both files. The original is normally still at backup and the
				# newly written content is still at temporary for manual recovery.
				return _failure([_error("project_recovery_failed", "Could not publish the project file or restore the previous file. Recovery copies were retained.")], path, backup, temporary)
		_remove_file(temporary)
		return _failure([_error("project_publish_failed", "Could not publish the project file.")], path)

	var publish_diagnostics: Array = []
	if had_file and DirAccess.remove_absolute(backup) != OK:
		publish_diagnostics.append(_warning("project_backup_retained", "Project was saved, but the previous backup could not be removed."))
	return {"ok": true, "diagnostics": publish_diagnostics, "path": absolute, "metadata": encoded.get("metadata", {}).duplicate(true)}

static func load(registry: Variant, path: Variant) -> Dictionary:
	var diagnostics: Array = []
	var absolute := _absolute_file_path(path, diagnostics)
	if absolute.is_empty():
		return _load_failure(diagnostics, path)
	if not _is_safe_project_path(absolute):
		return _load_failure([_error("unsafe_project_path", "Project file must not pass through a symbolic link or junction.")], path)
	if DirAccess.dir_exists_absolute(absolute):
		return _load_failure([_error("project_read_failed", "Project file path names a directory.")], path)
	if not FileAccess.file_exists(absolute):
		return _load_failure([_error("project_not_found", "Project file does not exist.")], path)
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return _load_failure([_error("project_read_failed", "Could not open the project file.")], path)
	if file.get_length() > MAX_PROJECT_FILE_BYTES:
		file.close()
		return _load_failure([_error("project_file_too_large", "Project file exceeds the maximum supported size.")], path)
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _load_failure([_error("project_read_failed", "Could not read the project file.")], path)
	var decoded: Dictionary = CODEC.decode_json(text)
	if not bool(decoded.get("ok", false)):
		return _load_failure(decoded.get("diagnostics", []), path)
	if registry == null:
		return _load_failure([_error("invalid_registry", "Loading a project requires a node registry.")], path)

	# Restore into a detached candidate. The caller can attach this document only
	# after every container and model validation step has succeeded.
	var candidate = DOCUMENT.new(registry, false)
	var restored: Dictionary = candidate.restore_snapshot(decoded.snapshot)
	if not bool(restored.get("ok", false)):
		return _load_failure(restored.get("diagnostics", []), path)
	return {
		"ok": true,
		"diagnostics": [],
		"path": absolute,
		"document": candidate,
		"metadata": decoded.get("metadata", {}).duplicate(true),
		"editor_state": decoded.get("editor_state", {}).duplicate(true),
	}

static func _absolute_file_path(path: Variant, diagnostics: Array) -> String:
	if not path is String or path.is_empty():
		diagnostics.append(_error("invalid_project_path", "Project file path must be non-empty."))
		return ""
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if absolute.is_empty() or absolute.get_file().is_empty():
		diagnostics.append(_error("invalid_project_path", "Project file path must name a file."))
		return ""
	return absolute

static func _is_link(parent: String, name: String) -> bool:
	var directory := DirAccess.open(parent)
	return directory != null and directory.is_link(name)

static func _path_occupied(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) or _is_link(path.get_base_dir(), path.get_file())

static func _is_safe_project_path(path: String) -> bool:
	var parent := path.get_base_dir()
	return not parent.is_empty() and _is_safe_parent_path(parent) and not _is_link(parent, path.get_file())

static func _is_safe_parent_path(path: String) -> bool:
	# Walk every component, including the destination parent itself. A link in
	# any existing ancestor can redirect the later rename outside this path.
	var current := path.simplify_path()
	while not current.is_empty():
		var parent := current.get_base_dir()
		var name := current.get_file()
		if not name.is_empty() and _is_link(parent, name):
			return false
		if parent.is_empty() or current == parent:
			break
		current = parent
	return true

static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var failed := file.get_error() != OK
	file.close()
	return not failed

static func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path) or _is_link(path.get_base_dir(), path.get_file()):
		DirAccess.remove_absolute(path)

static func _error(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"severity": "error",
		"graph_id": "",
		"node_id": "",
		"port_id": "",
		"link_id": "",
	}

static func _warning(code: String, message: String) -> Dictionary:
	var diagnostic := _error(code, message)
	diagnostic.severity = "warning"
	return diagnostic

static func _failure(diagnostics: Array, path: Variant, recovery_path: String = "", temporary_path: String = "") -> Dictionary:
	return {"ok": false, "diagnostics": diagnostics, "path": path, "metadata": {}, "recovery_path": recovery_path, "temporary_path": temporary_path}

static func _load_failure(diagnostics: Array, path: Variant) -> Dictionary:
	return {"ok": false, "diagnostics": diagnostics, "path": path, "document": null, "metadata": {}, "editor_state": {}}
