extends "res://workspace/node_map/widgets/value_widget.gd"

var _editor: LineEdit
var _observed_text := ""


func _setup_editor() -> void:
	_editor = get_node("Editor") as LineEdit
	_editor.text_changed.connect(_on_text_changed)
	_editor.text_submitted.connect(_on_text_submitted)
	_editor.focus_entered.connect(_begin_editing)
	_editor.focus_exited.connect(finish_edit)


func _render_value() -> void:
	_observed_text = _value if _has_value and _value is String else ""
	_editor.text = _observed_text
	_editor.placeholder_text = _state_text()


func _apply_read_only() -> void:
	_editor.editable = not _read_only


func _accepts_value(candidate: Variant) -> bool:
	return candidate is String


func _on_text_changed(text: String) -> void:
	if _updating or _read_only or text != _editor.text or text == _observed_text:
		return
	_observed_text = text
	_stage_value(text)


func _on_text_submitted(_text: String) -> void:
	finish_edit()


func _flush_editor() -> void:
	# 同帧关闭节点时，LineEdit 的文本通知可能尚未派发。
	_on_text_changed(_editor.text)
