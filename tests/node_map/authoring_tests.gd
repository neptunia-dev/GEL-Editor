extends SceneTree

const Builtins := preload("res://node_map/registry/builtin_nodes.gd")
const Document := preload("res://node_map/model/node_map_document.gd")
const Controller := preload("res://workspace/node_map/node_map_controller.gd")
const AUTHORING := preload("res://workspace/authoring/authoring_workspace.tscn")

var _checks := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_execute_batch()
	await _test_authoring_files()
	if _failures == 0:
		print("PASS: %d authoring checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d authoring checks" % [_failures, _checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK FAILED: " + message)

func _test_execute_batch() -> void:
	var document = Document.new(Builtins.create_registry())
	var controller = Controller.new(document)
	var graph_id: String = document.root_graph_id
	var before_count: int = document.get_nodes(graph_id).size()
	var created: Dictionary = controller.execute_batch([
		{"op": "create_node", "type_id": "gel.scene", "graph_id": graph_id},
		{"op": "create_node", "type_id": "gel.scene", "graph_id": graph_id},
	])
	_check(created.ok, "batch create succeeds")
	_check(document.get_nodes(graph_id).size() == before_count + 2, "batch creates both scenes")
	_check(controller.can_undo() and not controller.can_redo(), "batch records a single undo entry")
	var snapshot: Dictionary = document.get_snapshot()
	var failed: Dictionary = controller.execute_batch([
		{"op": "create_node", "type_id": "gel.scene", "graph_id": graph_id},
		{"op": "connect", "graph_id": graph_id, "source_node_id": "missing", "source_port_id": "out", "target_node_id": "missing", "target_port_id": "enter"},
	])
	_check(not failed.ok, "invalid batch command fails")
	_check(document.get_snapshot() == snapshot, "failed batch restores the document")
	_check(controller.undo(), "one undo reverts the successful batch")
	_check(document.get_nodes(graph_id).size() == before_count, "undo restores pre-batch nodes")

func _test_authoring_files() -> void:
	var panel = AUTHORING.instantiate()
	root.add_child(panel)
	await process_frame
	var dir := ProjectSettings.globalize_path("user://authoring-contract-test")
	DirAccess.make_dir_recursive_absolute(dir.path_join("scenes"))
	_write(dir.path_join("outline.md"), "---\ntitle: Test Story\n---\n\n# Outline\n")
	_write(dir.path_join("scenes/prologue.md"), "---\nid: prologue\ntitle: 序章\n---\n\n# Goal\n")
	panel.set_directory(dir)
	var files: PackedStringArray = panel.list_relative_files()
	_check("outline.md" in files, "authoring lists outline.md")
	_check("scenes/prologue.md" in files, "authoring lists scene markdown")
	_check(panel.save_relative("scenes/prologue.md", "---\nid: prologue\ntitle: 序章\n---\n\n# Goal\nEdited\n"), "authoring writes scene markdown")
	_check(panel.load_relative("scenes/prologue.md").contains("Edited"), "authoring reloads saved markdown")
	panel.queue_free()
	await process_frame

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
