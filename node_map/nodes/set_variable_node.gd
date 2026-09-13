extends "res://node_map/model/node_map_node.gd"

var variable_key: String = ""

func get_parameter_values() -> Dictionary:
	return {"variable_key": variable_key}

func serialize_data() -> Dictionary:
	return get_parameter_values()

func _set_parameter(parameter_id: String, value: Variant) -> bool:
	if parameter_id != "variable_key" or not value is String:
		return false
	variable_key = value
	return true

func _restore_data(data: Dictionary) -> bool:
	return Values.has_keys(data, ["variable_key"]) and _set_parameter("variable_key", data.variable_key)
