extends "res://node_map/model/node_map_node.gd"

## 项目入口永远启用，数量和删除保护由文档维护。
func validate_self() -> Array:
	var errors := super.validate_self()
	if not enabled:
		errors.append(Values.diagnostic("protected_node", "项目入口不能禁用。", "", node_id))
	return errors
