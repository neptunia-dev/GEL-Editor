extends "res://node_map/model/node_map_node.gd"

## 选项使用稳定身份；删除和重排不能把数组下标变成连接端点。
var _choices: Array = []

func serialize_data() -> Dictionary:
	return {"choices": _choices.duplicate(true)}

func _restore_data(data: Dictionary) -> bool:
	if not Values.has_keys(data, ["choices"]) or not data.choices is Array:
		return false
	var seen: Dictionary = {}
	var restored: Array = []
	for index in data.choices.size():
		var item: Variant = data.choices[index]
		if not item is Dictionary or not Values.has_keys(item, ["choice_id", "label", "order"]):
			return false
		if not Values.valid_id(item.choice_id) or not item.label is String or not Values.is_integer(item.order) or int(item.order) != index or seen.has(item.choice_id):
			return false
		seen[item.choice_id] = true
		restored.append({"choice_id": item.choice_id, "label": item.label, "order": index})
	_choices = restored
	return true

func get_local_port_specs() -> Array:
	var ports := super.get_local_port_specs()
	for item in _choices:
		var port := PortSpec.new()
		port.port_id = item.choice_id
		port.display_name = item.label if not item.label.strip_edges().is_empty() else "Choice"
		port.direction = "output"
		port.kind = "flow"
		port.value_type = ""
		port.required = true
		port.order = item.order + 1
		ports.append(port)
	return ports

func _add_choice(label: String) -> String:
	var item_id := Values.new_id("choice")
	_choices.append({"choice_id": item_id, "label": label, "order": _choices.size()})
	return item_id

func _rename_choice(item_id: String, label: String) -> bool:
	for item in _choices:
		if item.choice_id == item_id:
			item.label = label
			return true
	return false

func _remove_choice(item_id: String) -> bool:
	for index in _choices.size():
		if _choices[index].choice_id == item_id:
			_choices.remove_at(index)
			for new_index in _choices.size():
				_choices[new_index].order = new_index
			return true
	return false

func _reorder_choices(item_ids: Array) -> bool:
	if item_ids.size() != _choices.size():
		return false
	var by_id: Dictionary = {}
	for item in _choices:
		by_id[item.choice_id] = item
	var ordered: Array = []
	for item_id in item_ids:
		if not item_id is String or not by_id.has(item_id):
			return false
		ordered.append(by_id[item_id].duplicate())
		by_id.erase(item_id)
	for index in ordered.size():
		ordered[index].order = index
	_choices = ordered
	return true

func _reset_duplicate_identity() -> void:
	for item in _choices:
		item.choice_id = Values.new_id("choice")
