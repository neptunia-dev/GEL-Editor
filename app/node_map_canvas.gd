extends GraphEdit
class_name NodeMapCanvas

const SCENE_NODE_VIEW_SCRIPT := preload("res://app/scene_node_view.gd")

signal endpoint_connection_requested(endpoint: Dictionary, target_node_id: String)
signal route_disconnection_requested(edge_id: String)
signal scenes_deletion_requested(node_ids: Array)
signal node_positions_committed(positions: Dictionary)
signal object_selected(kind: String, stable_id: Variant)
signal add_scene_requested(graph_position: Vector2)
signal root_wrapper_requested(node_id: String, wrapper_kind: String)

const POPUP_ADD_SCENE := 1
const POPUP_ADD_IF_WRAPPER := 101
const POPUP_ADD_SWITCH_WRAPPER := 102
const POPUP_ADD_NUMERIC_WRAPPER := 103
const HOVER_DISTANCE := 10.0
const PORT_HOTZONE_HALF_SIZE := Vector2(30, 22)

var _scene_map: SceneMap = SceneMap.new()
var _views: Dictionary = {}
var _connection_edges: Dictionary = {}
var _hover_connection: Dictionary = {}
var _hover_edge_id: String = ""
var _selected_edge_id: String = ""
var _popup_position: Vector2 = Vector2.ZERO
var _popup: PopupMenu
var _node_popup: PopupMenu
var _context_node_id: String = ""
var _connection_drag_origin: Dictionary = {}

func _ready() -> void:
    show_grid = true
    grid_pattern = GraphEdit.GRID_PATTERN_LINES
    snapping_enabled = false
    snapping_distance = 20
    minimap_enabled = true
    minimap_opacity = 0.7
    minimap_size = Vector2(210, 140)
    panning_scheme = GraphEdit.SCROLL_ZOOMS
    right_disconnects = true
    connection_lines_antialiased = true
    connection_lines_curvature = 0.45
    connection_lines_thickness = 3.0
    zoom_min = 0.35
    zoom_max = 2.5
    zoom_step = 1.15
    show_menu = true
    show_arrange_button = false
    _apply_theme()
    _create_popup()
    _create_node_popup()

    connection_request.connect(_on_connection_request)
    connection_drag_started.connect(_on_connection_drag_started)
    connection_drag_ended.connect(_on_connection_drag_ended)
    disconnection_request.connect(_on_disconnection_request)
    delete_nodes_request.connect(_on_delete_nodes_request)
    end_node_move.connect(_on_end_node_move)
    node_selected.connect(_on_node_selected)
    node_deselected.connect(_on_node_deselected)
    popup_request.connect(_on_popup_request)

func set_scene_map(scene_map: SceneMap) -> void:
    _scene_map = scene_map.duplicate_map() if scene_map != null else SceneMap.new()
    _sync_views()
    _reconnect_edges()

func get_scene_view(node_id: String):
    return _views.get(node_id)

func get_view_count() -> int:
    return _views.size()

func get_selected_edge_id() -> String:
    return _selected_edge_id

func get_hover_edge_id() -> String:
    return _hover_edge_id

func get_context_node_id() -> String:
    return _context_node_id

func center_on_selection() -> void:
    var selected_views: Array = []
    for view in _views.values():
        if view.selected:
            selected_views.append(view)
    if selected_views.is_empty():
        return
    var bounds := Rect2(selected_views[0].position_offset, selected_views[0].size)
    for view in selected_views.slice(1):
        var node_view = view
        bounds = bounds.merge(Rect2(node_view.position_offset, node_view.size))
    scroll_offset = bounds.get_center() * zoom - size * 0.5

func reset_view() -> void:
    zoom = 1.0
    scroll_offset = Vector2.ZERO

func request_delete_selection() -> void:
    if not _selected_edge_id.is_empty():
        route_disconnection_requested.emit(_selected_edge_id)
        return
    var ids: Array = []
    for view in _views.values():
        if view.selected:
            ids.append(view.node_id)
    if not ids.is_empty():
        scenes_deletion_requested.emit(ids)

func _sync_views() -> void:
    var active: Dictionary = {}
    for scene_node in _scene_map.get_nodes():
        active[scene_node.node_id] = true
        var view = _views.get(scene_node.node_id)
        if view == null:
            view = SCENE_NODE_VIEW_SCRIPT.new()
            add_child(view)
            _views[scene_node.node_id] = view
            view.inspect_requested.connect(_on_view_inspect_requested)
            view.layout_changed.connect(_on_view_layout_changed)
            view.context_menu_requested.connect(_on_view_context_menu_requested)
        view.set_scene_node(scene_node, _scene_map.get_entry_node_id() == scene_node.node_id)
    for node_id in _views.keys():
        if active.has(node_id):
            continue
        var stale = _views[node_id]
        _views.erase(node_id)
        remove_child(stale)
        stale.queue_free()

