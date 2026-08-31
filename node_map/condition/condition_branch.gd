extends RefCounted
class_name ConditionBranch

## 条件树中的稳定分支。child_wrapper_id 为空时，该分支是需要 Scene 路由的叶子。
var branch_id: String
var label: String
var child_wrapper_id: String
var has_match_value: bool
var match_value: Variant

func _init(
        p_branch_id: String = "",
        p_label: String = "",
        p_child_wrapper_id: String = "",
        p_has_match_value: bool = false,
        p_match_value: Variant = null,
) -> void:
    branch_id = p_branch_id
    label = p_label
    child_wrapper_id = p_child_wrapper_id
    has_match_value = p_has_match_value
    match_value = p_match_value

func duplicate_branch() -> ConditionBranch:
    return ConditionBranch.new(branch_id, label, child_wrapper_id, has_match_value, match_value)

func is_terminal() -> bool:
    return child_wrapper_id.is_empty()

func validate_self(path: String = "branch") -> Array:
    var errors: Array = []
    if not _is_safe_id(branch_id):
        errors.append("%s.branch_id must match ^[A-Za-z0-9_-]+$" % path)
    if label != label.strip_edges():
        errors.append("%s.label must not have surrounding whitespace" % path)
    if not child_wrapper_id.is_empty() and not _is_safe_id(child_wrapper_id):
        errors.append("%s.child_wrapper_id must match ^[A-Za-z0-9_-]+$" % path)
    if has_match_value and not _is_scalar_match_value(match_value):
        errors.append("%s.match_value must be nil, boolean, finite number, or string" % path)
    return errors

func to_editor_dict() -> Dictionary:
    var result: Dictionary = {
        "branchId": branch_id,
        "label": label,
    }
    if not child_wrapper_id.is_empty():
        result["childWrapperId"] = child_wrapper_id
    if has_match_value:
        result["matchValue"] = match_value
    return result

static func scalar_key(value: Variant) -> String:
    if value == null:
        return "nil"
    match typeof(value):
        TYPE_BOOL:
            return "boolean:%s" % ("true" if value else "false")
        TYPE_INT:
            return "number:%s" % String.num(float(value), 17)
        TYPE_FLOAT:
            if not is_finite_number(value):
                return "invalid"
            if float(value) == 0.0:
                return "number:0"
            return "number:%s" % String.num(float(value), 17)
        TYPE_STRING:
            return "string:%s" % value
        _:
            return "invalid"

static func is_finite_number(value: Variant) -> bool:
    if typeof(value) == TYPE_INT:
        return true
    if typeof(value) != TYPE_FLOAT:
        return false
    return not is_nan(float(value)) and not is_inf(float(value))

func _is_scalar_match_value(value: Variant) -> bool:
    return value == null or typeof(value) == TYPE_BOOL or typeof(value) == TYPE_STRING or is_finite_number(value)

func _is_safe_id(value: String) -> bool:
    var regex := RegEx.new()
    return regex.compile("^[A-Za-z0-9_-]+$") == OK and regex.search(value) != null
