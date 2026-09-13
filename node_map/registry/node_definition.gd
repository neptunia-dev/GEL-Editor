extends RefCounted

## 注册定义不持有视图和资源；注册表以深复制固定其元数据。
const Values := preload("res://node_map/model/value_rules.gd")
const PortSpec := preload("res://node_map/model/port_spec.gd")
const ParameterSpec := preload("res://node_map/model/parameter_spec.gd")

var type_id: String = ""
var version: int = 1
var display_name: String = ""
var category: String = ""
var allowed_graph_kinds: Array = []
var port_specs: Array = []
var parameter_specs: Array = []
var factory: Callable = Callable()
var compiler_key: String = ""

func clone_snapshot():
	var copy = get_script().new()
	for field in ["type_id", "version", "display_name", "category", "factory", "compiler_key"]:
		copy.set(field, get(field))
	copy.allowed_graph_kinds = allowed_graph_kinds.duplicate()
	for port in port_specs:
		copy.port_specs.append(port.clone_snapshot())
	for parameter in parameter_specs:
		copy.parameter_specs.append(parameter.clone_snapshot())
	return copy

func validate_self() -> Array:
	var errors: Array = []
	if not Values.valid_id(type_id) or version < 1 or display_name.strip_edges().is_empty() or not factory.is_valid():
		errors.append(Values.diagnostic("invalid_definition", "节点定义的身份、版本、名称或工厂无效。"))
	if allowed_graph_kinds.is_empty():
		errors.append(Values.diagnostic("invalid_definition", "节点定义必须声明允许的图类别。"))
	var kinds: Dictionary = {}
	for graph_kind in allowed_graph_kinds:
		if not graph_kind is String or graph_kind not in ["root", "scene"] or kinds.has(graph_kind):
			errors.append(Values.diagnostic("invalid_definition", "图类别无效或重复。"))
		kinds[graph_kind] = true
	var ids: Dictionary = {}
	for port in port_specs:
		if not port is PortSpec:
			errors.append(Values.diagnostic("invalid_definition", "端口定义必须为 PortSpec。"))
			continue
		errors.append_array(port.validate_self())
		if ids.has(port.port_id):
			errors.append(Values.diagnostic("duplicate_port", "静态端口 ID 重复。", "", "", port.port_id))
		ids[port.port_id] = true
	ids.clear()
	for parameter in parameter_specs:
		if not parameter is ParameterSpec:
			errors.append(Values.diagnostic("invalid_definition", "参数定义必须为 ParameterSpec。"))
			continue
		errors.append_array(parameter.validate_self())
		if ids.has(parameter.parameter_id):
			errors.append(Values.diagnostic("duplicate_parameter", "参数 ID 重复。"))
		ids[parameter.parameter_id] = true
	return errors
