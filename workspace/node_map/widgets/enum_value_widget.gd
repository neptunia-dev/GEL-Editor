extends "res://workspace/node_map/widgets/value_widget.gd"

var _editor: OptionButton


func _setup_editor() -> void:
	_editor = get_node("Editor") as OptionButton
	_editor.item_selected.connect(_on_item_selected)
	_editor.get_popup().about_to_popup.connect(_begin_editing)


func _render_value() -> void:
	_editor.clear()
	var selected_index := -1
	for option in _get_options():
		var index := _editor.item_count
		var label: String = option.label
		# 菜单也限制显示长度，完整标签保存在提示中。
		var short_label := label if label.length() <= 64 else label.left(61) + "..."
		_editor.add_item(short_label)
		_editor.set_item_metadata(index, option.value)
		_editor.set_item_tooltip(index, label)
		if _has_value and _values_equal(option.value, _value):
			selected_index = index
	if selected_index < 0:
		# 保留未设置、空值和失效引用，绝不自动选择首项。
		selected_index = _editor.item_count
		var missing_label := _missing_label()
		_editor.add_item(missing_label.left(64))
		_editor.set_item_metadata(selected_index, _copy_value(_value))
		_editor.set_item_tooltip(selected_index, missing_label)
		_editor.set_item_disabled(selected_index, true)
	_editor.select(selected_index)
	_editor.tooltip_text = _editor.get_item_tooltip(selected_index)


func _apply_read_only() -> void:
	_editor.disabled = _read_only
	_editor.focus_mode = Control.FOCUS_NONE if _read_only else Control.FOCUS_ALL
	if _read_only:
		_editor.get_popup().hide()


func _get_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var values: Variant = _constraints.get("enum", [])
	if not values is Array:
		return result
	for value in values:
		if not _is_json_primitive(value):
			continue
		result.append({"value": value, "label": _display_value(value)})
	return result


func _accepts_value(candidate: Variant) -> bool:
	return _is_json_primitive(candidate)


func _missing_label() -> String:
	if not _has_value:
		return "Unset"
	if _value == null:
		return "null"
	return "Missing: " + _display_value(_value)


func _on_item_selected(index: int) -> void:
	if _updating or _read_only or index < 0 or index >= _editor.item_count:
		return
	if _editor.is_item_disabled(index):
		return
	_stage_value(_editor.get_item_metadata(index))
	_updating = true
	_render_value()
	_updating = false
	finish_edit()
