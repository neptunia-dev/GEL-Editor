extends VBoxContainer

## 当前会话中的正式模型编辑器，不读写工程文件，也不执行节点。
const BUILTINS := preload("res://node_map/registry/builtin_nodes.gd")
const DOCUMENT := preload("res://node_map/model/node_map_document.gd")
const CONTROLLER := preload("res://workspace/node_map/node_map_controller.gd")
const WIDGETS := preload("res://workspace/node_map/widgets/node_widget_registry.gd")
const PRESENTATIONS := preload("res://workspace/node_map/node_presentation_registry.gd")
const BUILTIN_PRESENTATIONS := preload("res://workspace/node_map/builtin_node_presentations.gd")
const SAMPLE := preload("res://workspace/node_map/sample_document.gd")

var registry
var document
var controller
var widgets
var presentations
var _graph_states: Dictionary = {}
var _add_position := Vector2.ZERO

@onready var graph = $Graph
@onready var _picker: PopupPanel = $NodePicker
@onready var _search: LineEdit = $NodePicker/Contents/Search
@onready var _types: ItemList = $NodePicker/Contents/Types
@onready var _status: Label = $Status/Diagnostic

func _ready() -> void:
	registry = BUILTINS.create_registry()
	document = DOCUMENT.new(registry)
	controller = CONTROLLER.new(document)
	widgets = WIDGETS.standard()
	presentations = PRESENTATIONS.new()
	BUILTIN_PRESENTATIONS.configure(presentations)
	SAMPLE.populate(document)
	graph.configure(document, registry, widgets, presentations)
	graph.command_requested.connect(_execute)
	graph.scene_requested.connect(show_graph)
	graph.selection_changed.connect(_update_toolbar)
	graph.popup_request.connect(_open_picker_at)
	document.changed.connect(_document_changed)
	controller.history_changed.connect(_update_toolbar)
	controller.diagnostics_changed.connect(_show_diagnostics)
	$Toolbar/Back.pressed.connect(func(): show_graph(document.root_graph_id))
	$Toolbar/Add.pressed.connect(_open_picker)
	$Toolbar/Undo.pressed.connect(_undo)
	$Toolbar/Redo.pressed.connect(_redo)
	$Toolbar/Duplicate.pressed.connect(graph.duplicate_selection)
	$Toolbar/Delete.pressed.connect(graph.delete_selection)
	$Toolbar/Frame.pressed.connect(graph.frame_all)
	_search.text_changed.connect(func(_text): _populate_types())
	_search.text_submitted.connect(func(_text): _add_selected_type())
	_types.item_activated.connect(func(_index): _add_selected_type())
	$NodePicker/Contents/Add.pressed.connect(_add_selected_type)
	show_graph(document.root_graph_id)

func show_graph(id: String) -> void:
	if document.get_graph(id) == null or graph.graph_id == id:
		return
	if not graph.graph_id.is_empty():
		_graph_states[graph.graph_id] = {"zoom": graph.zoom, "scroll": graph.scroll_offset, "selected": graph.get_selected_ids()}
	graph.show_graph(id)
	if _graph_states.has(id):
		graph.zoom = _graph_states[id].zoom
		graph.scroll_offset = _graph_states[id].scroll
		for selected in _graph_states[id].selected:
			var view = graph.get_node_view(selected)
			if view != null:
				view.selected = true
	else:
		_frame_after_layout(id)
	_update_toolbar()

func _frame_after_layout(id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if graph.graph_id == id:
		graph.frame_all()

func _execute(command: Dictionary) -> void:
	controller.execute(command)
	graph.request_refresh()

func _document_changed(_change: Dictionary) -> void:
	if document.get_graph(graph.graph_id) == null:
		call_deferred("show_graph", document.root_graph_id)
	else:
		graph.request_refresh()
	_update_toolbar()

func _update_toolbar() -> void:
	if controller == null:
		return
	$Toolbar/Undo.disabled = not controller.can_undo()
	$Toolbar/Redo.disabled = not controller.can_redo()
	$Toolbar/Back.disabled = graph.graph_id == document.root_graph_id
	var selected: Array = graph.get_selected_ids()
	$Toolbar/Delete.disabled = selected.is_empty()
	$Toolbar/Duplicate.disabled = selected.is_empty()
	var current = document.get_graph(graph.graph_id)
	var caption := "Root Graph"
	if current != null and current.kind == "scene":
		var owner_node = document.get_node(current.owner_node_id)
		if owner_node != null:
			caption += " / " + str(owner_node.get_parameter_values().get("display_name", "Scene"))
	$Toolbar/Breadcrumb.text = caption
	$Status/Counts.text = "%d nodes   %d links" % [document.get_nodes(graph.graph_id).size(), document.get_links(graph.graph_id).size()]

func _show_diagnostics(items: Array) -> void:
	_status.text = "" if items.is_empty() else str(items[0].get("message", "Invalid change"))
	_status.tooltip_text = _status.text

func _undo() -> void:
	graph.finish_edits()
	controller.undo()

func _redo() -> void:
	graph.finish_edits()
	controller.redo()

func _open_picker() -> void:
	_open_picker_at(graph.size * 0.5)

func _open_picker_at(local_position: Vector2) -> void:
	graph.finish_edits()
	_add_position = (local_position + graph.scroll_offset) / graph.zoom
	_search.text = ""
	_populate_types()
	_picker.popup_centered(Vector2i(340, 360))
	_search.grab_focus()

func _populate_types() -> void:
	_types.clear()
	var current = document.get_graph(graph.graph_id)
	if current == null:
		return
	for definition in registry.list_definitions(current.kind):
		if definition.type_id in ["gel.project_start", "gel.graph_input"]:
			continue
		var caption: String = "%s / %s" % [definition.category, definition.display_name]
		if not _search.text.is_empty() and not (_search.text.to_lower() in (caption + definition.type_id).to_lower()):
			continue
		var index := _types.add_item(caption)
		_types.set_item_metadata(index, definition.type_id)
		_types.set_item_tooltip(index, definition.type_id)
	if _types.item_count > 0:
		_types.select(0)
	$NodePicker/Contents/Add.disabled = _types.item_count == 0

func _add_selected_type() -> void:
	var indices := _types.get_selected_items()
	if indices.is_empty():
		return
	var type_id: String = _types.get_item_metadata(indices[0])
	_picker.hide()
	add_node_type(type_id, _add_position)

func add_node_type(type_id: String, at: Vector2) -> Dictionary:
	var result: Dictionary = controller.execute({"op": "create_node", "type_id": type_id, "graph_id": graph.graph_id, "position": at})
	graph.request_refresh()
	return result

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or (focus != null and not is_ancestor_of(focus)):
		return
	if event.is_command_or_control_pressed() and event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo()
		else:
			_undo()
	elif event.is_command_or_control_pressed() and event.keycode == KEY_Y:
		_redo()
	elif event.keycode == KEY_DELETE:
		graph.delete_selection()
	else:
		return
	get_viewport().set_input_as_handled()
