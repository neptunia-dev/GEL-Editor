extends RefCounted

## 内建类型也走公开注册协议；新增普通节点无需修改文档命令分发。
const Registry := preload("res://node_map/registry/node_registry.gd")
const Definition := preload("res://node_map/registry/node_definition.gd")
const Port := preload("res://node_map/model/port_spec.gd")
const Parameter := preload("res://node_map/model/parameter_spec.gd")
const ProjectStart := preload("res://node_map/nodes/project_start_node.gd")
const SceneModel := preload("res://node_map/nodes/scene_node.gd")
const GraphInput := preload("res://node_map/nodes/graph_input_node.gd")
const GraphOutput := preload("res://node_map/nodes/graph_output_node.gd")
const Dialogue := preload("res://node_map/nodes/dialogue_node.gd")
const IfModel := preload("res://node_map/nodes/if_node.gd")
const Choice := preload("res://node_map/nodes/choice_node.gd")
const EndStory := preload("res://node_map/nodes/end_story_node.gd")
const NumberModel := preload("res://node_map/nodes/number_node.gd")
const BooleanModel := preload("res://node_map/nodes/boolean_node.gd")

static func create_registry():
	var registry := Registry.new()
	var definitions: Array = [
		_definition("gel.project_start", "Project Start", "Project", "root", ProjectStart, [_flow("out", "Start", "output")]),
		_definition("gel.scene", "Scene", "Project", "root", SceneModel, [], [_parameter("scene_id", "Scene ID", "string"), _parameter("display_name", "Name", "string")]),
		_definition("gel.graph_input", "Entry", "Interface", "scene", GraphInput, [_flow("out", "Enter", "output")], [_parameter("display_name", "Name", "string")]),
		_definition("gel.graph_output", "Output", "Interface", "scene", GraphOutput, [_flow("in", "In", "input")], [_parameter("interface_id", "Interface ID", "string"), _parameter("display_name", "Name", "string")]),
		_definition("gel.dialogue", "Dialogue", "Story", "scene", Dialogue, [_flow("in", "In", "input"), _data("speaker", "Speaker", "input", "character", 1), _data("text", "Text", "input", "string", 2), _flow("next", "Next", "output", 3)]),
		_definition("gel.if", "If", "Flow", "scene", IfModel, [_flow("in", "In", "input"), _data("condition", "Condition", "input", "boolean", 1), _flow("true", "True", "output", 2), _flow("false", "False", "output", 3)]),
		_definition("gel.choice", "Choice", "Flow", "scene", Choice, [_flow("in", "In", "input")]),
		_definition("gel.end_story", "End Story", "Story", "scene", EndStory, [_flow("in", "In", "input")]),
		_definition("gel.number", "Number", "Data", "scene", NumberModel, [_data("value", "Value", "output", "number")], [_parameter("value", "Value", "number", true, 0.0)]),
		_definition("gel.boolean", "Boolean", "Data", "scene", BooleanModel, [_data("value", "Value", "output", "boolean")], [_parameter("value", "Value", "boolean", true, false)]),
	]
	for definition in definitions:
		assert(registry.register_definition(definition), "内建节点定义必须有效。")
	return registry

static func _definition(type_id: String, label: String, category: String, graph_kind: String, model_script: Script, ports: Array, parameters: Array = []):
	var definition := Definition.new()
	definition.type_id = type_id
	definition.display_name = label
	definition.category = category
	definition.allowed_graph_kinds = [graph_kind]
	definition.factory = Callable(model_script, "new")
	definition.compiler_key = type_id
	definition.port_specs = ports
	definition.parameter_specs = parameters
	return definition

static func _flow(port_id: String, label: String, direction: String, order: int = 0):
	var port := Port.new()
	port.port_id = port_id
	port.display_name = label
	port.direction = direction
	port.kind = "flow"
	port.value_type = ""
	port.required = true
	port.max_connections = 1 if direction == "output" else -1
	port.order = order
	return port

static func _data(port_id: String, label: String, direction: String, value_type: String, order: int = 0):
	var port := Port.new()
	port.port_id = port_id
	port.display_name = label
	port.direction = direction
	port.value_type = value_type
	port.required = direction == "input"
	port.max_connections = 1 if direction == "input" else -1
	port.order = order
	return port

static func _parameter(parameter_id: String, label: String, value_type: String, has_default: bool = false, default_value: Variant = null):
	var parameter := Parameter.new()
	parameter.parameter_id = parameter_id
	parameter.display_name = label
	parameter.value_type = value_type
	parameter.required = true
	parameter.has_default_value = has_default
	parameter.default_value = default_value
	return parameter
