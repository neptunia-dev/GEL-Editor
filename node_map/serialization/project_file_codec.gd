extends RefCounted
class_name NodeMapProjectCodec

## 纯工程文件编解码边界。
##
## 工程文件是编辑器创作数据的外层容器，不是 Runtime Package。Node Map
## 快照仍由 NodeMapDocument 自己负责恢复和深度结构校验；本类只负责工程
## 容器、项目元数据和版本迁移边界，因此不访问磁盘，也不持有注册表。

const Values := preload("res://node_map/model/value_rules.gd")

const FORMAT := "gel.editor-project"
const FORMAT_VERSION := 1
const NODE_MAP_FORMAT := "gel.node-map"
const NODE_MAP_FORMAT_VERSION := 1
const DEFAULT_PROJECT_ID := "untitled"
const DEFAULT_PACKAGE_ID := "untitled.story"
const DEFAULT_PACKAGE_VERSION := "0.1.0"
const DEFAULT_SAVE_SCHEMA_VERSION := 1
const DEFAULT_TITLE := "Untitled Story"
const DEFAULT_ENGINE_MIN_VERSION := "0.1.0"

const _PROJECT_ID_PATTERN := "^[A-Za-z_][A-Za-z0-9_.-]*$"
const _RUNTIME_ID_PATTERN := "^[a-z][a-z0-9_.-]*$"
const _SEMVER_PATTERN := "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$"
const _METADATA_SOURCE_FIELDS := [
	"format", "formatVersion", "nodeMap", "editorState",
	"project_id", "projectId", "metadata", "title", "author", "language",
	"package", "package_id", "packageId", "package_version", "packageVersion",
	"save_schema_version", "saveSchemaVersion", "engine_min_version", "engineMinVersion",
	"entry_scene", "entryScene",
]

## 返回内部使用的 snake_case 元数据副本。
##
## 同时接受工程文件使用的 camelCase 形态和编译器历史公开的 snake_case
## 形态，方便宿主逐步迁移而不需要复制一份配置模型。
static func default_metadata() -> Dictionary:
	return {
		"project_id": DEFAULT_PROJECT_ID,
		"metadata": {
			"title": DEFAULT_TITLE,
			"author": "",
			"language": "",
		},
		"package": {
			"package_id": DEFAULT_PACKAGE_ID,
			"package_version": DEFAULT_PACKAGE_VERSION,
			"save_schema_version": DEFAULT_SAVE_SCHEMA_VERSION,
			"engine_min_version": DEFAULT_ENGINE_MIN_VERSION,
		},
		"entry_scene": "",
	}

