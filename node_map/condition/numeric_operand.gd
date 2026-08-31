extends RefCounted
class_name NumericOperand

const KIND_VARIABLE := "variable"
const KIND_CONSTANT := "constant"

var kind: String
var variable_key: String
var constant_value: Variant

func _init(
        p_kind: String = KIND_CONSTANT,
        p_variable_key: String = "",
        p_constant_value: Variant = 0,
) -> void:
    kind = p_kind
    variable_key = p_variable_key
    constant_value = p_constant_value

static func variable(key: String) -> NumericOperand:
    return NumericOperand.new(KIND_VARIABLE, key, 0)

static func constant(value: Variant) -> NumericOperand:
    return NumericOperand.new(KIND_CONSTANT, "", value)

func duplicate_operand() -> NumericOperand:
    return NumericOperand.new(kind, variable_key, constant_value)

func validate_self(path: String = "operand") -> Array:
    var errors: Array = []
    if kind == KIND_VARIABLE:
        if not ConditionWrapper.is_valid_variable_key(variable_key):
            errors.append("%s.variable_key must match ^[a-z][a-z0-9_.-]*$" % path)
    elif kind == KIND_CONSTANT:
        if not ConditionBranch.is_finite_number(constant_value):
            errors.append("%s.constant_value must be a finite number" % path)
    else:
        errors.append("%s.kind must be 'variable' or 'constant'" % path)
    return errors

func to_editor_dict() -> Dictionary:
    if kind == KIND_VARIABLE:
        return {"kind": kind, "variableKey": variable_key}
    return {"kind": kind, "value": constant_value}
