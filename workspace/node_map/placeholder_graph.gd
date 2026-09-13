@tool
extends GraphEdit

## 仅用于内存中的显示占位，不是 NodeGraph 或文档适配器。
signal scene_requested(scene_key: StringName)
signal selection_changed(title: String)
signal connections_changed(count: int)

const FLOW := 0

var _initial_positions: Dictionary = {}
var _initial_connections: Array[Dictionary] = []
var _pending_double_click_scene: StringName = &""

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_initial_connections = get_connection_list().duplicate(true)
	for node in get_graph_nodes():
		_initial_positions[node.name] = node.position_offset
		if node.has_node("OpenScene"):
			var target := StringName(node.get_meta("preview_target", ""))
			node.get_node("OpenScene").pressed.connect(_request_scene.bind(target))
			node.gui_input.connect(_on_node_input.bind(target))
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	node_selected.connect(_on_selection_changed)
	node_deselected.connect(_on_deselection_changed)

func get_graph_nodes() -> Array[GraphNode]:
	var nodes: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode:
			nodes.append(child)
	return nodes

func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var curve := Curve2D.new()
	if to_position.x > from_position.x:
		var handle := Vector2((to_position.x - from_position.x) * connection_lines_curvature, 0)
		curve.add_point(from_position, Vector2.ZERO, handle)
		curve.add_point(to_position, -handle)
	else:
		# 小地图和拖线使用平移后的坐标，因此按端口计算相对绕行间距。
		var output_clearance := 0.0
		var input_clearance := 0.0
		for node in get_graph_nodes():
			for port in range(node.get_output_port_count()):
				output_clearance = maxf(output_clearance, node.size.y - node.get_output_port_position(port).y)
			for port in range(node.get_input_port_count()):
				input_clearance = maxf(input_clearance, node.size.y - node.get_input_port_position(port).y)
		var lane_y := maxf(from_position.y + output_clearance * zoom, to_position.y + input_clearance * zoom) + 48 * zoom
		var bend := 44 * zoom
		curve.add_point(from_position, Vector2.ZERO, Vector2(bend, 0))
		curve.add_point(Vector2(from_position.x + bend, lane_y), Vector2(0, -bend), Vector2(-bend, 0))
		curve.add_point(Vector2(to_position.x - bend, lane_y), Vector2(bend, 0), Vector2(0, -bend))
		curve.add_point(to_position, Vector2(-bend, 0))
	return curve.tessellate(5, 2.0)

func frame_all() -> void:
	var nodes := get_graph_nodes()
	if nodes.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	var bounds := Rect2(nodes[0].position_offset, nodes[0].size)
	for node in nodes:
		bounds = bounds.merge(Rect2(node.position_offset, node.size))
	for link in get_connection_list():
		var source := get_node(NodePath(link.from_node)) as GraphNode
		var target := get_node(NodePath(link.to_node)) as GraphNode
		var from := (source.position_offset + source.get_output_port_position(link.from_port)) * zoom
		var to := (target.position_offset + target.get_input_port_position(link.to_port)) * zoom
		for point in get_connection_line(from, to):
			bounds = bounds.expand(point / zoom)
	# 为 GraphEdit 原生工具栏和小地图预留空间。
	var available := (size - Vector2(96, 160)).max(Vector2(1, 1))
	zoom = clampf(minf(available.x / bounds.size.x, available.y / bounds.size.y), zoom_min, 1.0)
	scroll_offset = bounds.get_center() * zoom - size * 0.5 + Vector2(0, 12)

func reset_preview() -> void:
	clear_connections()
	for node in get_graph_nodes():
		node.position_offset = _initial_positions[node.name]
		node.selected = false
	for link in _initial_connections:
		connect_node(link.from_node, link.from_port, link.to_node, link.to_port)
	selection_changed.emit("")
	connections_changed.emit(get_connection_list().size())
	frame_all()

func _request_scene(scene_key: StringName) -> void:
	# 在本次输入处理结束后切换图，避免中断 GraphNode 的输入状态。
	call_deferred("_emit_scene_request", scene_key)

func _on_node_input(event: InputEvent, scene_key: StringName) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and event.double_click:
		# 等待原生节点处理鼠标释放事件，避免返回根图时残留拖动状态。
		_pending_double_click_scene = scene_key
	elif not event.pressed and _pending_double_click_scene == scene_key:
		var requested_scene := _pending_double_click_scene
		_pending_double_click_scene = &""
		call_deferred("_emit_scene_request", requested_scene)

func _emit_scene_request(scene_key: StringName) -> void:
	scene_requested.emit(scene_key)

func _on_selection_changed(node: Node) -> void:
	if node is GraphNode:
		selection_changed.emit(node.title)

func _on_deselection_changed(_node: Node) -> void:
	for node in get_graph_nodes():
		if node.selected:
			selection_changed.emit(node.title)
			return
	selection_changed.emit("")

func _on_connection_request(from: StringName, output: int, to: StringName, input: int) -> void:
	# 仅检查显示占位的局部一致性，不保证流程可以导出。
	var source := get_node_or_null(NodePath(from)) as GraphNode
	var target := get_node_or_null(NodePath(to)) as GraphNode
	if source == null or target == null:
		return
	if output < 0 or output >= source.get_output_port_count() or input < 0 or input >= target.get_input_port_count():
		return
	var port_type := source.get_output_port_type(output)
	if port_type != target.get_input_port_type(input):
		return
	if is_node_connected(from, output, to, input):
		return
	for link in get_connection_list():
		if port_type == FLOW and link.from_node == from and link.from_port == output:
			return
		if port_type != FLOW and link.to_node == to and link.to_port == input:
			return
	if connect_node(from, output, to, input) == OK:
		connections_changed.emit(get_connection_list().size())

func _on_disconnection_request(from: StringName, output: int, to: StringName, input: int) -> void:
	if not is_node_connected(from, output, to, input):
		return
	disconnect_node(from, output, to, input)
	connections_changed.emit(get_connection_list().size())
