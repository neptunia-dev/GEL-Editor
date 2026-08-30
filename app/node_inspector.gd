extends PanelContainer
class_name NodeInspector

signal scene_apply_requested(draft: Dictionary)
signal wrapper_apply_requested(draft: Dictionary)
signal branch_apply_requested(draft: Dictionary)
signal child_wrapper_requested(node_id: String, branch_id: String, wrapper_kind: String)
signal branch_subtree_removal_requested(node_id: String, branch_id: String)
signal branch_removal_requested(node_id: String, branch_id: String)
signal edge_removal_requested(edge_id: String)

var _content: VBoxContainer
var _error_label: Label
var _fields: Dictionary = {}
var _selection_kind: String = "none"
var _selection_id: Variant = ""
var _scene_map: SceneMap = SceneMap.new()

func _ready() -> void:
    custom_minimum_size.x = 340
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(scroll)
    _content = VBoxContainer.new()
    _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _content.add_theme_constant_override("separation", 10)
    scroll.add_child(_content)
    _show_empty()
    _apply_theme()

func set_selection(kind: String, stable_id: Variant, scene_map: SceneMap) -> void:
    _selection_kind = kind
    _selection_id = stable_id
    _scene_map = scene_map.duplicate_map()
    _rebuild()

func refresh(scene_map: SceneMap) -> void:
    _scene_map = scene_map.duplicate_map()
    _rebuild()

func show_error(message: String) -> void:
    if _error_label != null:
        _error_label.text = message
        _error_label.visible = not message.is_empty()

func _rebuild() -> void:
    _clear()
    match _selection_kind:
        "scene":
            _show_scene(str(_selection_id))
        "wrapper":
            _show_wrapper(_selection_id as Dictionary)
        "branch":
            _show_branch(_selection_id as Dictionary)
        "edge":
            _show_edge(str(_selection_id))
        _:
            _show_empty()

func _show_empty() -> void:
    _add_heading("Inspector")
    var label := Label.new()
    label.text = "Select a Scene, wrapper, branch, or connection."
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.modulate = Color("8d98a8")
    _content.add_child(label)
    _add_error_label()

func _show_scene(node_id: String) -> void:
    var node := _scene_map.get_node(node_id)
    if node == null:
        _show_empty()
        return
    _add_heading("Scene")
    _add_readonly("Node ID", node.node_id)
    _fields["title"] = _add_line_edit("Title", node.title)
    _fields["scene_id"] = _add_line_edit("Scene ID", node.scene_id)
    _fields["main_script"] = _add_line_edit("Lua main", node.main_script)
    var entry := CheckButton.new()
    entry.text = "Entry Scene"
    entry.button_pressed = _scene_map.get_entry_node_id() == node_id
    _content.add_child(entry)
    _fields["entry"] = entry

    _add_field_label("Explicit exits  (port_id = name)")
    var exits := TextEdit.new()
    exits.custom_minimum_size.y = 130
    var lines: Array = []
    for port in node.get_exits():
        lines.append("%s = %s" % [port.port_id, port.name])
    exits.text = "\n".join(lines)
    _content.add_child(exits)
    _fields["exits"] = exits

    var apply := Button.new()
    apply.text = "Apply Scene"
    apply.pressed.connect(func():
        scene_apply_requested.emit({
            "nodeId": node_id,
            "title": (_fields["title"] as LineEdit).text,
            "sceneId": (_fields["scene_id"] as LineEdit).text,
            "mainScript": (_fields["main_script"] as LineEdit).text,
            "entry": (_fields["entry"] as CheckButton).button_pressed,
            "exits": (_fields["exits"] as TextEdit).text,
        })
    )
    _content.add_child(apply)
    _add_error_label()

