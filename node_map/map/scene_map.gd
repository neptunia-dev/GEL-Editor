extends RefCounted
class_name SceneMap

## 多个 SceneNode 组成的剧情图模型。
##
## SceneMap 是 Node Map 层的聚合根。所有会影响全局关系的操作都应该经过这个类，
## 而不是让调用方直接修改节点集合或连线集合。
##
## SceneMap 与单个 SceneNode 的职责边界：
## - SceneNode 只管理一个 Scene 自身的字段、角色和出口。
## - RouteEdge 只保存源 Node、源出口和目标 Node 的编辑器 ID。
## - SceneMap 负责解析这些 ID，并保证整张图的关系有效。
##
## 这里不继承 Godot 的 Node，也不负责绘制 GraphEdit。它是纯数据模型，未来的
## SceneMapView 才会把它显示为 Godot 画布。

## 内部以 node_id 为键保存 SceneNode。
##
## 保存的是副本，不是调用方传入的对象本身。这样外部修改自己的 SceneNode，不会
## 绕过 SceneMap 的 scene_id 唯一性和边引用检查。
var _nodes: Dictionary = {}

## 内部以 edge_id 为键保存 RouteEdge。
##
## Edge 同样使用副本保存。RouteEdge 只包含字符串 ID，因此不需要持有 Node 对象引用。
var _edges: Dictionary = {}

## 入口使用编辑器 node_id，而不是运行时 scene_id。
##
## Scene ID 可以被用户重命名；使用 node_id 可以保证入口仍指向原来的编辑器 Node。
## 空字符串表示当前没有设置入口。
var _entry_node_id: String = ""

## 最近一次 Map 操作的失败原因。
##
## 修改方法返回 bool；调用方收到 false 后可以读取此字段，把具体原因展示给用户。
var last_error: String = ""

## 添加一个 SceneNode。
##
## 添加前会执行 Node 的本地校验，并检查：
## - node_id 是否已经存在；
## - scene_id 是否已经被其他 Node 使用。
##
## 通过检查后保存 Node 的副本。Map 不会自动把第一个节点设置为入口，入口必须由
## 调用方显式设置，避免“添加顺序”意外决定故事起点。
func add_node(node: SceneNode) -> bool:
    if node == null:
        return _fail("node must not be null")

    var node_errors := node.validate_self()
    if not node_errors.is_empty():
        return _fail("cannot add node: %s" % str(node_errors[0]))

    if _nodes.has(node.node_id):
        return _fail("node_id '%s' already exists" % node.node_id)
    if _find_node_id_by_scene_id(node.scene_id) != "":
        return _fail("scene_id '%s' already exists" % node.scene_id)

    _nodes[node.node_id] = _copy_node(node)
    _clear_error()
    return true

## 更新一个已经存在的 SceneNode。
##
## node_id 是编辑器身份，更新时必须保持不变；如果需要更换 node_id，应通过更高层
## 的迁移操作处理，而不能让 Edge 引用在没有通知的情况下失效。
## scene_id 可以修改，但仍然必须满足整张 Map 的唯一性约束。
func update_node(node: SceneNode) -> bool:
    if node == null:
        return _fail("node must not be null")
    if not _nodes.has(node.node_id):
        return _fail("node_id '%s' does not exist" % node.node_id)

    var node_errors := node.validate_self()
    if not node_errors.is_empty():
        return _fail("cannot update node: %s" % str(node_errors[0]))

    var other_node_id := _find_node_id_by_scene_id(node.scene_id)
    if other_node_id != "" and other_node_id != node.node_id:
        return _fail("scene_id '%s' already exists" % node.scene_id)

    _nodes[node.node_id] = _copy_node(node)
    _clear_error()
    return true

