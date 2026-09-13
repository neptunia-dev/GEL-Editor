extends VBoxContainer

## 字段控件只保存显示值与编辑草稿，不持有节点或文档模型。
signal value_committed(value: Variant)
signal editing_started

var _constraints: Dictionary = {}
var _value: Variant = null
var _has_value := false
var _saved_value: Variant = null
var _saved_has_value := false
var _read_only := false
var _updating := false
var _initialized := false
var _editing := false
var _dirty := false


func _ready() -> void:
	_ensure_initialized()
	_refresh()


func configure(constraints: Dictionary) -> void:
	_ensure_initialized()
	_updating = true
	_cancel_edit()
	_constraints = constraints.duplicate(true)
	_configure_editor()
	_render_value()
	_apply_read_only()
	_refresh_state()
	_updating = false


func set_value(value: Variant, has_value: bool = true) -> void:
	_ensure_initialized()
	_updating = true
	_cancel_pending_input()
	_value = _copy_value(value)
	_has_value = has_value
	_saved_value = _copy_value(value)
	_saved_has_value = has_value
	_dirty = false
	_editing = false
	_render_value()
	_refresh_state()
	_updating = false


func set_read_only(read_only: bool) -> void:
	_ensure_initialized()
	_updating = true
	_read_only = read_only
	if read_only:
		# 切换只读不提交尚未确认的草稿，也不留下延迟提交。
		_cancel_edit()
		_render_value()
	_apply_read_only()
	_refresh_state()
	_updating = false


func get_value() -> Variant:
	return _copy_value(_value)


func has_value() -> bool:
	return _has_value


func finish_edit() -> void:
	if _updating or _read_only:
		return
	_ensure_initialized()
	_flush_editor()
	_cancel_pending_input()
	_editing = false
	if not _dirty:
		return
	_dirty = false
	_saved_value = _copy_value(_value)
	_saved_has_value = _has_value
	_refresh_state()
	value_committed.emit(_copy_value(_value))


func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_setup_editor()


func _refresh() -> void:
	_updating = true
	_configure_editor()
	_render_value()
	_apply_read_only()
	_refresh_state()
	_updating = false


func _begin_editing() -> void:
	if _updating or _read_only or _editing:
		return
	_editing = true
	editing_started.emit()


func _stage_value(value: Variant) -> void:
	if _updating or _read_only:
		return
	_begin_editing()
	# 宿主可能在 editing_started 回调中把字段切换为只读。
	if _read_only or _updating:
		return
	_value = _copy_value(value)
	_has_value = true
	_dirty = not _saved_has_value or not _values_equal(_saved_value, _value)
	_refresh_state()


func _cancel_edit() -> void:
	_cancel_pending_input()
	_value = _copy_value(_saved_value)
	_has_value = _saved_has_value
	_dirty = false
	_editing = false


func _refresh_state() -> void:
	var state := get_node_or_null("State") as Label
	if state == null:
		return
	state.text = _state_text()
	state.visible = not state.text.is_empty()


func _state_text() -> String:
	if not _has_value:
		return "Unset"
	if _value == null:
		return "null"
	if not _accepts_value(_value):
		return "Invalid type"
	return ""


func _setup_editor() -> void:
	pass


func _configure_editor() -> void:
	pass


func _render_value() -> void:
	pass


func _apply_read_only() -> void:
	pass


func _flush_editor() -> void:
	pass


func _cancel_pending_input() -> void:
	pass


func _accepts_value(_candidate: Variant) -> bool:
	return true


static func _copy_value(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


static func _values_equal(left: Variant, right: Variant) -> bool:
	# JSON 数字允许整数和浮点表示互等，其余类型不进行隐式转换。
	if _is_number(left) and _is_number(right):
		return left == right
	return typeof(left) == typeof(right) and left == right


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _is_json_primitive(value: Variant) -> bool:
	return value == null or value is bool or value is String or _is_number(value)


static func _display_value(value: Variant) -> String:
	if _is_json_primitive(value) or value is Array or value is Dictionary:
		return JSON.stringify(value)
	return str(value)
