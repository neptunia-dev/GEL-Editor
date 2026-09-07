extends RefCounted

## 示例仅作为宿主的初始数据，不进入节点注册或模型构造逻辑。
static func populate(document) -> void:
	var first := _create(document, "gel.scene", document.root_graph_id, Vector2(350, 80))
	var ending := _create(document, "gel.scene", document.root_graph_id, Vector2(750, 80))
	if first.is_empty() or ending.is_empty():
		return
	document.execute({"op": "set_parameter", "node_id": first, "parameter_id": "display_name", "value": "Prologue"})
	document.execute({"op": "set_parameter", "node_id": ending, "parameter_id": "display_name", "value": "Ending"})
	for node in document.get_nodes(document.root_graph_id):
		if node.node_type == "gel.project_start":
			_link(document, document.root_graph_id, node.node_id, "out", first, "enter")
	for port in document.get_ports(first):
		if port.direction == "output":
			_link(document, document.root_graph_id, first, port.port_id, ending, "enter")
	var child_id: String = document.get_node(first).child_graph_id
	var entry_id := ""
	var exit_id := ""
	for node in document.get_nodes(child_id):
		if node.node_type == "gel.graph_input":
			entry_id = node.node_id
		elif node.node_type == "gel.graph_output":
			exit_id = node.node_id
	for link in document.get_links(child_id):
		document.execute({"op": "disconnect", "link_id": link.link_id})
	var dialogue := _create(document, "gel.dialogue", child_id, Vector2(300, 80))
	var condition := _create(document, "gel.if", child_id, Vector2(680, 80))
	var flag := _create(document, "gel.boolean", child_id, Vector2(320, 450))
	var end_id := _create(document, "gel.end_story", child_id, Vector2(1020, 450))
	document.execute({"op": "move_nodes", "positions": {entry_id: Vector2(0, 80), exit_id: Vector2(1020, 80)}})
	document.execute({"op": "set_input", "node_id": dialogue, "port_id": "text", "value": "The station is quiet. A light is still on."})
	_link(document, child_id, entry_id, "out", dialogue, "in")
	_link(document, child_id, dialogue, "next", condition, "in")
	_link(document, child_id, flag, "value", condition, "condition")
	_link(document, child_id, condition, "true", exit_id, "in")
	_link(document, child_id, condition, "false", end_id, "in")
	var ending_graph: String = document.get_node(ending).child_graph_id
	for link in document.get_links(ending_graph):
		document.execute({"op": "disconnect", "link_id": link.link_id})
	var terminal := _create(document, "gel.end_story", ending_graph, Vector2(400, 80))
	for node in document.get_nodes(ending_graph):
		if node.node_type == "gel.graph_output":
			document.execute({"op": "remove_nodes", "node_ids": [node.node_id]})
		elif node.node_type == "gel.graph_input":
			_link(document, ending_graph, node.node_id, "out", terminal, "in")

static func _create(document, type_id: String, graph_id: String, at: Vector2) -> String:
	var result: Dictionary = document.execute({"op": "create_node", "type_id": type_id, "graph_id": graph_id, "position": at})
	return result.get("created_node_id", "")

static func _link(document, graph_id: String, source: String, output: String, target: String, input: String) -> void:
	document.execute({"op": "connect", "graph_id": graph_id, "source_node_id": source, "source_port_id": output, "target_node_id": target, "target_port_id": input})