## 删除一个 SceneNode，并级联删除与它相关的所有 RouteEdge。
##
## 删除操作会清理：
## - 从该 Node 发出的边；
## - 指向该 Node 的边；
## - 如果该 Node 是入口，则清空入口配置。
func remove_node(node_id: String) -> bool:
    if not _nodes.has(node_id):
        return _fail("node_id '%s' does not exist" % node_id)

    var edges_to_remove: Array = []
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        if edge.references_node(node_id):
            edges_to_remove.append(edge_id)
    for edge_id in edges_to_remove:
        _edges.erase(edge_id)

    _nodes.erase(node_id)
    if _entry_node_id == node_id:
        _entry_node_id = ""
    _clear_error()
    return true

## 按编辑器 node_id 获取一个 SceneNode 的独立副本。
## 找不到时返回 null。
func get_node(node_id: String) -> SceneNode:
    if not _nodes.has(node_id):
        return null
    return _copy_node(_nodes[node_id] as SceneNode)

## 判断 Map 是否包含指定的编辑器 Node。
func has_node(node_id: String) -> bool:
    return _nodes.has(node_id)

## 返回所有 Node 的独立副本，并按 node_id 稳定排序。
## 稳定排序让编辑器保存和测试结果不依赖 Dictionary 的插入顺序。
func get_nodes() -> Array:
    var result: Array = []
    for node_id in _sorted_node_ids():
        result.append(_copy_node(_nodes[node_id] as SceneNode))
    return result

## 返回当前 Map 中的 Node 数量。
func get_node_count() -> int:
    return _nodes.size()

## 通过 Map 修改指定 Node 的 Scene ID。
##
## 不能直接建议调用方从 get_node() 得到副本后随意改名再丢弃，因为 Map 需要检查
## 全局 scene_id 唯一性。这个方法将改名和受控更新合并为一个原子操作。
func rename_scene(node_id: String, new_scene_id: String) -> bool:
    var node := get_node(node_id)
    if node == null:
        return _fail("node_id '%s' does not exist" % node_id)
    if not node.rename_scene(new_scene_id):
        return _fail(node.last_error)
    return update_node(node)

## 设置故事入口 Node。
##
## 入口引用保存为 node_id。导出 Runtime Package 时再解析成对应的 scene_id。
func set_entry_node(node_id: String) -> bool:
    if not _nodes.has(node_id):
        return _fail("entry node '%s' does not exist" % node_id)
    _entry_node_id = node_id
    _clear_error()
    return true

## 清除入口 Node。
## 清除后 Map 可以继续作为编辑器草稿存在，但不能通过 Runtime 导出校验。
func clear_entry_node() -> void:
    _entry_node_id = ""
    _clear_error()

## 返回当前入口的编辑器 node_id；未设置时返回空字符串。
func get_entry_node_id() -> String:
    return _entry_node_id

## 返回入口 Node 的独立副本；未设置或引用失效时返回 null。
func get_entry_node() -> SceneNode:
    if _entry_node_id.is_empty() or not _nodes.has(_entry_node_id):
        return null
    return get_node(_entry_node_id)

## 添加一条 RouteEdge。
##
## 添加前会检查：
## - Edge 自身字段有效；
## - edge_id 没有重复；
## - 源 Node 和目标 Node 都存在；
## - source_port_id 属于源 Node；
## - 同一个源出口还没有另一条边。
##
## 允许目标 Node 与源 Node 相同，因为剧情图可以包含合法循环。
func add_route(edge: RouteEdge) -> bool:
    if edge == null:
        return _fail("edge must not be null")

    var edge_errors := edge.validate_self()
    if not edge_errors.is_empty():
        return _fail("cannot add edge: %s" % str(edge_errors[0]))

    if _edges.has(edge.edge_id):
        return _fail("edge_id '%s' already exists" % edge.edge_id)
    if not _nodes.has(edge.source_node_id):
        return _fail("source node '%s' does not exist" % edge.source_node_id)
    if not _nodes.has(edge.target_node_id):
        return _fail("target node '%s' does not exist" % edge.target_node_id)

    var source_node := _nodes[edge.source_node_id] as SceneNode
    if source_node.get_exit(edge.source_port_id) == null:
        return _fail("source port '%s' does not exist on node '%s'" % [edge.source_port_id, edge.source_node_id])

    if _find_edge_id_by_source_port(edge.source_node_id, edge.source_port_id) != "":
        return _fail("source port '%s' on node '%s' already has a route" % [edge.source_port_id, edge.source_node_id])

    _edges[edge.edge_id] = edge.duplicate_edge()
    _clear_error()
    return true

