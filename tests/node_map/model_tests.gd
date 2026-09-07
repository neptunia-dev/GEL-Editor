extends SceneTree

## 纯领域测试不实例化场景树控件，扩展节点夹具直接使用公开注册协议。
const API := preload("res://node_map/node_map.gd")
const Values := preload("res://node_map/model/value_rules.gd")
const Builtins := preload("res://node_map/registry/builtin_nodes.gd")
const Document := preload("res://node_map/model/node_map_document.gd")
const Definition := preload("res://node_map/registry/node_definition.gd")
const Port := preload("res://node_map/model/port_spec.gd")
const Parameter := preload("res://node_map/model/parameter_spec.gd")
const Model := preload("res://node_map/model/node_map_node.gd")

class ExtensionNode extends "res://node_map/model/node_map_node.gd":
	var payload: Dictionary = {"nested": ["original"]}
	var mode: String = "boolean"

	func get_parameter_values() -> Dictionary:
		return {"payload": payload.duplicate(true), "mode": mode}

	func serialize_data() -> Dictionary:
		return get_parameter_values()

	func _set_parameter(parameter_id: String, value: Variant) -> bool:
		if parameter_id == "payload" and value is Dictionary and Values.is_json_value(value):
			payload = value.duplicate(true)
			return true
		if parameter_id == "mode" and value in ["boolean", "number"]:
			mode = value
			return true
		return false

	func _restore_data(data: Dictionary) -> bool:
		return Values.has_keys(data, ["payload", "mode"]) and _set_parameter("payload", data.payload) and _set_parameter("mode", data.mode)

	func get_local_port_specs() -> Array:
		var ports := super.get_local_port_specs()
		for port in ports:
			if port.port_id == "output":
				port.value_type = mode
		return ports

