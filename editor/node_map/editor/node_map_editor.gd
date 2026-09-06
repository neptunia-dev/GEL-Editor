extends Control
class_name NodeMapEditor

const SceneNodeModel = preload("res://node_map/scene_node.gd")
const SceneMapModel = preload("res://node_map/map/scene_map.gd")
const RouteEdgeModel = preload("res://node_map/map/route_edge.gd")
const ExitPortModel = preload("res://node_map/exit_port.gd")
const SceneGraphNodeScene = preload("res://node_map/editor/scene_graph_node.tscn")
const DocumentModel = preload("res://node_map/persistence/node_map_document.gd")

signal changed

@onready var graph_edit: GraphEdit = $Layout/GraphEdit
@onready var status_label: Label = $Layout/Status
@onready var selection_label: Label = $Layout/Inspector/SelectionLabel
@onready var scene_id_edit: LineEdit = $Layout/Inspector/SceneId
@onready var title_edit: LineEdit = $Layout/Inspector/Title
@onready var script_edit: LineEdit = $Layout/Inspector/MainScript
@onready var exit_name_edit: LineEdit = $Layout/Inspector/ExitRow/ExitName
@onready var document_path_edit: LineEdit = $Layout/Toolbar/DocumentPath
@onready var exit_list: VBoxContainer = $Layout/Inspector/ExitList
@onready var diagnostics_view: RichTextLabel = $Layout/Diagnostics

var scene_map: SceneMap
var document = DocumentModel.new()
var graph_nodes: Dictionary = {}
var edge_views: Dictionary = {}
var _next_number := 1
var history := NodeMapHistory.new()
var _refreshing := false
var _moving := false
var _pending_action: Callable
var file_dialog := FileDialog.new()
var unsaved_dialog := ConfirmationDialog.new()
var context_menu := PopupMenu.new()
var advanced: NodeMapInspector

func _ready() -> void:
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	$Layout/Toolbar/AddNode.pressed.connect(add_default_node)
	$Layout/Toolbar/DeleteNode.pressed.connect(delete_selected_node)
	$Layout/Toolbar/SetEntry.pressed.connect(set_selected_entry)
	$Layout/Toolbar/Validate.pressed.connect(validate)
	$Layout/Toolbar/Save.pressed.connect(save_document)
	$Layout/Toolbar/Load.pressed.connect(load_document)
	$Layout/Inspector/ExitRow/AddExit.pressed.connect(add_exit_to_selected)
	scene_id_edit.text_submitted.connect(_on_scene_id_submitted)
	title_edit.text_submitted.connect(_on_title_submitted)
	script_edit.text_submitted.connect(_on_script_submitted)
	graph_edit.node_selected.connect(_on_graph_node_selected)
	graph_edit.node_deselected.connect(func(_node): _refresh_selection.call_deferred())
	graph_edit.begin_node_move.connect(func(): _moving = true)
	graph_edit.end_node_move.connect(_finish_move)
	_setup_controls()
	if scene_map == null:
		bind_scene_map(SceneMap.new())

func bind_scene_map(value: SceneMap) -> void:
	scene_map = value.duplicate_map()
	document.scene_map = scene_map
	history.reset(scene_map)
	document.mark_clean()
	_refresh_graph()

func get_scene_map() -> SceneMap:
	return scene_map.duplicate_map()

func add_default_node() -> bool:
	if scene_map == null:
		return false
	var node_id := "node-%d" % _next_number
	var scene_id := "scene-%d" % _next_number
	while scene_map.has_node(node_id) or scene_map.get_nodes().any(func(n): return n.scene_id == scene_id):
		_next_number += 1
		node_id = "node-%d" % _next_number
		scene_id = "scene-%d" % _next_number
	_next_number += 1
	var node := SceneNodeModel.new(node_id, scene_id, "New Scene", "scenes/%s/main.lua" % scene_id, [], [], (graph_edit.scroll_offset + graph_edit.size / 2) / graph_edit.zoom)
	if not scene_map.add_node(node):
		_show_error(scene_map.last_error)
		return false
	_refresh_graph()
	select_node(node_id)
	_commit()
	return true

