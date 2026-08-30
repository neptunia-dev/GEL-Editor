extends RefCounted
class_name RouteEdge

## SceneMap 中的一条编辑器路由连线。
##
## RouteEdge 只保存编辑器稳定 ID，不直接持有 SceneNode 或 ExitPort 对象引用。
## 这样做有三个目的：
## 1. 连线可以直接序列化为 JSON；
## 2. Node 和 Edge 不会互相持有可变对象而形成循环引用；
## 3. SceneNode 的 scene_id 改名时，连线仍然可以通过 node_id 和 port_id 找到原对象。
##
## 目标端暂时没有 target_port_id。当前设计中每个 SceneNode 只有一个默认输入端口，
## 所以只需要记录 target_node_id；将来出现多个输入端口时再扩展数据结构。

## 编辑器内部的连线身份，建议使用 UUID。
## 它和 source_node_id、source_port_id、target_node_id 的语义不同，不能互相替代。
var edge_id: String

## 起点 SceneNode 的编辑器 node_id。
var source_node_id: String

## 起点 SceneNode 中某个 ExitPort 的编辑器 port_id。
## 运行时导出时，会通过这个 ID 找到出口名称。
var source_port_id: String

## 终点 SceneNode 的编辑器 node_id。
var target_node_id: String

## 最近一次本地修改或校验失败的原因。
## RouteEdge 当前没有复杂的修改方法，但保留这个字段与其他模型保持一致。
var last_error: String = ""

## 创建一条只包含 ID 引用的连线。
##
## 构造函数不检查引用的 Node 和端口是否存在，因为 RouteEdge 本身无法访问
## SceneMap。引用完整性由 SceneMap.add_route() 和 SceneMap.get_diagnostics() 检查。
func _init(
        p_edge_id: String = "",
        p_source_node_id: String = "",
        p_source_port_id: String = "",
        p_target_node_id: String = "",
) -> void:
    edge_id = p_edge_id
    source_node_id = p_source_node_id
    source_port_id = p_source_port_id
    target_node_id = p_target_node_id

## 创建当前连线的独立副本。
##
## SceneMap 保存和返回 Edge 时都使用副本，避免调用方绕过 Map 的唯一性和引用检查。
func duplicate_edge() -> RouteEdge:
    return RouteEdge.new(edge_id, source_node_id, source_port_id, target_node_id)

## 检查连线自身的字段格式。
##
## 这里不检查 ID 是否指向真实对象，也不检查同一个出口是否已有另一条连线；这些
## 都是 Map 层才能判断的跨对象规则。
func validate_self(path: String = "edge") -> Array:
    var errors: Array = []

    # 四个 ID 都是引用所必需的值。这里不强制 UUID 格式，因为编辑器工程可以
    # 在导入旧数据或测试数据时使用其他稳定的非空字符串。
    if edge_id.is_empty():
        errors.append("%s.edge_id must not be empty" % path)
    elif edge_id != edge_id.strip_edges():
        errors.append("%s.edge_id must not have surrounding whitespace" % path)

    if source_node_id.is_empty():
        errors.append("%s.source_node_id must not be empty" % path)
    elif source_node_id != source_node_id.strip_edges():
        errors.append("%s.source_node_id must not have surrounding whitespace" % path)

    if source_port_id.is_empty():
        errors.append("%s.source_port_id must not be empty" % path)
    elif source_port_id != source_port_id.strip_edges():
        errors.append("%s.source_port_id must not have surrounding whitespace" % path)

    if target_node_id.is_empty():
        errors.append("%s.target_node_id must not be empty" % path)
    elif target_node_id != target_node_id.strip_edges():
        errors.append("%s.target_node_id must not have surrounding whitespace" % path)

    return errors

## 判断这条连线是否连接指定 Node。
## 这是删除 Node 时筛选级联删除 Edge 的小工具，不负责修改任何数据。
func references_node(node_id: String) -> bool:
    return source_node_id == node_id or target_node_id == node_id

## 判断这条连线是否正好占用指定的源出口。
## SceneMap 用它保证一个本地出口最多只有一个目标。
func starts_at(source_id: String, port_id: String) -> bool:
    return source_node_id == source_id and source_port_id == port_id

## 转换为编辑器工程 JSON 中的连线对象。
## 这些字段全部是编辑器引用，Runtime Package 导出时会解析成 Scene ID 和出口名称。
func to_editor_dict() -> Dictionary:
    return {
        "edgeId": edge_id,
        "sourceNodeId": source_node_id,
        "sourcePortId": source_port_id,
        "targetNodeId": target_node_id,
    }
