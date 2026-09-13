extends "res://node_map/model/node_map_node.gd"

## 常量由子类字段持有，所有赋值都检查数值类型。
var value: float = 0.0

func get_parameter_values() -> Dictionary:
	return {"value": value}

func serialize_data() -> Dictionary:
	return {"value": value}

func _set_parameter(parameter_id: String, new_value: Variant) -> bool:
	if parameter_id != "value" or not Values.matches_type(new_value, "number"):
		return false
	value = new_value
	return true

func _restore_data(data: Dictionary) -> bool:
	return Values.has_keys(data, ["value"]) and _set_parameter("value", data.value)
