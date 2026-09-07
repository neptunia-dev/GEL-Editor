extends "res://workspace/node_map/widgets/value_widget.gd"

const DEFAULT_MIN := -1.0e12
const DEFAULT_MAX := 1.0e12
const DEFAULT_STEP := 0.01

var _editor: SpinBox
var _line_edit: LineEdit
var _native_line_edit: LineEdit
var _commit_timer: Timer
var _input_text := ""
var _observed_text := ""
var _text_dirty := false
var _stepping := false


func _setup_editor() -> void:
	_editor = get_node("Editor") as SpinBox
	_line_edit = get_node("Editor/Input") as LineEdit
	_native_line_edit = _editor.get_line_edit()
	_commit_timer = get_node("CommitTimer") as Timer
	# 原生文本区会延迟解析并改写空值，独立草稿保留原文，步进仍由 SpinBox 负责。
	_native_line_edit.hide()
	_native_line_edit.focus_entered.connect(_line_edit.grab_focus)
	_native_line_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_native_line_edit.resized.connect(_layout_input)
	_editor.resized.connect(_layout_input)
	_line_edit.text_changed.connect(_on_text_changed)
	_line_edit.text_submitted.connect(_on_text_submitted)
	_line_edit.focus_entered.connect(_begin_editing)
	_line_edit.focus_exited.connect(finish_edit)
	_line_edit.gui_input.connect(_on_text_input)
	_editor.gui_input.connect(_on_step_input)
	_editor.value_changed.connect(_on_number_changed)
	_commit_timer.timeout.connect(finish_edit)
	_layout_input.call_deferred()


func _layout_input() -> void:
	_line_edit.position = _native_line_edit.position
	_line_edit.size = _native_line_edit.size.max(Vector2.ZERO)


func _configure_editor() -> void:
	var lower := DEFAULT_MIN
	var upper := DEFAULT_MAX
	var increment := DEFAULT_STEP
	if _is_number(_constraints.get("min")):
		lower = float(_constraints.min)
	if _is_number(_constraints.get("max")):
		upper = float(_constraints.max)
	if lower > upper:
		lower = DEFAULT_MIN
		upper = DEFAULT_MAX
	if _is_number(_constraints.get("step")) and float(_constraints.step) > 0.0:
		increment = float(_constraints.step)
	_editor.min_value = lower
	_editor.max_value = upper
	_editor.step = increment
	_editor.allow_lesser = false
	_editor.allow_greater = false


func _render_value() -> void:
	_text_dirty = false
	var number := float(_value) if _has_value and _is_number(_value) else 0.0
	_editor.set_value_no_signal(number)
	# 越界旧值保留原样，只在实际编辑时应用范围和步长。
	_observed_text = str(_value) if _has_value and _is_number(_value) else ""
	_input_text = _observed_text
	_line_edit.text = _observed_text
	_line_edit.placeholder_text = _state_text()


func _apply_read_only() -> void:
	_editor.editable = not _read_only
	_line_edit.editable = not _read_only
	_editor.mouse_filter = Control.MOUSE_FILTER_IGNORE if _read_only else Control.MOUSE_FILTER_STOP


func _accepts_value(candidate: Variant) -> bool:
	return _is_number(candidate)


func _state_text() -> String:
	var state := super._state_text()
	if not state.is_empty():
		return state
	if _editor != null and (_value < _editor.min_value or _value > _editor.max_value):
		return "Out of range"
	return ""


func _on_text_changed(text: String) -> void:
	if _updating or _read_only or text != _line_edit.text or text == _observed_text:
		return
	_begin_editing()
	_commit_timer.stop()
	_observed_text = text
	_input_text = text
	_text_dirty = true


func _on_number_changed(number: float) -> void:
	if _updating or _read_only or not _stepping:
		return
	_stage_value(number)
	_updating = true
	_render_value()
	_updating = false
	if is_inside_tree():
		# 连续点击或拖动步进器合并成一次提交，失焦可提前提交。
		_commit_timer.start()
	else:
		finish_edit()


func _on_text_submitted(_text: String) -> void:
	finish_edit()


func _flush_editor() -> void:
	_on_text_changed(_line_edit.text)
	if not _text_dirty:
		return
	var text := _input_text.strip_edges()
	_text_dirty = false
	# 不把空文本、非有限数或表达式静默转为零。
	if not text.is_valid_float() or not is_finite(text.to_float()):
		_updating = true
		_render_value()
		_updating = false
		return
	_updating = true
	_editor.set_value_no_signal(text.to_float())
	var number := _editor.value
	_updating = false
	_stage_value(number)
	_updating = true
	_render_value()
	_updating = false


func _cancel_pending_input() -> void:
	_text_dirty = false
	_stepping = false
	if _commit_timer != null:
		_commit_timer.stop()


func _on_text_input(event: InputEvent) -> void:
	if _read_only or _updating or not event is InputEventKey or not event.pressed:
		return
	if event.keycode in [KEY_UP, KEY_DOWN]:
		_flush_editor()
		_stepping = true
		_editor.value += _editor.step if event.keycode == KEY_UP else -_editor.step
		_stepping = false
		_line_edit.accept_event()


func _on_step_input(event: InputEvent) -> void:
	if _read_only or _updating:
		return
	if event is InputEventMouseButton:
		_stepping = event.pressed
		if event.pressed:
			_flush_editor()
	elif event is InputEventMouseMotion and event.button_mask != 0:
		_stepping = true