## 删除一条 RouteEdge。
func remove_route(edge_id: String) -> bool:
    if not _edges.has(edge_id):
        return _fail("edge_id '%s' does not exist" % edge_id)
    _edges.erase(edge_id)
    _clear_error()
    return true

## 按 edge_id 获取一条 RouteEdge 的独立副本。
func get_route(edge_id: String) -> RouteEdge:
    if not _edges.has(edge_id):
        return null
    return (_edges[edge_id] as RouteEdge).duplicate_edge()

## 返回所有 RouteEdge 的独立副本，并按 edge_id 稳定排序。
func get_routes() -> Array:
    var result: Array = []
    for edge_id in _sorted_edge_ids():
        result.append((_edges[edge_id] as RouteEdge).duplicate_edge())
    return result

## 返回当前 Map 中的连线数量。
func get_route_count() -> int:
    return _edges.size()

## 取得结构诊断结果。
##
## 返回的每一项都是：
##
##     {"severity": "error" | "warning" | "ok", "message": String}
##
## error 会阻止 Runtime Package 导出；warning（例如不可达 Node）允许编辑器继续
## 保存草稿，但应在诊断面板中提醒用户。
func get_diagnostics() -> Array:
    var diagnostics: Array = []

    if _nodes.is_empty():
        diagnostics.append(_diagnostic("error", "SceneMap 中没有任何 SceneNode。"))
        return diagnostics

    if _entry_node_id.is_empty():
        diagnostics.append(_diagnostic("error", "SceneMap 尚未设置入口 Node。"))
    elif not _nodes.has(_entry_node_id):
        diagnostics.append(_diagnostic("error", "入口 Node 不存在：%s" % _entry_node_id))

    # 检查每个 Node 的本地数据，并再次检查全局 scene_id 唯一性。
    var scene_ids: Dictionary = {}
    for node_id in _sorted_node_ids():
        var node := _nodes[node_id] as SceneNode
        var node_errors := node.validate_self()
        for message in node_errors:
            diagnostics.append(_diagnostic("error", "nodes.%s: %s" % [node_id, message]))

        if scene_ids.has(node.scene_id):
            diagnostics.append(_diagnostic("error", "scene_id '%s' 被多个 Node 使用。" % node.scene_id))
        else:
            scene_ids[node.scene_id] = node_id

    # 检查 Edge 自身和它所引用的两个端点。
    var used_source_ports: Dictionary = {}
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        var edge_errors := edge.validate_self()
        for message in edge_errors:
            diagnostics.append(_diagnostic("error", "edges.%s: %s" % [edge_id, message]))

        if not _nodes.has(edge.source_node_id):
            diagnostics.append(_diagnostic("error", "edges.%s 的源 Node 不存在：%s" % [edge_id, edge.source_node_id]))
        else:
            var source_node := _nodes[edge.source_node_id] as SceneNode
            if source_node.get_exit(edge.source_port_id) == null:
                diagnostics.append(_diagnostic("error", "edges.%s 的源出口不存在：%s" % [edge_id, edge.source_port_id]))

        if not _nodes.has(edge.target_node_id):
            diagnostics.append(_diagnostic("error", "edges.%s 的目标 Node 不存在：%s" % [edge_id, edge.target_node_id]))

        var source_key := "%s::%s" % [edge.source_node_id, edge.source_port_id]
        if used_source_ports.has(source_key):
            diagnostics.append(_diagnostic("error", "源出口 '%s' 被多条 RouteEdge 占用。" % source_key))
        else:
            used_source_ports[source_key] = edge_id

    # Runtime Package v1 要求每个声明出口都有且只有一个路由。
    for node_id in _sorted_node_ids():
        var node := _nodes[node_id] as SceneNode
        for port in node.get_exits():
            var source_key := "%s::%s" % [node_id, port.port_id]
            if not used_source_ports.has(source_key):
                diagnostics.append(_diagnostic(
                    "error",
                    "Node '%s' 的出口 '%s' 没有连接目标 Scene。" % [node.scene_id, port.name],
                ))

    # 只有入口有效时才计算可达性；不可达是警告，不把合法的草稿循环误报为错误。
    if _nodes.has(_entry_node_id):
        var reachable := _collect_reachable_nodes()
        for node_id in _sorted_node_ids():
            if not reachable.has(node_id):
                var unreachable_node := _nodes[node_id] as SceneNode
                diagnostics.append(_diagnostic(
                    "warning",
                    "Scene '%s' 无法从入口 Node 到达。" % unreachable_node.scene_id,
                ))

    if diagnostics.is_empty():
        diagnostics.append(_diagnostic("ok", "SceneMap 图结构校验通过。"))
    return diagnostics

