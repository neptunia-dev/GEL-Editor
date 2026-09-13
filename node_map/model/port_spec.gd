extends RefCounted

## 端口是独立值对象；顺序和显示名不参与连接身份。
const Values := preload("res://node_map/model/value_rules.gd")

var port_id: String = ""
var display_name: String = ""
var direction: String = "input"
var kind: String = "data"
var value_type: String = "string"
var required: bool = false
var max_connections: int = 1
var has_default_value: bool = false
var default_value: Variant = null
var order: int = 0

func clone_snapshot():
	var copy = get_script().new()
	for field in ["port_id", "display_name", "direction", "kind", "value_type", "required", "max_connections", "has_default_value", "order"]:
		copy.set(field, get(field))
	copy.default_value = Values.copy_value(default_value)
	return copy

func validate_value(value: Variant) -> bool:
	return kind == "data" and Values.matches_type(value, value_type)

func validate_self() -> Array:
	var errors: Array = []
	if not Values.valid_id(port_id) or display_name.strip_edges().is_empty():
		errors.append(Values.diagnostic("invalid_port", "端口身份和显示名必须有效。", "", "", port_id))
	if direction not in ["input", "output"] or kind not in ["flow", "data"]:
		errors.append(Values.diagnostic("invalid_port", "端口方向或类别无效。", "", "", port_id))
	if max_connections != -1 and max_connections < 1:
		errors.append(Values.diagnostic("invalid_limit", "连接上限必须为正整数或 -1。", "", "", port_id))
	if (kind == "data" and direction == "input") or (kind == "flow" and direction == "output"):
		if max_connections != 1:
			errors.append(Values.diagnostic("invalid_limit", "数据输入和流程输出只允许一个连接。", "", "", port_id))
	if kind == "flow" and (not value_type.is_empty() or has_default_value or default_value != null):
		errors.append(Values.diagnostic("invalid_default", "流程端口不能声明值类型或默认值。", "", "", port_id))
	if kind == "data" and not Values.VALUE_TYPES.has(value_type):
		errors.append(Values.diagnostic("invalid_value_type", "未知的数据值类型。", "", "", port_id))
	if has_default_value and (direction != "input" or not validate_value(default_value)):
		errors.append(Values.diagnostic("invalid_default", "默认值必须属于数据输入且类型合法。", "", "", port_id))
	if not Values.is_json_value(default_value) or order < 0:
		errors.append(Values.diagnostic("invalid_port", "默认值或端口顺序无效。", "", "", port_id))
	return errors
