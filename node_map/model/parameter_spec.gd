extends RefCounted

## 参数定义只描述校验规则，参数存储仍由具体节点负责。
const Values := preload("res://node_map/model/value_rules.gd")

var parameter_id: String = ""
var display_name: String = ""
var value_type: String = "string"
var required: bool = false
var has_default_value: bool = false
var default_value: Variant = null
var constraints: Dictionary = {}

func clone_snapshot():
	var copy = get_script().new()
	for field in ["parameter_id", "display_name", "value_type", "required", "has_default_value"]:
		copy.set(field, get(field))
	copy.default_value = Values.copy_value(default_value)
	copy.constraints = constraints.duplicate(true)
	return copy

func validate_value(value: Variant) -> bool:
	if not Values.matches_type(value, value_type, constraints.get("nullable", false)):
		return false
	if value == null and constraints.has("nullable") and not constraints.nullable:
		return false
	if constraints.has("enum") and not constraints.enum.has(value):
		return false
	if value == null:
		return true
	if value is int or value is float:
		if constraints.has("min") and value < constraints.min:
			return false
		if constraints.has("max") and value > constraints.max:
			return false
	if value is String or value is Array or value is Dictionary:
		var length: int = value.length() if value is String else value.size()
		if constraints.has("min_length") and length < constraints.min_length:
			return false
		if constraints.has("max_length") and length > constraints.max_length:
			return false
	if value is String and constraints.has("pattern"):
		var regex := RegEx.new()
		if regex.compile(constraints.pattern) != OK or regex.search(value) == null:
			return false
	return true

func validate_self() -> Array:
	var errors: Array = []
	if not Values.valid_id(parameter_id) or display_name.strip_edges().is_empty() or not Values.VALUE_TYPES.has(value_type):
		errors.append(Values.diagnostic("invalid_parameter", "参数身份、显示名或类型无效。"))
	if not Values.is_json_value(constraints) or not Values.is_json_value(default_value):
		return [Values.diagnostic("invalid_parameter", "参数定义只能包含 JSON 值。")]
	for key in constraints:
		var value: Variant = constraints[key]
		var valid := true
		match key:
			"nullable": valid = value is bool
			"enum": valid = value is Array and not value.is_empty()
			"min", "max": valid = value_type == "number" and (value is int or value is float)
			"min_length", "max_length": valid = value_type in ["string", "array", "dictionary"] and Values.is_integer(value) and value >= 0
			"pattern": valid = value_type == "string" and value is String and RegEx.new().compile(value) == OK
			_: valid = false
		if not valid:
			errors.append(Values.diagnostic("invalid_constraint", "参数约束无效：" + str(key)))
	if not errors.is_empty():
		return errors
	for pair in [["min", "max"], ["min_length", "max_length"]]:
		if constraints.has(pair[0]) and constraints.has(pair[1]) and constraints[pair[0]] > constraints[pair[1]]:
			errors.append(Values.diagnostic("invalid_constraint", "参数下限不能大于上限。"))
	for value in constraints.get("enum", []):
		if not validate_value(value):
			errors.append(Values.diagnostic("invalid_constraint", "枚举包含不符合类型或约束的值。"))
	if has_default_value and not validate_value(default_value):
		errors.append(Values.diagnostic("invalid_default", "参数默认值不符合类型或约束。"))
	return errors