## 返回适合旧式调用方使用的字符串诊断列表。
##
## get_diagnostics() 保留 severity；这个方法只把非 OK 项展平为文字，和 SceneNode 的
## validate_self() 保持相同的调用习惯。
func validate_self() -> Array:
    var messages: Array = []
    for diagnostic in get_diagnostics():
        if str(diagnostic["severity"]) == "ok":
            continue
        messages.append("%s: %s" % [diagnostic["severity"], diagnostic["message"]])
    return messages

## 将整个 Map 转换为编辑器工程中的字典。
##
## 这里保留编辑器 ID、出口 port_id、Node 位置和 entryNodeId；不做 Runtime Package
## 的字段裁剪。结果中的数组按稳定 ID 排序，便于版本控制和测试比较。
func to_editor_dict() -> Dictionary:
    var nodes_data: Array = []
    for node_id in _sorted_node_ids():
        nodes_data.append((_nodes[node_id] as SceneNode).to_editor_dict())

    var edges_data: Array = []
    for edge_id in _sorted_edge_ids():
        edges_data.append((_edges[edge_id] as RouteEdge).to_editor_dict())

    return {
        "entryNodeId": _entry_node_id,
        "nodes": nodes_data,
        "edges": edges_data,
    }

## 将 Map 中的所有 Node 转换为 Runtime Package 的 scenes 数组。
## 有 error 诊断时返回空数组，并把第一个错误写入 last_error。
func to_runtime_scenes() -> Array:
    if _has_blocking_errors():
        return []

    var scenes: Array = []
    for node_id in _sorted_node_ids():
        scenes.append((_nodes[node_id] as SceneNode).to_runtime_scene())
    _clear_error()
    return scenes

## 将编辑器 Edge 转换为 Runtime Package 的 routes 对象。
##
## 转换时通过 source_port_id 找到出口名称，通过两端 node_id 找到运行时 scene_id：
##
##     source node_id + source port_id
##         -> source scene_id + ExitPort.name
##         -> target scene_id
func to_runtime_routes() -> Dictionary:
    if _has_blocking_errors():
        return {}

    var routes: Dictionary = {}
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        var source_node := _nodes[edge.source_node_id] as SceneNode
        var target_node := _nodes[edge.target_node_id] as SceneNode
        var source_port := source_node.get_exit(edge.source_port_id)
        if source_port == null:
            return _fail_dictionary("source port '%s' cannot be resolved" % edge.source_port_id)

        if not routes.has(source_node.scene_id):
            routes[source_node.scene_id] = {}
        var scene_routes: Dictionary = routes[source_node.scene_id]
        scene_routes[source_port.name] = target_node.scene_id

    _clear_error()
    return routes