static func normalize_metadata(source: Variant) -> Dictionary:
	var diagnostics: Array = []
	if not source is Dictionary:
		return {"ok": false, "diagnostics": [_error("invalid_project_metadata", "Project metadata must be a dictionary.")]}
	if not Values.is_json_value(source):
		return {"ok": false, "diagnostics": [_error("invalid_project_metadata", "Project metadata must contain JSON values only.")]}

	var normalized := default_metadata()
	var source_dict: Dictionary = source
	for key in source_dict:
		if key not in _METADATA_SOURCE_FIELDS:
			diagnostics.append(_error("unknown_project_field", "Unknown project field '" + str(key) + "'."))
	_check_alias_conflict(source_dict, "project_id", "projectId", "projectId", diagnostics)

	var project_id: Variant = source_dict.get("project_id", source_dict.get("projectId", normalized.project_id))
	if not project_id is String or not _matches(project_id, _PROJECT_ID_PATTERN):
		diagnostics.append(_error("invalid_project_id", "project_id must match ^[A-Za-z_][A-Za-z0-9_.-]*$."))
	else:
		normalized.project_id = project_id

	var raw_metadata: Variant = source_dict.get("metadata", {})
	if not raw_metadata is Dictionary:
		diagnostics.append(_error("invalid_project_metadata", "metadata must be a dictionary."))
	else:
		var metadata: Dictionary = normalized.metadata
		for key in raw_metadata:
			if key not in ["title", "author", "language"]:
				diagnostics.append(_error("unknown_project_metadata", "Unknown metadata field '" + str(key) + "'."))
				continue
			if not raw_metadata[key] is String:
				diagnostics.append(_error("invalid_project_metadata", "metadata." + str(key) + " must be text."))
				continue
			metadata[key] = raw_metadata[key]
		# The first compiler API used a flat title option. Accepting these aliases
		# keeps unsaved sessions and old host integrations readable while the file
		# format itself always writes the nested metadata object.
		for key in ["title", "author", "language"]:
			if source_dict.has(key):
				if raw_metadata.has(key) and raw_metadata[key] != source_dict[key]:
					diagnostics.append(_error("conflicting_project_field", "metadata." + key + " conflicts with top-level " + key + "."))
				if not source_dict[key] is String:
					diagnostics.append(_error("invalid_project_metadata", key + " must be text."))
				else:
					metadata[key] = source_dict[key]
		if not metadata.title is String or metadata.title.is_empty() or metadata.title.strip_edges() != metadata.title:
			diagnostics.append(_error("invalid_project_metadata", "metadata.title must be non-empty text without surrounding whitespace."))
		if not metadata.author is String or metadata.author.strip_edges() != metadata.author:
			diagnostics.append(_error("invalid_project_metadata", "metadata.author must not have surrounding whitespace."))
		if not metadata.language is String or metadata.language.strip_edges() != metadata.language:
			diagnostics.append(_error("invalid_project_metadata", "metadata.language must not have surrounding whitespace."))

	var raw_package: Variant = source_dict.get("package", {})
	if not raw_package is Dictionary:
		diagnostics.append(_error("invalid_package_config", "package must be a dictionary."))
	else:
		_check_alias_conflict(raw_package, "package_id", "packageId", "package.packageId", diagnostics)
		_check_alias_conflict(raw_package, "package_version", "packageVersion", "package.packageVersion", diagnostics)
		_check_alias_conflict(raw_package, "save_schema_version", "saveSchemaVersion", "package.saveSchemaVersion", diagnostics)
		_check_alias_conflict(raw_package, "engine_min_version", "engineMinVersion", "package.engineMinVersion", diagnostics)
		_check_package_alias_conflict(source_dict, raw_package, "package_id", "packageId", diagnostics)
		_check_package_alias_conflict(source_dict, raw_package, "package_version", "packageVersion", diagnostics)
		_check_package_alias_conflict(source_dict, raw_package, "save_schema_version", "saveSchemaVersion", diagnostics)
		_check_package_alias_conflict(source_dict, raw_package, "engine_min_version", "engineMinVersion", diagnostics)
		var package: Dictionary = normalized.package
		var package_id: Variant = raw_package.get("package_id", raw_package.get("packageId", package.package_id))
		var package_version: Variant = raw_package.get("package_version", raw_package.get("packageVersion", package.package_version))
		var save_schema_version: Variant = raw_package.get("save_schema_version", raw_package.get("saveSchemaVersion", package.save_schema_version))
		var engine_min_version: Variant = raw_package.get("engine_min_version", raw_package.get("engineMinVersion", package.engine_min_version))
		for key in raw_package:
			if key not in ["package_id", "packageId", "package_version", "packageVersion", "save_schema_version", "saveSchemaVersion", "engine_min_version", "engineMinVersion"]:
				diagnostics.append(_error("unknown_package_config", "Unknown package field '" + str(key) + "'."))
		if not package_id is String or not _matches(package_id, _RUNTIME_ID_PATTERN):
			diagnostics.append(_error("invalid_package_config", "package.packageId must match ^[a-z][a-z0-9_.-]*$."))
		else:
			package.package_id = package_id
		if not package_version is String or not _matches(package_version, _SEMVER_PATTERN):
			diagnostics.append(_error("invalid_package_config", "package.packageVersion must be a semantic version."))
		else:
			package.package_version = package_version
		if not Values.is_integer(save_schema_version) or int(save_schema_version) < 0:
			diagnostics.append(_error("invalid_package_config", "package.saveSchemaVersion must be a non-negative integer."))
		else:
			package.save_schema_version = int(save_schema_version)
		if not engine_min_version is String or not _matches(engine_min_version, _SEMVER_PATTERN):
			diagnostics.append(_error("invalid_package_config", "package.engineMinVersion must be a semantic version."))
		else:
			package.engine_min_version = engine_min_version

	# 也接受编译器公开的扁平 snake_case 配置。若同时提供 package 对象，
	# 扁平字段作为显式覆盖，便于 set_project_metadata() 做局部修改。
	for pair in [
		["package_id", "package_id"],
		["package_version", "package_version"],
		["save_schema_version", "save_schema_version"],
		["engine_min_version", "engine_min_version"],
	]:
		if source_dict.has(pair[0]):
			normalized.package[pair[1]] = source_dict[pair[0]]
	# camelCase 顶层字段只在没有 package 对象对应值时有意义；它们在旧的
	# 临时配置中很常见，因此也统一作为覆盖处理。
	for pair in [
		["packageId", "package_id"],
		["packageVersion", "package_version"],
		["saveSchemaVersion", "save_schema_version"],
		["engineMinVersion", "engine_min_version"],
	]:
		if source_dict.has(pair[0]):
			normalized.package[pair[1]] = source_dict[pair[0]]
	# 重新校验扁平覆盖，避免局部更新绕过上面的约束。
	var final_package: Dictionary = normalized.package
	if not final_package.package_id is String or not _matches(final_package.package_id, _RUNTIME_ID_PATTERN):
		diagnostics.append(_error("invalid_package_config", "package_id must match ^[a-z][a-z0-9_.-]*$."))
	if not final_package.package_version is String or not _matches(final_package.package_version, _SEMVER_PATTERN):
		diagnostics.append(_error("invalid_package_config", "package_version must be a semantic version."))
	if not Values.is_integer(final_package.save_schema_version) or int(final_package.save_schema_version) < 0:
		diagnostics.append(_error("invalid_package_config", "save_schema_version must be a non-negative integer."))
	else:
		final_package.save_schema_version = int(final_package.save_schema_version)
	if not final_package.engine_min_version is String or not _matches(final_package.engine_min_version, _SEMVER_PATTERN):
		diagnostics.append(_error("invalid_package_config", "engine_min_version must be a semantic version."))

	_check_alias_conflict(source_dict, "entry_scene", "entryScene", "entryScene", diagnostics)
	var entry_scene: Variant = source_dict.get("entry_scene", source_dict.get("entryScene", normalized.entry_scene))
	if not entry_scene is String or (not entry_scene.is_empty() and not _matches(entry_scene, _RUNTIME_ID_PATTERN)):
		diagnostics.append(_error("invalid_entry_scene", "entryScene must be empty or match ^[a-z][a-z0-9_.-]*$."))
	else:
		normalized.entry_scene = entry_scene

	if not diagnostics.is_empty():
		return {"ok": false, "diagnostics": diagnostics}
	return {"ok": true, "diagnostics": [], "metadata": normalized}

