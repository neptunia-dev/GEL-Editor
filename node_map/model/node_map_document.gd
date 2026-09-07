extends RefCounted

## 聚合根只提交完整候选；快照为纯值，工厂只参与创建和恢复。
const Values := preload("res://node_map/model/value_rules.gd")
const Graph := preload("res://node_map/model/node_graph.gd")
const Link := preload("res://node_map/model/node_link.gd")
const Interface := preload("res://node_map/model/graph_interface.gd")
const SceneModel := preload("res://node_map/nodes/scene_node.gd")
const Boundary := preload("res://node_map/nodes/boundary_node.gd")
const Choice := preload("res://node_map/nodes/choice_node.gd")
const Subgraph := preload("res://node_map/model/subgraph_node.gd")

signal changed(change: Dictionary)

var registry: RefCounted
var root_graph_id: String:
	get: return _root_graph_id
var _root_graph_id: String = ""
var _graphs: Dictionary = {}

func _init(p_registry: RefCounted, initialize_root: bool = true) -> void:
	registry = p_registry
	if not initialize_root:
		return
	var root := Graph.new()
	_root_graph_id = root.graph_id
	_graphs[root.graph_id] = root
	var start = registry.create_node("gel.project_start")
	assert(start != null, "文档配置必须注册 gel.project_start。")
	if start != null:
		root._nodes[start.node_id] = start

func get_graph(graph_id: String):
	return _graphs[graph_id].clone_snapshot() if _graphs.has(graph_id) else null

func get_graph_ids() -> Array:
	return Graph._sorted_keys(_graphs)

func get_nodes(graph_id: String) -> Array:
	return _graphs[graph_id].get_nodes() if _graphs.has(graph_id) else []

func get_node(node_id: String):
	var graph = _graph_for_node(node_id)
	return graph._nodes[node_id].clone_snapshot() if graph != null else null

func get_links(graph_id: String) -> Array:
	return _graphs[graph_id].get_links() if _graphs.has(graph_id) else []

func get_ports(node_id: String) -> Array:
	var node = _node(node_id)
	if node == null:
		return []
	var ports: Array = []
	if node is SceneModel:
		var child = _graphs.get(node.child_graph_id)
		if child == null:
			return []
		for boundary in child._nodes.values():
			if not boundary is Boundary:
				continue
			var port := Interface.new()
			port.interface_id = boundary.interface_id
			port.port_id = boundary.interface_id
			port.display_name = boundary.display_name if not boundary.display_name.strip_edges().is_empty() else "Interface"
			port.direction = "input" if boundary.node_type == "gel.graph_input" else "output"
			port.kind = "flow"
			port.value_type = ""
			port.required = true
			port.max_connections = -1 if port.direction == "input" else 1
			port.order = boundary.order
			port.boundary_node_id = boundary.node_id
			port.boundary_port_id = "out" if port.direction == "input" else "in"
			ports.append(port)
	else:
		ports = node.get_local_port_specs()
	ports.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.port_id < b.port_id)
	return ports

func get_input_state(node_id: String, port_id: String) -> Dictionary:
	var missing := {"source": "missing", "has_value": false, "value": null}
	var node = _node(node_id)
	var port = _port(node_id, port_id)
	if node == null or port == null or port.direction != "input":
		return missing
	for link in _graph_for_node(node_id)._links.values():
		if link.target_node_id == node_id and link.target_port_id == port_id:
			# 连线表示数据来源，不在领域编辑模型内执行数据节点。
			return {"source": "link", "has_value": false, "value": null}
	if node.input_values.has(port_id):
		return {"source": "local", "has_value": true, "value": Values.copy_value(node.input_values[port_id])}
	if port.has_default_value:
		return {"source": "default", "has_value": true, "value": Values.copy_value(port.default_value)}
	return missing

func get_snapshot() -> Dictionary:
	var graphs: Array = []
	for graph_id in get_graph_ids():
		graphs.append(_graphs[graph_id].to_dict())
	return {"format": "gel.node-map", "formatVersion": 1, "rootGraphId": _root_graph_id, "graphs": graphs}

