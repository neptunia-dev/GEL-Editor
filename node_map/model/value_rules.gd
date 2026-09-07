extends RefCounted

## 领域值只接受有限的 JSON 值；深度上限同时拒绝循环容器。
const VALUE_TYPES := ["boolean", "number", "string", "character", "array", "dictionary", "json"]

static func is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not is_json_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not is_json_value(value[key], depth + 1):
					return false
			return true
	return false

static func copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value

static func matches_type(value: Variant, value_type: String, nullable: bool = false) -> bool:
	if not is_json_value(value) or not VALUE_TYPES.has(value_type):
		return false
	if value == null:
		return nullable or value_type in ["character", "json"]
	match value_type:
		"boolean": return value is bool
		"number": return value is int or value is float
		"string", "character": return value is String
		"array": return value is Array
		"dictionary": return value is Dictionary
		"json": return true
	return false

static func is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	var regex := RegEx.new()
	regex.compile("^[A-Za-z_][A-Za-z0-9_.-]*$")
	return regex.search(value) != null

static func new_id(prefix: String) -> String:
	return prefix + "-" + Crypto.new().generate_random_bytes(16).hex_encode()

static func diagnostic(code: String, message: String, graph_id: String = "", node_id: String = "", port_id: String = "", link_id: String = "") -> Dictionary:
	return {"code": code, "message": message, "severity": "error", "graph_id": graph_id,
		"node_id": node_id, "port_id": port_id, "link_id": link_id}

static func has_keys(data: Dictionary, keys: Array) -> bool:
	if data.size() != keys.size():
		return false
	for key in keys:
		if not data.has(key):
			return false
	return true