## 将文档和元数据编码成工程容器。这里允许结构正确但尚未可导出的草稿；
## 可导出性仍由 NodeMapCompiler 负责。
static func encode(document: Variant, metadata: Dictionary = {}, editor_state: Dictionary = {}) -> Dictionary:
	var diagnostics: Array = []
	if document == null or not document.has_method("get_snapshot") or not document.has_method("validate_self"):
		return _failure([_error("invalid_document", "Project encoder requires a NodeMapDocument-compatible value.")])
	var structure_errors: Array = document.validate_self()
	if not structure_errors.is_empty():
		for item in structure_errors:
			diagnostics.append(item.duplicate(true) if item is Dictionary else _error("invalid_document", str(item)))
		return _failure(diagnostics)
	var normalized_result := normalize_metadata(metadata if not metadata.is_empty() else default_metadata())
	if not normalized_result.ok:
		return _failure(normalized_result.diagnostics)
	var snapshot: Variant = document.get_snapshot()
	if not snapshot is Dictionary or not Values.is_json_value(snapshot):
		return _failure([_error("invalid_snapshot", "Node Map snapshot must be a JSON object.")])
	var snapshot_diagnostics := _validate_snapshot_container(snapshot)
	if not snapshot_diagnostics.is_empty():
		return _failure(snapshot_diagnostics)
	if not editor_state.is_empty() and not Values.is_json_value(editor_state):
		return _failure([_error("invalid_editor_state", "Editor state must contain JSON values only.")])

	var normalized: Dictionary = normalized_result.metadata
	var data := _to_file_metadata(normalized)
	data["format"] = FORMAT
	data["formatVersion"] = FORMAT_VERSION
	data["nodeMap"] = snapshot.duplicate(true)
	if not editor_state.is_empty():
		data["editorState"] = editor_state.duplicate(true)
	return {"ok": true, "diagnostics": [], "data": data, "metadata": normalized.duplicate(true), "snapshot": snapshot.duplicate(true)}