func execute(command: Dictionary) -> Dictionary:
	var errors := _validate_command(command)
	if not errors.is_empty():
		return _failure(errors)
	var before := get_snapshot()
	var candidate = get_script().new(registry, false)
	candidate._root_graph_id = _root_graph_id
	for graph_id in _graphs:
		candidate._graphs[graph_id] = _graphs[graph_id].clone_snapshot()
	var result: Dictionary = candidate._apply(command)
	if not result.ok:
		return result
	errors = candidate.validate_self()
	if not errors.is_empty():
		return _failure(errors)
	return _commit(candidate, before, result)

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if not Values.is_json_value(snapshot):
		return _failure([Values.diagnostic("invalid_snapshot", "快照只能包含有限 JSON 值。")])
	var candidate = get_script().new(registry, false)
	var errors: Array = candidate._restore(snapshot)
	if errors.is_empty():
		errors = candidate.validate_self()
	if not errors.is_empty():
		return _failure(errors)
	return _commit(candidate, get_snapshot(), {"ok": true, "diagnostics": []})

func _commit(candidate: RefCounted, before: Dictionary, result: Dictionary) -> Dictionary:
	var after: Dictionary = candidate.get_snapshot()
	var change := {"before": before, "after": after, "affected_node_ids": _affected_nodes(before, after)}
	result.change = change.duplicate(true)
	if before != after:
		_graphs = candidate._graphs
		_root_graph_id = candidate._root_graph_id
		changed.emit(change.duplicate(true))
	return result

func _failure(errors: Array) -> Dictionary:
	return {"ok": false, "diagnostics": errors, "change": {"before": {}, "after": {}, "affected_node_ids": []}}

func _graph_for_node(node_id: String):
	for graph in _graphs.values():
		if graph._nodes.has(node_id):
			return graph
	return null

func _node(node_id: String):
	var graph = _graph_for_node(node_id)
	return graph._nodes[node_id] if graph != null else null

func _port(node_id: String, port_id: String):
	for port in get_ports(node_id):
		if port.port_id == port_id:
			return port
	return null

func _command_error(command: Dictionary, code: String, message: String) -> Dictionary:
	var node_id: String = command.get("node_id", "")
	var graph = _graph_for_node(node_id)
	var graph_id: String = command.get("graph_id", graph.graph_id if graph != null else "")
	return _failure([Values.diagnostic(code, message, graph_id, node_id, command.get("port_id", ""), command.get("link_id", ""))])

