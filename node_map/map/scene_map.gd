extends RefCounted
class_name SceneMap

## Node Map 聚合根。Node 和 Edge 均以副本保存，所有跨对象修改通过这里完成。
var _nodes: Dictionary = {}
var _edges: Dictionary = {}
var _entry_node_id: String = ""
var last_error: String = ""

func add_node(node: SceneNode) -> bool:
    if node == null:
        return _fail("node must not be null")
    var errors := node.validate_self()
    if not errors.is_empty():
        return _fail("cannot add node: %s" % str(errors[0]))
    if _nodes.has(node.node_id):
        return _fail("node_id '%s' already exists" % node.node_id)
    if not _find_node_id_by_scene_id(node.scene_id).is_empty():
        return _fail("scene_id '%s' already exists" % node.scene_id)
    _nodes[node.node_id] = _copy_node(node)
    _clear_error()
    return true

## 更新前解析该 Node 现有边的源端点；若会造成悬空引用，整个更新被拒绝。
func update_node(node: SceneNode) -> bool:
    if node == null:
        return _fail("node must not be null")
    if not _nodes.has(node.node_id):
        return _fail("node_id '%s' does not exist" % node.node_id)
    var errors := node.validate_self()
    if not errors.is_empty():
        return _fail("cannot update node: %s" % str(errors[0]))
    var other_id := _find_node_id_by_scene_id(node.scene_id)
    if not other_id.is_empty() and other_id != node.node_id:
        return _fail("scene_id '%s' already exists" % node.scene_id)
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        if edge.source_node_id != node.node_id:
            continue
        var source := _resolve_source(node, edge)
        if not bool(source["ok"]):
            return _fail("cannot update node while edge '%s' would dangle: %s" % [edge_id, source["message"]])
    _nodes[node.node_id] = _copy_node(node)
    _clear_error()
    return true

func remove_node(node_id: String) -> bool:
    if not _nodes.has(node_id):
        return _fail("node_id '%s' does not exist" % node_id)
    var remove_ids: Array = []
    for edge_id in _sorted_edge_ids():
        if (_edges[edge_id] as RouteEdge).references_node(node_id):
            remove_ids.append(edge_id)
    _erase_edges(remove_ids)
    _nodes.erase(node_id)
    if _entry_node_id == node_id:
        _entry_node_id = ""
    _clear_error()
    return true

func get_node(node_id: String) -> SceneNode:
    return _copy_node(_nodes[node_id] as SceneNode) if _nodes.has(node_id) else null

func has_node(node_id: String) -> bool:
    return _nodes.has(node_id)

func get_nodes() -> Array:
    var result: Array = []
    for node_id in _sorted_node_ids():
        result.append(_copy_node(_nodes[node_id] as SceneNode))
    return result

func get_node_count() -> int:
    return _nodes.size()

func rename_scene(node_id: String, new_scene_id: String) -> bool:
    var node := get_node(node_id)
    if node == null:
        return _fail("node_id '%s' does not exist" % node_id)
    if not node.rename_scene(new_scene_id):
        return _fail(node.last_error)
    return update_node(node)

func set_entry_node(node_id: String) -> bool:
    if not _nodes.has(node_id):
        return _fail("entry node '%s' does not exist" % node_id)
    _entry_node_id = node_id
    _clear_error()
    return true

func clear_entry_node() -> void:
    _entry_node_id = ""
    _clear_error()

func get_entry_node_id() -> String:
    return _entry_node_id

func get_entry_node() -> SceneNode:
    return get_node(_entry_node_id) if _nodes.has(_entry_node_id) else null

func add_route(edge: RouteEdge) -> bool:
    if edge == null:
        return _fail("edge must not be null")
    var errors := edge.validate_self()
    if not errors.is_empty():
        return _fail("cannot add edge: %s" % str(errors[0]))
    if _edges.has(edge.edge_id):
        return _fail("edge_id '%s' already exists" % edge.edge_id)
    if not _nodes.has(edge.source_node_id):
        return _fail("source node '%s' does not exist" % edge.source_node_id)
    if not _nodes.has(edge.target_node_id):
        return _fail("target node '%s' does not exist" % edge.target_node_id)
    var source := _resolve_source(_nodes[edge.source_node_id] as SceneNode, edge)
    if not bool(source["ok"]):
        return _fail(str(source["message"]))
    if not _find_edge_id_by_endpoint(edge.source_endpoint_key()).is_empty():
        return _fail("source endpoint '%s' already has a route" % edge.source_endpoint_key())
    _edges[edge.edge_id] = edge.duplicate_edge()
    _clear_error()
    return true