func _reconnect_edges() -> void:
    clear_connections()
    _connection_edges.clear()
    for edge in _scene_map.get_routes():
        var source_view = get_scene_view(edge.source_node_id)
        var target_view = get_scene_view(edge.target_node_id)
        if source_view == null or target_view == null:
            continue
        var endpoint = _endpoint_from_edge(edge)
        var source_port = source_view.find_output_port(endpoint)
        if source_port < 0 or target_view.get_input_port_count() == 0:
            continue
        if connect_node(source_view.name, source_port, target_view.name, 0, true) != OK:
            continue
        _connection_edges[_connection_key(source_view.name, source_port, target_view.name, 0)] = edge.edge_id
    _restore_edge_activity()

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    var reverse := (
        not _connection_drag_origin.is_empty()
        and not bool(_connection_drag_origin.get("isOutput", true))
        and str(_connection_drag_origin.get("node", "")) == str(from_node)
        and int(_connection_drag_origin.get("port", -1)) == from_port
    )
    if reverse:
        _emit_connection_request(to_node, to_port, from_node, from_port)
    else:
        _emit_connection_request(from_node, from_port, to_node, to_port)

func _emit_connection_request(
        source_node: StringName,
        source_port: int,
        target_node: StringName,
        target_port: int,
) -> void:
    var source_view = _views.get(str(source_node))
    var target_view = _views.get(str(target_node))
    if source_view == null or target_view == null:
        return
    if source_port < 0 or source_port >= source_view.get_output_port_count():
        return
    if target_port < 0 or target_port >= target_view.get_input_port_count():
        return
    var endpoint = source_view.get_output_endpoint(source_port)
    if not endpoint.is_empty():
        endpoint_connection_requested.emit(endpoint, target_view.node_id)

func _on_connection_drag_started(from_node: StringName, from_port: int, is_output: bool) -> void:
    _connection_drag_origin = {
        "node": str(from_node),
        "port": from_port,
        "isOutput": is_output,
    }

func _on_connection_drag_ended() -> void:
    _connection_drag_origin = {}

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    var edge_id := str(_connection_edges.get(_connection_key(from_node, from_port, to_node, to_port), ""))
    if not edge_id.is_empty():
        route_disconnection_requested.emit(edge_id)

func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
    var ids: Array = []
    for node_name in nodes:
        if _views.has(str(node_name)):
            ids.append(str(node_name))
    if not ids.is_empty():
        scenes_deletion_requested.emit(ids)

func _on_end_node_move() -> void:
    var positions: Dictionary = {}
    for view in _views.values():
        var scene_view = view
        if scene_view.selected:
            positions[scene_view.node_id] = scene_view.position_offset
    if not positions.is_empty():
        node_positions_committed.emit(positions)

func _on_node_selected(node: Node) -> void:
    if _views.has(str(node.name)):
        _selected_edge_id = ""
        object_selected.emit("scene", node.node_id)

func _on_node_deselected(_node: Node) -> void:
    var has_selection := false
    for view in _views.values():
        if view.selected:
            has_selection = true
            break
    if not has_selection and _selected_edge_id.is_empty():
        object_selected.emit("none", "")

func _on_view_inspect_requested(kind: String, stable_id: Dictionary) -> void:
    _selected_edge_id = ""
    object_selected.emit(kind, stable_id)

func _on_view_layout_changed(_node_id: String) -> void:
    call_deferred("_reconnect_edges")

func _on_view_context_menu_requested(node_id: String, screen_position: Vector2) -> void:
    _context_node_id = node_id
    var scene_node := _scene_map.get_node(node_id)
    var disabled := scene_node == null or scene_node.has_condition_tree()
    for item_id in [POPUP_ADD_IF_WRAPPER, POPUP_ADD_SWITCH_WRAPPER, POPUP_ADD_NUMERIC_WRAPPER]:
        _node_popup.set_item_disabled(_node_popup.get_item_index(item_id), disabled)
    _node_popup.position = Vector2i(screen_position)
    _node_popup.popup()

func _on_node_popup_id_pressed(id: int) -> void:
    var kind := ""
    if id == POPUP_ADD_IF_WRAPPER:
        kind = "if"
    elif id == POPUP_ADD_SWITCH_WRAPPER:
        kind = "switch"
    elif id == POPUP_ADD_NUMERIC_WRAPPER:
        kind = "numeric_compare"
    if not kind.is_empty() and not _context_node_id.is_empty():
        root_wrapper_requested.emit(_context_node_id, kind)

func _on_popup_request(at_position: Vector2) -> void:
    _popup_position = at_position
    _popup.position = Vector2i(get_screen_position() + at_position)
    _popup.popup()

func _on_popup_id_pressed(id: int) -> void:
    if id == POPUP_ADD_SCENE:
        add_scene_requested.emit((_popup_position + scroll_offset) / zoom)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _update_hover((event as InputEventMouseMotion).position)
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and not _hover_edge_id.is_empty():
            _selected_edge_id = _hover_edge_id
            object_selected.emit("edge", _selected_edge_id)
            accept_event()
    elif event is InputEventKey:
        var key := event as InputEventKey
        if key.pressed and not key.echo and key.keycode == KEY_DELETE and not _selected_edge_id.is_empty():
            route_disconnection_requested.emit(_selected_edge_id)
            accept_event()

