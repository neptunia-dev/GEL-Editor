extends GraphNode
class_name SceneNodeView

signal inspect_requested(kind: String, stable_id: Dictionary)
signal layout_changed(node_id: String)
signal context_menu_requested(node_id: String, screen_position: Vector2)

const PORT_TYPE_FLOW := 0
const INPUT_COLOR := Color("8aa4c8")
const EXIT_COLOR := Color("63c7b2")
const CONDITION_COLOR := Color("d79ae8")
const PORT_HOVER_COLOR := Color("fff2a8")
const PORT_HOVER_RADIUS := 16.0

var node_id: String = ""
var _scene_node: SceneNode
var _is_entry: bool = false
var _wrapper_expanded: bool = true
var _hovered_input_port: int = -1
var _hovered_output_port: int = -1

func _ready() -> void:
    resizable = false
    draggable = true
    selectable = true
    custom_minimum_size = Vector2(300, 0)
    _apply_theme()
    set_process(true)

func _process(_delta: float) -> void:
    update_port_hover(get_local_mouse_position())

func _input(event: InputEvent) -> void:
    if not event is InputEventMouseButton:
        return
    var button := event as InputEventMouseButton
    if button.button_index != MOUSE_BUTTON_RIGHT or not button.pressed:
        return
    if not get_global_rect().has_point(button.position):
        return
    var local_position := get_global_transform_with_canvas().affine_inverse() * button.position
    if _closest_port(local_position, true) >= 0 or _closest_port(local_position, false) >= 0:
        return
    context_menu_requested.emit(node_id, get_screen_position() + local_position)
    get_viewport().set_input_as_handled()

func set_scene_node(scene_node: SceneNode, is_entry: bool) -> void:
    _scene_node = scene_node
    node_id = scene_node.node_id
    name = StringName(node_id)
    _is_entry = is_entry
    position_offset = scene_node.position
    rebuild()

func get_scene_node() -> SceneNode:
    return _scene_node

func is_wrapper_expanded() -> bool:
    return _wrapper_expanded

func set_wrapper_expanded(expanded: bool) -> void:
    if _wrapper_expanded == expanded:
        return
    _wrapper_expanded = expanded
    rebuild()
    layout_changed.emit(node_id)

func rebuild() -> void:
    if _scene_node == null:
        return
    _hovered_input_port = -1
    _hovered_output_port = -1
    clear_all_slots()
    for child in get_children():
        remove_child(child)
        child.queue_free()

    title = _scene_node.title if not _scene_node.title.is_empty() else _scene_node.scene_id
    var subtitle := "Scene ID  %s" % _scene_node.scene_id
    if _is_entry:
        subtitle += "    ◆ ENTRY"
    var core_row := _add_label_row(subtitle, 0, Color("9ca8b8"))
    var core_slot := core_row.get_index()
    set_slot(core_slot, true, PORT_TYPE_FLOW, INPUT_COLOR, false, PORT_TYPE_FLOW, Color.WHITE)
    set_slot_metadata_left(core_slot, {"kind": "scene_input", "nodeId": node_id})

    for exit_port in _scene_node.get_exits():
        var row := _add_button_row("Exit  %s" % exit_port.name, 0, EXIT_COLOR)
        var slot := row.get_index()
        set_slot(slot, false, PORT_TYPE_FLOW, Color.WHITE, true, PORT_TYPE_FLOW, EXIT_COLOR)
        set_slot_metadata_right(slot, {
            "kind": RouteEdge.SOURCE_SCENE_EXIT,
            "nodeId": node_id,
            "portId": exit_port.port_id,
            "label": exit_port.name,
        })

    var tree := _scene_node.get_condition_tree()
    if tree != null:
        _render_condition_tree(tree)

    reset_size()
    queue_redraw()

func get_output_endpoint(port_index: int) -> Dictionary:
    if port_index < 0 or port_index >= get_output_port_count():
        return {}
    var slot := get_output_port_slot(port_index)
    var metadata = get_slot_metadata_right(slot)
    return metadata.duplicate(true) if metadata is Dictionary else {}

func get_input_endpoint(port_index: int) -> Dictionary:
    if port_index < 0 or port_index >= get_input_port_count():
        return {}
    var slot := get_input_port_slot(port_index)
    var metadata = get_slot_metadata_left(slot)
    return metadata.duplicate(true) if metadata is Dictionary else {}

func find_output_port(endpoint: Dictionary) -> int:
    for port_index in range(get_output_port_count()):
        if _same_endpoint(get_output_endpoint(port_index), endpoint):
            return port_index
    return -1

func get_condition_output_count() -> int:
    var count := 0
    for port_index in range(get_output_port_count()):
        if str(get_output_endpoint(port_index).get("kind", "")) == RouteEdge.SOURCE_CONDITION_BRANCH:
            count += 1
    return count

