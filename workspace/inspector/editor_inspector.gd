extends MarginContainer
class_name GelEditorInspector

signal scene_requested(graph_id: String)

## 通用 Node Inspector。它只消费 NodeMapDocument 的只读查询，并通过 Controller
## 发出既有命令；Inspector 本身不拥有领域模型，也不写工程文件。
var _document
var _controller
var _registry
var _content: VBoxContainer
var _selected_node_id := ""
var _updating := false

func _ready() -> void:
	_content = get_node("InspectorContent")

func configure(document, controller, registry) -> void:
	_document = document
	_controller = controller
	_registry = registry
	_refresh()

func refresh() -> void:
	_refresh()

func show_node(node_id: String) -> void:
	_selected_node_id = node_id
	_refresh()

func _refresh() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		if child.name != "Heading" and child.name != "Rule":
			child.queue_free()
	if _document == null or _selected_node_id.is_empty():
		_add_label("Select a node to inspect", "Status")
		return
	var node = _document.get_node(_selected_node_id)
	if node == null:
		_selected_node_id = ""
		_add_label("Select a node to inspect", "Status")
		return
	var definition = _registry.get_definition(node.node_type)
	_add_label(str(definition.display_name) + "  /  " + node.node_type, "NodeType")
	_add_label("ID: " + node.node_id, "NodeId")
	_add_section("State")
	_add_toggle("Enabled", "enabled", node.enabled)
	_add_toggle("Locked", "locked", node.locked)
	_add_toggle("Collapsed", "collapsed", node.collapsed)
	_add_section("Layout")
	_add_number_pair("Position", node.position, "position")
	_add_number_pair("Size", node.size, "size")
	_add_section("Parameters")
	var parameters: Dictionary = node.get_parameter_values()
	for spec in definition.parameter_specs:
		if not parameters.has(spec.parameter_id):
			continue
		_add_parameter(spec, parameters[spec.parameter_id])
	if node.node_type == "gel.scene":
		_add_label("Child graph: " + str(node.child_graph_id), "ChildGraph")
		var open := Button.new()
		open.text = "Open Scene Graph"
		open.pressed.connect(func():
			if _document.get_graph(node.child_graph_id) != null:
				scene_requested.emit(node.child_graph_id)
		)
		_content.add_child(open)

func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.name = "Section_" + text
	label.add_theme_font_size_override("font_size", 11)
	_content.add_child(label)

func _add_label(text: String, id: String) -> void:
	var label := Label.new()
	label.name = id
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.tooltip_text = text
	_content.add_child(label)

func _add_toggle(label_text: String, field: String, value: bool) -> void:
	var toggle := CheckButton.new()
	toggle.name = "Toggle_" + field
	toggle.text = label_text
	toggle.button_pressed = value
	toggle.toggled.connect(func(next: bool):
		if _updating or _document == null:
			return
		_controller.execute({"op": "set_node_flags", "node_id": _selected_node_id, "values": {field: next}})
	)
	_content.add_child(toggle)

func _add_number_pair(label_text: String, value: Vector2, field: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 64
	row.add_child(label)
	for axis in ["x", "y"]:
		var input := SpinBox.new()
		input.name = field + axis
		input.allow_greater = true
		input.allow_lesser = true
		input.step = 1.0
		input.value = value.x if axis == "x" else value.y
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.value_changed.connect(func(next: float):
			if _updating or _document == null:
				return
			var current = _document.get_node(_selected_node_id)
			if current == null:
				return
			var next_position: Vector2 = current.position if field == "position" else current.size
			if axis == "x":
				next_position.x = next
			else:
				next_position.y = next
			if field == "position":
				_controller.execute({"op": "move_nodes", "positions": {_selected_node_id: next_position}})
			else:
				_controller.execute({"op": "resize_nodes", "sizes": {_selected_node_id: next_position}})
		)
		row.add_child(input)
	_content.add_child(row)

func _add_parameter(spec, value: Variant) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = spec.display_name
	label.custom_minimum_size.x = 84
	row.add_child(label)
	if spec.value_type == "boolean":
		var toggle := CheckButton.new()
		toggle.button_pressed = bool(value)
		toggle.toggled.connect(func(next: bool): _commit_parameter(spec.parameter_id, next))
		row.add_child(toggle)
	else:
		var input := LineEdit.new()
		input.text = str(value)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.text_submitted.connect(func(text: String): _commit_parameter(spec.parameter_id, _parse_value(spec.value_type, text)))
		row.add_child(input)
	_content.add_child(row)

func _parse_value(value_type: String, text: String) -> Variant:
	if value_type == "number":
		return text.to_float()
	return text

func _commit_parameter(parameter_id: String, value: Variant) -> void:
	if _updating or _document == null:
		return
	_controller.execute({"op": "set_parameter", "node_id": _selected_node_id, "parameter_id": parameter_id, "value": value})
