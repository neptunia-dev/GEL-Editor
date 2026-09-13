extends RefCounted

## 公共父类只存储实例公共数据；业务字段由子类及受控方法维护。
const Values := preload("res://node_map/model/value_rules.gd")
const PortSpec := preload("res://node_map/model/port_spec.gd")

var node_id: String = Values.new_id("node")
var node_type: String = ""
var node_version: int = 1
var position: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2(240, 140)
var collapsed: bool = false
var locked: bool = false
var enabled: bool = true
var title_override: String = ""
var input_values: Dictionary = {}
var _definition: RefCounted

func get_type_id() -> String:
	return node_type

func get_local_port_specs() -> Array:
	var ports: Array = []
	if _definition != null:
		for port in _definition.port_specs:
			ports.append(port.clone_snapshot())
	return ports

func get_parameter_values() -> Dictionary:
	return {}

func serialize_data() -> Dictionary:
	return {}

func _set_parameter(_parameter_id: String, _value: Variant) -> bool:
	return false

func _restore_data(data: Dictionary) -> bool:
	return data.is_empty()

func _reset_duplicate_identity() -> void:
	pass

func clone_snapshot():
	var copy = get_script().new()
	for field in ["node_id", "node_type", "node_version", "position", "size", "collapsed", "locked", "enabled", "title_override"]:
		copy.set(field, get(field))
	copy.input_values = input_values.duplicate(true)
	copy._definition = _definition.clone_snapshot() if _definition != null else null
	if not copy._restore_data(serialize_data().duplicate(true)):
		return null
	return copy

func duplicate_node():
	var copy = clone_snapshot()
	copy.node_id = Values.new_id("node")
	copy._reset_duplicate_identity()
	return copy

func to_editor_dict() -> Dictionary:
	return {"id": node_id, "type": node_type, "version": node_version,
		"position": {"x": position.x, "y": position.y}, "size": {"x": size.x, "y": size.y},
		"ui": {"collapsed": collapsed, "locked": locked, "titleOverride": title_override},
		"enabled": enabled, "inputs": input_values.duplicate(true), "data": serialize_data().duplicate(true)}

func _load_editor_dict(data: Dictionary) -> bool:
	if not Values.has_keys(data, ["id", "type", "version", "position", "size", "ui", "enabled", "inputs", "data"]):
		return false
	if not data.id is String or data.type != node_type or not Values.is_integer(data.version) or data.version != node_version:
		return false
	for field in ["position", "size"]:
		var vector: Variant = data[field]
		if not vector is Dictionary or not Values.has_keys(vector, ["x", "y"]):
			return false
		if not Values.matches_type(vector.x, "number") or not Values.matches_type(vector.y, "number"):
			return false
	if not data.ui is Dictionary or not Values.has_keys(data.ui, ["collapsed", "locked", "titleOverride"]):
		return false
	if not data.ui.collapsed is bool or not data.ui.locked is bool or not data.ui.titleOverride is String or not data.enabled is bool:
		return false
	if not data.inputs is Dictionary or not data.data is Dictionary or not Values.is_json_value(data):
		return false
	if not _restore_data(data.data.duplicate(true)):
		return false
	node_id = data.id
	position = Vector2(data.position.x, data.position.y)
	size = Vector2(data.size.x, data.size.y)
	collapsed = data.ui.collapsed
	locked = data.ui.locked
	title_override = data.ui.titleOverride
	enabled = data.enabled
	input_values = data.inputs.duplicate(true)
	return true

func validate_self() -> Array:
	var errors: Array = []
	if not Values.valid_id(node_id) or _definition == null or node_type != _definition.type_id or node_version != _definition.version:
		errors.append(Values.diagnostic("invalid_node", "节点身份或注册版本无效。", "", node_id))
	if not position.is_finite() or not size.is_finite() or size.x <= 0 or size.y <= 0:
		errors.append(Values.diagnostic("invalid_layout", "节点位置必须有限，尺寸必须为正值。", "", node_id))
	if not Values.is_json_value(input_values) or not Values.is_json_value(serialize_data()) or not Values.is_json_value(get_parameter_values()):
		errors.append(Values.diagnostic("invalid_value", "节点数据只能包含 JSON 基础值。", "", node_id))
	var ports: Dictionary = {}
	for port in get_local_port_specs():
		if not port is PortSpec:
			errors.append(Values.diagnostic("invalid_port", "模型必须返回 PortSpec。", "", node_id))
			continue
		errors.append_array(port.validate_self())
		if ports.has(port.port_id):
			errors.append(Values.diagnostic("duplicate_port", "节点端口 ID 重复。", "", node_id, port.port_id))
		ports[port.port_id] = port
	for key in input_values:
		if not ports.has(key) or ports[key].direction != "input" or not ports[key].validate_value(input_values[key]):
			errors.append(Values.diagnostic("invalid_input", "本地值必须对应合法的数据输入。", "", node_id, str(key)))
	if _definition != null:
		var parameters := get_parameter_values()
		for spec in _definition.parameter_specs:
			if parameters.has(spec.parameter_id) and not spec.validate_value(parameters[spec.parameter_id]):
				errors.append(Values.diagnostic("invalid_parameter", "节点参数值不符合定义：" + spec.parameter_id, "", node_id))
	return errors