func _show_wrapper(stable_id: Dictionary) -> void:
    var node_id := str(stable_id.get("nodeId", ""))
    var wrapper_id := str(stable_id.get("wrapperId", ""))
    var node := _scene_map.get_node(node_id)
    var tree := node.get_condition_tree() if node != null else null
    var wrapper := tree.get_wrapper(wrapper_id) if tree != null else null
    if wrapper == null:
        _show_empty()
        return
    _add_heading("Condition Wrapper")
    _add_readonly("Wrapper ID", wrapper.wrapper_id)
    if wrapper is IfWrapper:
        _add_readonly("Type", "If")
        _fields["variable"] = _add_line_edit("Boolean variable", (wrapper as IfWrapper).variable_key)
    elif wrapper is SwitchCaseWrapper:
        var switch_wrapper := wrapper as SwitchCaseWrapper
        _add_readonly("Type", "Switch")
        _fields["variable"] = _add_line_edit("Scalar variable", switch_wrapper.variable_key)
        _add_field_label("Cases  (branch_id = JSON value | label)")
        var cases := TextEdit.new()
        cases.custom_minimum_size.y = 150
        var lines: Array = []
        for branch_id in switch_wrapper.case_branch_ids:
            var branch := tree.get_branch(str(branch_id))
            lines.append("%s = %s | %s" % [branch_id, JSON.stringify(branch.match_value), branch.label])
        var default_branch := tree.get_branch(switch_wrapper.default_branch_id)
        lines.append("%s = default | %s" % [switch_wrapper.default_branch_id, default_branch.label])
        cases.text = "\n".join(lines)
        _content.add_child(cases)
        _fields["cases"] = cases
    elif wrapper is NumericCompareWrapper:
        var numeric := wrapper as NumericCompareWrapper
        _add_readonly("Type", "Numeric compare")
        _fields["left"] = _add_line_edit("Left operand", _operand_text(numeric.left_operand))
        _fields["right"] = _add_line_edit("Right operand", _operand_text(numeric.right_operand))
        var hint := Label.new()
        hint.text = "Use var:score.value or a finite number."
        hint.modulate = Color("8d98a8")
        _content.add_child(hint)

    var apply := Button.new()
    apply.text = "Apply Wrapper"
    apply.pressed.connect(func():
        var draft := {"nodeId": node_id, "wrapperId": wrapper_id}
        if _fields.has("variable"):
            draft["variableKey"] = (_fields["variable"] as LineEdit).text
        if _fields.has("cases"):
            draft["cases"] = (_fields["cases"] as TextEdit).text
        if _fields.has("left"):
            draft["leftOperand"] = (_fields["left"] as LineEdit).text
            draft["rightOperand"] = (_fields["right"] as LineEdit).text
        wrapper_apply_requested.emit(draft)
    )
    _content.add_child(apply)
    _add_error_label()

