extends RefCounted
class_name ConditionWrapper

var wrapper_id: String

func _init(p_wrapper_id: String = "") -> void:
    wrapper_id = p_wrapper_id

func get_branch_ids() -> Array:
    return []

func duplicate_wrapper() -> ConditionWrapper:
    return ConditionWrapper.new(wrapper_id)

func validate_self(path: String = "wrapper") -> Array:
    var errors: Array = []
    var regex := RegEx.new()
    if regex.compile("^[A-Za-z0-9_-]+$") != OK or regex.search(wrapper_id) == null:
        errors.append("%s.wrapper_id must match ^[A-Za-z0-9_-]+$" % path)
    return errors

func to_editor_dict() -> Dictionary:
    return {"wrapperId": wrapper_id, "type": "unknown"}

static func is_valid_variable_key(value: String) -> bool:
    var regex := RegEx.new()
    return regex.compile("^[a-z][a-z0-9_.-]*$") == OK and regex.search(value) != null