## Port hover is updated independently from child Controls, so row buttons cannot hide it.
func update_port_hover(local_mouse_position: Vector2) -> void:
    var next_input := _closest_port(local_mouse_position, true)
    var next_output := _closest_port(local_mouse_position, false)
    if next_input == _hovered_input_port and next_output == _hovered_output_port:
        return
    _restore_hovered_port_colors()
    _hovered_input_port = next_input
    _hovered_output_port = next_output
    if _hovered_input_port >= 0:
        set_slot_color_left(get_input_port_slot(_hovered_input_port), PORT_HOVER_COLOR)
    if _hovered_output_port >= 0:
        set_slot_color_right(get_output_port_slot(_hovered_output_port), PORT_HOVER_COLOR)
    queue_redraw()

func get_hovered_input_port() -> int:
    return _hovered_input_port

func get_hovered_output_port() -> int:
    return _hovered_output_port

func _render_condition_tree(tree: ConditionTree) -> void:
    var root := tree.get_wrapper(tree.root_wrapper_id)
    if root == null:
        return
    var shell := HBoxContainer.new()
    shell.add_theme_constant_override("separation", 6)
    var toggle := Button.new()
    toggle.text = "▾" if _wrapper_expanded else "▸"
    toggle.flat = true
    toggle.tooltip_text = "Expand or collapse condition wrapper"
    toggle.pressed.connect(func(): set_wrapper_expanded(not _wrapper_expanded))
    shell.add_child(toggle)
    var summary := Button.new()
    summary.flat = true
    summary.text = "%s    · %d leaves" % [_wrapper_summary(root), tree.get_leaf_endpoints().size()]
    summary.alignment = HORIZONTAL_ALIGNMENT_LEFT
    summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    summary.pressed.connect(_emit_inspect.bind("wrapper", {
        "nodeId": node_id,
        "wrapperId": root.wrapper_id,
    }))
    shell.add_child(summary)
    add_child(shell)
    set_slot_draw_stylebox(shell.get_index(), false)

    if _wrapper_expanded:
        _render_wrapper(tree, root.wrapper_id, 0, true)
    else:
        for endpoint in tree.get_leaf_endpoints():
            var branch := tree.get_branch(str(endpoint["branchId"]))
            var label := "↳ %s" % _branch_label(branch)
            _add_condition_branch_row(label, endpoint, 1)

func _render_wrapper(tree: ConditionTree, wrapper_id: String, depth: int, is_root: bool = false) -> void:
    var wrapper := tree.get_wrapper(wrapper_id)
    if wrapper == null:
        return
    if not is_root:
        var header := _add_button_row(_wrapper_summary(wrapper), depth, Color("b8a2cb"))
        _row_button(header).pressed.connect(_emit_inspect.bind("wrapper", {
            "nodeId": node_id,
            "wrapperId": wrapper.wrapper_id,
        }))

    for branch_id in wrapper.get_branch_ids():
        var branch := tree.get_branch(str(branch_id))
        if branch == null:
            continue
        var label := "%s  %s" % [_branch_role(wrapper, branch.branch_id), _branch_label(branch)]
        if branch.is_terminal():
            _add_condition_branch_row(label, {
                "wrapperId": wrapper.wrapper_id,
                "branchId": branch.branch_id,
            }, depth + 1)
        else:
            var row := _add_button_row(label, depth + 1, Color("9c84ad"))
            _row_button(row).pressed.connect(_emit_inspect.bind("branch", {
                "nodeId": node_id,
                "wrapperId": wrapper.wrapper_id,
                "branchId": branch.branch_id,
            }))
            _render_wrapper(tree, branch.child_wrapper_id, depth + 2)

func _add_condition_branch_row(label: String, endpoint: Dictionary, depth: int) -> void:
    var row := _add_button_row(label, depth, CONDITION_COLOR)
    var slot := row.get_index()
    var metadata := {
        "kind": RouteEdge.SOURCE_CONDITION_BRANCH,
        "nodeId": node_id,
        "wrapperId": str(endpoint["wrapperId"]),
        "branchId": str(endpoint["branchId"]),
        "label": label.strip_edges(),
    }
    set_slot(slot, false, PORT_TYPE_FLOW, Color.WHITE, true, PORT_TYPE_FLOW, CONDITION_COLOR)
    set_slot_metadata_right(slot, metadata)
    _row_button(row).pressed.connect(_emit_inspect.bind("branch", metadata))