func remove_route(edge_id: String) -> bool:
    if not _edges.has(edge_id):
        return _fail("edge_id '%s' does not exist" % edge_id)
    _edges.erase(edge_id)
    _clear_error()
    return true

func get_route(edge_id: String) -> RouteEdge:
    return (_edges[edge_id] as RouteEdge).duplicate_edge() if _edges.has(edge_id) else null

func get_routes() -> Array:
    var result: Array = []
    for edge_id in _sorted_edge_ids():
        result.append((_edges[edge_id] as RouteEdge).duplicate_edge())
    return result

func get_route_count() -> int:
    return _edges.size()

## 创建整张 Map 的深副本，供 standalone 控制器维持独占所有权。
func duplicate_map() -> SceneMap:
    var result := SceneMap.new()
    for node_id in _sorted_node_ids():
        result._nodes[node_id] = _copy_node(_nodes[node_id] as SceneNode)
    for edge_id in _sorted_edge_ids():
        result._edges[edge_id] = (_edges[edge_id] as RouteEdge).duplicate_edge()
    result._entry_node_id = _entry_node_id
    return result

## 删除显式出口并同步清理它占用的 RouteEdge。
func remove_exit(node_id: String, port_id: String) -> bool:
    var node := get_node(node_id)
    if node == null:
        return _fail("node_id '%s' does not exist" % node_id)
    if not node.remove_exit(port_id):
        return _fail(node.last_error)
    var remove_ids: Array = []
    for edge_id in _sorted_edge_ids():
        if (_edges[edge_id] as RouteEdge).starts_at_scene_exit(node_id, port_id):
            remove_ids.append(edge_id)
    _erase_edges(remove_ids)
    _nodes[node_id] = _copy_node(node)
    _clear_error()
    return true

## 删除 switch case 及其子树，并清理所有被删除叶子分支的 RouteEdge。
func remove_condition_branch(node_id: String, branch_id: String) -> bool:
    var node := get_node(node_id)
    if node == null:
        return _fail("node_id '%s' does not exist" % node_id)
    var before := _condition_branch_set(node)
    if not node.remove_condition_branch(branch_id):
        return _fail(node.last_error)
    _remove_deleted_condition_edges(node_id, before, _condition_branch_set(node))
    _nodes[node_id] = _copy_node(node)
    _clear_error()
    return true

func remove_condition_wrapper(node_id: String, wrapper_id: String) -> bool:
    var node := get_node(node_id)
    if node == null:
        return _fail("node_id '%s' does not exist" % node_id)
    var before := _condition_branch_set(node)
    if not node.remove_condition_wrapper(wrapper_id):
        return _fail(node.last_error)
    _remove_deleted_condition_edges(node_id, before, _condition_branch_set(node))
    _nodes[node_id] = _copy_node(node)
    _clear_error()
    return true

func clear_condition_tree(node_id: String) -> bool:
    var node := get_node(node_id)
    if node == null:
        return _fail("node_id '%s' does not exist" % node_id)
    if not node.has_condition_tree():
        return _fail("condition tree does not exist")
    node.clear_condition_tree()
    var remove_ids: Array = []
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        if edge.source_node_id == node_id and edge.source_kind == RouteEdge.SOURCE_CONDITION_BRANCH:
            remove_ids.append(edge_id)
    _erase_edges(remove_ids)
    _nodes[node_id] = _copy_node(node)
    _clear_error()
    return true

