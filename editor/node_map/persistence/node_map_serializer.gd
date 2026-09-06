extends RefCounted
class_name NodeMapSerializer

const SceneMapModel = preload("res://node_map/map/scene_map.gd")
const SceneNodeModel = preload("res://node_map/scene_node.gd")
const ExitPortModel = preload("res://node_map/exit_port.gd")
const RouteEdgeModel = preload("res://node_map/map/route_edge.gd")

const FORMAT_VERSION := 1

static func serialize(scene_map: SceneMap) -> Dictionary:
	var result := scene_map.to_editor_dict()
	result["formatVersion"] = FORMAT_VERSION
	result["moduleVersion"] = NodeMapModule.MODULE_VERSION
	return result

static func deserialize(data: Variant) -> Dictionary:
	var error := _validate(data, "map")
	if not error.is_empty():
		return {"ok": false, "error": error}
	if data.formatVersion != FORMAT_VERSION or data.moduleVersion != NodeMapModule.MODULE_VERSION:
		return {"ok": false, "error": "Unsupported Node Map version"}
	var result := SceneMapModel.new()
	for raw_node in data.nodes:
		var position_data: Dictionary = raw_node.position
		var exits: Array = []
		for raw_exit in raw_node.exits:
			exits.append(ExitPortModel.new(raw_exit.portId, raw_exit.name))
		var cast: Array = []
		for member in raw_node.cast:
			cast.append(CastMember.new(member.characterId, member.get("role", ""), member.get("displayName", "")))
		var tree: ConditionTree = null
		if raw_node.get("conditionTree") != null:
			var decoded := decode_tree(raw_node.conditionTree)
			if not decoded.ok:
				return decoded
			tree = decoded.tree
		var node := SceneNodeModel.new(
			raw_node.nodeId, raw_node.sceneId, raw_node.title, raw_node.mainScript,
			cast, exits, Vector2(position_data.x, position_data.y), tree,
		)
		if raw_node.mainScript != node.main_script or not node.position.is_finite():
			return {"ok": false, "error": "mainScript must be canonical and position must be finite"}
		if not result.add_node(node):
			return {"ok": false, "error": result.last_error}
	for raw_edge in data.edges:
		var edge := RouteEdgeModel.new(
			raw_edge.edgeId, raw_edge.sourceNodeId, raw_edge.get("sourcePortId", ""),
			raw_edge.targetNodeId, raw_edge.sourceKind,
			raw_edge.get("sourceWrapperId", ""), raw_edge.get("sourceBranchId", ""),
		)
		if not result.add_route(edge):
			return {"ok": false, "error": result.last_error}
	var entry_id := str(data.get("entryNodeId", ""))
	if not entry_id.is_empty() and not result.set_entry_node(entry_id):
		return {"ok": false, "error": result.last_error}
	return {"ok": true, "scene_map": result, "diagnostics": result.get_diagnostics()}