func _show_branch(stable_id: Dictionary) -> void:
    var node_id := str(stable_id.get("nodeId", ""))
    var wrapper_id := str(stable_id.get("wrapperId", ""))
    var branch_id := str(stable_id.get("branchId", ""))
    var node := _scene_map.get_node(node_id)
    var tree := node.get_condition_tree() if node != null else null
    var wrapper := tree.get_wrapper(wrapper_id) if tree != null else null
    var branch := tree.get_branch(branch_id) if tree != null else null
    if branch == null or wrapper == null:
        _show_empty()
        return
    _add_heading("Condition Branch")
    _add_readonly("Branch ID", branch.branch_id)
    _fields["label"] = _add_line_edit("Display label", branch.label)
    if branch.has_match_value:
        _fields["match"] = _add_line_edit("Case value (JSON)", JSON.stringify(branch.match_value))

    var apply := Button.new()
    apply.text = "Apply Branch"
    apply.pressed.connect(func():
        branch_apply_requested.emit({
            "nodeId": node_id,
            "wrapperId": wrapper_id,
            "branchId": branch_id,
            "label": (_fields["label"] as LineEdit).text,
            "hasMatchValue": branch.has_match_value,
            "matchValue": (_fields["match"] as LineEdit).text if _fields.has("match") else "",
        })
    )
    _content.add_child(apply)

    if branch.child_wrapper_id.is_empty():
        _add_field_label("Add child wrapper")
        var row := HBoxContainer.new()
        var kind := OptionButton.new()
        kind.add_item("If", 0)
        kind.set_item_metadata(0, "if")
        kind.add_item("Switch", 1)
        kind.set_item_metadata(1, "switch")
        kind.add_item("Numeric compare", 2)
        kind.set_item_metadata(2, "numeric_compare")
        kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(kind)
        var add := Button.new()
        add.text = "Add"
        add.pressed.connect(func():
            child_wrapper_requested.emit(node_id, branch_id, str(kind.get_selected_metadata()))
        )
        row.add_child(add)
        _content.add_child(row)
    else:
        _add_readonly("Child wrapper", branch.child_wrapper_id)
        var remove_subtree := Button.new()
        remove_subtree.text = "Remove Child Subtree"
        remove_subtree.pressed.connect(func(): branch_subtree_removal_requested.emit(node_id, branch_id))
        _content.add_child(remove_subtree)

    if wrapper is SwitchCaseWrapper and branch_id != (wrapper as SwitchCaseWrapper).default_branch_id:
        var remove_case := Button.new()
        remove_case.text = "Delete Switch Case"
        remove_case.pressed.connect(func(): branch_removal_requested.emit(node_id, branch_id))
        _content.add_child(remove_case)
    _add_error_label()

func _show_edge(edge_id: String) -> void:
    var edge := _scene_map.get_route(edge_id)
    if edge == null:
        _show_empty()
        return
    _add_heading("Route Edge")
    _add_readonly("Edge ID", edge.edge_id)
    _add_readonly("Source kind", edge.source_kind)
    _add_readonly("Source Scene", edge.source_node_id)
    if edge.source_kind == RouteEdge.SOURCE_SCENE_EXIT:
        _add_readonly("Exit port", edge.source_port_id)
    else:
        _add_readonly("Wrapper", edge.source_wrapper_id)
        _add_readonly("Branch", edge.source_branch_id)
    _add_readonly("Target Scene", edge.target_node_id)
    var remove := Button.new()
    remove.text = "Delete Connection"
    remove.pressed.connect(func(): edge_removal_requested.emit(edge_id))
    _content.add_child(remove)
    _add_error_label()

func _clear() -> void:
    _fields.clear()
    _error_label = null
    if _content == null:
        return
    for child in _content.get_children():
        _content.remove_child(child)
        child.queue_free()

func _add_heading(text: String) -> void:
    var heading := Label.new()
    heading.text = text
    heading.add_theme_font_size_override("font_size", 20)
    heading.modulate = Color("eef2f8")
    _content.add_child(heading)
    var separator := HSeparator.new()
    _content.add_child(separator)

func _add_readonly(label_text: String, value: String) -> void:
    _add_field_label(label_text)
    var label := Label.new()
    label.text = value
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.modulate = Color("aeb8c6")
    _content.add_child(label)

func _add_line_edit(label_text: String, value: String) -> LineEdit:
    _add_field_label(label_text)
    var field := LineEdit.new()
    field.text = value
    _content.add_child(field)
    return field

func _add_field_label(text: String) -> void:
    var label := Label.new()
    label.text = text
    label.modulate = Color("8793a4")
    _content.add_child(label)

func _add_error_label() -> void:
    _error_label = Label.new()
    _error_label.visible = false
    _error_label.modulate = Color("ff8d8d")
    _error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _content.add_child(_error_label)

func _operand_text(operand: NumericOperand) -> String:
    if operand == null:
        return ""
    return "var:%s" % operand.variable_key if operand.kind == NumericOperand.KIND_VARIABLE else str(operand.constant_value)

func _apply_theme() -> void:
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("20242d")
    panel.content_margin_left = 18
    panel.content_margin_right = 18
    panel.content_margin_top = 18
    panel.content_margin_bottom = 18
    add_theme_stylebox_override("panel", panel)
