extends "res://workspace/node_map/widgets/value_widget.gd"

var _editor: TextEdit
var _observed_text := ""


func _setup_editor() -> void:
	_editor = get_node("Editor") as TextEdit
	_editor.text_changed.connect(_on_text_changed)
	_editor.focus_entered.connect(_begin_editing)
	# 不拦截回车，保留 TextEdit 自身的换行与输入法行为。
	_editor.focus_exited.connect(finish_edit)


func _render_value() -> void:
	_observed_text = _value if _has_value and _value is String else ""
	_editor.text = _observed_text
	_editor.placeholder_text = _state_text()


func _apply_read_only() -> void:
	_editor.editable = not _read_only


func _accepts_value(candidate: Variant) -> bool:
	return candidate is String


func _on_text_changed() -> void:
	# TextEdit 的延迟通知可能在程序赋值保护结束后到达。
	if _updating or _read_only or _editor.text == _observed_text:
		return
	_observed_text = _editor.text
	_stage_value(_observed_text)


func _flush_editor() -> void:
	# 关闭节点前主动收取尚未派发的文本通知。
	_on_text_changed()