func add_exit_to_selected() -> bool:
	var selected := _selected_view()
	var name := exit_name_edit.text.strip_edges()
	if selected == null or name.is_empty():
		_show_error("Select a Scene and enter an exit name")
		return false
	var node := scene_map.get_node(selected.model_node_id)
	var port := ExitPortModel.new(_new_id("port"), name)
	if not node.add_exit(port) or not scene_map.update_node(node):
		_show_error(node.last_error if not node.last_error.is_empty() else scene_map.last_error)
		return false
	exit_name_edit.clear()
	_refresh_graph()
	_commit()
	return true

func save_document() -> bool:
	var path := document_path_edit.text.strip_edges()
	if path.is_empty():
		_show_file_dialog(true)
		return false
	document.scene_map = scene_map
	if not document.save_as(path):
		_show_error(document.last_error)
		return false
	status_label.text = "Saved: %s" % path
	history.mark_saved(scene_map)
	_sync_dirty()
	return true

func load_document() -> bool:
	var path := document_path_edit.text.strip_edges()
	if path.is_empty():
		_show_file_dialog(false)
		return false
	if document.is_dirty:
		_guard(func(): _load_path(path))
		return false
	return _load_path(path)

func _load_path(path: String) -> bool:
	if not document.load_file(path):
		_show_error(document.last_error if not document.last_error.is_empty() else "Enter a JSON path before loading")
		return false
	scene_map = document.scene_map
	history.reset(scene_map)
	_refresh_graph()
	status_label.text = "Loaded: %s" % path
	document_path_edit.text = path
	_sync_dirty()
	return true

func delete_selected_node() -> bool:
	var selected := _selected_view()
	if selected == null:
		return false
	for view in graph_nodes.values():
		if view.selected and not scene_map.remove_node(view.model_node_id):
			_show_error(scene_map.last_error)
			return false
	_refresh_graph()
	_commit()
	return true

func set_selected_entry() -> bool:
	var selected := _selected_view()
	if selected == null or not scene_map.set_entry_node(selected.model_node_id):
		_show_error(scene_map.last_error if scene_map != null else "No node selected")
		return false
	_refresh_graph()
	_commit()
	return true

func validate() -> Array:
	var diagnostics := scene_map.get_diagnostics() if scene_map != null else []
	var messages: Array[String] = []
	for diagnostic in diagnostics:
		messages.append("%s: %s" % [diagnostic["severity"], diagnostic["message"]])
	status_label.text = "\n".join(messages)
	_refresh_diagnostics()
	return diagnostics

func _refresh_graph() -> void:
	if graph_edit == null or scene_map == null:
		return
	_refreshing = true
	graph_edit.clear_connections()
	for id in graph_nodes.keys():
		if not scene_map.has_node(id):
			var old: GraphNode = graph_nodes[id]
			graph_edit.remove_child(old)
			old.queue_free()
			graph_nodes.erase(id)
	edge_views.clear()
	for node in scene_map.get_nodes():
		if graph_nodes.has(node.node_id):
			var existing: SceneGraphNodeView = graph_nodes[node.node_id]
			if existing._model.to_editor_dict() != node.to_editor_dict() or existing._entry != (node.node_id == scene_map.get_entry_node_id()):
				existing.refresh_from_model(node, node.node_id == scene_map.get_entry_node_id())
			existing.position_offset = node.position
			continue
		var view: SceneGraphNodeView = SceneGraphNodeScene.instantiate()
		view.name = _view_name(node.node_id)
		view.position_offset = node.position
		view.bind_scene_node(node, node.node_id == scene_map.get_entry_node_id())
		view.move_committed.connect(_on_node_move_committed)
		view.position_offset_changed.connect(_on_graph_node_position_changed.bind(node.node_id))
		graph_edit.add_child(view)
		graph_nodes[node.node_id] = view
	for edge in scene_map.get_routes():
		_connect_edge_view(edge)
	_refreshing = false
	_refresh_selection()
	_refresh_diagnostics()

func _on_graph_node_position_changed(node_id: String) -> void:
	var view: SceneGraphNodeView = graph_nodes.get(node_id)
	if view == null or view.dragging or _refreshing or _moving:
		return
	_on_node_move_committed(node_id, view.position_offset)