func get_diagnostics() -> Array:
    var diagnostics: Array = []
    if _nodes.is_empty():
        return [_diagnostic("error", "SceneMap 中没有任何 SceneNode。")]
    if _entry_node_id.is_empty():
        diagnostics.append(_diagnostic("error", "SceneMap 尚未设置入口 Node。"))
    elif not _nodes.has(_entry_node_id):
        diagnostics.append(_diagnostic("error", "入口 Node 不存在：%s" % _entry_node_id))

    var scene_ids: Dictionary = {}
    for node_id in _sorted_node_ids():
        var node := _nodes[node_id] as SceneNode
        for message in node.validate_self():
            diagnostics.append(_diagnostic("error", "nodes.%s: %s" % [node_id, message]))
        if scene_ids.has(node.scene_id):
            diagnostics.append(_diagnostic("error", "scene_id '%s' 被多个 Node 使用。" % node.scene_id))
        scene_ids[node.scene_id] = node_id

    var used_endpoints: Dictionary = {}
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        for message in edge.validate_self("edges.%s" % edge_id):
            diagnostics.append(_diagnostic("error", str(message)))
        if not _nodes.has(edge.source_node_id):
            diagnostics.append(_diagnostic("error", "edges.%s 的源 Node 不存在：%s" % [edge_id, edge.source_node_id]))
        else:
            var source := _resolve_source(_nodes[edge.source_node_id] as SceneNode, edge)
            if not bool(source["ok"]):
                diagnostics.append(_diagnostic("error", "edges.%s: %s" % [edge_id, source["message"]]))
        if not _nodes.has(edge.target_node_id):
            diagnostics.append(_diagnostic("error", "edges.%s 的目标 Node 不存在：%s" % [edge_id, edge.target_node_id]))
        var endpoint_key := edge.source_endpoint_key()
        if used_endpoints.has(endpoint_key):
            diagnostics.append(_diagnostic("error", "源端点 '%s' 被多条 RouteEdge 占用。" % endpoint_key))
        used_endpoints[endpoint_key] = edge_id

    for node_id in _sorted_node_ids():
        var node := _nodes[node_id] as SceneNode
        for port in node.get_exits():
            var key := "%s::exit::%s" % [node_id, port.port_id]
            if not used_endpoints.has(key):
                diagnostics.append(_diagnostic("error", "Node '%s' 的出口 '%s' 没有连接目标 Scene。" % [node.scene_id, port.name]))
        var tree := node.get_condition_tree()
        if tree != null:
            for endpoint in tree.get_leaf_endpoints():
                var key := "%s::condition::%s::%s" % [node_id, endpoint["wrapperId"], endpoint["branchId"]]
                if not used_endpoints.has(key):
                    diagnostics.append(_diagnostic("error", "Node '%s' 的条件分支 '%s/%s' 没有连接目标 Scene。" % [node.scene_id, endpoint["wrapperId"], endpoint["branchId"]]))

    if _nodes.has(_entry_node_id):
        var reachable := _collect_reachable_nodes()
        for node_id in _sorted_node_ids():
            if not reachable.has(node_id):
                diagnostics.append(_diagnostic("warning", "Scene '%s' 无法从入口 Node 到达。" % (_nodes[node_id] as SceneNode).scene_id))
    if diagnostics.is_empty():
        diagnostics.append(_diagnostic("ok", "SceneMap 图结构校验通过。"))
    return diagnostics

## 项目/导出边界的变量类型诊断；结构诊断仍由 get_diagnostics() 提供。
func get_export_diagnostics(variable_catalog: Dictionary) -> Array:
    var diagnostics: Array = []
    for diagnostic in get_diagnostics():
        if str(diagnostic["severity"]) != "ok":
            diagnostics.append(diagnostic)
    var compiler := LuaConditionCompiler.new()
    for node_id in _sorted_node_ids():
        var tree := (_nodes[node_id] as SceneNode).get_condition_tree()
        if tree == null:
            continue
        var result := compiler.compile(tree, variable_catalog)
        for message in result["diagnostics"]:
            diagnostics.append(_diagnostic("error", "nodes.%s conditions: %s" % [node_id, message]))
    if diagnostics.is_empty():
        diagnostics.append(_diagnostic("ok", "SceneMap 导出校验通过。"))
    return diagnostics

func validate_self() -> Array:
    var messages: Array = []
    for diagnostic in get_diagnostics():
        if str(diagnostic["severity"]) != "ok":
            messages.append("%s: %s" % [diagnostic["severity"], diagnostic["message"]])
    return messages

func to_editor_dict() -> Dictionary:
    var nodes_data: Array = []
    for node_id in _sorted_node_ids():
        nodes_data.append((_nodes[node_id] as SceneNode).to_editor_dict())
    var edges_data: Array = []
    for edge_id in _sorted_edge_ids():
        edges_data.append((_edges[edge_id] as RouteEdge).to_editor_dict())
    return {"entryNodeId": _entry_node_id, "nodes": nodes_data, "edges": edges_data}

func to_runtime_scenes() -> Array:
    if _has_blocking_errors():
        return []
    var scenes: Array = []
    for node_id in _sorted_node_ids():
        scenes.append((_nodes[node_id] as SceneNode).to_runtime_scene())
    _clear_error()
    return scenes

func to_runtime_routes() -> Dictionary:
    if _has_blocking_errors():
        return {}
    var routes: Dictionary = {}
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        var source_node := _nodes[edge.source_node_id] as SceneNode
        var target_node := _nodes[edge.target_node_id] as SceneNode
        var source := _resolve_source(source_node, edge)
        if not bool(source["ok"]):
            return _fail_dictionary(str(source["message"]))
        if not routes.has(source_node.scene_id):
            routes[source_node.scene_id] = {}
        (routes[source_node.scene_id] as Dictionary)[str(source["port"])] = target_node.scene_id
    _clear_error()
    return routes