## 解码只校验工程容器和项目配置；NodeMapDocument.restore_snapshot() 负责
## 节点、图、连接和注册表相关的深度恢复校验。
static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return _failure([_error("invalid_project_file", "Project file root must be a JSON object.")])
	if not data.has("format") or data.format != FORMAT:
		return _failure([_error("invalid_project_format", "File is not a GEL editor project.")])
	if not Values.is_integer(data.get("formatVersion", null)) or int(data.formatVersion) != FORMAT_VERSION:
		return _failure([_error("unsupported_project_version", "Unsupported GEL editor project format version.")])
	for key in data:
		if key not in ["format", "formatVersion", "projectId", "metadata", "package", "entryScene", "nodeMap", "editorState"]:
			return _failure([_error("unknown_project_field", "Unknown project field '" + str(key) + "'.")])
	if not data.has("nodeMap") or not data.nodeMap is Dictionary or not Values.is_json_value(data.nodeMap):
		return _failure([_error("invalid_snapshot", "Project file must contain a JSON nodeMap object.")])
	var snapshot_diagnostics := _validate_snapshot_container(data.nodeMap)
	if not snapshot_diagnostics.is_empty():
		return _failure(snapshot_diagnostics)
	var metadata_result := normalize_metadata(data)
	if not metadata_result.ok:
		return _failure(metadata_result.diagnostics)
	if data.has("editorState") and (not data.editorState is Dictionary or not Values.is_json_value(data.editorState)):
		return _failure([_error("invalid_editor_state", "editorState must be a JSON object.")])
	return {
		"ok": true,
		"diagnostics": [],
		"metadata": metadata_result.metadata,
		"snapshot": data.nodeMap.duplicate(true),
		"editor_state": data.get("editorState", {}).duplicate(true) if data.get("editorState", {}) is Dictionary else {},
	}

static func encode_json(document: Variant, metadata: Dictionary = {}, editor_state: Dictionary = {}) -> Dictionary:
	var encoded := encode(document, metadata, editor_state)
	if not encoded.ok:
		return encoded
	encoded["text"] = JSON.stringify(encoded.data, "  ") + "\n"
	return encoded

static func decode_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure([_error("invalid_project_json", "Project file contains invalid JSON.")])
	return decode(json.data)

static func to_compile_options(metadata: Dictionary) -> Dictionary:
	var normalized_result := normalize_metadata(metadata)
	if not normalized_result.ok:
		return {}
	var normalized: Dictionary = normalized_result.metadata
	var package: Dictionary = normalized.package
	var result := {
		"package_id": package.package_id,
		"package_version": package.package_version,
		"save_schema_version": package.save_schema_version,
		"title": normalized.metadata.title,
		"engine_min_version": package.engine_min_version,
	}
	if not normalized.entry_scene.is_empty():
		result["entry_scene"] = normalized.entry_scene
	return result

static func _to_file_metadata(normalized: Dictionary) -> Dictionary:
	var package: Dictionary = normalized.package
	return {
		"projectId": normalized.project_id,
		"metadata": {
			"title": normalized.metadata.title,
			"author": normalized.metadata.author,
			"language": normalized.metadata.language,
		},
		"package": {
			"packageId": package.package_id,
			"packageVersion": package.package_version,
			"saveSchemaVersion": package.save_schema_version,
			"engineMinVersion": package.engine_min_version,
		},
		"entryScene": normalized.entry_scene,
	}

static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null

## Project v1 only supports the current Node Map snapshot contract. Future
## migrations belong here, before a snapshot reaches NodeMapDocument.restore_snapshot().
static func _validate_snapshot_container(snapshot: Variant) -> Array:
	if not snapshot is Dictionary or not Values.is_json_value(snapshot):
		return [_error("invalid_snapshot", "Node Map snapshot must be a JSON object.")]
	if snapshot.get("format", "") != NODE_MAP_FORMAT or not Values.is_integer(snapshot.get("formatVersion", null)) or int(snapshot.get("formatVersion", -1)) != NODE_MAP_FORMAT_VERSION:
		return [_error("unsupported_snapshot_version", "Project contains an unsupported Node Map snapshot format.")]
	return []

static func _check_alias_conflict(source: Dictionary, first: String, second: String, field_name: String, diagnostics: Array) -> void:
	if source.has(first) and source.has(second) and source[first] != source[second]:
		diagnostics.append(_error("conflicting_project_field", "Aliases for " + field_name + " contain different values."))

static func _check_package_alias_conflict(source: Dictionary, package: Dictionary, snake_key: String, camel_key: String, diagnostics: Array) -> void:
	var found := false
	var value: Variant = null
	for container in [source, package]:
		for key in [snake_key, camel_key]:
			if not container.has(key):
				continue
			if not found:
				found = true
				value = container[key]
			elif value != container[key]:
				diagnostics.append(_error("conflicting_project_field", "Aliases for package." + camel_key + " contain different values."))
				return

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

static func _failure(diagnostics: Array) -> Dictionary:
	return {"ok": false, "diagnostics": diagnostics, "data": {}, "metadata": {}, "snapshot": {}}
