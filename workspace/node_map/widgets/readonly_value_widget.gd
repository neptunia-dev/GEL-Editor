extends "res://workspace/node_map/widgets/value_widget.gd"

var _editor: LineEdit
var _reason := "Unsupported widget"


func _setup_editor() -> void:
	_editor = get_node("Editor") as LineEdit
	_read_only = true


func set_reason(reason: String) -> void:
	_reason = reason
	_ensure_initialized()
	_refresh_state()


func set_read_only(_read_only_requested: bool) -> void:
	super.set_read_only(true)


func _render_value() -> void:
	_editor.text = _display_value(_value) if _has_value else ""
	_editor.placeholder_text = "Unset"
	_editor.tooltip_text = _editor.text


func _apply_read_only() -> void:
	_read_only = true
	_editor.editable = false


func _state_text() -> String:
	var state := super._state_text()
	return _reason if state.is_empty() else _reason + " / " + state
