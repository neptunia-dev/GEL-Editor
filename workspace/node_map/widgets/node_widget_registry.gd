extends RefCounted
class_name NodeWidgetRegistry

const REGISTRY_SCRIPT := preload("res://workspace/node_map/widgets/node_widget_registry.gd")
const VALUE_WIDGET_SCRIPT := preload("res://workspace/node_map/widgets/value_widget.gd")
const BOOLEAN_WIDGET := preload("res://workspace/node_map/widgets/boolean_value_widget.tscn")
const NUMBER_WIDGET := preload("res://workspace/node_map/widgets/number_value_widget.tscn")
const STRING_WIDGET := preload("res://workspace/node_map/widgets/string_value_widget.tscn")
const MULTILINE_WIDGET := preload("res://workspace/node_map/widgets/multiline_value_widget.tscn")
const ENUM_WIDGET := preload("res://workspace/node_map/widgets/enum_value_widget.tscn")
const CHARACTER_WIDGET := preload("res://workspace/node_map/widgets/character_value_widget.tscn")
const READONLY_WIDGET := preload("res://workspace/node_map/widgets/readonly_value_widget.tscn")

const STANDARD_HINT_TYPES := {
	"boolean": ["boolean", "bool"],
	"bool": ["boolean", "bool"],
	"number": ["number"],
	"string": ["string"],
	"multiline": ["string"],
	"enum": ["boolean", "bool", "number", "string", "enum"],
	"character": ["character", "string"],
}

var _factories: Dictionary = {}


## 每次创建独立注册表；工厂无参数，约束由注册表统一配置。
static func standard():
	var registry = REGISTRY_SCRIPT.new()
	registry.register_widget("boolean", func(): return BOOLEAN_WIDGET.instantiate())
	registry.register_widget("bool", func(): return BOOLEAN_WIDGET.instantiate())
	registry.register_widget("number", func(): return NUMBER_WIDGET.instantiate())
	registry.register_widget("string", func(): return STRING_WIDGET.instantiate())
	registry.register_widget("multiline", func(): return MULTILINE_WIDGET.instantiate())
	registry.register_widget("enum", func(): return ENUM_WIDGET.instantiate())
	registry.register_widget("character", func(): return CHARACTER_WIDGET.instantiate())
	return registry


func register_widget(key: String, factory: Callable) -> bool:
	if key.is_empty() or key != key.strip_edges() or _factories.has(key):
		return false
	if not factory.is_valid() or factory.get_argument_count() != 0:
		return false
	_factories[key] = factory
	return true


func create_widget(value_type: String, hint: String = "", constraints: Dictionary = {}) -> Control:
	var key := hint if not hint.is_empty() else value_type
	if hint.is_empty() and constraints.has("enum") and value_type in STANDARD_HINT_TYPES.enum:
		key = "enum"
	if not _factories.has(key):
		return _fallback("Unsupported: " + value_type + (" / " + hint if not hint.is_empty() else ""), constraints)
	# 标准提示不能把不兼容的数据类型静默转换成另一种编辑器。
	if not hint.is_empty() and STANDARD_HINT_TYPES.has(key) and not value_type in STANDARD_HINT_TYPES[key]:
		return _fallback("Incompatible: " + value_type + " / " + hint, constraints)
	if key == "enum" and not _valid_enum(constraints.get("enum")):
		return _fallback("Invalid enum options", constraints)
	var factory: Callable = _factories[key]
	if not factory.is_valid():
		return _fallback("Unavailable: " + key, constraints)
	var candidate: Variant = factory.call()
	# 工厂返回的无效对象所有权未知，不能释放或修改调用方已有实例。
	if not is_instance_valid(candidate) or not candidate is VALUE_WIDGET_SCRIPT:
		return _fallback("Invalid widget: " + key, constraints)
	if candidate.get_parent() != null or candidate.is_inside_tree() or candidate.is_queued_for_deletion():
		return _fallback("Widget already in use: " + key, constraints)
	candidate.configure(constraints.duplicate(true))
	return candidate as Control


func _fallback(reason: String, constraints: Dictionary) -> Control:
	var widget = READONLY_WIDGET.instantiate()
	widget.configure(constraints.duplicate(true))
	widget.set_reason(reason)
	widget.set_read_only(true)
	return widget


static func _valid_enum(values: Variant) -> bool:
	if not values is Array:
		return false
	for value in values:
		if not VALUE_WIDGET_SCRIPT._is_json_primitive(value):
			return false
	return true