func _update_hover(point: Vector2) -> void:
    var closest := get_closest_connection_at_point(point, HOVER_DISTANCE)
    var next_edge := ""
    if not closest.is_empty():
        next_edge = str(_connection_edges.get(_connection_key(
            closest["from_node"], int(closest["from_port"]),
            closest["to_node"], int(closest["to_port"]),
        ), ""))
    if next_edge == _hover_edge_id:
        return
    _clear_hover_activity()
    _hover_connection = closest
    _hover_edge_id = next_edge
    if not _hover_edge_id.is_empty():
        set_connection_activity(
            closest["from_node"], int(closest["from_port"]),
            closest["to_node"], int(closest["to_port"]), 1.0,
        )
        tooltip_text = _edge_tooltip(_scene_map.get_route(_hover_edge_id))
    else:
        tooltip_text = ""

func _clear_hover_activity() -> void:
    if _hover_connection.is_empty():
        return
    set_connection_activity(
        _hover_connection["from_node"], int(_hover_connection["from_port"]),
        _hover_connection["to_node"], int(_hover_connection["to_port"]), 0.0,
    )
    _hover_connection = {}

func _restore_edge_activity() -> void:
    _hover_connection = {}
    _hover_edge_id = ""
    if not _selected_edge_id.is_empty() and _scene_map.get_route(_selected_edge_id) == null:
        _selected_edge_id = ""

func _endpoint_from_edge(edge: RouteEdge) -> Dictionary:
    if edge.source_kind == RouteEdge.SOURCE_SCENE_EXIT:
        return {"kind": edge.source_kind, "nodeId": edge.source_node_id, "portId": edge.source_port_id}
    return {
        "kind": edge.source_kind,
        "nodeId": edge.source_node_id,
        "wrapperId": edge.source_wrapper_id,
        "branchId": edge.source_branch_id,
    }

func _edge_tooltip(edge: RouteEdge) -> String:
    if edge == null:
        return ""
    var source_node := _scene_map.get_node(edge.source_node_id)
    var target_node := _scene_map.get_node(edge.target_node_id)
    if source_node == null or target_node == null:
        return ""
    var source_label := edge.source_port_id
    if edge.source_kind == RouteEdge.SOURCE_SCENE_EXIT:
        var port := source_node.get_exit(edge.source_port_id)
        if port != null:
            source_label = port.name
    else:
        var branch := source_node.get_condition_tree().get_branch(edge.source_branch_id)
        source_label = branch.label if branch != null and not branch.label.is_empty() else edge.source_branch_id
    return "%s → %s" % [source_label, target_node.scene_id]

func _connection_key(from_node: Variant, from_port: int, to_node: Variant, to_port: int) -> String:
    return "%s::%d::%s::%d" % [str(from_node), from_port, str(to_node), to_port]

func _create_popup() -> void:
    _popup = PopupMenu.new()
    _popup.add_item("Add Scene", POPUP_ADD_SCENE)
    _popup.id_pressed.connect(_on_popup_id_pressed)
    add_child(_popup)

func _create_node_popup() -> void:
    _node_popup = PopupMenu.new()
    _node_popup.add_item("Add If Wrapper", POPUP_ADD_IF_WRAPPER)
    _node_popup.add_item("Add Switch Wrapper", POPUP_ADD_SWITCH_WRAPPER)
    _node_popup.add_item("Add Numeric Compare Wrapper", POPUP_ADD_NUMERIC_WRAPPER)
    _node_popup.id_pressed.connect(_on_node_popup_id_pressed)
    add_child(_node_popup)

func _apply_theme() -> void:
    add_theme_color_override("grid_minor", Color("2b313c"))
    add_theme_color_override("grid_major", Color("3a4352"))
    add_theme_color_override("activity", Color("fff0a8"))
    add_theme_color_override("connection_hover_tint_color", Color("607fb8"))
    add_theme_color_override("selection_fill", Color(0.28, 0.42, 0.68, 0.18))
    add_theme_color_override("selection_stroke", Color("7198dc"))
    add_theme_constant_override("connection_hover_thickness", 4)
    add_theme_constant_override("port_hotzone_inner_extent", 28)
    add_theme_constant_override("port_hotzone_outer_extent", 30)
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("171a21")
    add_theme_stylebox_override("panel", panel)

func _is_in_input_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
    if not in_node is GraphNode:
        return false
    var graph_node := in_node as GraphNode
    var center := graph_node.position + graph_node.get_input_port_position(in_port)
    return Rect2(center - PORT_HOTZONE_HALF_SIZE, PORT_HOTZONE_HALF_SIZE * 2.0).has_point(mouse_position)

func _is_in_output_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
    if not in_node is GraphNode:
        return false
    var graph_node := in_node as GraphNode
    var center := graph_node.position + graph_node.get_output_port_position(in_port)
    return Rect2(center - PORT_HOTZONE_HALF_SIZE, PORT_HOTZONE_HALF_SIZE * 2.0).has_point(mouse_position)
