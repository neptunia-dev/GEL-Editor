extends RefCounted

## 连接只保存身份，不持有节点和端口对象。
const Values := preload("res://node_map/model/value_rules.gd")

var link_id: String = Values.new_id("link")
var source_node_id: String = ""
var source_port_id: String = ""
var target_node_id: String = ""
var target_port_id: String = ""

func clone_snapshot():
	var copy = get_script().new()
	for field in ["link_id", "source_node_id", "source_port_id", "target_node_id", "target_port_id"]:
		copy.set(field, get(field))
	return copy

func to_dict() -> Dictionary:
	return {"linkId": link_id, "sourceNodeId": source_node_id, "sourcePortId": source_port_id,
		"targetNodeId": target_node_id, "targetPortId": target_port_id}

func _load_dict(data: Dictionary) -> bool:
	if not Values.has_keys(data, ["linkId", "sourceNodeId", "sourcePortId", "targetNodeId", "targetPortId"]):
		return false
	for value in data.values():
		if not Values.valid_id(value):
			return false
	link_id = data.linkId
	source_node_id = data.sourceNodeId
	source_port_id = data.sourcePortId
	target_node_id = data.targetNodeId
	target_port_id = data.targetPortId
	return true
