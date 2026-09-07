extends "res://node_map/model/node_map_node.gd"

## 边界节点只声明接口身份，父图连线不保存在这里。
var interface_id: String = ""
var display_name: String = "Output"
var order: int = 0

func get_parameter_values() -> Dictionary:
	return {"interface_id": interface_id, "display_name": display_name}

func serialize_data() -> Dictionary:
	return {"interfaceId": interface_id, "displayName": display_name, "order": order}

func _set_parameter(parameter_id: String, value: Variant) -> bool:
	if parameter_id != "display_name" or not value is String:
		return false
	display_name = value
	return true

func _restore_data(data: Dictionary) -> bool:
	if not Values.has_keys(data, ["interfaceId", "displayName", "order"]):
		return false
	if not data.interfaceId is String or not data.displayName is String or not Values.is_integer(data.order):
		return false
	interface_id = data.interfaceId
	display_name = data.displayName
	order = int(data.order)
	return true

func validate_self() -> Array:
	var errors := super.validate_self()
	if not Values.valid_id(interface_id) or order < 0 or not enabled:
		errors.append(Values.diagnostic("invalid_interface", "边界身份和顺序必须有效，且边界必须启用。", "", node_id))
	return errors