func _connect_edge_view(edge: RouteEdge) -> void:
	if not graph_nodes.has(edge.source_node_id) or not graph_nodes.has(edge.target_node_id):
		return
	var source: SceneGraphNodeView = graph_nodes[edge.source_node_id]
	var source_port := _source_port_index(source, edge)
	if source_port < 0:
		return
	var from_name: String = source.name
	var to_name: String = (graph_nodes[edge.target_node_id] as GraphNode).name
	graph_edit.connect_node(from_name, source_port, to_name, 0)
	edge_views[edge.source_endpoint_key()] = edge.edge_id

func _source_port_index(source: SceneGraphNodeView, edge: RouteEdge) -> int:
	return source.find_port_index(edge.source_endpoint_key())

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var source := _view_by_name(str(from_node))
	var target := _view_by_name(str(to_node))
	if source == null or target == null or to_port != 0:
		_show_error("Invalid route endpoint")
		return
	if from_port < 0 or from_port >= source.endpoints.size():
		_show_error("Invalid source port")
		return
	var endpoint: Dictionary = source.endpoints[from_port]
	var edge: RouteEdge
	if endpoint.kind == RouteEdge.SOURCE_SCENE_EXIT:
		edge = RouteEdgeModel.new(_new_edge_id(), source.model_node_id, endpoint.port_id, target.model_node_id)
	else:
		edge = RouteEdge.from_condition_branch(_new_edge_id(), source.model_node_id, endpoint.wrapper_id, endpoint.branch_id, target.model_node_id)
	if not scene_map.add_route(edge):
		_show_error(scene_map.last_error)
		return
	graph_edit.connect_node(from_node, from_port, to_node, to_port)
	edge_views[edge.source_endpoint_key()] = edge.edge_id
	_commit()

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var source := _view_by_name(str(from_node))
	if source == null:
		return
	var key := source.get_endpoint_key_for_port(from_port)
	var edge_id: String = edge_views.get(key, "")
	if edge_id.is_empty() or not scene_map.remove_route(edge_id):
		_show_error(scene_map.last_error)
		return
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	edge_views.erase(key)
	_commit()

func _on_node_move_committed(node_id: String, new_position: Vector2) -> void:
	if _moving or _refreshing:
		return
	var node := scene_map.get_node(node_id)
	if node == null:
		return
	node.set_position(new_position)
	if not scene_map.update_node(node):
		_show_error(scene_map.last_error)
		_refresh_graph()
		return
	_commit()

func _selected_view() -> SceneGraphNodeView:
	for node_id in graph_nodes:
		var view: SceneGraphNodeView = graph_nodes[node_id]
		if view.selected:
			return view
	return null

func _on_graph_node_selected(node: Node) -> void:
	var view := node as SceneGraphNodeView
	if view == null:
		return
	var model := scene_map.get_node(view.model_node_id)
	if model == null:
		return
	selection_label.text = "Selected: %s" % model.scene_id
	scene_id_edit.text = model.scene_id
	title_edit.text = model.title
	script_edit.text = model.main_script
	_refresh_exit_list(model)
	advanced.bind_node(model)

func _refresh_exit_list(node: SceneNode) -> void:
	for child in exit_list.get_children():
		exit_list.remove_child(child)
		child.queue_free()
	for port in node.get_exits():
		var row := HBoxContainer.new()
		var name_edit := LineEdit.new()
		name_edit.text = port.name
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text_submitted.connect(_on_exit_name_submitted.bind(node.node_id, port.port_id))
		row.add_child(name_edit)
		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(_delete_exit.bind(node.node_id, port.port_id))
		row.add_child(delete_button)
		exit_list.add_child(row)

func _on_exit_name_submitted(value: String, node_id: String, port_id: String) -> void:
	var node := scene_map.get_node(node_id)
	if node == null or not node.rename_exit(port_id, value) or not scene_map.update_node(node):
		_show_error(node.last_error if node != null and not node.last_error.is_empty() else scene_map.last_error)
		return
	_refresh_graph()
	_commit()

func _delete_exit(node_id: String, port_id: String) -> void:
	if not scene_map.remove_exit(node_id, port_id):
		_show_error(scene_map.last_error)
		return
	_refresh_graph()
	_commit()

func _on_scene_id_submitted(value: String) -> void:
	_update_selected_node(func(node): return node.rename_scene(value))

func _on_title_submitted(value: String) -> void:
	_update_selected_node(func(node): return node.set_title(value))