func _apply(command: Dictionary) -> Dictionary:
	var result := {"ok": true, "diagnostics": []}
	var node = _node(command.get("node_id", ""))
	if command.has("node_id") and node == null:
		return _command_error(command, "missing_node", "节点不存在。")
	match command.op:
		"create_node":
			return _create_node(command)
		"set_input", "clear_input":
			var port = _port(node.node_id, command.port_id)
			if port == null or port.direction != "input" or port.kind != "data":
				return _command_error(command, "invalid_input", "只能编辑数据输入的本地值。")
			if command.op == "set_input":
				if not port.validate_value(command.value):
					return _command_error(command, "invalid_value", "本地值不符合端口类型。")
				node.input_values[command.port_id] = Values.copy_value(command.value)
			else:
				node.input_values.erase(command.port_id)
		"set_parameter":
			var found := false
			for parameter in registry.get_definition(node.node_type).parameter_specs:
				if parameter.parameter_id == command.parameter_id:
					found = parameter.validate_value(command.value)
			if not found or not node._set_parameter(command.parameter_id, Values.copy_value(command.value)):
				return _command_error(command, "invalid_parameter", "参数不存在、不可编辑或不符合约束。")
		"move_nodes":
			for node_id in command.positions:
				var moved = _node(node_id)
				if moved == null or moved.locked:
					return _command_error({"node_id": node_id}, "invalid_move", "节点不存在或布局已锁定。")
				moved.position = command.positions[node_id]
		"set_node_flags":
			for field in command.values:
				node.set(field, command.values[field])
		"remove_nodes":
			return _remove_nodes(command.node_ids)
		"duplicate_nodes":
			return _duplicate_nodes(command.node_ids)
		"connect":
			if not _graphs.has(command.graph_id):
				return _command_error(command, "missing_graph", "图不存在。")
			var link := Link.new()
			for field in ["source_node_id", "source_port_id", "target_node_id", "target_port_id"]:
				link.set(field, command[field])
			_graphs[command.graph_id]._links[link.link_id] = link
			result.created_link_id = link.link_id
		"disconnect":
			for graph in _graphs.values():
				if graph._links.has(command.link_id):
					graph._links.erase(command.link_id)
					return result
			return _command_error(command, "missing_link", "连接不存在。")
		"add_choice", "rename_choice", "remove_choice", "reorder_choices":
			if not node is Choice:
				return _command_error(command, "wrong_node_type", "选项命令只适用于 Choice 节点。")
			match command.op:
				"add_choice": result.created_item_id = node._add_choice(command.label)
				"rename_choice":
					if not node._rename_choice(command.item_id, command.label):
						return _command_error(command, "missing_choice", "选项不存在。")
				"remove_choice":
					if not node._remove_choice(command.item_id):
						return _command_error(command, "missing_choice", "选项不存在。")
					_remove_port_links(node.node_id, command.item_id)
				"reorder_choices":
					if not node._reorder_choices(command.item_ids):
						return _command_error(command, "invalid_choice_order", "排序必须完整包含每个选项且不能重复。")
		"add_output":
			if not node is SceneModel:
				return _command_error(command, "wrong_node_type", "出口必须添加到 Scene 节点。")
			result = _create_node({"op": "create_node", "type_id": "gel.graph_output", "graph_id": node.child_graph_id})
			if result.ok:
				var output = _node(result.created_node_id)
				output.display_name = command.display_name
				result.created_item_id = output.interface_id
		"rename_output", "remove_output":
			if node.node_type != "gel.graph_output":
				return _command_error(command, "wrong_node_type", "此命令只适用于输出边界节点。")
			if command.op == "remove_output":
				return _remove_nodes([node.node_id])
			node.display_name = command.display_name
	return result

func _create_node(command: Dictionary) -> Dictionary:
	var graph = _graphs.get(command.graph_id)
	var definition = registry.get_definition(command.type_id)
	if graph == null or definition == null:
		return _command_error(command, "unknown_type_or_graph", "节点类型未注册或目标图不存在。")
	if not definition.allowed_graph_kinds.has(graph.kind):
		return _command_error(command, "wrong_graph_kind", "节点类型不允许放在目标图中。")
	if command.type_id in ["gel.project_start", "gel.graph_input"]:
		return _command_error(command, "protected_node", "固定入口不能通过普通命令创建。")
	var node = registry.create_node(command.type_id)
	if node == null:
		return _command_error(command, "invalid_factory", "工厂没有返回符合定义的模型。")
	node.position = command.get("position", Vector2.ZERO)
	graph._nodes[node.node_id] = node
	var result := {"ok": true, "diagnostics": [], "created_node_id": node.node_id}
	if node is Boundary:
		for existing in graph._nodes.values():
			if existing is Boundary and existing != node:
				node.order = maxi(node.order, existing.order + 1)
	if node is SceneModel:
		node.scene_id = Values.new_id("scene")
		var child := Graph.new()
		child.kind = "scene"
		child.owner_node_id = node.node_id
		node.child_graph_id = child.graph_id
		_graphs[child.graph_id] = child
		var entry = registry.create_node("gel.graph_input")
		var output = registry.create_node("gel.graph_output")
		if not entry is Boundary or not output is Boundary:
			return _command_error(command, "invalid_factory", "场景创建需要有效边界工厂。")
		output.display_name = "Continue"
		output.order = 1
		output.position = Vector2(400, 0)
		child._nodes[entry.node_id] = entry
		child._nodes[output.node_id] = output
		var link := Link.new()
		link.source_node_id = entry.node_id
		link.source_port_id = "out"
		link.target_node_id = output.node_id
		link.target_port_id = "in"
		child._links[link.link_id] = link
		result.created_graph_id = child.graph_id
	return result

