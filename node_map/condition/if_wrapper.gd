extends ConditionWrapper
class_name IfWrapper

var variable_key: String
var true_branch_id: String
var false_branch_id: String

func _init(
        p_wrapper_id: String = "",
        p_variable_key: String = "",
        p_true_branch_id: String = "",
        p_false_branch_id: String = "",
) -> void:
    super(p_wrapper_id)
    variable_key = p_variable_key
    true_branch_id = p_true_branch_id
    false_branch_id = p_false_branch_id

func get_branch_ids() -> Array:
    return [true_branch_id, false_branch_id]

func duplicate_wrapper() -> ConditionWrapper:
    return IfWrapper.new(wrapper_id, variable_key, true_branch_id, false_branch_id)

func validate_self(path: String = "wrapper") -> Array:
    var errors := super(path)
    if not ConditionWrapper.is_valid_variable_key(variable_key):
        errors.append("%s.variable_key must match ^[a-z][a-z0-9_.-]*$" % path)
    if true_branch_id.is_empty():
        errors.append("%s.true_branch_id must not be empty" % path)
    if false_branch_id.is_empty():
        errors.append("%s.false_branch_id must not be empty" % path)
    if true_branch_id == false_branch_id and not true_branch_id.is_empty():
        errors.append("%s true and false branches must be different" % path)
    return errors

func to_editor_dict() -> Dictionary:
    return {
        "wrapperId": wrapper_id,
        "type": "if",
        "variableKey": variable_key,
        "trueBranchId": true_branch_id,
        "falseBranchId": false_branch_id,
    }
