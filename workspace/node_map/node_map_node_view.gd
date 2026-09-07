extends GraphNode

## 统一外壳只消费只读投影；字段和操作通过命令交给宿主。
signal command_requested(command: Dictionary)
signal scene_requested(graph_id: String)

const ROW := preload("res://workspace/node_map/node_row.tscn")
const RESET := preload("res://workspace/node_map/icons/rotate-ccw.svg")
const FOLD := preload("res://workspace/node_map/icons/chevron-up.svg")
var node_id := ""
var input_port_ids: Array = []
var output_port_ids: Array = []
var _document
var _definition
var _widgets
var _presentation: Dictionary = {}
var _fields: Dictionary = {}
var _port_rows: Dictionary = {}
var _extra_rows: Dictionary = {}
var _signature: Array = []
var _parameter_rows: Array = []
var _fold_button: Button
var _navigation := ""
var _pending_navigation := false

func _ready() -> void:
	_fold_button = Button.new()
	_fold_button.icon = FOLD
	_fold_button.custom_minimum_size = Vector2(24, 24)
	_fold_button.tooltip_text = "Collapse node"
	get_titlebar_hbox().add_child(_fold_button)
	_fold_button.pressed.connect(_toggle_collapsed)
	gui_input.connect(_on_title_input)

func configure(id: String, document, definition, widgets, presentations) -> void:
	node_id = id
	_document = document
	_definition = definition
	_widgets = widgets
	_presentation = presentations.get_presentation(definition.type_id)
	_apply_styles()
	sync_from_document()

func sync_from_document() -> void:
	if _document == null:
		return
	var model = _document.get_node(node_id)
	if model == null:
		return
	var ports: Array = _document.get_ports(node_id)
	var extras: Array = []
	if _presentation.has("rows"):
		extras = _presentation.rows.call(model, ports)
	var shape: Array = []
	for port in ports:
		shape.append([port.port_id, port.direction, port.kind, port.value_type])
	for parameter in _definition.parameter_specs:
		shape.append(["parameter", parameter.parameter_id, parameter.value_type])
	for row in extras:
		shape.append(["extra", row.id, row.kind])
	if shape != _signature:
		_rebuild(ports, extras)
		_signature = shape
	var parameters: Dictionary = model.get_parameter_values()
	title = model.title_override if not model.title_override.is_empty() else str(parameters.get(_presentation.get("title_parameter", ""), _definition.display_name))
	if title.is_empty():
		title = _definition.display_name
	position_offset = model.position
	draggable = not model.locked
	self_modulate = Color.WHITE if model.enabled else Color("9fa5ac")
	_fold_button.tooltip_text = "Expand node" if model.collapsed else "Collapse node"
	for port in ports:
		var row: Control = _port_rows[port.port_id]
		row.get_node("Label").text = port.display_name
		row.tooltip_text = "%s: %s" % [port.port_id, port.kind if port.kind == "flow" else port.value_type]
		if port.kind != "data" or port.direction != "input":
			continue
		var state: Dictionary = _document.get_input_state(node_id, port.port_id)
		var linked: bool = state.source == "link"
		var has_value: bool = model.input_values.has(port.port_id) or port.has_default_value
		var value: Variant = model.input_values.get(port.port_id, port.default_value)
		_sync_field("input:" + port.port_id, value, has_value, linked)
		row.get_node("Content").visible = not model.collapsed
		var reset: Button = row.get_node("Content/Reset")
		reset.disabled = linked or not model.input_values.has(port.port_id)
		row.tooltip_text += " (connected)" if linked else ""
	for parameter in _definition.parameter_specs:
		var has_value: bool = parameters.has(parameter.parameter_id) or parameter.has_default_value
		var value: Variant = parameters.get(parameter.parameter_id, parameter.default_value)
		var hint: Dictionary = _hint("parameter:" + parameter.parameter_id)
		_sync_field("parameter:" + parameter.parameter_id, value, has_value, hint.get("read_only", false))
	_navigation = ""
	for extra in extras:
		var item: Dictionary = _extra_rows[extra.id]
		if extra.kind == "field":
			item.row.get_node("Label").text = extra.label
			_fields["command:" + extra.id].command = extra.command
			_sync_field("command:" + extra.id, extra.value, true, false)
			_refresh_actions(item.actions, extra.get("actions", []))
		else:
			item.row.text = extra.label
			item.row.set_meta("descriptor", extra)
			if extra.kind == "navigate":
				_navigation = extra.graph_id
	for row in _parameter_rows:
		row.visible = not model.collapsed
	# 折叠保留端口行及身份，只收起编辑区域。
	size = Vector2(maxf(270, model.size.x), 0)

func get_widget(binding_kind: String, binding_id: String) -> Control:
	return _fields.get(binding_kind + ":" + binding_id, {}).get("widget")

func finish_edits() -> void:
	for field in _fields.values():
		field.widget.finish_edit()

func _hint(key: String) -> Dictionary:
	return _presentation.get("fields", {}).get(key, {})