func _remove_port_links(node_id: String, port_id: String) -> void:
	for graph in _graphs.values():
		for link_id in graph._links.keys():
			var link = graph._links[link_id]
			if (link.source_node_id == node_id and link.source_port_id == port_id) or (link.target_node_id == node_id and link.target_port_id == port_id):
				graph._links.erase(link_id)

func _remove_nodes(node_ids: Array) -> Dictionary:
	var doomed: Dictionary = {}
	var doomed_graphs: Dictionary = {}
	for node_id in node_ids:
		var node = _node(node_id)
		if node == null:
			return _command_error({"node_id": node_id}, "missing_node", "待删除节点不存在。")
		doomed[node_id] = true
		if node is SceneModel:
			doomed_graphs[node.child_graph_id] = true
			for child_id in _graphs[node.child_graph_id]._nodes:
				doomed[child_id] = true
	for node_id in node_ids:
		var node = _node(node_id)
		var graph = _graph_for_node(node_id)
		if node.node_type == "gel.project_start" or (node.node_type == "gel.graph_input" and not doomed_graphs.has(graph.graph_id)):
			return _command_error({"node_id": node_id}, "protected_node", "固定入口不能单独删除。")
	# 先清理投影接口的父图路由，再移除子图和局部端点。
	for node_id in doomed:
		var node = _node(node_id)
		if node.node_type == "gel.graph_output":
			_remove_port_links(_graph_for_node(node_id).owner_node_id, node.interface_id)
	for graph in _graphs.values():
		for link_id in graph._links.keys():
			var link = graph._links[link_id]
			if doomed.has(link.source_node_id) or doomed.has(link.target_node_id):
				graph._links.erase(link_id)
		for node_id in doomed:
			graph._nodes.erase(node_id)
	for graph_id in doomed_graphs:
		_graphs.erase(graph_id)
	return {"ok": true, "diagnostics": []}

func _duplicate_nodes(node_ids: Array) -> Dictionary:
	var selected: Dictionary = {}
	var owned: Dictionary = {}
	for node_id in node_ids:
		var node = _node(node_id)
		if node == null:
			return _command_error({"node_id": node_id}, "missing_node", "待复制节点不存在。")
		if node.node_type in ["gel.project_start", "gel.graph_input"]:
			return _command_error({"node_id": node_id}, "protected_node", "固定入口不能单独复制。")
		selected[node_id] = true
		if node is SceneModel:
			owned[node.child_graph_id] = node_id
	var node_map: Dictionary = {}
	var port_map: Dictionary = {}
	var graph_map: Dictionary = {}
	var source_graphs: Array = _graphs.values()
	for graph_id in owned:
		var child := Graph.new()
		child.kind = "scene"
		graph_map[graph_id] = child.graph_id
		_graphs[child.graph_id] = child
		for node_id in _graphs[graph_id]._nodes:
			selected[node_id] = true
	for graph in source_graphs:
		var target = _graphs[graph_map.get(graph.graph_id, graph.graph_id)]
		for original in graph._nodes.values():
			if not selected.has(original.node_id):
				continue
			var copy = original.duplicate_node()
			if not owned.has(graph.graph_id):
				copy.position += Vector2(32, 32)
			node_map[original.node_id] = copy.node_id
			port_map[original.node_id] = {}
			if original is Choice:
				var old_items: Array = original.serialize_data().choices
				var new_items: Array = copy.serialize_data().choices
				for index in old_items.size():
					port_map[original.node_id][old_items[index].choice_id] = new_items[index].choice_id
			if original is SceneModel:
				copy.scene_id = Values.new_id("scene")
				copy.child_graph_id = graph_map[original.child_graph_id]
				_graphs[copy.child_graph_id].owner_node_id = copy.node_id
			target._nodes[copy.node_id] = copy
	for graph in source_graphs:
		var target = _graphs[graph_map.get(graph.graph_id, graph.graph_id)]
		for original in graph._links.values():
			if not node_map.has(original.source_node_id) or not node_map.has(original.target_node_id):
				continue
			# Scene 的父图路由不随复制带入；子图内部连接全部重建。
			if graph._nodes[original.source_node_id] is SceneModel or graph._nodes[original.target_node_id] is SceneModel:
				continue
			var copy = original.clone_snapshot()
			copy.link_id = Values.new_id("link")
			copy.source_node_id = node_map[original.source_node_id]
			copy.target_node_id = node_map[original.target_node_id]
			copy.source_port_id = port_map[original.source_node_id].get(original.source_port_id, original.source_port_id)
			copy.target_port_id = port_map[original.target_node_id].get(original.target_port_id, original.target_port_id)
			target._links[copy.link_id] = copy
	var result := {"ok": true, "diagnostics": [], "node_id_map": node_map, "graph_id_map": graph_map, "created_node_ids": []}
	for node_id in node_ids:
		result.created_node_ids.append(node_map[node_id])
	if not node_ids.is_empty():
		result.created_node_id = node_map[node_ids[0]]
		var first = _node(result.created_node_id)
		if first is SceneModel:
			result.created_graph_id = first.child_graph_id
	return result

