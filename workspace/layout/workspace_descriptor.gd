extends RefCounted
class_name EditorWorkspaceDescriptor

## 中央编辑器工作区的 UI 无关注册描述。
##
## 描述对象只保存工作区的稳定 ID、显示标题、默认激活标记和默认排序顺序。
## 它不持有工作区内容 Control，也不保存当前激活状态；当前激活的工作区由
## EditorLayoutState 负责记录。

const ID_PATTERN := "^[a-z][a-z0-9_.-]*$"

var workspace_id: String
var title: String
var default_active: bool
var default_order: int

func _init(
        p_workspace_id: String = "",
        p_title: String = "",
        p_default_active: bool = false,
        p_default_order: int = 0,
) -> void:
    workspace_id = p_workspace_id
    title = p_title
    default_active = p_default_active
    default_order = p_default_order

func duplicate_descriptor():
    return get_script().new(workspace_id, title, default_active, default_order)

func validate_self() -> Array:
    var errors: Array = []
    var regex := RegEx.new()
    if regex.compile(ID_PATTERN) != OK or regex.search(workspace_id) == null:
        errors.append("workspace_id must match %s" % ID_PATTERN)
    if title.strip_edges().is_empty():
        errors.append("workspace '%s' title must not be empty" % workspace_id)
    return errors