## 将 Map 的入口、Scene 定义和路由组合成 Runtime Package 的剧情部分。
##
## 这里不生成 packageId、assets、characters 或 variables；那些字段属于更高层的 Project
## 或 Exporter。返回结果可以作为完整 manifest 的一部分。
func to_runtime_definition() -> Dictionary:
    if _has_blocking_errors():
        return {}

    var entry_node := get_entry_node()
    if entry_node == null:
        return _fail_dictionary("entry node cannot be resolved")

    var scenes := to_runtime_scenes()
    var routes := to_runtime_routes()
    if scenes.is_empty() and not _nodes.is_empty():
        return {}
    if not last_error.is_empty():
        return {}

    return {
        "entryScene": entry_node.scene_id,
        "scenes": scenes,
        "routes": routes,
    }

## 找到使用指定 scene_id 的编辑器 Node ID。
## 找不到时返回空字符串；scene_id 本身允许为空时仍然由 Node 校验拦截。
func _find_node_id_by_scene_id(scene_id: String) -> String:
    for node_id in _sorted_node_ids():
        var node := _nodes[node_id] as SceneNode
        if node.scene_id == scene_id:
            return node_id
    return ""

## 找到占用指定源出口的 Edge ID。
func _find_edge_id_by_source_port(source_node_id: String, source_port_id: String) -> String:
    for edge_id in _sorted_edge_ids():
        var edge := _edges[edge_id] as RouteEdge
        if edge.starts_at(source_node_id, source_port_id):
            return edge_id
    return ""

## 深度优先/广度优先遍历都可以完成这里的可达性计算；使用待处理数组实现 BFS，
## 并且只沿着当前引用仍然有效的 Edge 前进，避免损坏草稿把不存在的 Node 算成可达。
func _collect_reachable_nodes() -> Dictionary:
    var reachable: Dictionary = {}
    if _entry_node_id.is_empty() or not _nodes.has(_entry_node_id):
        return reachable

    var pending: Array = [_entry_node_id]
    reachable[_entry_node_id] = true
    while not pending.is_empty():
        var current_node_id := str(pending.pop_front())
        for edge_id in _sorted_edge_ids():
            var edge := _edges[edge_id] as RouteEdge
            if edge.source_node_id != current_node_id:
                continue
            if not _nodes.has(edge.target_node_id):
                continue
            var source_node := _nodes[current_node_id] as SceneNode
            if source_node.get_exit(edge.source_port_id) == null:
                continue
            if not reachable.has(edge.target_node_id):
                reachable[edge.target_node_id] = true
                pending.append(edge.target_node_id)
    return reachable

## 判断诊断中是否存在会阻止导出的 error。
func _has_blocking_errors() -> bool:
    for diagnostic in get_diagnostics():
        if str(diagnostic["severity"]) == "error":
            _fail(str(diagnostic["message"]))
            return true
    return false

## 创建统一格式的诊断字典。
func _diagnostic(severity: String, message: String) -> Dictionary:
    return {
        "severity": severity,
        "message": message,
    }

## 按 node_id 返回稳定排序后的键列表。
func _sorted_node_ids() -> Array:
    var ids: Array = _nodes.keys()
    ids.sort()
    return ids

## 按 edge_id 返回稳定排序后的键列表。
func _sorted_edge_ids() -> Array:
    var ids: Array = _edges.keys()
    ids.sort()
    return ids

## 复制一个已验证的 SceneNode。
##
## SceneNode 自身已经通过 get_cast()/get_exits() 提供深复制边界，因此这里不需要访问
## 它的私有数组。Map 只在 add/update 时复制合法对象；内部对象不会暴露给外部。
func _copy_node(node: SceneNode) -> SceneNode:
    return SceneNode.new(
        node.node_id,
        node.scene_id,
        node.title,
        node.main_script,
        node.get_cast(),
        node.get_exits(),
        node.position,
    )

## 记录错误并返回 false。
func _fail(message: String) -> bool:
    last_error = message
    return false

## 记录错误并返回空字典，供字典型转换方法使用。
func _fail_dictionary(message: String) -> Dictionary:
    last_error = message
    return {}

## 成功操作后清理旧错误，避免调用方读到过期诊断。
func _clear_error() -> void:
    last_error = ""