func validate_self() -> Array:
	var errors: Array = []
	if not _graphs.has(_root_graph_id) or _graphs[_root_graph_id].kind != "root":
		return [Values.diagnostic("missing_root", "文档必须引用有效根图。")]
	var root_count := 0
	var start_count := 0
	var node_ids: Dictionary = {}
	var link_ids: Dictionary = {}
	var scene_ids: Dictionary = {}
	var owned_graphs: Dictionary = {}
	for graph in _graphs.values():
		errors.append_array(graph.validate_self(registry))
		if graph.kind == "root":
			root_count += 1
			if not graph.owner_node_id.is_empty():
				errors.append(Values.diagnostic("invalid_owner", "根图不能有拥有者。", graph.graph_id))
		else:
			var owner = _node(graph.owner_node_id)
			if not owner is SceneModel or owner.child_graph_id != graph.graph_id or _graph_for_node(graph.owner_node_id).graph_id != _root_graph_id:
				errors.append(Values.diagnostic("invalid_owner", "子图必须由根图中的场景一对一拥有。", graph.graph_id, graph.owner_node_id))
		var inputs := 0
		var interfaces: Dictionary = {}
		for node in graph._nodes.values():
			if node_ids.has(node.node_id):
				errors.append(Values.diagnostic("duplicate_node", "节点 ID 在文档中重复。", graph.graph_id, node.node_id))
			node_ids[node.node_id] = true
			if node.node_type == "gel.project_start":
				start_count += 1
				if graph.graph_id != _root_graph_id:
					errors.append(Values.diagnostic("invalid_start", "项目入口只能属于根图。", graph.graph_id, node.node_id))
			if node is Subgraph:
				if not node is SceneModel or graph.graph_id != _root_graph_id or not _graphs.has(node.child_graph_id) or node.child_graph_id == _root_graph_id:
					errors.append(Values.diagnostic("invalid_child_graph", "第一版只允许根图场景拥有 scene 子图。", graph.graph_id, node.node_id))
				else:
					var child = _graphs[node.child_graph_id]
					if child.kind != "scene" or child.owner_node_id != node.node_id or owned_graphs.has(child.graph_id):
						errors.append(Values.diagnostic("invalid_owner", "子图拥有关系不匹配或重复。", child.graph_id, node.node_id))
					owned_graphs[child.graph_id] = node.node_id
			if node is SceneModel:
				if scene_ids.has(node.scene_id):
					errors.append(Values.diagnostic("duplicate_scene_id", "Runtime Scene ID 在文档中重复。", graph.graph_id, node.node_id))
				scene_ids[node.scene_id] = true
			if node is Boundary:
				if graph.kind != "scene" or interfaces.has(node.interface_id):
					errors.append(Values.diagnostic("duplicate_interface", "边界必须属于场景且接口身份不能重复。", graph.graph_id, node.node_id, node.interface_id))
				interfaces[node.interface_id] = true
				if node.node_type == "gel.graph_input":
					inputs += 1
		if graph.kind == "scene" and inputs != 1:
			errors.append(Values.diagnostic("invalid_entry_count", "每个场景必须恰有一个入口。", graph.graph_id))
		for link_id in graph._links:
			if link_ids.has(link_id):
				errors.append(Values.diagnostic("duplicate_link", "连接 ID 在文档中重复。", graph.graph_id, "", "", link_id))
			link_ids[link_id] = true
	if root_count != 1 or start_count != 1:
		errors.append(Values.diagnostic("invalid_root", "文档必须恰有一个根图和一个项目入口。", _root_graph_id))
	if not errors.is_empty():
		return errors
	for graph in _graphs.values():
		var resolved: Dictionary = {}
		for node_id in graph._nodes:
			resolved[node_id] = {}
			for port in get_ports(node_id):
				resolved[node_id][port.port_id] = port
		errors.append_array(graph.validate_connections(resolved))
	return errors