func to_runtime_definition(variable_catalog: Dictionary = {}) -> Dictionary:
    if _has_blocking_errors() or _has_export_errors(variable_catalog):
        return {}
    var entry := get_entry_node()
    if entry == null:
        return _fail_dictionary("entry node cannot be resolved")
    var scenes := to_runtime_scenes()
    var routes := to_runtime_routes()
    if not last_error.is_empty():
        return {}
    return {"entryScene": entry.scene_id, "scenes": scenes, "routes": routes}

func _resolve_source(node: SceneNode, edge: RouteEdge) -> Dictionary:
    if edge.source_kind == RouteEdge.SOURCE_SCENE_EXIT:
        var port := node.get_exit(edge.source_port_id)
        if port == null:
            return {"ok": false, "message": "source port '%s' does not exist on node '%s'" % [edge.source_port_id, node.node_id]}
        return {"ok": true, "port": port.name}
    if edge.source_kind == RouteEdge.SOURCE_CONDITION_BRANCH:
        var tree := node.get_condition_tree()
        if tree == null:
            return {"ok": false, "message": "source node '%s' has no condition tree" % node.node_id}
        if not tree.is_leaf_branch(edge.source_wrapper_id, edge.source_branch_id):
            return {"ok": false, "message": "condition source '%s/%s' is missing or is not a leaf branch" % [edge.source_wrapper_id, edge.source_branch_id]}
        return {"ok": true, "port": tree.runtime_port(edge.source_wrapper_id, edge.source_branch_id)}
    return {"ok": false, "message": "unsupported source kind '%s'" % edge.source_kind}

func _collect_reachable_nodes() -> Dictionary:
    var reachable: Dictionary = {}
    if not _nodes.has(_entry_node_id):
        return reachable
    var pending: Array = [_entry_node_id]
    reachable[_entry_node_id] = true
    while not pending.is_empty():
        var current := str(pending.pop_front())
        for edge_id in _sorted_edge_ids():
            var edge := _edges[edge_id] as RouteEdge
            if edge.source_node_id != current or not _nodes.has(edge.target_node_id):
                continue
            if not bool(_resolve_source(_nodes[current] as SceneNode, edge)["ok"]):
                continue
            if not reachable.has(edge.target_node_id):
                reachable[edge.target_node_id] = true
                pending.append(edge.target_node_id)
    return reachable

func _condition_branch_set(node: SceneNode) -> Dictionary:
    var result: Dictionary = {}
    var tree := node.get_condition_tree()
    if tree != null:
        for branch_id in tree.get_all_branch_ids():
            result[branch_id] = true
    return result

func _remove_deleted_condition_edges(node_id: String, before: Dictionary, after: Dictionary) -> void:
    var remove_ids: Array = []
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        if edge.source_node_id != node_id or edge.source_kind != RouteEdge.SOURCE_CONDITION_BRANCH:
            continue
        if before.has(edge.source_branch_id) and not after.has(edge.source_branch_id):
            remove_ids.append(edge_id)
    _erase_edges(remove_ids)

func _erase_edges(edge_ids: Array) -> void:
    for edge_id in edge_ids:
        _edges.erase(edge_id)

func _find_node_id_by_scene_id(scene_id: String) -> String:
    for node_id in _sorted_node_ids():
        if (_nodes[node_id] as SceneNode).scene_id == scene_id:
            return node_id
    return ""

func _find_edge_id_by_endpoint(endpoint_key: String) -> String:
    for edge_id in _sorted_edge_ids():
        if (_edges[edge_id] as RouteEdge).source_endpoint_key() == endpoint_key:
            return edge_id
    return ""

func _has_blocking_errors() -> bool:
    for diagnostic in get_diagnostics():
        if str(diagnostic["severity"]) == "error":
            _fail(str(diagnostic["message"]))
            return true
    return false

func _has_export_errors(variable_catalog: Dictionary) -> bool:
    for diagnostic in get_export_diagnostics(variable_catalog):
        if str(diagnostic["severity"]) == "error":
            _fail(str(diagnostic["message"]))
            return true
    return false

func _diagnostic(severity: String, message: String) -> Dictionary:
    return {"severity": severity, "message": message}

func _sorted_node_ids() -> Array:
    var ids := _nodes.keys()
    ids.sort()
    return ids

func _sorted_edge_ids() -> Array:
    var ids := _edges.keys()
    ids.sort()
    return ids

func _copy_node(node: SceneNode) -> SceneNode:
    return SceneNode.new(
        node.node_id, node.scene_id, node.title, node.main_script,
        node.get_cast(), node.get_exits(), node.position, node.get_condition_tree(),
    )

func _fail(message: String) -> bool:
    last_error = message
    return false

func _fail_dictionary(message: String) -> Dictionary:
    last_error = message
    return {}

func _clear_error() -> void:
    last_error = ""
