extends "res://workspace/node_map/widgets/enum_value_widget.gd"


func _get_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var options: Variant = _constraints.get("options", [])
	if not options is Array:
		return result
	var seen: Dictionary = {}
	for option in options:
		if not option is Dictionary:
			continue
		var id: Variant = option.get("id")
		var label: Variant = option.get("label")
		if not id is String or id.is_empty() or not label is String or seen.has(id):
			continue
		seen[id] = true
		result.append({"value": id, "label": label})
	return result


func _accepts_value(candidate: Variant) -> bool:
	return candidate is String


func _missing_label() -> String:
	if not _has_value or _value == null:
		return super._missing_label()
	return "Unresolved: " + _display_value(_value)