func _restore(snapshot: Dictionary) -> Array:
	if not Values.has_keys(snapshot, ["format", "formatVersion", "rootGraphId", "graphs"]) or snapshot.format != "gel.node-map" or not Values.is_integer(snapshot.formatVersion) or snapshot.formatVersion != 1:
		return [Values.diagnostic("invalid_snapshot", "快照格式或容器版本无效。")]
	if not Values.valid_id(snapshot.rootGraphId) or not snapshot.graphs is Array:
		return [Values.diagnostic("invalid_snapshot", "根图身份或图集合无效。")]
	_root_graph_id = snapshot.rootGraphId
	var node_ids: Dictionary = {}
	var link_ids: Dictionary = {}
	for raw in snapshot.graphs:
		if not raw is Dictionary or not Values.has_keys(raw, ["graphId", "kind", "ownerNodeId", "nodes", "links"]):
			return [Values.diagnostic("invalid_snapshot", "图记录结构无效。")]
		if not Values.valid_id(raw.graphId) or not raw.kind is String or not raw.ownerNodeId is String or not raw.nodes is Array or not raw.links is Array:
			return [Values.diagnostic("invalid_snapshot", "图记录字段类型无效。")]
		if _graphs.has(raw.graphId):
			return [Values.diagnostic("duplicate_graph", "图身份重复。", raw.graphId)]
		var graph := Graph.new()
		graph.graph_id = raw.graphId
		graph.kind = raw.kind
		graph.owner_node_id = raw.ownerNodeId
		_graphs[graph.graph_id] = graph
		for record in raw.nodes:
			if not record is Dictionary or not record.get("type") is String:
				return [Values.diagnostic("invalid_snapshot", "节点记录类型无效。", graph.graph_id)]
			var node = registry.create_node(record.type)
			if node == null:
				return [Values.diagnostic("unknown_type", "未注册节点类型不能构建内存模型。", graph.graph_id)]
			if not node._load_editor_dict(record):
				return [Values.diagnostic("invalid_node_record", "节点版本或字段无效。", graph.graph_id)]
			if node_ids.has(node.node_id):
				return [Values.diagnostic("duplicate_node", "节点身份重复。", graph.graph_id, node.node_id)]
			node_ids[node.node_id] = true
			graph._nodes[node.node_id] = node
		for record in raw.links:
			var link := Link.new()
			if not record is Dictionary or not link._load_dict(record):
				return [Values.diagnostic("invalid_link_record", "连接记录无效。", graph.graph_id)]
			if link_ids.has(link.link_id):
				return [Values.diagnostic("duplicate_link", "连接身份重复。", graph.graph_id, "", "", link.link_id)]
			link_ids[link.link_id] = true
			graph._links[link.link_id] = link
	return []

