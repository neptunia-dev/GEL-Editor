extends "res://node_map/model/node_map_node.gd"

const OPERATIONS := ["and", "or", "not"]
var operation: String = "and"

func get_parameter_values() -> Dictionary:
	return {"operation": operation}

func serialize_data() -> Dictionary:
	return get_parameter_values()

func _set_parameter(parameter_id: String, value: Variant) -> bool:
	if parameter_id != "operation" or not value is String or not OPERATIONS.has(value):
		return false
	operation = value
	return true

func _restore_data(data: Dictionary) -> bool:
	return Values.has_keys(data, ["operation"]) and _set_parameter("operation", data.operation)