# Validate types before calling typed model constructors. Unknown fields are rejected
# rather than silently dropped by a newer/foreign file format.
static func _validate(value: Variant, shape: String, depth: int = 0) -> String:
	if depth > 64:
		return "JSON nesting limit exceeded"
	if shape.begins_with("?"):
		return "" if value == null else _validate(value, shape.substr(1), depth + 1)
	if shape.begins_with("[]"):
		if not value is Array:
			return "%s must be an array" % shape
		for item in value:
			var error := _validate(item, shape.substr(2), depth + 1)
			if not error.is_empty():
				return error
		return ""
	if shape == "string":
		return "" if value is String else "Expected string"
	if shape == "number":
		return "" if ConditionBranch.is_finite_number(value) else "Expected finite number"
	if shape == "scalar":
		return "" if value == null or value is String or value is bool or ConditionBranch.is_finite_number(value) else "Expected scalar"
	if not value is Dictionary:
		return "%s must be an object" % shape
	var schemas := {
		"map": {"formatVersion": "number", "moduleVersion": "number", "entryNodeId": "string", "nodes": "[]node", "edges": "[]edge"},
		"node": {"nodeId": "string", "sceneId": "string", "title": "string", "mainScript": "string", "position": "position", "cast": "[]cast", "exits": "[]exit", "conditionTree?": "?tree"},
		"position": {"x": "number", "y": "number"},
		"cast": {"characterId": "string", "role?": "string", "displayName?": "string"},
		"exit": {"portId": "string", "name": "string"},
		"tree": {"rootWrapperId": "string", "wrappers": "[]wrapper", "branches": "[]branch"},
		"branch": {"branchId": "string", "label": "string", "childWrapperId?": "string", "matchValue?": "scalar"},
	}
	var schema: Dictionary
	if shape == "edge":
		schema = {"edgeId": "string", "sourceNodeId": "string", "sourceKind": "string", "targetNodeId": "string"}
		if value.get("sourceKind") == "scene_exit":
			schema["sourcePortId"] = "string"
		elif value.get("sourceKind") == "condition_branch":
			schema.merge({"sourceWrapperId": "string", "sourceBranchId": "string"})
		else:
			return "Unknown route sourceKind"
	elif shape == "wrapper":
		schema = {"wrapperId": "string", "type": "string"}
		match value.get("type"):
			"if": schema.merge({"variableKey": "string", "trueBranchId": "string", "falseBranchId": "string"})
			"switch": schema.merge({"variableKey": "string", "caseBranchIds": "[]string", "defaultBranchId": "string"})
			"numeric_compare": schema.merge({"leftOperand": "operand", "rightOperand": "operand", "lessBranchId": "string", "equalBranchId": "string", "greaterBranchId": "string"})
			_: return "Unknown condition type"
	elif shape == "operand":
		schema = {"kind": "string"}
		match value.get("kind"):
			"variable": schema["variableKey"] = "string"
			"constant": schema["value"] = "number"
			_: return "Unknown operand kind"
	else:
		schema = schemas[shape]
	for key in value:
		if not key is String or (not schema.has(key) and not schema.has(key + "?")):
			return "Unknown %s field: %s" % [shape, key]
	for field in schema:
		var key: String = field.trim_suffix("?")
		if not value.has(key):
			if field.ends_with("?"):
				continue
			return "Missing %s.%s" % [shape, key]
		var error := _validate(value[key], schema[field], depth + 1)
		if not error.is_empty():
			return "%s.%s: %s" % [shape, key, error]
	return ""

static func decode_tree(data: Variant) -> Dictionary:
	var error := _validate(data, "tree")
	if not error.is_empty():
		return {"ok": false, "error": error}
	# Model tree traversal is recursive; bound imported depth by wrapper count.
	if data.wrappers.size() > 128:
		return {"ok": false, "error": "At most 128 wrappers per Scene"}
	var wrappers: Array = []
	var branches: Array = []
	for w in data.wrappers:
		match w.type:
			"if": wrappers.append(IfWrapper.new(w.wrapperId, w.variableKey, w.trueBranchId, w.falseBranchId))
			"switch": wrappers.append(SwitchCaseWrapper.new(w.wrapperId, w.variableKey, w.caseBranchIds, w.defaultBranchId))
			"numeric_compare": wrappers.append(NumericCompareWrapper.new(w.wrapperId, _operand(w.leftOperand), _operand(w.rightOperand), w.lessBranchId, w.equalBranchId, w.greaterBranchId))
	for b in data.branches:
		branches.append(ConditionBranch.new(b.branchId, b.label, b.get("childWrapperId", ""), b.has("matchValue"), b.get("matchValue")))
	var tree := ConditionTree.new(data.rootWrapperId, wrappers, branches)
	var errors := tree.validate_self()
	return {"ok": true, "tree": tree} if errors.is_empty() else {"ok": false, "error": str(errors[0])}

static func _operand(data: Dictionary) -> NumericOperand:
	return NumericOperand.variable(data.variableKey) if data.kind == "variable" else NumericOperand.constant(data.value)

static func save_file(path: String, scene_map: SceneMap) -> Dictionary:
	var data := serialize(scene_map)
	var checked := deserialize(data)
	if not checked.ok:
		return checked
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Unable to open file for writing: %s" % path}
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		return {"ok": false, "error": "Unable to replace file: %s" % path}
	return {"ok": true}

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "File does not exist: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Unable to read file: %s" % path}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var parsed = json.data
	if not parsed is Dictionary:
		return {"ok": false, "error": "Node Map JSON root must be an object"}
	return deserialize(parsed)
