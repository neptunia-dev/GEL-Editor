extends ConditionWrapper
class_name SwitchCaseWrapper

var variable_key: String
var case_branch_ids: Array = []
var default_branch_id: String

func _init(
        p_wrapper_id: String = "",
        p_variable_key: String = "",
        p_case_branch_ids: Array = [],
        p_default_branch_id: String = "",
) -> void:
    super(p_wrapper_id)
    variable_key = p_variable_key
    case_branch_ids = p_case_branch_ids.duplicate()
    default_branch_id = p_default_branch_id

func get_branch_ids() -> Array:
    var result := case_branch_ids.duplicate()
    result.append(default_branch_id)
    return result

func duplicate_wrapper() -> ConditionWrapper:
    return SwitchCaseWrapper.new(wrapper_id, variable_key, case_branch_ids, default_branch_id)

func remove_case_branch(branch_id: String) -> bool:
    var index := case_branch_ids.find(branch_id)
    if index < 0:
        return false
    case_branch_ids.remove_at(index)
    return true

func validate_self(path: String = "wrapper") -> Array:
    var errors := super(path)
    if not ConditionWrapper.is_valid_variable_key(variable_key):
        errors.append("%s.variable_key must match ^[a-z][a-z0-9_.-]*$" % path)
    if default_branch_id.is_empty():
        errors.append("%s.default_branch_id must not be empty" % path)
    var seen: Dictionary = {}
    for index in range(case_branch_ids.size()):
        var branch_id = case_branch_ids[index]
        if not branch_id is String or str(branch_id).is_empty():
            errors.append("%s.case_branch_ids[%d] must be a non-empty string" % [path, index])
            continue
        if seen.has(branch_id):
            errors.append("%s contains duplicate case branch '%s'" % [path, branch_id])
        seen[branch_id] = true
    if seen.has(default_branch_id):
        errors.append("%s default branch must not also be a case branch" % path)
    return errors

func to_editor_dict() -> Dictionary:
    return {
        "wrapperId": wrapper_id,
        "type": "switch",
        "variableKey": variable_key,
        "caseBranchIds": case_branch_ids.duplicate(),
        "defaultBranchId": default_branch_id,
    }
