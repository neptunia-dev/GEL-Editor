extends "res://node_map/model/subgraph_node.gd"

## 场景没有出口缓存，对外接口始终由文档从子图投影。
var scene_id: String = ""
var display_name: String = "Scene"

func get_parameter_values() -> Dictionary:
	return {"scene_id": scene_id, "display_name": display_name}

func serialize_data() -> Dictionary:
	return {"sceneId": scene_id, "displayName": display_name, "childGraphId": child_graph_id}

func _set_parameter(parameter_id: String, value: Variant) -> bool:
	if not value is String:
		return false
	match parameter_id:
		"scene_id": scene_id = value
		"display_name": display_name = value
		_: return false
	return true

func _restore_data(data: Dictionary) -> bool:
	if not Values.has_keys(data, ["sceneId", "displayName", "childGraphId"]):
		return false
	if not data.sceneId is String or not data.displayName is String or not data.childGraphId is String:
		return false
	scene_id = data.sceneId
	display_name = data.displayName
	child_graph_id = data.childGraphId
	return true

func validate_self() -> Array:
	var errors := super.validate_self()
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_.-]*$")
	if pattern.search(scene_id) == null or not Values.valid_id(child_graph_id) or not input_values.is_empty():
		errors.append(Values.diagnostic("invalid_scene", "场景身份、子图引用或本地输入无效。", "", node_id))
	return errors