func _add_label_row(text: String, depth: int, color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 28
    _add_indent(row, depth)
    var label := Label.new()
    label.text = text
    label.modulate = color
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(label)
    add_child(row)
    return row

func _add_button_row(text: String, depth: int, color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 30
    _add_indent(row, depth)
    var button := Button.new()
    button.text = text
    button.flat = true
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.modulate = color
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(button)
    # Keep the inner half of the output hotzone free from Button mouse capture.
    var port_space := Control.new()
    port_space.custom_minimum_size.x = 24
    port_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(port_space)
    add_child(row)
    return row

func _add_indent(row: HBoxContainer, depth: int) -> void:
    if depth <= 0:
        return
    var spacer := Control.new()
    spacer.custom_minimum_size.x = depth * 16.0
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(spacer)

func _row_button(row: HBoxContainer) -> Button:
    for child in row.get_children():
        if child is Button:
            return child as Button
    return null

func _wrapper_summary(wrapper: ConditionWrapper) -> String:
    if wrapper is IfWrapper:
        return "IF  %s" % (wrapper as IfWrapper).variable_key
    if wrapper is SwitchCaseWrapper:
        var value := wrapper as SwitchCaseWrapper
        return "SWITCH  %s  · %d cases" % [value.variable_key, value.case_branch_ids.size()]
    if wrapper is NumericCompareWrapper:
        var value := wrapper as NumericCompareWrapper
        return "COMPARE  %s  ↔  %s" % [_operand_summary(value.left_operand), _operand_summary(value.right_operand)]
    return "CONDITION"

func _operand_summary(operand: NumericOperand) -> String:
    if operand == null:
        return "?"
    return operand.variable_key if operand.kind == NumericOperand.KIND_VARIABLE else str(operand.constant_value)

func _branch_role(wrapper: ConditionWrapper, branch_id: String) -> String:
    if wrapper is IfWrapper:
        return "TRUE" if branch_id == (wrapper as IfWrapper).true_branch_id else "FALSE"
    if wrapper is SwitchCaseWrapper:
        return "DEFAULT" if branch_id == (wrapper as SwitchCaseWrapper).default_branch_id else "CASE"
    if wrapper is NumericCompareWrapper:
        var numeric := wrapper as NumericCompareWrapper
        if branch_id == numeric.less_branch_id:
            return "<"
        if branch_id == numeric.greater_branch_id:
            return ">"
        return "="
    return "BRANCH"

func _branch_label(branch: ConditionBranch) -> String:
    if branch == null:
        return "missing"
    var label := branch.label if not branch.label.is_empty() else branch.branch_id
    if branch.has_match_value:
        label += "  [%s]" % JSON.stringify(branch.match_value)
    return label

func _emit_inspect(kind: String, stable_id: Dictionary) -> void:
    inspect_requested.emit(kind, stable_id)

func _same_endpoint(left: Dictionary, right: Dictionary) -> bool:
    if str(left.get("kind", "")) != str(right.get("kind", "")):
        return false
    if str(left.get("nodeId", "")) != str(right.get("nodeId", "")):
        return false
    if str(left.get("kind", "")) == RouteEdge.SOURCE_SCENE_EXIT:
        return str(left.get("portId", "")) == str(right.get("portId", ""))
    return (
        str(left.get("wrapperId", "")) == str(right.get("wrapperId", ""))
        and str(left.get("branchId", "")) == str(right.get("branchId", ""))
    )

func _closest_port(local_mouse_position: Vector2, input: bool) -> int:
    var count := get_input_port_count() if input else get_output_port_count()
    var closest := -1
    var closest_distance := PORT_HOVER_RADIUS
    for port_index in range(count):
        var position := (
            get_input_port_position(port_index)
            if input else get_output_port_position(port_index)
        )
        var distance := local_mouse_position.distance_to(position)
        if distance <= closest_distance:
            closest = port_index
            closest_distance = distance
    return closest

func _restore_hovered_port_colors() -> void:
    if _hovered_input_port >= 0 and _hovered_input_port < get_input_port_count():
        set_slot_color_left(get_input_port_slot(_hovered_input_port), INPUT_COLOR)
    if _hovered_output_port >= 0 and _hovered_output_port < get_output_port_count():
        var endpoint := get_output_endpoint(_hovered_output_port)
        var color := (
            EXIT_COLOR
            if str(endpoint.get("kind", "")) == RouteEdge.SOURCE_SCENE_EXIT
            else CONDITION_COLOR
        )
        set_slot_color_right(get_output_port_slot(_hovered_output_port), color)

func _apply_theme() -> void:
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("252a34")
    panel.border_color = Color("414a5a")
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(10)
    panel.content_margin_left = 12
    panel.content_margin_right = 12
    panel.content_margin_top = 8
    panel.content_margin_bottom = 10
    add_theme_stylebox_override("panel", panel)
    var selected := panel.duplicate()
    selected.border_color = Color("80a8ff")
    selected.set_border_width_all(2)
    add_theme_stylebox_override("panel_selected", selected)
    var titlebar := StyleBoxFlat.new()
    titlebar.bg_color = Color("303746")
    titlebar.set_corner_radius_all(9)
    titlebar.content_margin_left = 10
    titlebar.content_margin_right = 10
    titlebar.content_margin_top = 7
    titlebar.content_margin_bottom = 7
    add_theme_stylebox_override("titlebar", titlebar)
    add_theme_stylebox_override("titlebar_selected", titlebar)
    add_theme_color_override("title_color", Color("eef2f8"))
