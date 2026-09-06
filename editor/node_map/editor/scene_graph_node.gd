extends GraphNode
class_name SceneGraphNodeView

signal move_committed(node_id: String, position: Vector2)

var model_node_id: String = ""
var _port_ids: Array[String] = []
var _dragging := false
var endpoints: Array = []
var _model: SceneNode
var _entry := false

var dragging: bool:
	get:
		return _dragging

func bind_scene_node(node: SceneNode, entry: bool = false) -> void:
	model_node_id = node.node_id
	_refresh_from_model(node, entry)

func refresh_from_model(node: SceneNode, entry: bool = false) -> void:
	_refresh_from_model(node, entry)

func get_scene_node_id() -> String:
	return model_node_id

func get_exit_port_id(port_index: int) -> String:
	if port_index < 0 or port_index >= _port_ids.size():
		return ""
	return _port_ids[port_index]

func refresh_ports() -> void:
	if _model != null:
		_refresh_from_model(_model, _entry)

func get_endpoint_key_for_port(index: int) -> String:
	if index < 0 or index >= endpoints.size():
		return ""
	var endpoint: Dictionary = endpoints[index]
	if endpoint.kind == RouteEdge.SOURCE_SCENE_EXIT:
		return "%s::exit::%s" % [model_node_id, endpoint.port_id]
	return "%s::condition::%s::%s" % [model_node_id, endpoint.wrapper_id, endpoint.branch_id]

func find_port_index(key: String) -> int:
	for index in endpoints.size():
		if get_endpoint_key_for_port(index) == key:
			return index
	return -1

func _refresh_from_model(node: SceneNode, entry: bool) -> void:
		_model = node
		_entry = entry
		clear_all_slots()
		for child in get_children():
			remove_child(child)
			child.queue_free()

		title = ("[Entry] " if entry else "") + (node.title if not node.title.is_empty() else node.scene_id)
		custom_minimum_size = Vector2(220, 0)
		var scene_label := Label.new()
		scene_label.text = node.scene_id
		scene_label.name = "SceneId"
		add_child(scene_label)
		# Every Scene accepts incoming routes on input port 0. Outgoing exits
		# occupy the following visual rows while keeping their own port indices.
		set_slot(0, true, 0, Color(0.35, 0.7, 1.0), false, 0, Color.TRANSPARENT)

		_port_ids.clear()
		endpoints.clear()
		var exits := node.get_exits()
		if exits.is_empty():
			var empty_label := Label.new()
			empty_label.text = "No exits"
			empty_label.modulate = Color(0.6, 0.6, 0.6)
			add_child(empty_label)
		else:
			for index in range(exits.size()):
				var port: ExitPort = exits[index]
				var label := Label.new()
				label.text = port.name
				add_child(label)
				_port_ids.append(port.port_id)
				endpoints.append({"kind": RouteEdge.SOURCE_SCENE_EXIT, "port_id": port.port_id})
				set_slot(get_child_count() - 1, false, 0, Color.TRANSPARENT, true, 0, Color(0.35, 0.7, 1.0))
		var tree := node.get_condition_tree()
		if tree != null:
			for endpoint in tree.get_leaf_endpoints():
				var label := Label.new()
				var wrapper := tree.get_wrapper(endpoint.wrapperId)
				label.text = "%s / %s: %s" % [wrapper.to_editor_dict().type, endpoint.wrapperId, tree.get_branch(endpoint.branchId).label]
				add_child(label)
				_port_ids.append("")
				endpoints.append({"kind": RouteEdge.SOURCE_CONDITION_BRANCH, "wrapper_id": endpoint.wrapperId, "branch_id": endpoint.branchId})
				set_slot(get_child_count() - 1, false, 0, Color.TRANSPARENT, true, 0, Color(0.95, 0.7, 0.3))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed:
			move_committed.emit(model_node_id, position_offset)