func _validate_command(command: Dictionary) -> Array:
	var schemas := {
		"create_node": {"type_id": TYPE_STRING, "graph_id": TYPE_STRING},
		"set_input": {"node_id": TYPE_STRING, "port_id": TYPE_STRING, "value": -1},
		"clear_input": {"node_id": TYPE_STRING, "port_id": TYPE_STRING},
		"set_parameter": {"node_id": TYPE_STRING, "parameter_id": TYPE_STRING, "value": -1},
		"move_nodes": {"positions": TYPE_DICTIONARY},
		"remove_nodes": {"node_ids": TYPE_ARRAY}, "duplicate_nodes": {"node_ids": TYPE_ARRAY},
		"connect": {"graph_id": TYPE_STRING, "source_node_id": TYPE_STRING, "source_port_id": TYPE_STRING, "target_node_id": TYPE_STRING, "target_port_id": TYPE_STRING},
		"disconnect": {"link_id": TYPE_STRING},
		"set_node_flags": {"node_id": TYPE_STRING, "values": TYPE_DICTIONARY},
		"add_choice": {"node_id": TYPE_STRING, "label": TYPE_STRING},
		"rename_choice": {"node_id": TYPE_STRING, "item_id": TYPE_STRING, "label": TYPE_STRING},
		"remove_choice": {"node_id": TYPE_STRING, "item_id": TYPE_STRING},
		"reorder_choices": {"node_id": TYPE_STRING, "item_ids": TYPE_ARRAY},
		"add_output": {"node_id": TYPE_STRING, "display_name": TYPE_STRING},
		"rename_output": {"node_id": TYPE_STRING, "display_name": TYPE_STRING},
		"remove_output": {"node_id": TYPE_STRING},
	}
	var invalid := [Values.diagnostic("invalid_command", "命令名称、字段或字段类型无效。")]
	if not command.get("op") is String or not schemas.has(command.op):
		return invalid
	var schema: Dictionary = schemas[command.op]
	for key in schema:
		if not command.has(key) or (schema[key] != -1 and typeof(command[key]) != schema[key]):
			return invalid
	for key in command:
		if key != "op" and not schema.has(key) and not (command.op == "create_node" and key == "position"):
			return invalid
	if command.has("value") and not Values.is_json_value(command.value):
		return invalid
	if command.has("position") and (not command.position is Vector2 or not command.position.is_finite()):
		return invalid
	if command.has("positions"):
		for node_id in command.positions:
			if not node_id is String or not command.positions[node_id] is Vector2 or not command.positions[node_id].is_finite():
				return invalid
	for key in ["node_ids", "item_ids"]:
		if command.has(key):
			var seen: Dictionary = {}
			for item in command[key]:
				if not item is String or seen.has(item):
					return invalid
				seen[item] = true
	if command.has("values"):
		for key in command.values:
			if key not in ["collapsed", "locked", "enabled", "title_override"]:
				return invalid
			if typeof(command.values[key]) != (TYPE_STRING if key == "title_override" else TYPE_BOOL):
				return invalid
	return []

static func _affected_nodes(before: Dictionary, after: Dictionary) -> Array:
	var old_nodes: Dictionary = {}
	var new_nodes: Dictionary = {}
	var old_graphs: Dictionary = {}
	var new_graphs: Dictionary = {}
	for pair in [[before, old_nodes, old_graphs], [after, new_nodes, new_graphs]]:
		for graph in pair[0].graphs:
			pair[2][graph.graphId] = graph
			for node in graph.nodes:
				pair[1][node.id] = node
	var affected: Dictionary = {}
	for node_id in old_nodes.keys() + new_nodes.keys():
		if old_nodes.get(node_id) != new_nodes.get(node_id):
			affected[node_id] = true
	for graph_id in old_graphs.keys() + new_graphs.keys():
		var old: Dictionary = old_graphs.get(graph_id, {})
		var current: Dictionary = new_graphs.get(graph_id, {})
		if old == current:
			continue
		for graph in [old, current]:
			if not graph.get("ownerNodeId", "").is_empty():
				affected[graph.ownerNodeId] = true
		for link in old.get("links", []) + current.get("links", []):
			if not old.get("links", []).has(link) or not current.get("links", []).has(link):
				affected[link.sourceNodeId] = true
				affected[link.targetNodeId] = true
	return Graph._sorted_keys(affected)