var _checks := 0
var _failures := 0
var _notifications := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_definitions_and_values()
	_test_minimal_document()
	_test_connections()
	_test_inputs_and_parameters()
	_test_choices()
	_test_scene_lifecycle()
	_test_snapshot_validation()
	_test_malformed_commands()
	if _failures == 0:
		print("PASS: %d node map model checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d node map model checks" % [_failures, _checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK FAILED: " + message)

func _new_document():
	var document := Document.new(Builtins.create_registry())
	document.changed.connect(func(_change): _notifications += 1)
	return document

func _ok(document, command: Dictionary) -> Dictionary:
	var result: Dictionary = document.execute(command)
	_check(result.ok, "命令成功：%s %s" % [command.op, result.diagnostics])
	_check(result.has("change") and result.change.has("before") and result.change.has("after") and result.change.has("affected_node_ids"), "成功返回完整变更协议")
	return result

func _reject(document, command: Dictionary, code: String = "") -> void:
	var before: Dictionary = document.get_snapshot()
	var notifications := _notifications
	var result: Dictionary = document.execute(command)
	_check(not result.ok and not result.diagnostics.is_empty(), "非法命令返回诊断：" + str(command))
	_check(before == document.get_snapshot(), "失败命令不改变文档")
	_check(notifications == _notifications, "失败命令不通知")
	for diagnostic in result.diagnostics:
		_check(diagnostic.has_all(["code", "message", "graph_id", "node_id", "port_id", "link_id"]), "诊断具有完整定位字段")
	if not code.is_empty():
		_check(result.diagnostics.any(func(d): return d.code == code), "诊断包含 " + code)

func _create(document, type_id: String, graph_id: String) -> String:
	return _ok(document, {"op": "create_node", "type_id": type_id, "graph_id": graph_id, "position": Vector2(20, 30)}).get("created_node_id", "")

func _scene(document) -> String:
	var scene_id := _create(document, "gel.scene", document.root_graph_id)
	return document.get_node(scene_id).child_graph_id

func _of_type(document, graph_id: String, type_id: String) -> Array:
	return document.get_nodes(graph_id).filter(func(node): return node.node_type == type_id)

func _connection(graph_id: String, source: String, source_port: String, target: String, target_port: String) -> Dictionary:
	return {"op": "connect", "graph_id": graph_id, "source_node_id": source, "source_port_id": source_port, "target_node_id": target, "target_port_id": target_port}

func _data_port(port_id: String, direction: String, value_type: String):
	var port := Port.new()
	port.port_id = port_id
	port.display_name = port_id
	port.direction = direction
	port.value_type = value_type
	port.max_connections = 1 if direction == "input" else -1
	return port

func _test_definitions_and_values() -> void:
	var registry = Builtins.create_registry()
	_check(registry.list_definitions().size() == 10, "十个内建类型注册")
	_check(registry.list_definitions("root").size() == 2 and registry.list_definitions("scene").size() == 8, "定义按图类别筛选")
	_check(registry.get_definition("missing") == null and registry.create_node("missing") == null, "未知类型不构建节点")
	var definition = _extension_definition()
	_check(registry.register_definition(definition), "扩展定义可以注册")
	definition.allowed_graph_kinds.clear()
	definition.port_specs[0].value_type = "number"
	definition.parameter_specs[0].default_value.nested.append("changed")
	var returned = registry.get_definition("test.extension")
	_check(returned.allowed_graph_kinds == ["scene"] and returned.port_specs[0].value_type == "boolean", "注册防御性复制元数据")
	_check(returned.parameter_specs[0].default_value == {"nested": ["original"]}, "注册深复制参数默认值")
	returned.parameter_specs[0].default_value.nested.clear()
	returned.parameter_specs[1].constraints.enum.clear()
	registry.list_definitions()[0].allowed_graph_kinds.clear()
	_check(registry.get_definition("test.extension").parameter_specs[1].constraints.enum.size() == 2, "定义查询隔离嵌套约束")
	_check(not registry.register_definition(_extension_definition()), "重复类型拒绝")
	_check(registry.list_definitions().size() == 11, "重复注册不改变集合")
	var invalid = _extension_definition()
	invalid.type_id = "test.invalid"
	invalid.port_specs.append(invalid.port_specs[0])
	_check(not registry.register_definition(invalid) and registry.get_definition("test.invalid") == null, "重复端口使注册原子失败")
	invalid = _extension_definition()
	invalid.type_id = "test.invalid"
	invalid.port_specs[0].max_connections = 0
	_check(not registry.register_definition(invalid), "连接上限零无效")
	invalid.port_specs[0].max_connections = -1
	_check(not registry.register_definition(invalid), "数据输入不能无限连接")
	invalid.port_specs[0].max_connections = 1
	invalid.port_specs[0].default_value = RefCounted.new()
	_check(not registry.register_definition(invalid), "隐藏默认值也不能含对象")
	var parameter := Parameter.new()
	parameter.parameter_id = "amount"
	parameter.display_name = "Amount"
	parameter.value_type = "number"
	parameter.constraints = {"min": 1, "max": 3, "enum": [1, 2, 3], "nullable": false}
	_check(parameter.validate_self().is_empty() and parameter.validate_value(2), "参数范围和枚举有效")
	_check(not parameter.validate_value(0) and not parameter.validate_value(4) and not parameter.validate_value(null) and not parameter.validate_value(true), "参数拒绝范围外、空值和隐式类型转换")
	parameter.constraints = {"min": 4, "max": 3}
	_check(not parameter.validate_self().is_empty(), "倒置范围无效")
	parameter.constraints = {"nullable": true}
	_check(parameter.validate_value(null), "参数约束可以显式允许空值")
	var flow = Builtins._flow("out", "Out", "output")
	flow.has_default_value = true
	_check(not flow.validate_self().is_empty(), "流程端口不能有默认值")
	for value in [Vector2.ZERO, RefCounted.new(), Callable(self, "_run"), INF, NAN, {1: "bad"}, PackedStringArray(["bad"])]:
		_check(not Values.is_json_value(value), "拒绝非 JSON 值 " + type_string(typeof(value)))
	_check(Values.is_json_value({"value": [null, true, 1, 2.5, "text", {}]}), "接受递归 JSON 基础值")
	var cycle: Array = []
	cycle.append(cycle)
	_check(not Values.is_json_value(cycle), "循环值容器被拒绝")
	cycle.clear()
	var node = registry.create_node("test.extension")
	var clone = node.clone_snapshot()
	var duplicate = node.duplicate_node()
	_check(node is Model and clone.node_id == node.node_id and duplicate.node_id != node.node_id, "模型快照保留 ID，复制分配 ID")
	clone.payload.nested.clear()
	duplicate.payload.nested.append("duplicate")
	_check(node.payload == {"nested": ["original"]}, "子类业务字段复制隔离")
	node.position = Vector2(INF, 0)
	_check(not node.validate_self().is_empty(), "无穷布局无效")

func _test_minimal_document() -> void:
	var document = _new_document()
	var root: String = document.root_graph_id
	_check(document.validate_self().is_empty(), "最小草稿结构有效")
	_check(document.get_graph_ids() == [root] and document.get_nodes(root).size() == 1, "初始化根图和唯一入口")
	var start = document.get_nodes(root)[0]
	_check(start.node_type == "gel.project_start" and document.get_ports(start.node_id)[0].port_id == "out", "入口使用 out 端口")
	_check(document.get_graph(root).kind == "root" and document.get_graph(root).owner_node_id == "", "根图没有拥有者")
	_check(Values.is_json_value(document.get_snapshot()), "完整快照无对象引用")
	for op in ["remove_nodes", "duplicate_nodes"]:
		_reject(document, {"op": op, "node_ids": [start.node_id]}, "protected_node")
	_reject(document, {"op": "set_node_flags", "node_id": start.node_id, "values": {"enabled": false}}, "protected_node")
	_reject(document, {"op": "create_node", "type_id": "gel.project_start", "graph_id": root}, "protected_node")
	_reject(document, {"op": "create_node", "type_id": "gel.dialogue", "graph_id": root}, "wrong_graph_kind")
	_reject(document, {"op": "create_node", "type_id": "gel.unknown", "graph_id": root})
	var graph_copy = document.get_graph(root)
	graph_copy.kind = "scene"
	graph_copy._nodes.clear()
	start.title_override = "mutated"
	var snapshot: Dictionary = document.get_snapshot()
	snapshot.graphs[0].nodes.clear()
	_check(document.get_nodes(root).size() == 1 and document.get_graph(root).kind == "root" and document.get_node(start.node_id).title_override == "", "图、节点和快照查询均隔离")
	var count := _notifications
	_ok(document, {"op": "move_nodes", "positions": {start.node_id: Vector2.ZERO}})
	_check(count == _notifications, "无状态差异不通知")
	var result := _ok(document, {"op": "move_nodes", "positions": {start.node_id: Vector2(5, 9)}})
	_check(count + 1 == _notifications and result.change.affected_node_ids.has(start.node_id), "提交恰好通知一次并标识受影响节点")
	result.change.after.graphs.clear()
	_check(document.get_graph_ids() == [root], "返回变更快照也不暴露所有权")
	_check(document.get_node("missing") == null and document.get_graph("missing") == null and document.get_ports("missing").is_empty(), "未知查询为空")

func _test_connections() -> void:
	var document = _new_document()
	var graph_id := _scene(document)
	var other_graph := _scene(document)
	var dialogue := _create(document, "gel.dialogue", graph_id)
	var branch := _create(document, "gel.if", graph_id)
	var boolean := _create(document, "gel.boolean", graph_id)
	var number := _create(document, "gel.number", graph_id)
	var other := _create(document, "gel.if", other_graph)
	_reject(document, _connection(graph_id, boolean, "value", branch, "in"), "incompatible_ports")
	_reject(document, _connection(graph_id, number, "value", branch, "condition"), "incompatible_ports")
	_reject(document, _connection(graph_id, branch, "condition", boolean, "value"), "invalid_direction")
	_reject(document, _connection(graph_id, boolean, "missing", branch, "condition"), "missing_port")
	_reject(document, _connection(graph_id, boolean, "value", other, "condition"), "cross_graph_or_missing_node")
	_reject(document, _connection(graph_id, "missing", "value", branch, "condition"), "cross_graph_or_missing_node")
	var connected := _ok(document, _connection(graph_id, boolean, "value", branch, "condition"))
	_reject(document, _connection(graph_id, boolean, "value", branch, "condition"), "duplicate_connection")
	var boolean2 := _create(document, "gel.boolean", graph_id)
	_reject(document, _connection(graph_id, boolean2, "value", branch, "condition"), "connection_limit")
	_ok(document, _connection(graph_id, dialogue, "next", branch, "in"))
	_ok(document, _connection(graph_id, branch, "true", dialogue, "in"))
	_ok(document, _connection(graph_id, branch, "false", dialogue, "in"))
	_check(document.validate_self().is_empty(), "流程环与多个前驱合流有效")
	_reject(document, _connection(graph_id, dialogue, "next", dialogue, "in"), "connection_limit")
	var queried_link = document.get_links(graph_id)[0]
	queried_link.source_port_id = "corrupt"
	_check(document.validate_self().is_empty(), "连接查询是副本")
	_ok(document, {"op": "disconnect", "link_id": connected.created_link_id})
	_check(document.get_input_state(branch, "condition").source == "missing", "断线后的输入重新解析")
	_check(document.registry.register_definition(_extension_definition()), "数据中继通过扩展定义注册")
	var first := _create(document, "test.extension", graph_id)
	var second := _create(document, "test.extension", graph_id)
	_ok(document, _connection(graph_id, first, "output", second, "input"))
	_reject(document, _connection(graph_id, second, "output", first, "input"), "data_cycle")
	_reject(document, _connection(graph_id, first, "output", first, "input"), "data_cycle")
	_reject(document, {"op": "set_parameter", "node_id": first, "parameter_id": "mode", "value": "number"}, "incompatible_ports")
	_check(document.get_node(first).mode == "boolean", "端口变更破坏连接时保留旧参数")

func _test_inputs_and_parameters() -> void:
	var document = _new_document()
	_check(document.registry.register_definition(_extension_definition()), "输入测试扩展定义注册")
	var graph_id := _scene(document)
	var extension := _create(document, "test.extension", graph_id)
	var boolean := _create(document, "gel.boolean", graph_id)
	var number := _create(document, "gel.number", graph_id)
	var dialogue := _create(document, "gel.dialogue", graph_id)
	_check(document.get_input_state(extension, "input") == {"source": "missing", "has_value": false, "value": null}, "无默认值的 missing 状态")
	_check(document.get_input_state(extension, "default_null") == {"source": "default", "has_value": true, "value": null}, "显式 null 默认值与缺失不同")
	_check(document.get_input_state(extension, "default_false") == {"source": "default", "has_value": true, "value": false}, "false 默认值没有被视为缺失")
	_ok(document, {"op": "set_input", "node_id": dialogue, "port_id": "speaker", "value": null})
	_check(document.get_input_state(dialogue, "speaker").source == "local" and document.get_input_state(dialogue, "speaker").has_value, "本地 null 被保留")
	_reject(document, {"op": "set_input", "node_id": dialogue, "port_id": "text", "value": null}, "invalid_value")
	_reject(document, {"op": "set_input", "node_id": dialogue, "port_id": "in", "value": true}, "invalid_input")
	_reject(document, {"op": "clear_input", "node_id": boolean, "port_id": "value"}, "invalid_input")
	_ok(document, {"op": "set_input", "node_id": extension, "port_id": "default_false", "value": true})
	var link := _ok(document, _connection(graph_id, boolean, "value", extension, "default_false"))
	_check(document.get_input_state(extension, "default_false") == {"source": "link", "has_value": false, "value": null}, "连线优先且不执行数据求值")
	_check(document.get_node(extension).input_values.default_false == true, "连接不会擦除本地值")
	_ok(document, {"op": "disconnect", "link_id": link.created_link_id})
	_check(document.get_input_state(extension, "default_false").value == true, "断开后恢复本地值")
	_ok(document, {"op": "clear_input", "node_id": extension, "port_id": "default_false"})
	_check(document.get_input_state(extension, "default_false").source == "default", "清除后恢复默认值")
	var payload := {"nested": ["first", {"value": 2}]}
	_ok(document, {"op": "set_parameter", "node_id": extension, "parameter_id": "payload", "value": payload})
	_ok(document, {"op": "set_input", "node_id": extension, "port_id": "json", "value": payload})
	payload.nested.clear()
	var query = document.get_node(extension)
	query.payload.nested.clear()
	query.input_values.json.nested.clear()
	query.get_parameter_values().payload.nested.clear()
	document.get_input_state(extension, "json").value.nested.clear()
	_check(document.get_node(extension).payload.nested.size() == 2 and document.get_node(extension).input_values.json.nested.size() == 2, "命令值、参数、输入和状态查询均深复制")
	_ok(document, {"op": "set_parameter", "node_id": number, "parameter_id": "value", "value": 12.5})
	_ok(document, {"op": "set_parameter", "node_id": boolean, "parameter_id": "value", "value": true})
	_check(document.get_node(number).value == 12.5 and document.get_node(boolean).value, "常量值由子类字段持有")
	_reject(document, {"op": "set_parameter", "node_id": number, "parameter_id": "value", "value": "12"}, "invalid_parameter")
	_reject(document, {"op": "set_parameter", "node_id": boolean, "parameter_id": "value", "value": 1}, "invalid_parameter")
	var duplicate := _ok(document, {"op": "duplicate_nodes", "node_ids": [extension]})
	_ok(document, {"op": "set_parameter", "node_id": duplicate.created_node_id, "parameter_id": "payload", "value": {"nested": []}})
	_check(document.get_node(extension).payload.nested.size() == 2, "普通节点复制隔离业务值")
	var before: Dictionary = document.get_snapshot()
	_check(document.restore_snapshot(before).ok and before == document.get_snapshot(), "扩展节点也能经注册工厂恢复")

func _test_choices() -> void:
	var document = _new_document()
	var graph_id := _scene(document)
	var choice := _create(document, "gel.choice", graph_id)
	var ending := _create(document, "gel.end_story", graph_id)
	var outside := _create(document, "gel.dialogue", graph_id)
	var first := _ok(document, {"op": "add_choice", "node_id": choice, "label": "First"})
	var second := _ok(document, {"op": "add_choice", "node_id": choice, "label": "Second"})
	var first_id: String = first.created_item_id
	var second_id: String = second.created_item_id
	var route := _ok(document, _connection(graph_id, choice, first_id, ending, "in"))
	_ok(document, _connection(graph_id, outside, "next", choice, "in"))
	_ok(document, {"op": "rename_choice", "node_id": choice, "item_id": first_id, "label": "Renamed"})
	_ok(document, {"op": "reorder_choices", "node_id": choice, "item_ids": [second_id, first_id]})
	var items: Array = document.get_node(choice).serialize_data().choices
	_check(items[0].choice_id == second_id and items[0].order == 0 and items[1].choice_id == first_id and items[1].label == "Renamed", "动态重排和改名不改变身份")
	_check(document.get_links(graph_id).any(func(link): return link.link_id == route.created_link_id and link.source_port_id == first_id), "改名重排保持现有连线")
	_reject(document, {"op": "reorder_choices", "node_id": choice, "item_ids": [first_id]}, "invalid_choice_order")
	_reject(document, {"op": "rename_choice", "node_id": choice, "item_id": "missing", "label": "No"}, "missing_choice")
	var before_links: int = document.get_links(graph_id).size()
	var duplicate := _ok(document, {"op": "duplicate_nodes", "node_ids": [choice, ending]})
	var copied_choice = document.get_node(duplicate.node_id_map[choice])
	var copied_items: Array = copied_choice.serialize_data().choices
	_check(copied_items[0].choice_id != second_id and copied_items[1].choice_id != first_id, "复制选项分配全新端口身份")
	_check(document.get_links(graph_id).size() == before_links + 1, "批量复制只包含选择集内部连线")
	_check(document.get_links(graph_id).any(func(link): return link.source_node_id == copied_choice.node_id and link.source_port_id == copied_items[1].choice_id and link.target_node_id == duplicate.node_id_map[ending]), "批量复制重映射动态端点")
	_ok(document, {"op": "remove_choice", "node_id": choice, "item_id": first_id})
	_check(not document.get_links(graph_id).any(func(link): return link.link_id == route.created_link_id), "删除选项清理关联连接")
	_check(document.get_node(choice).serialize_data().choices[0].choice_id == second_id, "删除不影响剩余选项身份")
	var third := _ok(document, {"op": "add_choice", "node_id": choice, "label": "New"})
	_check(third.created_item_id != first_id and third.created_item_id != second_id, "已删除动态 ID 不复用")
	_reject(document, _connection(graph_id, choice, first_id, ending, "in"), "missing_port")

func _test_scene_lifecycle() -> void:
	var document = _new_document()
	var root: String = document.root_graph_id
	var start = document.get_nodes(root)[0]
	var first := _create(document, "gel.scene", root)
	var second := _create(document, "gel.scene", root)
	var scene = document.get_node(first)
	var child: String = scene.child_graph_id
	var entry = _of_type(document, child, "gel.graph_input")[0]
	var output = _of_type(document, child, "gel.graph_output")[0]
	_check(document.get_graph(child).owner_node_id == first and document.get_nodes(child).size() == 2 and document.get_links(child).size() == 1, "创建 Scene 原子创建子图、入口、出口与连线")
	_check(document.get_links(child)[0].source_port_id == "out" and document.get_links(child)[0].target_port_id == "in", "边界内部端口为固定 out 和 in")
	_check(document.get_ports(first)[0].port_id == "enter" and document.get_ports(first)[1].port_id == output.interface_id, "父图接口实时投影")
	_check(not scene.serialize_data().has("outputs") and not scene.serialize_data().has("ports"), "Scene 业务数据不缓存出口")
	var draft = scene.duplicate_node()
	_check(draft.child_graph_id == "" and draft.node_id != first and scene.clone_snapshot().child_graph_id == child, "Scene 草稿复制清空子图，快照保留子图身份")
	_ok(document, _connection(root, start.node_id, "out", first, "enter"))
	var route := _ok(document, _connection(root, first, output.interface_id, second, "enter"))
	_ok(document, {"op": "rename_output", "node_id": output.node_id, "display_name": "Continue Renamed"})
	_check(document.get_ports(first)[1].display_name == "Continue Renamed", "出口改名立即更新投影")
	_check(document.get_links(root).any(func(link): return link.link_id == route.created_link_id), "出口改名保持父图连接身份")
	var port_copy = document.get_ports(first)[1]
	port_copy.port_id = "bad"
	_check(document.get_ports(first)[1].port_id == output.interface_id, "接口投影查询隔离")
	for op in ["remove_nodes", "duplicate_nodes"]:
		_reject(document, {"op": op, "node_ids": [entry.node_id]}, "protected_node")
	_reject(document, {"op": "create_node", "type_id": "gel.graph_input", "graph_id": child}, "protected_node")
	_reject(document, {"op": "create_node", "type_id": "gel.scene", "graph_id": child}, "wrong_graph_kind")
	_reject(document, {"op": "set_node_flags", "node_id": output.node_id, "values": {"enabled": false}}, "invalid_interface")
	_reject(document, {"op": "set_parameter", "node_id": output.node_id, "parameter_id": "interface_id", "value": "enter"}, "invalid_parameter")
	_reject(document, {"op": "set_parameter", "node_id": first, "parameter_id": "scene_id", "value": document.get_node(second).scene_id}, "duplicate_scene_id")
	_reject(document, {"op": "set_parameter", "node_id": first, "parameter_id": "scene_id", "value": "Uppercase"}, "invalid_scene")
	_ok(document, {"op": "set_parameter", "node_id": first, "parameter_id": "scene_id", "value": "prologue"})
	_ok(document, {"op": "set_parameter", "node_id": first, "parameter_id": "display_name", "value": "Prologue"})
	var added := _ok(document, {"op": "add_output", "node_id": first, "display_name": "Retry"})
	_ok(document, _connection(root, first, added.created_item_id, first, "enter"))
	var choice := _create(document, "gel.choice", child)
	var item := _ok(document, {"op": "add_choice", "node_id": choice, "label": "Choose"})
	_ok(document, _connection(child, choice, item.created_item_id, output.node_id, "in"))
	var dialogue := _create(document, "gel.dialogue", child)
	_ok(document, {"op": "set_input", "node_id": dialogue, "port_id": "text", "value": output.interface_id})
	var old_links: int = document.get_links(root).size()
	var duplicated := _ok(document, {"op": "duplicate_nodes", "node_ids": [first, second]})
	var copy = document.get_node(duplicated.node_id_map[first])
	_check(copy.scene_id != "prologue" and copy.child_graph_id != child and copy.display_name == "Prologue", "Scene 复制重映射业务与子图身份")
	_check(document.get_graph(copy.child_graph_id).owner_node_id == copy.node_id, "复制后子图双向所有权匹配")
	_check(document.get_links(root).size() == old_links, "Scene 复制不复制父图路由")
	var copied_entry = document.get_node(duplicated.node_id_map[entry.node_id])
	var copied_output = document.get_node(duplicated.node_id_map[output.node_id])
	_check(copied_entry.interface_id == "enter" and copied_output.interface_id != output.interface_id, "复制保留固定入口并重建出口接口身份")
	_check(document.get_node(duplicated.node_id_map[dialogue]).input_values.text == output.interface_id, "ID 重映射不替换任意业务字符串")
	_check(document.get_links(copy.child_graph_id).size() == document.get_links(child).size(), "Scene 深复制全部内部连接")
	var copied_choice = document.get_node(duplicated.node_id_map[choice])
	_check(document.get_links(copy.child_graph_id).any(func(link): return link.source_node_id == copied_choice.node_id and link.source_port_id == copied_choice.serialize_data().choices[0].choice_id), "Scene 内动态端口正确重映射")
	_check(document.validate_self().is_empty(), "深复制后的完整文档有效")
	var before: Dictionary = document.get_snapshot()
	var deletion := _ok(document, {"op": "remove_nodes", "node_ids": [first]})
	_check(document.get_node(first) == null and document.get_graph(child) == null, "删除 Scene 同时删除拥有子图")
	_check(not document.get_links(root).any(func(link): return link.source_node_id == first or link.target_node_id == first), "删除 Scene 清理所有父图端点")
	_check(deletion.change.affected_node_ids.has(entry.node_id) and deletion.change.affected_node_ids.has(second), "复合变更包含子图与路由相关节点")
	_check(document.restore_snapshot(before).ok and document.get_snapshot() == before, "撤销 Scene 删除恢复全部原 ID 和连接")
	_check(document.restore_snapshot(deletion.change.after).ok and document.get_node(first) == null, "重做恢复删除后的确切状态")
	_check(document.restore_snapshot(before).ok, "再次撤销可恢复原 Scene")
	_ok(document, {"op": "remove_output", "node_id": output.node_id})
	_check(not document.get_ports(first).any(func(port): return port.port_id == output.interface_id), "删除出口即时移除父图投影")
	_check(not document.get_links(root).any(func(link): return link.link_id == route.created_link_id), "删除出口原子清理父图路由")
	_check(not document.get_links(child).any(func(link): return link.target_node_id == output.node_id), "删除出口原子清理内部连线")
	_ok(document, {"op": "remove_nodes", "node_ids": [added.created_node_id]})
	_check(document.get_ports(first).size() == 1 and document.validate_self().is_empty(), "零出口且缺少终点仍是有效草稿")
	var scenes: Array = _of_type(document, root, "gel.scene").map(func(node): return node.node_id)
	_ok(document, {"op": "remove_nodes", "node_ids": scenes})
	_check(document.get_graph_ids() == [root] and document.get_nodes(root).size() == 1, "删除全部 Scene 后仍保留最小根图")

func _test_snapshot_validation() -> void:
	var document = _new_document()
	var snapshot: Dictionary = document.get_snapshot()
	_check(document.restore_snapshot(snapshot).ok, "合法快照可以恢复")
	_check(document.get_snapshot() == snapshot, "快照恢复保持所有身份")
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.format = "wrong.format"
	_reject(document, {"op": "restore_snapshot"})
	var failed := document.restore_snapshot(malformed)
	_check(not failed.ok and not failed.diagnostics.is_empty(), "错误容器格式被拒绝")
	_check(document.get_snapshot() == snapshot, "错误快照不污染当前文档")
	malformed = snapshot.duplicate(true)
	malformed.graphs[0].nodes[0].type = "gel.unknown"
	failed = document.restore_snapshot(malformed)
	_check(not failed.ok, "未知节点类型不能恢复")
	_check(document.get_snapshot() == snapshot, "未知节点恢复失败后保持原文档")

func _test_malformed_commands() -> void:
	var document = _new_document()
	_reject(document, {})
	_reject(document, {"op": "unknown"})
	_reject(document, {"op": "move_nodes", "positions": {"missing": Vector2.ZERO}})
	_reject(document, {"op": "set_node_flags", "node_id": document.get_nodes(document.root_graph_id)[0].node_id, "values": {"position": true}})
	_reject(document, {"op": "create_node", "type_id": "gel.scene", "graph_id": document.root_graph_id, "unexpected": true})

func _extension_definition():
	var definition := Definition.new()
	definition.type_id = "test.extension"
	definition.display_name = "Extension"
	definition.allowed_graph_kinds = ["scene"]
	definition.factory = func(): return ExtensionNode.new()
	definition.port_specs = [_data_port("input", "input", "boolean"), _data_port("output", "output", "boolean"), _data_port("default_null", "input", "character"), _data_port("default_false", "input", "boolean"), _data_port("json", "input", "json")]
	definition.port_specs[2].has_default_value = true
	definition.port_specs[3].has_default_value = true
	definition.port_specs[3].default_value = false
	var payload := Parameter.new()
	payload.parameter_id = "payload"
	payload.display_name = "Payload"
	payload.value_type = "dictionary"
	payload.has_default_value = true
	payload.default_value = {"nested": ["original"]}
	var mode := Parameter.new()
	mode.parameter_id = "mode"
	mode.display_name = "Mode"
	mode.constraints = {"enum": ["boolean", "number"]}
	definition.parameter_specs = [payload, mode]
	return definition
