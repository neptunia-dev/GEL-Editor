extends SceneTree

## Node Map 工程文件持久化测试。
##
## 覆盖纯工程容器、原子文件替换以及通过临时文档恢复快照的边界；领域
## NodeMapDocument 本身的结构校验仍由 model_tests.gd 单独覆盖。

const Builtins := preload("res://node_map/registry/builtin_nodes.gd")
const Document := preload("res://node_map/model/node_map_document.gd")
const Codec := preload("res://node_map/serialization/project_file_codec.gd")
const ProjectFile := preload("res://node_map/serialization/node_map_project_file.gd")
const Sample := preload("res://workspace/node_map/sample_document.gd")

var _checks := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_codec_round_trip()
	_test_codec_validation_guards()
	_test_file_round_trip_and_replacement()
	_test_rejects_bad_inputs_without_load_result()
	_test_rejects_junction_paths_when_available()
	if _failures == 0:
		print("PASS: %d node map project file checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d node map project file checks" % [_failures, _checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK FAILED: " + message)

func _new_document():
	return Document.new(Builtins.create_registry())

func _metadata() -> Dictionary:
	return {
		"project_id": "persistence_fixture",
		"metadata": {"title": "Persistence Fixture", "author": "GEL", "language": "en"},
		"package": {
			"package_id": "persistence.fixture",
			"package_version": "1.2.3",
			"save_schema_version": 7,
			"engine_min_version": "0.1.0",
		},
		"entry_scene": "prologue",
	}

func _test_codec_round_trip() -> void:
	var document = _new_document()
	Sample.populate(document)
	var state := {"activeGraphId": document.root_graph_id, "graphStates": {document.root_graph_id: {"zoom": 1.0, "scroll": {"x": 2.0, "y": 3.0}}}}
	var encoded: Dictionary = Codec.encode(document, _metadata(), state)
	_check(encoded.ok, "project codec encodes a structurally valid document: " + str(encoded.diagnostics))
	if not encoded.ok:
		return
	_check(encoded.data.format == "gel.editor-project" and encoded.data.formatVersion == 1, "project container has its independent format identity")
	_check(encoded.data.nodeMap == document.get_snapshot(), "project container keeps the complete Node Map snapshot")
	_check(encoded.metadata.package.package_id == "persistence.fixture" and encoded.metadata.entry_scene == "prologue", "project metadata normalizes runtime package configuration")
	var decoded: Dictionary = Codec.decode(encoded.data)
	_check(decoded.ok, "project codec decodes its own container: " + str(decoded.diagnostics))
	if decoded.ok:
		_check(decoded.snapshot == document.get_snapshot(), "codec round trip preserves graph/node/link identities")
		_check(decoded.metadata == encoded.metadata and decoded.editor_state == state, "codec round trip preserves metadata and optional editor state")
	var json_result: Dictionary = Codec.encode_json(document, _metadata())
	_check(json_result.ok and json_result.text.ends_with("\n"), "project JSON encoder produces formatted text")
	var json_decoded: Dictionary = Codec.decode_json(json_result.get("text", ""))
	var json_document = Document.new(Builtins.create_registry(), false)
	var json_restored: Dictionary = json_document.restore_snapshot(json_decoded.get("snapshot", {})) if json_decoded.ok else {"ok": false}
	_check(json_decoded.ok and json_restored.ok and json_document.get_snapshot() == document.get_snapshot(), "project JSON decoder supplies a snapshot that restores to the same document")

func _test_codec_validation_guards() -> void:
	var document = _new_document()
	var encoded: Dictionary = Codec.encode(document, _metadata())
	_check(encoded.ok, "codec validation fixture encodes")
	if not encoded.ok:
		return
	var unsupported_snapshot: Dictionary = encoded.data.duplicate(true)
	unsupported_snapshot.nodeMap.formatVersion = 2
	var unsupported_snapshot_result: Dictionary = Codec.decode(unsupported_snapshot)
	_check(not unsupported_snapshot_result.ok and unsupported_snapshot_result.diagnostics.any(func(item): return item.code == "unsupported_snapshot_version"), "project v1 rejects an incompatible embedded Node Map version")
	var non_json_snapshot: Dictionary = encoded.data.duplicate(true)
	non_json_snapshot.nodeMap.graphs[0].nodes[0].position = Vector2.ZERO
	var non_json_result: Dictionary = Codec.decode(non_json_snapshot)
	_check(not non_json_result.ok and non_json_result.diagnostics.any(func(item): return item.code == "invalid_snapshot"), "codec rejects non-JSON snapshot values before model restoration")
	var unsupported_project: Dictionary = encoded.data.duplicate(true)
	unsupported_project.formatVersion = 2
	var unsupported_project_result: Dictionary = Codec.decode(unsupported_project)
	_check(not unsupported_project_result.ok and unsupported_project_result.diagnostics.any(func(item): return item.code == "unsupported_project_version"), "codec rejects an unknown project container version")
	var conflicting_metadata := _metadata()
	conflicting_metadata["projectId"] = "other_project"
	var conflicting_metadata_result: Dictionary = Codec.normalize_metadata(conflicting_metadata)
	_check(not conflicting_metadata_result.ok and conflicting_metadata_result.diagnostics.any(func(item): return item.code == "conflicting_project_field"), "metadata aliases cannot silently disagree")
	var conflicting_package := _metadata()
	var nested_package: Dictionary = conflicting_package["package"]
	nested_package["packageId"] = "other.package"
	conflicting_package["package"] = nested_package
	var conflicting_package_result: Dictionary = Codec.normalize_metadata(conflicting_package)
	_check(not conflicting_package_result.ok and conflicting_package_result.diagnostics.any(func(item): return item.code == "conflicting_project_field"), "nested package aliases cannot silently disagree")
	var conflicting_top_level := _metadata()
	conflicting_top_level["packageId"] = "other.package"
	var conflicting_top_level_result: Dictionary = Codec.normalize_metadata(conflicting_top_level)
	_check(not conflicting_top_level_result.ok and conflicting_top_level_result.diagnostics.any(func(item): return item.code == "conflicting_project_field"), "top-level and nested package values cannot silently disagree")
	var conflicting_title := _metadata()
	conflicting_title["title"] = "Other Title"
	var conflicting_title_result: Dictionary = Codec.normalize_metadata(conflicting_title)
	_check(not conflicting_title_result.ok and conflicting_title_result.diagnostics.any(func(item): return item.code == "conflicting_project_field"), "flat and nested metadata values cannot silently disagree")
	var unknown_field := _metadata()
	unknown_field["unexpected"] = true
	var unknown_field_result: Dictionary = Codec.normalize_metadata(unknown_field)
	_check(not unknown_field_result.ok and unknown_field_result.diagnostics.any(func(item): return item.code == "unknown_project_field"), "metadata updates reject unknown project fields")

func _test_file_round_trip_and_replacement() -> void:
	var path := "user://node-map-project-file-tests/persistence" + ProjectFile.DEFAULT_EXTENSION
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(absolute)
	for suffix in [".gel-tmp-", ".gel-backup-"]:
		# Cleanup from interrupted earlier local test runs without relying on exact tick values.
		var parent := absolute.get_base_dir()
		var directory := DirAccess.open(parent)
		if directory != null:
			directory.list_dir_begin()
			while true:
				var name := directory.get_next()
				if name.is_empty():
					break
				if name.begins_with(absolute.get_file() + suffix):
					DirAccess.remove_absolute(parent.path_join(name))
			directory.list_dir_end()
	var document = _new_document()
	Sample.populate(document)
	var saved: Dictionary = ProjectFile.save(document, _metadata(), path, {"activeGraphId": document.root_graph_id})
	_check(saved.ok, "project file saves through staging publication: " + str(saved.diagnostics))
	if not saved.ok:
		return
	_check(FileAccess.file_exists(saved.path), "project save creates its final file")
	var parsed := JSON.new()
	_check(parsed.parse(FileAccess.get_file_as_string(saved.path)) == OK and parsed.data is Dictionary and parsed.data.format == "gel.editor-project" and parsed.data.nodeMap is Dictionary, "written project JSON has an editor container and Node Map snapshot")
	var loaded: Dictionary = ProjectFile.load(Builtins.create_registry(), path)
	_check(loaded.ok, "project file loads into a detached validated document: " + str(loaded.diagnostics))
	if loaded.ok:
		_check(loaded.document.get_snapshot() == document.get_snapshot(), "file load preserves all document identities and layout")
		_check(loaded.metadata == saved.metadata and loaded.editor_state == {"activeGraphId": document.root_graph_id}, "file load returns normalized project configuration and state")

	var updated_metadata := _metadata()
	updated_metadata.metadata.title = "Updated Fixture"
	var updated: Dictionary = ProjectFile.save(document, updated_metadata, path)
	_check(updated.ok, "saving an existing project atomically replaces it: " + str(updated.diagnostics))
	var reloaded: Dictionary = ProjectFile.load(Builtins.create_registry(), path)
	_check(reloaded.ok and reloaded.metadata.metadata.title == "Updated Fixture", "replacement publishes new metadata")
	var parent := absolute.get_base_dir()
	var directory := DirAccess.open(parent)
	var leftovers: Array = []
	if directory != null:
		directory.list_dir_begin()
		while true:
			var name := directory.get_next()
			if name.is_empty():
				break
			if name.begins_with(absolute.get_file() + ".gel-tmp-") or name.begins_with(absolute.get_file() + ".gel-backup-"):
				leftovers.append(name)
		directory.list_dir_end()
	_check(leftovers.is_empty(), "successful save cleans temporary and backup files")

func _test_rejects_bad_inputs_without_load_result() -> void:
	var path := "user://node-map-project-file-tests/invalid" + ProjectFile.DEFAULT_EXTENSION
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	FileAccess.open(absolute, FileAccess.WRITE).store_string("{ not json")
	var malformed: Dictionary = ProjectFile.load(Builtins.create_registry(), path)
	_check(not malformed.ok and malformed.document == null and malformed.diagnostics[0].code == "invalid_project_json", "invalid JSON is rejected before a document is returned")
	var wrong_format := {"format": "wrong", "formatVersion": 1, "nodeMap": _new_document().get_snapshot()}
	FileAccess.open(absolute, FileAccess.WRITE).store_string(JSON.stringify(wrong_format))
	var bad_format: Dictionary = ProjectFile.load(Builtins.create_registry(), path)
	_check(not bad_format.ok and bad_format.document == null and bad_format.diagnostics[0].code == "invalid_project_format", "unknown project container format is rejected")
	var invalid_snapshot: Dictionary = Codec.encode(_new_document(), _metadata()).data
	invalid_snapshot.nodeMap.graphs[0].nodes[0].type = "gel.unknown"
	FileAccess.open(absolute, FileAccess.WRITE).store_string(JSON.stringify(invalid_snapshot))
	var invalid_document: Dictionary = ProjectFile.load(Builtins.create_registry(), path)
	_check(not invalid_document.ok and invalid_document.document == null and invalid_document.diagnostics.any(func(item): return item.code == "unknown_type"), "container-valid but unresolvable snapshots do not produce a candidate document")
	var invalid_metadata := _metadata()
	invalid_metadata.package.package_id = "Bad Package"
	var rejected_save: Dictionary = ProjectFile.save(_new_document(), invalid_metadata, "user://node-map-project-file-tests/rejected" + ProjectFile.DEFAULT_EXTENSION)
	_check(not rejected_save.ok and rejected_save.diagnostics.any(func(item): return item.code == "invalid_package_config"), "invalid Runtime Package configuration cannot be persisted")
	var empty_path: Dictionary = ProjectFile.save(_new_document(), _metadata(), "")
	_check(not empty_path.ok and empty_path.diagnostics.any(func(item): return item.code == "invalid_project_path"), "empty project paths are rejected")
	var directory_path := "user://node-map-project-file-tests/directory-as-file"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path))
	var directory_load: Dictionary = ProjectFile.load(Builtins.create_registry(), directory_path)
	_check(not directory_load.ok and directory_load.diagnostics.any(func(item): return item.code == "project_read_failed"), "directories cannot be loaded as project files")
	var oversized_path := "user://node-map-project-file-tests/oversized" + ProjectFile.DEFAULT_EXTENSION
	var oversized_absolute := ProjectSettings.globalize_path(oversized_path)
	var oversized_file := FileAccess.open(oversized_absolute, FileAccess.WRITE)
	if oversized_file != null:
		oversized_file.seek(ProjectFile.MAX_PROJECT_FILE_BYTES)
		oversized_file.store_8(0)
		oversized_file.close()
	var oversized: Dictionary = ProjectFile.load(Builtins.create_registry(), oversized_path)
	_check(not oversized.ok and oversized.diagnostics.any(func(item): return item.code == "project_file_too_large"), "oversized project files are rejected before JSON parsing")
	DirAccess.remove_absolute(oversized_absolute)

