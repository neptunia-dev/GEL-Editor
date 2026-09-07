extends "res://node_map/nodes/boundary_node.gd"

## 普通出口复制也必须获得独立接口身份。
func _init() -> void:
	interface_id = Values.new_id("interface")

func _reset_duplicate_identity() -> void:
	interface_id = Values.new_id("interface")

func validate_self() -> Array:
	var errors := super.validate_self()
	if interface_id == "enter":
		errors.append(Values.diagnostic("invalid_interface", "出口不能占用保留入口身份。", "", node_id))
	return errors