func _rebuild(ports: Array, extras: Array) -> void:
	clear_all_slots()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_fields.clear()
	_port_rows.clear()
	_extra_rows.clear()
	_parameter_rows.clear()
	input_port_ids.clear()
	output_port_ids.clear()
	for port in ports:
		var row = ROW.instantiate()
		add_child(row)
		_port_rows[port.port_id] = row
		var input: bool = port.direction == "input"
		var code: int = 0 if port.kind == "flow" else int(hash(port.value_type) & 0x7fffffff) + 1
		var color := _port_color(port.kind, port.value_type)
		set_slot(row.get_index(), input, code, color, not input, code, color)
		if input:
			input_port_ids.append(port.port_id)
		else:
			output_port_ids.append(port.port_id)
			row.get_node("Label").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if port.kind == "data" and input:
			_add_field(row, "input", port.port_id, port.value_type, {})
			var reset := _icon_button("rotate-ccw", "Clear local value")
			reset.name = "Reset"
			row.get_node("Content").add_child(reset)
			reset.pressed.connect(func(): command_requested.emit({"op": "clear_input", "node_id": node_id, "port_id": port.port_id}))
		else:
			row.get_node("Content").hide()
	for parameter in _definition.parameter_specs:
		var row = ROW.instantiate()
		add_child(row)
		row.get_node("Label").text = parameter.display_name
		_parameter_rows.append(row)
		_add_field(row, "parameter", parameter.parameter_id, parameter.value_type, parameter.constraints)
	for extra in extras:
		_build_extra(extra)

func _add_field(row: Control, kind: String, id: String, value_type: String, constraints: Dictionary) -> void:
	var key := kind + ":" + id
	var hint := _hint(key)
	var merged := constraints.duplicate(true)
	merged.merge(hint.get("constraints", {}), true)
	var widget: Control = _widgets.create_widget(value_type, hint.get("hint", ""), merged)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.get_node("Content").add_child(widget)
	_fields[key] = {"widget": widget, "last": [], "command": {}, "value_key": "value"}
	widget.value_committed.connect(func(value): _commit_field(key, kind, id, value))

func _commit_field(key: String, kind: String, id: String, value: Variant) -> void:
	var command: Dictionary
	if kind == "command":
		command = _fields[key].command.duplicate(true)
		command[_fields[key].value_key] = value
	else:
		command = {"op": "set_input" if kind == "input" else "set_parameter", "node_id": node_id, "value": value}
		command["port_id" if kind == "input" else "parameter_id"] = id
	# 即使校验失败且文档未变化，也必须恢复控件的权威值。
	_fields[key].last = []
	command_requested.emit(command)

func _sync_field(key: String, value: Variant, has_value: bool, read_only: bool) -> void:
	var field: Dictionary = _fields[key]
	var state: Array = [value, has_value, read_only]
	if field.last == state:
		return
	field.widget.set_value(value, has_value)
	field.widget.set_read_only(read_only)
	field.last = state.duplicate(true)

func _build_extra(extra: Dictionary) -> void:
	if extra.kind == "field":
		var row = ROW.instantiate()
		add_child(row)
		_parameter_rows.append(row)
		_add_field(row, "command", extra.id, extra.value_type, extra.get("constraints", {}))
		_fields["command:" + extra.id].value_key = extra.get("value_key", "value")
		var actions := HBoxContainer.new()
		row.get_node("Content").add_child(actions)
		_extra_rows[extra.id] = {"row": row, "actions": actions}
	else:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 28)
		button.text = extra.label
		button.icon = load("res://workspace/node_map/icons/%s.svg" % extra.get("icon_key", "arrow-left"))
		button.set_meta("descriptor", extra)
		button.pressed.connect(func(): _run_action(button.get_meta("descriptor")))
		add_child(button)
		_parameter_rows.append(button)
		_extra_rows[extra.id] = {"row": button}

func _refresh_actions(container: HBoxContainer, actions: Array) -> void:
	if container.get_child_count() != actions.size():
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
		for descriptor in actions:
			var button := _icon_button(descriptor.icon_key, descriptor.tooltip)
			container.add_child(button)
			button.pressed.connect(func(): _run_action(button.get_meta("descriptor")))
	for index in range(actions.size()):
		var button: Button = container.get_child(index)
		button.set_meta("descriptor", actions[index])

func _icon_button(icon_key: String, tooltip: String) -> Button:
	var button := Button.new()
	button.icon = load("res://workspace/node_map/icons/%s.svg" % icon_key)
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(24, 24)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button

func _run_action(descriptor: Dictionary) -> void:
	finish_edits()
	if descriptor.get("kind", "") == "navigate":
		call_deferred("_navigate", descriptor.graph_id)
	else:
		command_requested.emit(descriptor.command.duplicate(true))

func _toggle_collapsed() -> void:
	finish_edits()
	var model = _document.get_node(node_id)
	command_requested.emit({"op": "set_node_flags", "node_id": node_id, "values": {"collapsed": not model.collapsed}})

func _on_title_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and event.double_click and not _navigation.is_empty():
		_pending_navigation = true
	elif not event.pressed and _pending_navigation:
		_pending_navigation = false
		call_deferred("_navigate", _navigation)

func _navigate(graph_id: String) -> void:
	if is_visible_in_tree() and not graph_id.is_empty():
		scene_requested.emit(graph_id)

func _apply_styles() -> void:
	var accent: Color = _presentation.get("accent", Color("8db8ae"))
	for style_name in ["panel", "panel_selected", "titlebar", "titlebar_selected"]:
		var source := get_theme_stylebox(style_name)
		if not source is StyleBoxFlat:
			continue
		var style: StyleBoxFlat = source.duplicate()
		if style_name.begins_with("titlebar"):
			style.bg_color = accent.darkened(0.66)
		style.border_color = accent if style_name.ends_with("selected") else accent.darkened(0.4)
		add_theme_stylebox_override(style_name, style)
	for child in get_titlebar_hbox().get_children():
		if child is Label:
			child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _port_color(kind: String, value_type: String) -> Color:
	if kind == "flow":
		return Color("c7ced3")
	match value_type:
		"boolean": return Color("d78e9d")
		"number": return Color("b4cc7c")
		"string": return Color("86bdd1")
		"character": return Color("d3ba88")
	return Color("b7a9d4")
