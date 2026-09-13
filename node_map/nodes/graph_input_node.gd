extends "res://node_map/nodes/boundary_node.gd"

## 第一版子图只允许固定入口 enter。
func _init() -> void:
	interface_id = "enter"
	display_name = "Enter"

func validate_self() -> Array:
	var errors := super.validate_self()
	if interface_id != "enter":
		errors.append(Values.diagnostic("invalid_interface", "入口接口必须为 enter。", "", node_id))
	return errors
