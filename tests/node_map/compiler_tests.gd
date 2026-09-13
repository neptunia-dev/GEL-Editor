extends SceneTree

## Node Map -> Runtime Package 编译边界测试。
##
## 测试只验证 Godot 侧的纯 DTO 和目录 writer；TypeScript PackageLoader 的跨层
## 验收由开发命令在本测试后针对 writer 目录执行。

const Builtins := preload("res://node_map/registry/builtin_nodes.gd")
const Document := preload("res://node_map/model/node_map_document.gd")
const Compiler := preload("res://node_map/compiler/node_map_compiler.gd")
const Writer := preload("res://node_map/compiler/runtime_package_writer.gd")
const Sample := preload("res://workspace/node_map/sample_document.gd")

class SnapshotDocument extends RefCounted:
	var snapshot: Dictionary
	func _init(value: Dictionary) -> void:
		snapshot = value
	func get_snapshot() -> Dictionary:
		return snapshot
	func validate_self() -> Array:
		return []

var _checks := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_two_scene_export_and_writer()
	_test_sample_if_compiles()
	_test_missing_dialogue_text_is_rejected()
	_test_invalid_options_are_rejected()
	_test_variable_nodes()
	_test_p0_expression_nodes()
	if _failures == 0:
		print("PASS: %d node map compiler checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d node map compiler checks" % [_failures, _checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK FAILED: " + message)

func _new_document():
	return Document.new(Builtins.create_registry())

func _ok(document, command: Dictionary) -> Dictionary:
	var result: Dictionary = document.execute(command)
	_check(result.ok, "command succeeds: %s %s" % [command.op, str(result.get("diagnostics", []))])
	return result

func _create(document, type_id: String, graph_id: String) -> String:
	return str(_ok(document, {"op": "create_node", "type_id": type_id, "graph_id": graph_id}).get("created_node_id", ""))

func _connect(document, graph_id: String, source_id: String, source_port: String, target_id: String, target_port: String) -> void:
	_ok(document, {
		"op": "connect",
		"graph_id": graph_id,
		"source_node_id": source_id,
		"source_port_id": source_port,
		"target_node_id": target_id,
		"target_port_id": target_port,
	})

func _disconnect_all(document, graph_id: String) -> void:
	for link in document.get_links(graph_id):
		_ok(document, {"op": "disconnect", "link_id": link.link_id})

func _find_node(document, graph_id: String, type_id: String):
	for node in document.get_nodes(graph_id):
		if node.node_type == type_id:
			return node
	return null

func _scene_output_port(document, scene_node_id: String) -> String:
	for port in document.get_ports(scene_node_id):
		if port.direction == "output":
			return port.port_id
	return ""

func _build_two_scene_story(dialogue_text: Variant = "Hello from GEL.") -> Dictionary:
	var document = _new_document()
	var root: String = document.root_graph_id
	var prologue := _create(document, "gel.scene", root)
	var ending := _create(document, "gel.scene", root)
	_ok(document, {"op": "set_parameter", "node_id": prologue, "parameter_id": "scene_id", "value": "prologue"})
	_ok(document, {"op": "set_parameter", "node_id": prologue, "parameter_id": "display_name", "value": "Prologue"})
	_ok(document, {"op": "set_parameter", "node_id": ending, "parameter_id": "scene_id", "value": "ending"})
	_ok(document, {"op": "set_parameter", "node_id": ending, "parameter_id": "display_name", "value": "Ending"})

	var start = _find_node(document, root, "gel.project_start")
	_connect(document, root, start.node_id, "out", prologue, "enter")
	var prologue_output := _scene_output_port(document, prologue)
	_check(not prologue_output.is_empty(), "scene projects a stable output port")
	_connect(document, root, prologue, prologue_output, ending, "enter")

	var prologue_graph: String = document.get_node(prologue).child_graph_id
	var entry = _find_node(document, prologue_graph, "gel.graph_input")
	var output = _find_node(document, prologue_graph, "gel.graph_output")
	_disconnect_all(document, prologue_graph)
	var dialogue := _create(document, "gel.dialogue", prologue_graph)
	if dialogue_text != null:
		_ok(document, {"op": "set_input", "node_id": dialogue, "port_id": "text", "value": dialogue_text})
	_connect(document, prologue_graph, entry.node_id, "out", dialogue, "in")
	_connect(document, prologue_graph, dialogue, "next", output.node_id, "in")

	var ending_graph: String = document.get_node(ending).child_graph_id
	var ending_entry = _find_node(document, ending_graph, "gel.graph_input")
	var ending_output = _find_node(document, ending_graph, "gel.graph_output")
	_disconnect_all(document, ending_graph)
	_ok(document, {"op": "remove_nodes", "node_ids": [ending_output.node_id]})
	var end_story := _create(document, "gel.end_story", ending_graph)
	_connect(document, ending_graph, ending_entry.node_id, "out", end_story, "in")
	_check(document.validate_self().is_empty(), "fixture document remains structurally valid")
	return {"document": document, "prologue_output": prologue_output}

func _test_two_scene_export_and_writer() -> void:
	var fixture := _build_two_scene_story()
	var compiler = Compiler.new()
	var compiled: Dictionary = compiler.compile(fixture.document, {
		"package_id": "editor.integration",
		"package_version": "1.2.3",
		"save_schema_version": 4,
		"title": "Editor Integration",
	})
	_check(compiled.ok, "two-scene document compiles: " + str(compiled.diagnostics))
	if not compiled.ok:
		return
	var manifest: Dictionary = compiled.manifest
	_check(manifest.formatVersion == 1 and manifest.packageId == "editor.integration", "compiler emits Runtime Package identity")
	_check(manifest.entryScene == "prologue", "Project Start determines entry scene")
	_check(manifest.scenes.size() == 2 and manifest.assets.is_empty() and manifest.characters.is_empty() and manifest.variables.is_empty(), "compiler emits only runtime-safe static collections")
	_check(manifest.routes.get("prologue", {}).get(fixture.prologue_output, "") == "ending", "scene output compiles into a stable route")
	_check(compiled.scripts.has("scenes/prologue/main.lua") and compiled.scripts.has("scenes/ending/main.lua"), "compiler emits explicit scene main.lua files")
	_check("ctx.dialogue:narrate(\"Hello from GEL.\")" in str(compiled.scripts["scenes/prologue/main.lua"]), "dialogue with no speaker emits narration")
	_check("ctx.flow:exit(" in str(compiled.scripts["scenes/prologue/main.lua"]) and "ctx.flow:end_story()" in str(compiled.scripts["scenes/ending/main.lua"]), "flow endpoints compile to Runtime API calls")
	_check(not str(JSON.stringify(manifest)).contains("position") and not str(JSON.stringify(manifest)).contains("collapsed"), "editor layout state does not leak into manifest")

	var writer = Writer.new()
	var unsafe: Dictionary = writer.write(compiled, "res://must-not-write-runtime-package")
	_check(not unsafe.ok and unsafe.diagnostics.any(func(item): return item.code == "unsafe_destination"), "writer rejects project-resource destinations")
	var written: Dictionary = writer.write(compiled, "user://node-map-compiler-test-package")
	_check(written.ok, "writer writes a successful compiler result: " + str(written.diagnostics))
	if written.ok:
		_check(FileAccess.file_exists(written.manifest_path), "writer creates manifest.json")
		_check(FileAccess.file_exists(written.directory.path_join("scenes/prologue/main.lua")), "writer creates nested Lua entry")
		var parsed := JSON.new()
		_check(parsed.parse(FileAccess.get_file_as_string(written.manifest_path)) == OK and parsed.data.entryScene == "prologue", "writer preserves JSON manifest data")

func _test_sample_if_compiles() -> void:
	var document = _new_document()
	Sample.populate(document)
	_check(document.validate_self().is_empty(), "sample remains a valid document before export")
	var compiled: Dictionary = Compiler.new().compile(document)
	_check(compiled.ok, "current editor sample compiles through Boolean + If support: " + str(compiled.diagnostics))
	if compiled.ok:
		var prologue_script := ""
		for path in compiled.scripts:
			var script: String = compiled.scripts[path]
			if script.contains("The station is quiet."):
				prologue_script = script
		_check(prologue_script.contains("if false then"), "Boolean source compiles into an If branch")
		_check(prologue_script.contains("ctx.flow:end_story()") and prologue_script.contains("ctx.flow:exit("), "sample preserves terminal and Scene-exit paths")

func _test_missing_dialogue_text_is_rejected() -> void:
	var fixture := _build_two_scene_story(null)
	var compiled: Dictionary = Compiler.new().compile(fixture.document)
	_check(not compiled.ok, "dialogue without required text cannot export")
	_check(compiled.diagnostics.any(func(item): return item.code == "missing_required_input" and item.port_id == "text"), "missing text returns a locatable compiler diagnostic")

func _test_invalid_options_are_rejected() -> void:
	var fixture := _build_two_scene_story()
	var compiler = Compiler.new()
	var compiled: Dictionary = compiler.compile(fixture.document, {"package_id": "Bad Package", "unknown": true})
	_check(not compiled.ok, "invalid package options cannot export")
	_check(compiled.diagnostics.any(func(item): return item.code == "invalid_compile_option"), "invalid option produces compiler diagnostics")
	for invalid_options in [
		{"package_id": 7},
		{"package_version": true},
		{"title": " Title "},
		{"engine_min_version": 1.0},
	]:
		var invalid: Dictionary = compiler.compile(fixture.document, invalid_options)
		_check(not invalid.ok and invalid.diagnostics.any(func(item): return item.code == "invalid_compile_option"), "compiler rejects invalid option type " + str(invalid_options))
	var dialogue_fixture := _build_two_scene_story()
	var dialogue_graph: String = dialogue_fixture.document.get_node(_find_scene_node_id(dialogue_fixture.document, "prologue")).child_graph_id
	var dialogue = _find_node(dialogue_fixture.document, dialogue_graph, "gel.dialogue")
	_ok(dialogue_fixture.document, {"op": "set_input", "node_id": dialogue.node_id, "port_id": "speaker", "value": "alice"})
	var with_speaker: Dictionary = compiler.compile(dialogue_fixture.document)
	_check(not with_speaker.ok and with_speaker.diagnostics.any(func(item): return item.code == "unsupported_speaker"), "character dialogue waits for an exported character/cast model")
	var cycle_fixture := _build_two_scene_story()
	var cycle_scene_id := _find_scene_node_id(cycle_fixture.document, "prologue")
	var cycle_graph: String = cycle_fixture.document.get_node(cycle_scene_id).child_graph_id
	var cycle_dialogue = _find_node(cycle_fixture.document, cycle_graph, "gel.dialogue")
	var cycle_output = _find_node(cycle_fixture.document, cycle_graph, "gel.graph_output")
	for link in cycle_fixture.document.get_links(cycle_graph):
		if link.source_node_id == cycle_dialogue.node_id and link.source_port_id == "next":
			_ok(cycle_fixture.document, {"op": "disconnect", "link_id": link.link_id})
	_connect(cycle_fixture.document, cycle_graph, cycle_dialogue.node_id, "next", cycle_dialogue.node_id, "in")
	var cycle: Dictionary = compiler.compile(cycle_fixture.document)
	_check(not cycle.ok and cycle.diagnostics.any(func(item): return item.code in ["missing_terminal", "flow_cycle", "non_terminating_flow"]), "reachable runtime flow cycles are rejected before Lua generation")
	var invalid_id_fixture := _build_two_scene_story()
	var invalid_scene_node_id := _find_scene_node_id(invalid_id_fixture.document, "prologue")
	var invalid_scene: Variant = invalid_id_fixture.document.get_node(invalid_scene_node_id)
	invalid_scene.scene_id = "BadScene"
	var invalid_snapshot: Dictionary = invalid_id_fixture.document.get_snapshot()
	for graph in invalid_snapshot.graphs:
		for node in graph.nodes:
			if node.id == invalid_scene_node_id:
				node.data.sceneId = "BadScene"
	var compiler_snapshot_document = SnapshotDocument.new(invalid_snapshot)
	var invalid_scene_id: Dictionary = compiler.compile(compiler_snapshot_document)
	_check(not invalid_scene_id.ok and invalid_scene_id.diagnostics.any(func(item): return item.code == "invalid_scene_id"), "compiler rejects editor-valid IDs that Runtime Package rejects")
	var write_result: Dictionary = Writer.new().write({"ok": false}, "user://ignored")
	_check(not write_result.ok and write_result.diagnostics[0].code == "invalid_compiled_package", "writer refuses failed compiler results")

func _test_variable_nodes() -> void:
	var fixture := _build_two_scene_story()
	var document = fixture.document
	var graph_id := _find_scene_node_id(document, "prologue")
	graph_id = document.get_node(graph_id).child_graph_id
	var entry = _find_node(document, graph_id, "gel.graph_input")
	var output = _find_node(document, graph_id, "gel.graph_output")
	_disconnect_all(document, graph_id)
	var set_node := _create(document, "gel.set_variable", graph_id)
	var number := _create(document, "gel.number", graph_id)
	_ok(document, {"op": "set_parameter", "node_id": set_node, "parameter_id": "variable_key", "value": "score"})
	_ok(document, {"op": "set_parameter", "node_id": number, "parameter_id": "value", "value": 3.0})
	_connect(document, graph_id, entry.node_id, "out", set_node, "in")
	_connect(document, graph_id, number, "value", set_node, "value")
	_connect(document, graph_id, set_node, "next", output.node_id, "in")
	var options := {"variables": [{"key": "score", "schema": {"type": "number"}, "defaultValue": 0}]}
	var compiled: Dictionary = Compiler.new().compile(document, options)
	_check(compiled.ok, "Set Variable compiles against a declared package variable: " + str(compiled.diagnostics))
	if compiled.ok:
		var script := str(compiled.scripts["scenes/prologue/main.lua"])
		_check(compiled.manifest.variables.size() == 1 and "ctx.state:set(\"score\", 3" in script, "variable declaration and state write are emitted")
	var unknown := Compiler.new().compile(document)
	_check(not unknown.ok and unknown.diagnostics.any(func(item): return item.code == "unknown_variable"), "unknown variable keys are rejected")

func _test_p0_expression_nodes() -> void:
	var fixture := _build_two_scene_story()
	var document = fixture.document
	var scene_id := _find_scene_node_id(document, "prologue")
	var graph_id: String = document.get_node(scene_id).child_graph_id
	var entry = _find_node(document, graph_id, "gel.graph_input")
	var output = _find_node(document, graph_id, "gel.graph_output")
	_disconnect_all(document, graph_id)
	var set_node := _create(document, "gel.set_variable", graph_id)
	var math := _create(document, "gel.math", graph_id)
	var left_number := _create(document, "gel.number", graph_id)
	var right_number := _create(document, "gel.number", graph_id)
	var get_node := _create(document, "gel.get_variable", graph_id)
	var compare := _create(document, "gel.compare", graph_id)
	var compare_right := _create(document, "gel.number", graph_id)
	var logic := _create(document, "gel.logic", graph_id)
	var boolean := _create(document, "gel.boolean", graph_id)
	var branch := _create(document, "gel.if", graph_id)
	var end_story := _create(document, "gel.end_story", graph_id)
	for item in [[left_number, "value", 2.0], [right_number, "value", 3.0], [compare_right, "value", 4.0]]:
		_ok(document, {"op": "set_parameter", "node_id": item[0], "parameter_id": item[1], "value": item[2]})
	_ok(document, {"op": "set_parameter", "node_id": set_node, "parameter_id": "variable_key", "value": "score"})
	_ok(document, {"op": "set_parameter", "node_id": get_node, "parameter_id": "variable_key", "value": "score"})
	_ok(document, {"op": "set_parameter", "node_id": math, "parameter_id": "operation", "value": "add"})
	_ok(document, {"op": "set_parameter", "node_id": compare, "parameter_id": "operation", "value": "greater_than"})
	_ok(document, {"op": "set_parameter", "node_id": logic, "parameter_id": "operation", "value": "and"})
	_connect(document, graph_id, entry.node_id, "out", set_node, "in")
	_connect(document, graph_id, math, "value", set_node, "value")
	_connect(document, graph_id, left_number, "value", math, "left")
	_connect(document, graph_id, right_number, "value", math, "right")
	_connect(document, graph_id, set_node, "next", branch, "in")
	_connect(document, graph_id, get_node, "value", compare, "left")
	_connect(document, graph_id, compare_right, "value", compare, "right")
	_connect(document, graph_id, compare, "value", logic, "left")
	_connect(document, graph_id, boolean, "value", logic, "right")
	_connect(document, graph_id, logic, "value", branch, "condition")
	_connect(document, graph_id, branch, "true", output.node_id, "in")
	_connect(document, graph_id, branch, "false", end_story, "in")
	var compiled: Dictionary = Compiler.new().compile(document, {"variables": [{"key": "score", "schema": {"type": "number"}, "defaultValue": 0}]})
	_check(compiled.ok, "P0 variable, compare, logic and math graph compiles: " + str(compiled.diagnostics))
	if compiled.ok:
		var script := str(compiled.scripts["scenes/prologue/main.lua"])
		_check("ctx.state:set(\"score\", (2" in script, "Set Variable emits state:set with Math expression")
		_check("ctx.state:get(\"score\")" in script and " > 4" in script and " and false" in script, "Get Variable, Compare and Logic emit typed Lua expressions")
	var bad_math: Variant = document.get_node(math)
	bad_math.operation = "divide"
	var zero := _create(document, "gel.number", graph_id)
	_ok(document, {"op": "set_parameter", "node_id": zero, "parameter_id": "value", "value": 0.0})
	for link in document.get_links(graph_id):
		if link.target_node_id == math and link.target_port_id == "right":
			_ok(document, {"op": "disconnect", "link_id": link.link_id})
	_connect(document, graph_id, zero, "value", math, "right")
	var rejected: Dictionary = Compiler.new().compile(document, {"variables": [{"key": "score", "schema": {"type": "number"}, "defaultValue": 0}]})
	_check(not rejected.ok and rejected.diagnostics.any(func(item): return item.code == "division_by_zero"), "Math division by zero is rejected")

func _find_scene_node_id(document, scene_id: String) -> String:
	for node in document.get_nodes(document.root_graph_id):
		if node.node_type == "gel.scene" and node.scene_id == scene_id:
			return node.node_id
	return ""
