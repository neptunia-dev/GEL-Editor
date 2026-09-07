extends SceneTree

## 集成测试以宿主公开命令与真实输入验证定义驱动编辑，不依赖专用节点场景。
const SHELL := preload("res://workspace/editor_shell.tscn")
const WORKSPACE_PATH := "EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace/WorkspaceCanvas/CanvasRoot/NodeMapWorkspace"
const Definition := preload("res://node_map/registry/node_definition.gd")
const Port := preload("res://node_map/model/port_spec.gd")
const Parameter := preload("res://node_map/model/parameter_spec.gd")

class TestNode extends "res://node_map/model/node_map_node.gd":
	var label := "Fixture"
	func get_parameter_values() -> Dictionary:
		return {"label": label}
	func serialize_data() -> Dictionary:
		return get_parameter_values()
	func _set_parameter(id: String, value: Variant) -> bool:
		if id != "label" or not value is String:
			return false
		label = value
		return true
	func _restore_data(data: Dictionary) -> bool:
		return data.has("label") and _set_parameter("label", data.label)

var _checks := 0
var _failures := 0
var _shell: Control
var _editor
var _document
var _graph
var _child_id := ""
var _scene_id := ""
var _test_id := ""
var _screenshots := false

func _init() -> void:
	_screenshots = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	_shell = SHELL.instantiate()
	root.add_child(_shell)
	await _settle()
	_editor = _shell.get_node(WORKSPACE_PATH + "/NodeMapEditor")
	_document = _editor.document
	_graph = _editor.graph
	_check(_editor.is_visible_in_tree(), "functional editor is default tab")
	_check(_document.validate_self().is_empty(), "sample document is structurally valid")
	_check(_document.get_nodes(_document.root_graph_id).size() == 3, "root contains start and two scenes")
	_check(_document.get_links(_document.root_graph_id).size() == 2, "sample root links exist")
	_check(not _editor.controller.can_undo(), "sample does not pollute undo history")
	for node in _document.get_nodes(_document.root_graph_id):
		if node.node_type == "gel.scene" and node.display_name == "Prologue":
			_scene_id = node.node_id
			_child_id = node.child_graph_id
	_check(not _child_id.is_empty(), "sample prologue exists")
	await _capture("root-1440")
	await _test_navigation()
	await _test_extension()
	await _test_inputs()
	await _test_choices()
	await _test_history()
	await _test_layouts()
	_shell.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: %d node map editor checks" % _checks)
	else:
		push_error("FAIL: %d of %d node map editor checks" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK FAILED: " + message)

func _settle() -> void:
	for frame in range(6):
		await process_frame

func _execute(command: Dictionary) -> Dictionary:
	var result: Dictionary = _editor.controller.execute(command)
	_check(result.ok, "command succeeds: " + str(command.op) + " " + str(result.diagnostics))
	return result

func _test_navigation() -> void:
	for iteration in range(3):
		_graph.frame_all()
		await _settle()
		var view = _graph.get_node_view(_scene_id)
		var position_before: Vector2 = view.position_offset
		var title_position: Vector2 = view.get_global_transform() * Vector2(70, 16)
		_mouse_button(title_position, true)
		_mouse_button(title_position, false)
		_mouse_button(title_position, true, true)
		await _settle()
		_check(_graph.graph_id == _document.root_graph_id, "double click press does not hide native drag owner")
		_mouse_button(title_position, false)
		await _settle()
		_check(_graph.graph_id == _child_id, "release enters owned scene")
		var back: Button = _editor.get_node("Toolbar/Back")
		_mouse_button(back.get_global_rect().get_center(), true)
		_mouse_button(back.get_global_rect().get_center(), false)
		await _settle()
		_check(_graph.graph_id == _document.root_graph_id, "back click returns root")
		view = _graph.get_node_view(_scene_id)
		_mouse_motion(title_position + Vector2(30, 20), Vector2(30, 20), 0)
		await _settle()
		_check(view.position_offset.is_equal_approx(position_before), "no stuck drag after navigation")
		_mouse_button(title_position, true)
		_mouse_motion(title_position + Vector2(40, 40), Vector2(40, 40), MOUSE_BUTTON_MASK_LEFT)
		_mouse_button(title_position + Vector2(40, 40), false)
		await _settle()
		_check(not view.position_offset.is_equal_approx(position_before), "drag remains functional after return")
		_check(_document.get_node(_scene_id).position == view.position_offset, "drag commits to model")
	_editor.show_graph(_child_id)
	await _settle()
	_check(_document.get_links(_child_id).size() == 5, "sample child links exist")
	await _capture("scene-1440")

func _mouse_button(at: Vector2, pressed: bool, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	root.push_input(event)

func _mouse_motion(at: Vector2, relative: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	event.button_mask = mask
	root.push_input(event)

func _test_extension() -> void:
	var definition := Definition.new()
	definition.type_id = "test.extension"
	definition.display_name = "Extension Fixture"
	definition.category = "Tests"
	definition.allowed_graph_kinds = ["scene"]
	definition.factory = func(): return TestNode.new()
	var port := Port.new()
	port.port_id = "amount"
	port.display_name = "Amount"
	port.value_type = "number"
	port.has_default_value = true
	port.default_value = 2.5
	definition.port_specs = [port]
	var parameter := Parameter.new()
	parameter.parameter_id = "label"
	parameter.display_name = "Label"
	parameter.constraints = {"max_length": 12}
	definition.parameter_specs = [parameter]
	_check(_editor.registry.register_definition(definition), "new type registers without canvas changes")
	_editor._open_picker()
	await _settle()
	var search: LineEdit = _editor.get_node("NodePicker/Contents/Search")
	search.text = "Extension Fixture"
	search.text_changed.emit(search.text)
	var types: ItemList = _editor.get_node("NodePicker/Contents/Types")
	_check(types.item_count == 1 and types.get_item_metadata(0) == "test.extension", "registered type appears in filtered add menu")
	_editor._add_selected_type()
	await _settle()
	for node in _document.get_nodes(_child_id):
		if node.node_type == "test.extension":
			_test_id = node.node_id
	_check(not _test_id.is_empty(), "menu creates registered model")
	var view = _graph.get_node_view(_test_id)
	_check(view.input_port_ids == ["amount"] and view.get_input_port_count() == 1, "port indices map to stable IDs")
	var number = view.get_widget("input", "amount")
	_check(number != null and number.get_value() == 2.5, "numeric input generated with default")
	var text = view.get_widget("parameter", "label")
	_check(text != null and text.get_value() == "Fixture", "parameter generated from definition")
	var line: LineEdit = text.get_node("Editor")
	line.grab_focus()
	line.text = "Draft"
	line.text_changed.emit(line.text)
	var boolean_id := _find_type("gel.boolean")
	_execute({"op": "set_parameter", "node_id": boolean_id, "parameter_id": "value", "value": true})
	await _settle()
	_check(view.get_widget("parameter", "label") == text and line.has_focus() and line.text == "Draft", "unrelated change preserves widget focus and uncommitted text")
	_check(_document.get_node(_test_id).label == "Fixture", "widget draft is not domain state")
	line.text_submitted.emit(line.text)
	await _settle()
	_check(_document.get_node(_test_id).label == "Draft", "field submit commits to subclass parameter")
	_check(_editor.controller.undo(), "field edit can undo")
	await _settle()
	_check(line.text == "Fixture", "undo refreshes same editor in place")
	_check(_editor.controller.redo(), "field edit can redo")
	await _settle()
	line.text = "This value is much too long"
	line.text_changed.emit(line.text)
	line.text_submitted.emit(line.text)
	await _settle()
	_check(line.text == "Draft" and _document.get_node(_test_id).label == "Draft", "rejected edit restores authoritative value")
	_check(not _editor.get_node("Status/Diagnostic").text.is_empty(), "invalid edit reports diagnostic")
	line.release_focus()
	var editor: LineEdit = number.get_node("Editor/Input")
	editor.text = "7.5"
	editor.text_changed.emit(editor.text)
	editor.text_submitted.emit(editor.text)
	await _settle()
	_check(_document.get_input_state(_test_id, "amount").value == 7.5, "numeric input edits bind local port value")
	view._toggle_collapsed()
	await _settle()
	_check(_document.get_node(_test_id).collapsed and view.get_input_port_count() == 1, "collapse preserves port identity")
	view._toggle_collapsed()
	await _settle()

func _find_type(type_id: String) -> String:
	for node in _document.get_nodes(_child_id):
		if node.node_type == type_id:
			return node.node_id
	return ""

func _test_inputs() -> void:
	var condition_id := _find_type("gel.if")
	_execute({"op": "set_input", "node_id": condition_id, "port_id": "condition", "value": false})
	await _settle()
	var widget = _graph.get_node_view(condition_id).get_widget("input", "condition")
	_check(_document.get_input_state(condition_id, "condition").source == "link", "connected source takes precedence over local")
	_check(widget.get_value() == false and widget.get_node("Editor").disabled, "connected widget shows retained local value read-only")
	var connection_id := ""
	for link in _document.get_links(_child_id):
		if link.target_node_id == condition_id and link.target_port_id == "condition":
			connection_id = link.link_id
	_execute({"op": "disconnect", "link_id": connection_id})
	await _settle()
	_check(_document.get_input_state(condition_id, "condition").source == "local" and not widget.get_node("Editor").disabled, "disconnect restores local input editing")
	_execute({"op": "clear_input", "node_id": condition_id, "port_id": "condition"})
	await _settle()
	_check(not widget.has_value(), "cleared input remains unset instead of false")
	var before: Dictionary = _document.get_snapshot()
	var flag = _graph.get_node_view(_find_type("gel.boolean"))
	var test_view = _graph.get_node_view(_test_id)
	_graph.connection_request.emit(flag.name, 0, test_view.name, 0)
	await _settle()
	_check(before == _document.get_snapshot(), "view connection request cannot bypass type validation")
	var dialogue_id := _find_type("gel.dialogue")
	var dialogue_widget = _graph.get_node_view(dialogue_id).get_widget("input", "text")
	_check(dialogue_widget.get_node("Editor") is TextEdit, "host presentation chooses multiline editor")
	_execute({"op": "set_input", "node_id": dialogue_id, "port_id": "speaker", "value": null})
	await _settle()
	_check(_document.get_input_state(dialogue_id, "speaker").has_value, "explicit nullable reference differs from missing")

func _test_choices() -> void:
	var result: Dictionary = _editor.add_node_type("gel.choice", Vector2(500, 650))
	_check(result.ok, "choice created from registered type")
	var id: String = result.created_node_id
	var first: String = _execute({"op": "add_choice", "node_id": id, "label": "Left"}).created_item_id
	var second: String = _execute({"op": "add_choice", "node_id": id, "label": "Right"}).created_item_id
	await _settle()
	var view = _graph.get_node_view(id)
	var target = _graph.get_node_view(_find_type("gel.end_story"))
	_check(view.output_port_ids == [first, second], "dynamic choice IDs project into output ports")
	_graph.connection_request.emit(view.name, 1, target.name, 0)
	await _settle()
	var link_id := ""
	for link in _document.get_links(_child_id):
		if link.source_node_id == id:
			link_id = link.link_id
	_check(not link_id.is_empty(), "UI index translated to dynamic stable port")
	_execute({"op": "reorder_choices", "node_id": id, "item_ids": [second, first]})
	await _settle()
	_check(view.output_port_ids == [second, first], "port mapping follows new order")
	var visual_link := false
	for connection in _graph.get_connection_list():
		if connection.from_node == view.name:
			visual_link = connection.from_port == 0
	_check(visual_link, "visual connection rebuilt against stable ID after reorder")
	var field = view.get_widget("command", second)
	var text: LineEdit = field.get_node("Editor")
	text.text = "Renamed"
	text.text_changed.emit(text.text)
	text.text_submitted.emit(text.text)
	await _settle()
	_check(_document.get_node(id).serialize_data().choices[0].label == "Renamed", "extension field commits through generic binding")
	_check(view.get_widget("command", second) == field, "renaming dynamic item preserves widget instance")
	_execute({"op": "remove_choice", "node_id": id, "item_id": second})
	await _settle()
	_check(view.output_port_ids == [first], "removed item removes only its port")
	_check(not _document.get_links(_child_id).any(func(link): return link.link_id == link_id), "item removal atomically clears incident link")
	_check(_editor.controller.undo(), "choice deletion can undo")
	await _settle()
	_check(view.output_port_ids == [second, first], "undo restores dynamic port ID and order")
	_check(_document.get_links(_child_id).any(func(link): return link.link_id == link_id), "undo restores original link ID")

func _test_history() -> void:
	_editor.graph.finish_edits()
	var initial: Dictionary = _document.get_snapshot()
	var result := _execute({"op": "duplicate_nodes", "node_ids": [_test_id]})
	var copy_id: String = result.created_node_id
	await _settle()
	_check(copy_id != _test_id and _document.get_node(copy_id).input_values == _document.get_node(_test_id).input_values, "duplicate has fresh identity and copied local values")
	_check(_editor.controller.undo(), "duplicate undo")
	await _settle()
	_check(initial == _document.get_snapshot(), "undo restores exact document")
	_check(_editor.controller.redo(), "duplicate redo")
	await _settle()
	_check(_document.get_node(copy_id) != null, "redo retains copied identity")
	_execute({"op": "remove_nodes", "node_ids": [copy_id]})
	await _settle()
	_check(_graph.get_node_view(copy_id) == null, "delete removes visual node")
	var before: Dictionary = _document.get_snapshot()
	var failed: Dictionary = _editor.controller.execute({"op": "move_nodes", "positions": {"missing": Vector2.ZERO}})
	_check(not failed.ok and before == _document.get_snapshot(), "failed command is atomic")
	_check(_editor.controller.undo(), "failed command creates no history entry")
	await _settle()
	_check(_document.get_node(copy_id) != null, "undo skips failed command")
	var scene_before: Dictionary = _document.get_snapshot()
	_execute({"op": "remove_nodes", "node_ids": [_scene_id]})
	await _settle()
	_check(_graph.graph_id == _document.root_graph_id and _document.get_graph(_child_id) == null, "deleting active scene returns to root and removes owned graph")
	_check(_editor.controller.undo(), "scene deletion undo")
	await _settle()
	_check(scene_before == _document.get_snapshot(), "scene undo restores all nodes ports and links")
	_check(_graph.graph_id == _document.root_graph_id, "history does not overwrite navigation")

func _test_layouts() -> void:
	for window_size in [Vector2i(1024, 720), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = window_size
		await _settle()
		for graph_id in [_document.root_graph_id, _child_id]:
			_editor.show_graph(graph_id)
			await _settle()
			_graph.frame_all()
			await _settle()
			_check(_graph.size.x >= 280 and _graph.size.y >= 240, "graph retains usable minimum dimensions")
			for view in _graph.get_graph_nodes():
				_check(view.get_input_port_count() == view.input_port_ids.size(), "native input count matches stable projection")
				_check(view.get_output_port_count() == view.output_port_ids.size(), "native output count matches stable projection")
				var rect: Rect2 = view.get_global_rect()
				_check(rect.size.x > 0 and rect.size.y > 0, "node has nonzero layout")
				_check_controls(view)
			for child in _editor.get_node("Toolbar").get_children():
				if child is Control:
					_check(_editor.get_global_rect().grow(1).encloses(child.get_global_rect()), "toolbar remains within editor")
			await _capture("%s-%d" % ["root" if graph_id == _document.root_graph_id else "scene", window_size.x])
		_shell.get_node(WORKSPACE_PATH).current_tab = 1
		await _settle()
		_check(not _editor.is_visible_in_tree(), "static preview remains separately accessible")
		_shell.get_node(WORKSPACE_PATH).current_tab = 0
		await _settle()

func _check_controls(parent: Control) -> void:
	for child in parent.get_children():
		if not child is Control or not child.is_visible_in_tree():
			continue
		_check(parent.get_global_rect().grow(2).encloses(child.get_global_rect()), "control fits parent: " + str(child.get_path()))
		if child is Label and child.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var font: Font = child.get_theme_font("font")
			var required := font.get_string_size(child.text, HORIZONTAL_ALIGNMENT_LEFT, -1, child.get_theme_font_size("font_size"))
			_check(required.x <= child.size.x + 2, "label text fits: " + child.text)
		_check_controls(child)

func _capture(name: String) -> void:
	if not _screenshots or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var directory := "res://.godot/node-map-editor"
	DirAccess.make_dir_recursive_absolute(directory)
	_check(image.save_png(directory + "/" + name + ".png") == OK, "screenshot saved")
	var sample: Rect2 = _graph.get_global_rect()
	var colors: Dictionary = {}
	for y in range(int(sample.position.y), int(sample.end.y), 11):
		for x in range(int(sample.position.x), int(sample.end.x), 11):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				colors[image.get_pixel(x, y).to_html()] = true
	_check(colors.size() > 25, "canvas contains rendered nodes and connections")
