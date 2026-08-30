extends RefCounted
class_name ExitPort

## SceneNode 所拥有的一个本地出口。
##
## 一个出口表达的是“当前 Scene 可以从这里离开”，例如 continue、retry 或
## true-ending。它只描述出口本身，不描述出口最终要跳转到哪个 Scene。
##
## 目标 Scene 属于未来的 Graph/RouteEdge 数据，而不是 ExitPort。这样单个 Node
## 可以独立编辑出口，Graph 再负责把出口和其他 Node 连接起来。

## 编辑器内部的稳定端口 ID。
##
## 这个 ID 建议使用 UUID。出口改名或调整显示顺序时，port_id 都应该保持不变，
## 这样未来的编辑器连线仍可以识别它所引用的是同一个出口。
var port_id: String

## 导出到 Runtime Package 的本地出口名称。
##
## 名称只要求在同一个 SceneNode 内唯一；不同 Scene 可以使用相同的出口名称，
## 因为运行时路由使用的是“源 Scene + 出口名称”的组合。
var name: String

## 创建一个出口定义。
##
## 构造函数只保存原始值，不负责检查同一个 Node 中是否已经存在相同的端口。
## 列表级别的唯一性由 SceneNode.add_exit() 和 SceneNode.validate_self() 负责。
func _init(p_port_id: String = "", p_name: String = "") -> void:
    port_id = p_port_id
    name = p_name

## 创建当前出口的独立副本。
##
## SceneNode 对外返回出口时使用副本，避免调用方直接修改 Node 内部对象。例如：
##
##     var port = node.get_exit("exit-001")
##     port.name = "changed"
##
## 上面的修改只能影响返回的副本，不会绕过 SceneNode.rename_exit() 修改 Node 内部数据。
func duplicate_port() -> ExitPort:
    return ExitPort.new(port_id, name)

## 修改出口名称，同时保留原有的 port_id。
##
## 名称会去除首尾空格，空名称直接拒绝。这里无法检查是否与同一个 Node 的其他
## 出口重名，因此完整的改名操作由 SceneNode.rename_exit() 执行。
func rename(new_name: String) -> bool:
    var normalized_name := new_name.strip_edges()
    if normalized_name.is_empty():
        return false
    name = normalized_name
    return true

## 检查单个出口自身的字段格式。
##
## path 用于在错误信息中保留字段位置，例如 exits[1]。本方法不检查名称或
## port_id 是否与其他出口重复，因为 ExitPort 不知道自己当前属于哪个列表。
func validate_self(path: String = "exit") -> Array:
    var errors: Array = []

    # port_id 是编辑器稳定引用，不能为空，也不应通过静默 trim 改变原始 ID。
    if port_id.is_empty():
        errors.append("%s.port_id must not be empty" % path)
    elif port_id != port_id.strip_edges():
        errors.append("%s.port_id must not have surrounding whitespace" % path)

    # name 会被导出到运行时，不能为空；首尾空格会导致看似相同的出口产生歧义。
    if name.is_empty():
        errors.append("%s.name must not be empty" % path)
    elif name != name.strip_edges():
        errors.append("%s.name must not have surrounding whitespace" % path)
    return errors

## 转换为编辑器工程中的字典格式。
##
## portId 是编辑器专属字段，保存它是为了让未来的连线可以引用稳定端口；该
## 字段不会直接进入 Runtime Package 的 Scene.exits 数组。
func to_editor_dict() -> Dictionary:
    return {
        "portId": port_id,
        "name": name,
    }

## 返回导出到 Runtime Package 的出口名称。
##
## Runtime Package v1 的 Scene.exits 是字符串数组，所以这里有意丢弃 port_id，
## 只保留引擎执行时可以返回的本地名称。
func to_runtime_name() -> String:
    return name
