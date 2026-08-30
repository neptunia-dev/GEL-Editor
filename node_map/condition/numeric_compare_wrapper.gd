extends ConditionWrapper
class_name NumericCompareWrapper

var left_operand: NumericOperand
var right_operand: NumericOperand
var less_branch_id: String
var equal_branch_id: String
var greater_branch_id: String

func _init(
        p_wrapper_id: String = "",
        p_left_operand: NumericOperand = null,
        p_right_operand: NumericOperand = null,
        p_less_branch_id: String = "",
        p_equal_branch_id: String = "",
        p_greater_branch_id: String = "",
) -> void:
    super(p_wrapper_id)
    left_operand = p_left_operand.duplicate_operand() if p_left_operand != null else null
    right_operand = p_right_operand.duplicate_operand() if p_right_operand != null else null
    less_branch_id = p_less_branch_id
    equal_branch_id = p_equal_branch_id
    greater_branch_id = p_greater_branch_id

func get_branch_ids() -> Array:
    return [less_branch_id, equal_branch_id, greater_branch_id]

func duplicate_wrapper() -> ConditionWrapper:
    return NumericCompareWrapper.new(
        wrapper_id, left_operand, right_operand,
        less_branch_id, equal_branch_id, greater_branch_id,
    )

func validate_self(path: String = "wrapper") -> Array:
    var errors := super(path)
    if left_operand == null:
        errors.append("%s.left_operand must not be null" % path)
    else:
        errors.append_array(left_operand.validate_self("%s.left_operand" % path))
    if right_operand == null:
        errors.append("%s.right_operand must not be null" % path)
    else:
        errors.append_array(right_operand.validate_self("%s.right_operand" % path))
    var ids := get_branch_ids()
    var seen: Dictionary = {}
    for branch_id in ids:
        if str(branch_id).is_empty():
            errors.append("%s numeric branch IDs must not be empty" % path)
        elif seen.has(branch_id):
            errors.append("%s numeric branch IDs must be distinct" % path)
        seen[branch_id] = true
    return errors

func to_editor_dict() -> Dictionary:
    return {
        "wrapperId": wrapper_id,
        "type": "numeric_compare",
        "leftOperand": left_operand.to_editor_dict() if left_operand != null else null,
        "rightOperand": right_operand.to_editor_dict() if right_operand != null else null,
        "lessBranchId": less_branch_id,
        "equalBranchId": equal_branch_id,
        "greaterBranchId": greater_branch_id,
    }
