extends GraphEdit

## 图视图只把整数端口下标转换为稳定 ID，所有合法性由文档判断。
signal command_requested(command: Dictionary)
signal scene_requested(graph_id: String)
signal selection_changed

const NODE_SCENE := preload("res://workspace/node_map/node_map_node_view.tscn")
var document
var registry
var widgets
var presentations
var graph_id := ""
var _views: Dictionary = {}
var _view_names: Dictionary = {}
var _view_sequence := 0
var _dragging := false
var _refresh_pending := false

func _ready() -> void:
	connection_request.connect(_connect_requested)
	disconnection_request.connect(_disconnect_requested)
	begin_node_move.connect(func(): _dragging = true)
	end_node_move.connect(_move_finished)
	delete_nodes_request.connect(func(_names): delete_selection())
	duplicate_nodes_request.connect(duplicate_selection)
	node_selected.connect(func(_node): selection_changed.emit())
	node_deselected.connect(func(_node): selection_changed.emit())

func configure(p_document, p_registry, p_widgets, p_presentations) -> void:
	document = p_document
	registry = p_registry
	widgets = p_widgets
	presentations = p_presentations

func show_graph(id: String) -> void:
	finish_edits()
	graph_id = id
	refresh()

func request_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_flush_refresh")

func _flush_refresh() -> void:
	_refresh_pending = false
	if not _dragging:
		refresh()

func refresh() -> void:
	if document == null or document.get_graph(graph_id) == null:
		return
	clear_connections()
	var present: Dictionary = {}
	for model in document.get_nodes(graph_id):
		present[model.node_id] = true
	for id in _views.keys():
		if not present.has(id):
			var old: GraphNode = _views[id]
			_view_names.erase(str(old.name))
			remove_child(old)
			old.queue_free()
			_views.erase(id)
	for model in document.get_nodes(graph_id):
		if not _views.has(model.node_id):
			var view = NODE_SCENE.instantiate()
			_view_sequence += 1
			view.name = "Node_%d" % _view_sequence
			add_child(view)
			view.configure(model.node_id, document, registry.get_definition(model.node_type), widgets, presentations)
			view.command_requested.connect(func(command): command_requested.emit(command))
			view.scene_requested.connect(func(id): scene_requested.emit(id))
			_views[model.node_id] = view
			_view_names[str(view.name)] = model.node_id
		_views[model.node_id].sync_from_document()
	for link in document.get_links(graph_id):
		var source = _views.get(link.source_node_id)
		var target = _views.get(link.target_node_id)
		if source == null or target == null:
			continue
		var output: int = source.output_port_ids.find(link.source_port_id)
		var input: int = target.input_port_ids.find(link.target_port_id)
		if output >= 0 and input >= 0:
			connect_node(source.name, output, target.name, input)
	selection_changed.emit()

func get_node_view(id: String):
	return _views.get(id)

func get_graph_nodes() -> Array:
	return _views.values()

func get_selected_ids() -> Array:
	var ids: Array = []
	for id in _views:
		if _views[id].selected:
			ids.append(id)
	return ids

func finish_edits() -> void:
	for view in _views.values():
		view.finish_edits()

func delete_selection() -> void:
	var ids := get_selected_ids()
	if not ids.is_empty():
		command_requested.emit({"op": "remove_nodes", "node_ids": ids})

func duplicate_selection() -> void:
	var ids := get_selected_ids()
	if not ids.is_empty():
		command_requested.emit({"op": "duplicate_nodes", "node_ids": ids})

func _move_finished() -> void:
	_dragging = false
	var positions: Dictionary = {}
	for id in _views:
		var model = document.get_node(id)
		if model != null and not model.position.is_equal_approx(_views[id].position_offset):
			positions[id] = _views[id].position_offset
	if not positions.is_empty():
		command_requested.emit({"op": "move_nodes", "positions": positions})
	request_refresh()

func _endpoints(from: StringName, output: int, to: StringName, input: int) -> Dictionary:
	var source = _views.get(_view_names.get(str(from), ""))
	var target = _views.get(_view_names.get(str(to), ""))
	if source == null or target == null:
		return {}
	if output < 0 or input < 0 or output >= source.output_port_ids.size() or input >= target.input_port_ids.size():
		return {}
	return {"graph_id": graph_id, "source_node_id": source.node_id, "source_port_id": source.output_port_ids[output], "target_node_id": target.node_id, "target_port_id": target.input_port_ids[input]}

func _connect_requested(from: StringName, output: int, to: StringName, input: int) -> void:
	var command := _endpoints(from, output, to, input)
	if not command.is_empty():
		command["op"] = "connect"
		command_requested.emit(command)

func _disconnect_requested(from: StringName, output: int, to: StringName, input: int) -> void:
	var endpoints := _endpoints(from, output, to, input)
	if endpoints.is_empty():
		return
	for link in document.get_links(graph_id):
		if link.source_node_id == endpoints.source_node_id and link.source_port_id == endpoints.source_port_id and link.target_node_id == endpoints.target_node_id and link.target_port_id == endpoints.target_port_id:
			command_requested.emit({"op": "disconnect", "link_id": link.link_id})
			return

func frame_all() -> void:
	var nodes := get_graph_nodes()
	if nodes.is_empty() or size.x < 1 or size.y < 1:
		return
	var bounds := Rect2(nodes[0].position_offset, nodes[0].size)
	for node in nodes:
		bounds = bounds.merge(Rect2(node.position_offset, node.size))
	for link in get_connection_list():
		var source: GraphNode = get_node(NodePath(link.from_node))
		var target: GraphNode = get_node(NodePath(link.to_node))
		var from := (source.position_offset + source.get_output_port_position(link.from_port)) * zoom
		var to := (target.position_offset + target.get_input_port_position(link.to_port)) * zoom
		for point in get_connection_line(from, to):
			bounds = bounds.expand(point / zoom)
	var available := (size - Vector2(96, 160)).max(Vector2.ONE)
	zoom = clampf(minf(available.x / maxf(bounds.size.x, 1), available.y / maxf(bounds.size.y, 1)), zoom_min, 1)
	scroll_offset = bounds.get_center() * zoom - size * 0.5 + Vector2(0, 12)

func _get_connection_line(from: Vector2, to: Vector2) -> PackedVector2Array:
	var curve := Curve2D.new()
	if to.x > from.x:
		var handle := Vector2((to.x - from.x) * connection_lines_curvature, 0)
		curve.add_point(from, Vector2.ZERO, handle)
		curve.add_point(to, -handle)
	else:
		# 回连按节点高度预留绕行空间；这不是任意图的自动避障布线。
		var clearance := 40.0
		for node in get_graph_nodes():
			clearance = maxf(clearance, node.size.y)
		var lane := maxf(from.y, to.y) + (clearance + 40) * zoom
		var bend := 44 * zoom
		curve.add_point(from, Vector2.ZERO, Vector2(bend, 0))
		curve.add_point(Vector2(from.x + bend, lane), Vector2(0, -bend), Vector2(-bend, 0))
		curve.add_point(Vector2(to.x - bend, lane), Vector2(bend, 0), Vector2(0, -bend))
		curve.add_point(to, Vector2(-bend, 0))
	return curve.tessellate(5, 2)
