extends RefCounted

## 局部集合只通过副本查询；文档提供解析端口进行连接校验。
const Values := preload("res://node_map/model/value_rules.gd")

var graph_id: String = Values.new_id("graph")
var kind: String = "root"
var owner_node_id: String = ""
var _nodes: Dictionary = {}
var _links: Dictionary = {}

func get_nodes() -> Array:
	var result: Array = []
	for node_id in _sorted_keys(_nodes):
		result.append(_nodes[node_id].clone_snapshot())
	return result

func get_links() -> Array:
	var result: Array = []
	for link_id in _sorted_keys(_links):
		result.append(_links[link_id].clone_snapshot())
	return result

func clone_snapshot():
	var copy = get_script().new()
	copy.graph_id = graph_id
	copy.kind = kind
	copy.owner_node_id = owner_node_id
	for node in _nodes.values():
		copy._nodes[node.node_id] = node.clone_snapshot()
	for link in _links.values():
		copy._links[link.link_id] = link.clone_snapshot()
	return copy

func to_dict() -> Dictionary:
	var nodes: Array = []
	var links: Array = []
	for node_id in _sorted_keys(_nodes):
		nodes.append(_nodes[node_id].to_editor_dict())
	for link_id in _sorted_keys(_links):
		links.append(_links[link_id].to_dict())
	return {"graphId": graph_id, "kind": kind, "ownerNodeId": owner_node_id, "nodes": nodes, "links": links}

func validate_self(registry: RefCounted) -> Array:
	var errors: Array = []
	if not Values.valid_id(graph_id) or kind not in ["root", "scene"]:
		errors.append(Values.diagnostic("invalid_graph", "图身份或类别无效。", graph_id))
	for node_id in _nodes:
		var node = _nodes[node_id]
		if node_id != node.node_id:
			errors.append(Values.diagnostic("invalid_node", "节点集合键与身份不一致。", graph_id, node.node_id))
		var definition = registry.get_definition(node.node_type)
		if definition == null or not definition.allowed_graph_kinds.has(kind):
			errors.append(Values.diagnostic("wrong_graph_kind", "该节点类型不允许出现在此图。", graph_id, node.node_id))
		for error in node.validate_self():
			error.graph_id = graph_id
			if error.node_id.is_empty():
				error.node_id = node.node_id
			errors.append(error)
	return errors

func validate_connections(resolved_ports: Dictionary) -> Array:
	var errors: Array = []
	var seen: Dictionary = {}
	var counts: Dictionary = {}
	var adjacency: Dictionary = {}
	var indegrees: Dictionary = {}
	for node_id in _nodes:
		adjacency[node_id] = []
		indegrees[node_id] = 0
	for link_id in _links:
		var link = _links[link_id]
		if link_id != link.link_id or not Values.valid_id(link.link_id):
			errors.append(_link_error("invalid_link", "连接身份无效。", link))
			continue
		if not _nodes.has(link.source_node_id) or not _nodes.has(link.target_node_id):
			errors.append(_link_error("cross_graph_or_missing_node", "连接两端必须在同一图内存在。", link))
			continue
		var source = resolved_ports.get(link.source_node_id, {}).get(link.source_port_id)
		var target = resolved_ports.get(link.target_node_id, {}).get(link.target_port_id)
		if source == null or target == null:
			errors.append(_link_error("missing_port", "连接引用的端口不存在。", link))
			continue
		if source.direction != "output" or target.direction != "input":
			errors.append(_link_error("invalid_direction", "连接必须从输出指向输入。", link))
			continue
		if source.kind != target.kind or source.value_type != target.value_type:
			errors.append(_link_error("incompatible_ports", "连接类别或值类型不匹配。", link))
			continue
		var key := JSON.stringify([link.source_node_id, link.source_port_id, link.target_node_id, link.target_port_id])
		if seen.has(key):
			errors.append(_link_error("duplicate_connection", "端点组合已经连接。", link))
		seen[key] = true
		for endpoint in [[link.source_node_id, source], [link.target_node_id, target]]:
			var endpoint_key := JSON.stringify([endpoint[0], endpoint[1].port_id])
			counts[endpoint_key] = counts.get(endpoint_key, 0) + 1
			if endpoint[1].max_connections != -1 and counts[endpoint_key] > endpoint[1].max_connections:
				errors.append(Values.diagnostic("connection_limit", "端口连接数超过上限。", graph_id, endpoint[0], endpoint[1].port_id, link.link_id))
		if source.kind == "data":
			adjacency[link.source_node_id].append(link.target_node_id)
			indegrees[link.target_node_id] += 1
	# 只对数据依赖做拓扑检查，流程环是合法的草稿结构。
	var queue: Array = []
	for node_id in indegrees:
		if indegrees[node_id] == 0:
			queue.append(node_id)
	var cursor := 0
	while cursor < queue.size():
		var node_id: String = queue[cursor]
		cursor += 1
		for target_id in adjacency[node_id]:
			indegrees[target_id] -= 1
			if indegrees[target_id] == 0:
				queue.append(target_id)
	if queue.size() != _nodes.size():
		for link in _links.values():
			var port = resolved_ports.get(link.source_node_id, {}).get(link.source_port_id)
			if port != null and port.kind == "data" and indegrees.get(link.target_node_id, 0) > 0:
				errors.append(_link_error("data_cycle", "数据依赖不能形成环。", link))
				break
	return errors

func _link_error(code: String, message: String, link: RefCounted) -> Dictionary:
	return Values.diagnostic(code, message, graph_id, link.target_node_id, link.target_port_id, link.link_id)

static func _sorted_keys(values: Dictionary) -> Array:
	var keys: Array = values.keys()
	keys.sort()
	return keys
