extends RefCounted

## 显示扩展属于宿主，绝不写入领域快照或工程文件。
var _definitions: Dictionary = {}

func register_presentation(type_id: String, descriptor: Dictionary) -> bool:
	if type_id.is_empty() or _definitions.has(type_id):
		return false
	if descriptor.has("rows") and (not descriptor.rows is Callable or not descriptor.rows.is_valid()):
		return false
	_definitions[type_id] = descriptor.duplicate(true)
	return true

func get_presentation(type_id: String) -> Dictionary:
	return _definitions.get(type_id, {}).duplicate(true)
