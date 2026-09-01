extends RefCounted
class_name EditorDockDescriptor

## 单个编辑器 Dock 的 UI 无关注册描述。
##
## 描述对象只记录 Dock 的稳定身份、显示信息、默认槽位和允许停靠位置等元数据。
## 它不创建、不持有具体 Control，也不记录用户当前的可变布局；当前布局由
## EditorLayoutState 统一保存。这样同一个 Dock 的内容可以在不同槽位之间移动，
## 而描述对象本身仍保持稳定。

const ID_PATTERN := "^[a-z][a-z0-9_.-]*$"

var dock_id: String
var title: String
var icon_name: StringName
var default_slot: String
var allowed_slots: Array
var default_open: bool
var closable: bool
var transient: bool
var default_order: int

func _init(
		p_dock_id: String = "",
		p_title: String = "",
		p_default_slot: String = "",
		p_allowed_slots: Array = [],
		p_default_open: bool = true,
		p_closable: bool = true,
		p_transient: bool = false,
		p_default_order: int = 0,
		p_icon_name: StringName = &"",
) -> void:
	dock_id = p_dock_id
	title = p_title
	default_slot = p_default_slot
	allowed_slots = p_allowed_slots.duplicate()
	if allowed_slots.is_empty() and not default_slot.is_empty():
		allowed_slots.append(default_slot)
	default_open = p_default_open
	closable = p_closable
	transient = p_transient
	default_order = p_default_order
	icon_name = p_icon_name

func duplicate_descriptor():
	return get_script().new(
		dock_id, title, default_slot, allowed_slots, default_open,
		closable, transient, default_order, icon_name,
	)

func allows_slot(slot_id: String) -> bool:
	return allowed_slots.has(slot_id)

func validate_self(known_slots: Array = []) -> Array:
	var errors: Array = []
	if not _is_valid_id(dock_id):
		errors.append("dock_id must match %s" % ID_PATTERN)
	if title.strip_edges().is_empty():
		errors.append("dock '%s' title must not be empty" % dock_id)
	if default_slot.is_empty():
		errors.append("dock '%s' default_slot must not be empty" % dock_id)
	if allowed_slots.is_empty():
		errors.append("dock '%s' must allow at least one slot" % dock_id)
	elif not allowed_slots.has(default_slot):
		errors.append("dock '%s' default_slot must be included in allowed_slots" % dock_id)

	var seen: Dictionary = {}
	for raw_slot in allowed_slots:
		if not raw_slot is String:
			errors.append("dock '%s' allowed_slots must contain strings" % dock_id)
			continue
		var slot_id := str(raw_slot)
		if seen.has(slot_id):
			errors.append("dock '%s' contains duplicate allowed slot '%s'" % [dock_id, slot_id])
			continue
		seen[slot_id] = true
		if not known_slots.is_empty() and not known_slots.has(slot_id):
			errors.append("dock '%s' references unknown slot '%s'" % [dock_id, slot_id])

	if not known_slots.is_empty() and not known_slots.has(default_slot):
		errors.append("dock '%s' default_slot '%s' does not exist" % [dock_id, default_slot])
	return errors

static func _is_valid_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(ID_PATTERN) == OK and regex.search(value) != null