func _test_rejects_junction_paths_when_available() -> void:
	if OS.get_name() != "Windows":
		return
	var base := ProjectSettings.globalize_path("user://node-map-project-file-tests/junction")
	var target := base.path_join("target")
	var link := base.path_join("linked-parent")
	DirAccess.make_dir_recursive_absolute(target)
	OS.execute("cmd.exe", ["/C", "rmdir \"" + link + "\" >nul 2>nul"])
	var created := OS.execute("cmd.exe", ["/C", "mklink /J \"" + link + "\" \"" + target + "\" >nul"])
	if created != 0:
		_check(true, "junction creation is unavailable in this environment")
		return
	var parent := DirAccess.open(base)
	if parent == null or not parent.is_link("linked-parent"):
		OS.execute("cmd.exe", ["/C", "rmdir \"" + link + "\" >nul 2>nul"])
		_check(true, "Godot does not expose this junction as a link")
		return
	var document = _new_document()
	var direct_path := target.path_join("fixture" + ProjectFile.DEFAULT_EXTENSION)
	var direct_saved: Dictionary = ProjectFile.save(document, _metadata(), direct_path)
	_check(direct_saved.ok, "direct project file exists for junction load guard")
	var linked_path := link.path_join("fixture" + ProjectFile.DEFAULT_EXTENSION)
	var linked_save: Dictionary = ProjectFile.save(document, _metadata(), linked_path)
	_check(not linked_save.ok and linked_save.diagnostics.any(func(item): return item.code == "unsafe_project_path"), "save rejects a junction parent")
	var linked_load: Dictionary = ProjectFile.load(Builtins.create_registry(), linked_path)
	_check(not linked_load.ok and linked_load.diagnostics.any(func(item): return item.code == "unsafe_project_path"), "load rejects a junction parent")
	OS.execute("cmd.exe", ["/C", "rmdir \"" + link + "\" >nul 2>nul"])
