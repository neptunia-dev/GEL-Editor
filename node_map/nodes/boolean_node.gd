extends "res://node_map/model/node_map_node.gd"

## 布尔常量不接受数字或字符串的隐式转换。
var value: bool = false

func get_parameter_values() -> Dictionary:
	return {"value": value}

func serialize_data() -> Dictionary:
	return {"value": value}

func _set_parameter(parameter_id: String, new_value: Variant) -> bool:
	if parameter_id != "value" or not new_value is bool:
		return false
	value = new_value
	return true

func _restore_data(data: Dictionary) -> bool:
	return Values.has_keys(data, ["value"]) and _set_parameter("value", data.value)