func _on_script_submitted(value: String) -> void:
	_update_selected_node(func(node): return node.set_main_script(value))

func _update_selected_node(operation: Callable) -> void:
	var selected := _selected_view()
	if selected == null:
		return
	var node := scene_map.get_node(selected.model_node_id)
	if not operation.call(node) or not scene_map.update_node(node):
		_show_error(node.last_error if not node.last_error.is_empty() else scene_map.last_error)
		return
	_refresh_graph()
	_commit()

func _view_by_name(value: String) -> SceneGraphNodeView:
	for node_id in graph_nodes:
		var view: SceneGraphNodeView = graph_nodes[node_id]
		if view.name == value:
			return view
	return null

func _view_name(node_id: String) -> String:
	return "Scene_%s" % node_id.to_utf8_buffer().hex_encode()

func _new_edge_id() -> String:
	return _new_id("edge")

func _new_id(prefix: String) -> String:
	return "%s-%d" % [prefix, Time.get_ticks_usec()]

func _show_error(message: String) -> void:
	status_label.text = message
	_refresh_diagnostics()


func _refresh_diagnostics() -> void:
	if diagnostics_view == null or scene_map == null:
		return
	var lines: Array[String] = []
	for diagnostic in scene_map.get_diagnostics():
		lines.append("[%s] %s" % [diagnostic["severity"], diagnostic["message"]])
	diagnostics_view.text = "\n".join(lines)

func _setup_controls() -> void:
	# Keep the inspector scrollable without shrinking the graph as rows are added.
	var inspector := $Layout/Inspector
	var scroll := ScrollContainer.new()
	scroll.name = "InspectorScroll"
	scroll.custom_minimum_size.y = 220
	$Layout.remove_child(inspector)
	$Layout.add_child(scroll)
	$Layout.move_child(scroll, 2)
	scroll.add_child(inspector)
	inspector.size_flags_horizontal = SIZE_EXPAND_FILL
	advanced = NodeMapInspector.new()
	advanced.editor = self
	inspector.add_child(advanced)
	graph_edit.custom_minimum_size.y = 160
	diagnostics_view.fit_content = false
	add_child(file_dialog)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Node Map JSON"])
	file_dialog.file_selected.connect(func(path):
		document_path_edit.text = path
		if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
			if save_document() and _pending_action.is_valid():
				_run_pending()
			else:
				_pending_action = Callable()
		else:
			load_document())
	file_dialog.canceled.connect(func(): _pending_action = Callable())
	add_child(unsaved_dialog)
	unsaved_dialog.dialog_text = "This document has unsaved changes."
	unsaved_dialog.ok_button_text = "Discard"
	unsaved_dialog.add_button("Save", false, "save")
	unsaved_dialog.confirmed.connect(_run_pending)
	unsaved_dialog.canceled.connect(func(): _pending_action = Callable())
	unsaved_dialog.custom_action.connect(func(_action):
		unsaved_dialog.hide()
		# Saving before Open must save the current document, not overwrite the
		# target path the user just entered for loading.
		document_path_edit.text = document.file_path
		if save_document():
			_run_pending()
		elif not file_dialog.visible:
			_pending_action = Callable())
	add_child(context_menu)
	for label in ["Add Scene", "Delete Selected", "Set Entry", "Focus All", "Auto Layout"]:
		context_menu.add_item(label)
	context_menu.id_pressed.connect(func(id):
		[add_default_node, delete_selected_node, set_selected_entry, focus_nodes.bind(false), auto_layout][id].call())
	graph_edit.popup_request.connect(func(at):
		context_menu.position = Vector2i(graph_edit.global_position + at)
		context_menu.popup())
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(request_quit)

func _show_file_dialog(saving: bool) -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.7)

func _guard(action: Callable) -> void:
	if not document.is_dirty:
		action.call()
		return
	_pending_action = action
	unsaved_dialog.popup_centered()

func _run_pending() -> void:
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid(): action.call()

func can_close() -> bool:
	return not document.is_dirty

func close_document() -> bool:
	_guard(func():
		bind_scene_map(SceneMap.new())
		document.file_path = ""
		document_path_edit.clear()
		_sync_dirty())
	return can_close()

func request_quit() -> void:
	_guard(func(): get_tree().quit())

