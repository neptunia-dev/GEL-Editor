extends RefCounted

## 注册和查询均复制元数据；工厂返回的草稿也不直接进入文档。
const Definition := preload("res://node_map/registry/node_definition.gd")
const NodeModel := preload("res://node_map/model/node_map_node.gd")
const Values := preload("res://node_map/model/value_rules.gd")

var _definitions: Dictionary = {}
var last_diagnostics: Array = []

func register_definition(definition: Variant) -> bool:
	last_diagnostics = []
	if not definition is Definition:
		last_diagnostics = [Values.diagnostic("invalid_definition", "注册对象必须为 NodeDefinition。")]
		return false
	if _definitions.has(definition.type_id):
		last_diagnostics = [Values.diagnostic("duplicate_type", "节点类型已经注册：" + definition.type_id)]
		return false
	last_diagnostics = definition.validate_self()
	if not last_diagnostics.is_empty():
		return false
	_definitions[definition.type_id] = definition.clone_snapshot()
	return true

func get_definition(type_id: String):
	return _definitions[type_id].clone_snapshot() if _definitions.has(type_id) else null

func list_definitions(graph_kind: String = "") -> Array:
	var result: Array = []
	var ids: Array = _definitions.keys()
	ids.sort()
	for type_id in ids:
		if graph_kind.is_empty() or _definitions[type_id].allowed_graph_kinds.has(graph_kind):
			result.append(_definitions[type_id].clone_snapshot())
	return result

func create_node(type_id: String):
	var definition = get_definition(type_id)
	if definition == null or not definition.factory.is_valid():
		return null
	var draft: Variant = definition.factory.call()
	if not draft is NodeModel:
		return null
	if not Values.is_json_value(draft.serialize_data()) or not Values.is_json_value(draft.input_values) or not Values.is_json_value(draft.get_parameter_values()):
		return null
	var node = draft.clone_snapshot()
	if node == null:
		return null
	node.node_id = Values.new_id("node")
	node.node_type = definition.type_id
	node.node_version = definition.version
	node._definition = definition
	for parameter in definition.parameter_specs:
		if parameter.has_default_value and not node._set_parameter(parameter.parameter_id, Values.copy_value(parameter.default_value)):
			return null
	return node
