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
	_test_ir_apply()
	_test_ir_events()
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

func _test_ir_apply() -> void:
	var story := {
		"format": "gel.story-ir",
		"formatVersion": 1,
		"entryScene": "prologue",
		"scenes": [
			{
				"sceneId": "prologue",
				"title": "序章",
				"nodes": [
					{"id": "d1", "type": "gel.dialogue", "text": "The station is quiet."},
					{"id": "out1", "type": "gel.graph_output", "interfaceId": "continue"},
				],
				"links": [["entry", "out", "d1", "in"], ["d1", "next", "out1", "in"]],
			},
			{
				"sceneId": "ending",
				"title": "结局",
				"nodes": [{"id": "end", "type": "gel.end_story"}],
				"links": [["entry", "out", "end", "in"]],
			},
		],
		"routes": {"prologue": {"continue": "ending"}},
	}
	var document = Document.new(Builtins.create_registry())
	var controller = Controller.new(document)
	var Applier := preload("res://node_map/compiler/story_ir_applier.gd")
	var applied: Dictionary = Applier.new().apply_story(controller, story)
	_check(applied.ok, "story IR applies: " + str(applied.get("diagnostics", [])))
	_check(document.validate_self().is_empty(), "applied document is structurally valid")
	var Compiler := preload("res://node_map/compiler/node_map_compiler.gd")
	var compiled: Dictionary = Compiler.new().compile(document)
	_check(compiled.ok, "applied document compiles: " + str(compiled.get("diagnostics", [])))
	if compiled.ok:
		_check("ctx.dialogue:narrate(\"The station is quiet.\")" in str(compiled.scripts["scenes/prologue/main.lua"]), "applied dialogue compiles to narration")
		_check("ctx.flow:end_story()" in str(compiled.scripts["scenes/ending/main.lua"]), "applied ending compiles to end_story")

func _test_ir_events() -> void:
	var events: Array = [
		{"op": "story", "entryScene": "prologue"},
		{"op": "scene", "sceneId": "prologue", "title": "序章"},
		{"op": "node", "id": "d1", "type": "gel.dialogue", "text": "The station is quiet."},
		{"op": "node", "id": "out1", "type": "gel.graph_output", "interfaceId": "continue"},
		{"op": "link", "from": ["entry", "out"], "to": ["d1", "in"]},
		{"op": "link", "from": ["d1", "next"], "to": ["out1", "in"]},
		{"op": "scene", "sceneId": "ending", "title": "结局"},
		{"op": "node", "id": "end", "type": "gel.end_story"},
		{"op": "link", "from": ["entry", "out"], "to": ["end", "in"]},
		{"op": "route", "from": "prologue", "exit": "continue", "to": "ending"},
		{"op": "done"},
	]
	var document = Document.new(Builtins.create_registry())
	var controller = Controller.new(document)
	var Applier := preload("res://node_map/compiler/story_ir_applier.gd")
	var applier = Applier.new()
	var session: Dictionary = applier.create_session()
	controller.begin_external_batch()
	for event in events:
		var applied: Dictionary = applier.apply_event(document, session, event)
		_check(applied.ok, "IR event %s applies: %s" % [str(event.get("op", "")), str(applied.get("diagnostics", []))])
	controller.commit_external_batch()
	_check(document.validate_self().is_empty(), "streamed document is structurally valid")
	var compiled: Dictionary = preload("res://node_map/compiler/node_map_compiler.gd").new().compile(document)
	_check(compiled.ok, "streamed document compiles: " + str(compiled.get("diagnostics", [])))
	var rolled = Document.new(Builtins.create_registry())
	var rolling = Controller.new(rolled)
	var fail_session: Dictionary = applier.create_session()
	var start: Dictionary = rolled.get_snapshot()
	rolling.begin_external_batch()
	applier.apply_event(rolled, fail_session, {"op": "story", "entryScene": "prologue"})
	applier.apply_event(rolled, fail_session, {"op": "scene", "sceneId": "prologue", "title": "序章"})
	var failed: Dictionary = applier.apply_event(rolled, fail_session, {"op": "link", "from": ["entry", "out"], "to": ["missing", "in"]})
	_check(not failed.ok, "forward link is rejected")
	rolling.abort_external_batch()
	_check(rolled.get_snapshot() == start, "failed stream restores the document")

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