func _commit() -> void:
	if history.record(scene_map):
		_sync_dirty()
		_refresh_diagnostics()
		changed.emit()

func _sync_dirty() -> void:
	document.is_dirty = history.is_dirty(scene_map)
	$Layout/Toolbar/Save.text = "Save *" if document.is_dirty else "Save"

func undo() -> void:
	_restore(history.undo())

func redo() -> void:
	_restore(history.redo())

func _restore(map: SceneMap) -> void:
	if map == null: return
	scene_map = map
	document.scene_map = map
	_refresh_graph()
	_sync_dirty()
	changed.emit()

func _finish_move() -> void:
	for id in graph_nodes:
		var node := scene_map.get_node(id)
		node.set_position(graph_nodes[id].position_offset)
		if not scene_map.update_node(node): _show_error(scene_map.last_error)
	_moving = false
	_commit()

func select_node(id: String) -> void:
	for key in graph_nodes:
		graph_nodes[key].selected = key == id
	_refresh_selection()

func _refresh_selection() -> void:
	var selected := _selected_view()
	if selected != null:
		_on_graph_node_selected(selected)
	else:
		selection_label.text = "No Scene selected"
		for edit in [scene_id_edit, title_edit, script_edit]: edit.clear()
		for child in exit_list.get_children():
			exit_list.remove_child(child)
			child.queue_free()
		advanced.bind_node(null)

func apply_tree(tree: ConditionTree) -> void:
	_update_selected_node(func(node): return node.set_condition_tree(tree))

func remove_condition(kind: String, id: String) -> void:
	var selected := _selected_view()
	if selected == null: return
	var node_id := selected.model_node_id
	var ok := false
	match kind:
		"tree": ok = scene_map.clear_condition_tree(node_id)
		"wrapper": ok = scene_map.remove_condition_wrapper(node_id, id)
		"branch": ok = scene_map.remove_condition_branch(node_id, id)
	if not ok:
		_show_error(scene_map.last_error)
		return
	_refresh_graph()
	_commit()

func focus_nodes(selected_only: bool = false) -> void:
	var bounds := Rect2()
	var found := false
	for view in graph_nodes.values():
		if selected_only and not view.selected: continue
		var rect := Rect2(view.position_offset, view.size)
		bounds = bounds.merge(rect) if found else rect
		found = true
	if not found: return
	graph_edit.zoom = clampf(minf(graph_edit.size.x / (bounds.size.x + 100), graph_edit.size.y / (bounds.size.y + 100)), graph_edit.zoom_min, 1.0)
	graph_edit.scroll_offset = bounds.get_center() * graph_edit.zoom - graph_edit.size / 2

func auto_layout() -> void:
	var nodes := scene_map.get_nodes()
	nodes.sort_custom(func(a, b): return a.scene_id < b.scene_id)
	var levels: Dictionary = {}
	var pending: Array = []
	var entry := scene_map.get_entry_node_id()
	if scene_map.has_node(entry):
		levels[entry] = 0
		pending.append(entry)
	var routes := scene_map.get_routes()
	var cursor := 0
	while cursor < pending.size():
		var id: String = pending[cursor]
		cursor += 1
		for edge in routes:
			if edge.source_node_id == id and not levels.has(edge.target_node_id):
				levels[edge.target_node_id] = levels[id] + 1
				pending.append(edge.target_node_id)
	var rows: Dictionary = {}
	var unreachable := 0
	for node in nodes:
		if levels.has(node.node_id):
			var level: int = levels[node.node_id]
			var row: int = rows.get(level, 0)
			node.set_position(Vector2(level * 420, row * 360))
			rows[level] = row + 1
		else:
			node.set_position(Vector2(-480, unreachable * 360))
			unreachable += 1
		scene_map.update_node(node)
	_refresh_graph()
	_commit()
	focus_nodes()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if focus != null and focus != self and not is_ancestor_of(focus): return
	if file_dialog.visible or unsaved_dialog.visible: return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed: redo()
				else: undo()
			KEY_S: save_document()
			_: return
	else:
		if focus != graph_edit and not (focus != null and graph_edit.is_ancestor_of(focus)): return
		match event.keycode:
			KEY_DELETE: delete_selected_node()
			KEY_F: focus_nodes(true)
			KEY_A: focus_nodes(false)
			_: return
	get_viewport().set_input_as_handled()
