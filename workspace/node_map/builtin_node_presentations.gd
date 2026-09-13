extends RefCounted

## 内建特殊内容通过同一个行描述扩展点注册，不修改通用节点外壳。
static func configure(registry) -> void:
	registry.register_presentation("gel.scene", {"accent": Color("76bcb0"), "title_parameter": "display_name", "rows": _scene_rows})
	registry.register_presentation("gel.dialogue", {"accent": Color("85abc9"), "fields": {"input:text": {"hint": "multiline"}}})
	registry.register_presentation("gel.choice", {"accent": Color("d6af70"), "rows": _choice_rows})
	registry.register_presentation("gel.if", {"accent": Color("d6af70")})
	registry.register_presentation("gel.graph_output", {"fields": {"parameter:interface_id": {"read_only": true}}})
	registry.register_presentation("gel.number", {"accent": Color("b4cc7c")})
	registry.register_presentation("gel.boolean", {"accent": Color("d78e9d")})

static func _scene_rows(model, _ports: Array) -> Array:
	return [
		{"kind": "navigate", "id": "open", "label": "Open Scene", "graph_id": model.child_graph_id},
		{"kind": "action", "id": "add_output", "label": "Add Output", "icon_key": "plus", "command": {"op": "add_output", "node_id": model.node_id, "display_name": "Output"}},
	]

static func _choice_rows(model, _ports: Array) -> Array:
	var rows: Array = []
	var choices: Array = model.serialize_data().get("choices", [])
	var ids: Array = []
	for item in choices:
		ids.append(item.choice_id)
	for index in range(choices.size()):
		var item: Dictionary = choices[index]
		var actions: Array = []
		if index > 0:
			var reordered := ids.duplicate()
			reordered[index] = ids[index - 1]
			reordered[index - 1] = ids[index]
			actions.append({"icon_key": "chevron-up", "tooltip": "Move up", "command": {"op": "reorder_choices", "node_id": model.node_id, "item_ids": reordered}})
		actions.append({"icon_key": "trash-2", "tooltip": "Remove choice", "command": {"op": "remove_choice", "node_id": model.node_id, "item_id": item.choice_id}})
		rows.append({"kind": "field", "id": item.choice_id, "label": "Choice %d" % (index + 1), "value_type": "string", "value": item.label, "command": {"op": "rename_choice", "node_id": model.node_id, "item_id": item.choice_id}, "value_key": "label", "actions": actions})
	rows.append({"kind": "action", "id": "add", "label": "Add Choice", "icon_key": "plus", "command": {"op": "add_choice", "node_id": model.node_id, "label": "Choice %d" % (choices.size() + 1)}})
	return rows
