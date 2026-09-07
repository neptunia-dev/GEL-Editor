extends "res://workspace/node_map/widgets/value_widget.gd"

var _editor: CheckBox


func _setup_editor() -> void:
	_editor = get_node("Editor") as CheckBox
	# pressed 只对应操作，程序设置 button_pressed 不会触发提交。
	_editor.pressed.connect(_on_pressed)


func _render_value() -> void:
	_editor.set_pressed_no_signal(_has_value and _value is bool and _value)
	_editor.text = str(_value) if _has_value and _value is bool else ""


func _apply_read_only() -> void:
	_editor.disabled = _read_only
	_editor.focus_mode = Control.FOCUS_NONE if _read_only else Control.FOCUS_ALL


func _accepts_value(candidate: Variant) -> bool:
	return candidate is bool


func _on_pressed() -> void:
	if _updating or _read_only:
		return
	_stage_value(_editor.button_pressed)
	_editor.text = str(_value)
	finish_edit()
