extends Control
class_name NodeMapApplication

const NODE_MAP_CONTROLLER_SCRIPT := preload("res://app/node_map_controller.gd")
const NODE_MAP_CANVAS_SCRIPT := preload("res://app/node_map_canvas.gd")
const NODE_INSPECTOR_SCRIPT := preload("res://app/node_inspector.gd")
const DEMO_MAP_FACTORY_SCRIPT := preload("res://app/demo_map_factory.gd")

var _controller = NODE_MAP_CONTROLLER_SCRIPT.new()
var _canvas
var _inspector
var _status: Label
var _add_dialog: ConfirmationDialog
var _scene_id_field: LineEdit
var _scene_title_field: LineEdit
var _pending_scene_position: Vector2 = Vector2(120, 100)
var _delete_dialog: ConfirmationDialog
var _pending_delete_ids: Array = []

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_interface()
    _connect_controller()
    _controller.set_scene_map(SceneMap.new())
    if OS.get_cmdline_user_args().has("--demo"):
        _controller.set_scene_map(DEMO_MAP_FACTORY_SCRIPT.create())
    OS.low_processor_usage_mode = true

func set_scene_map(scene_map: SceneMap) -> void:
    _controller.set_scene_map(scene_map)

func get_scene_map() -> SceneMap:
    return _controller.get_scene_map()

func get_controller():
    return _controller

func get_node_map_canvas():
    return _canvas

func get_inspector():
    return _inspector

func _build_interface() -> void:
    var background := ColorRect.new()
    background.color = Color("11141a")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 0)
    add_child(root)

    var toolbar_panel := PanelContainer.new()
    toolbar_panel.custom_minimum_size.y = 52
    var toolbar_style := StyleBoxFlat.new()
    toolbar_style.bg_color = Color("20242d")
    toolbar_style.border_color = Color("343b48")
    toolbar_style.border_width_bottom = 1
    toolbar_style.content_margin_left = 14
    toolbar_style.content_margin_right = 14
    toolbar_style.content_margin_top = 8
    toolbar_style.content_margin_bottom = 8
    toolbar_panel.add_theme_stylebox_override("panel", toolbar_style)
    root.add_child(toolbar_panel)

    var toolbar := HBoxContainer.new()
    toolbar.add_theme_constant_override("separation", 8)
    toolbar_panel.add_child(toolbar)
    var brand := Label.new()
    brand.text = "GEL  NODE MAP"
    brand.add_theme_font_size_override("font_size", 18)
    brand.modulate = Color("edf2fa")
    toolbar.add_child(brand)
    _add_toolbar_separator(toolbar)
    _add_toolbar_button(toolbar, "+  Add Scene", _show_add_dialog)
    _add_toolbar_button(toolbar, "Delete", func(): _canvas.request_delete_selection())
    _add_toolbar_button(toolbar, "Frame Selection", func(): _canvas.center_on_selection())
    _add_toolbar_button(toolbar, "Reset View", func(): _canvas.reset_view())
    _add_toolbar_button(toolbar, "Load Demo", func(): _controller.set_scene_map(DEMO_MAP_FACTORY_SCRIPT.create()))
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toolbar.add_child(spacer)
    _status = Label.new()
    _status.text = "In-memory project"
    _status.modulate = Color("8290a2")
    toolbar.add_child(_status)

    var split := HSplitContainer.new()
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.split_offset = -340
    root.add_child(split)
    _canvas = NODE_MAP_CANVAS_SCRIPT.new()
    _canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.add_child(_canvas)
    _inspector = NODE_INSPECTOR_SCRIPT.new()
    _inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.add_child(_inspector)

    _connect_canvas()
    _connect_inspector()
    _create_add_dialog()
    _create_delete_dialog()

func _connect_controller() -> void:
    _controller.scene_map_changed.connect(_on_scene_map_changed)
    _controller.selection_changed.connect(_on_selection_changed)
    _controller.operation_failed.connect(_on_operation_failed)

func _connect_canvas() -> void:
    _canvas.endpoint_connection_requested.connect(func(endpoint: Dictionary, target: String):
        _controller.connect_endpoint(endpoint, target)
    )
    _canvas.route_disconnection_requested.connect(func(edge_id: String):
        _controller.remove_route(edge_id)
    )
    _canvas.node_positions_committed.connect(func(positions: Dictionary):
        _controller.commit_node_positions(positions)
    )
    _canvas.object_selected.connect(func(kind: String, stable_id: Variant):
        _controller.select_object(kind, stable_id)
    )
    _canvas.add_scene_requested.connect(_show_add_dialog_at)
    _canvas.root_wrapper_requested.connect(func(node_id: String, kind: String):
        _controller.add_root_wrapper(node_id, kind)
    )
    _canvas.scenes_deletion_requested.connect(_confirm_scene_deletion)

func _connect_inspector() -> void:
    _inspector.scene_apply_requested.connect(_apply_scene_draft)
    _inspector.wrapper_apply_requested.connect(_apply_wrapper_draft)
    _inspector.branch_apply_requested.connect(_apply_branch_draft)
    _inspector.child_wrapper_requested.connect(func(node_id: String, branch_id: String, kind: String):
        _controller.add_child_wrapper(node_id, branch_id, kind)
    )
    _inspector.switch_case_add_requested.connect(func(node_id: String, wrapper_id: String):
        _controller.add_switch_case(node_id, wrapper_id)
    )
    _inspector.branch_subtree_removal_requested.connect(func(node_id: String, branch_id: String):
        _controller.remove_branch_subtree(node_id, branch_id)
    )
    _inspector.branch_removal_requested.connect(func(node_id: String, branch_id: String):
        _controller.remove_condition_branch(node_id, branch_id)
    )
    _inspector.edge_removal_requested.connect(func(edge_id: String):
        _controller.remove_route(edge_id)
    )

func _on_scene_map_changed() -> void:
    var snapshot = _controller.get_scene_map()
    _canvas.set_scene_map(snapshot)
    _inspector.refresh(snapshot)
    _status.text = "%d scenes  ·  %d routes  ·  in memory" % [snapshot.get_node_count(), snapshot.get_route_count()]
    _status.modulate = Color("8290a2")

func _on_selection_changed(kind: String, stable_id: Variant) -> void:
    _inspector.set_selection(kind, stable_id, _controller.get_scene_map())

func _on_operation_failed(message: String) -> void:
    _status.text = message
    _status.modulate = Color("ff8d8d")
    _inspector.show_error(message)

func _show_add_dialog() -> void:
    _show_add_dialog_at((_canvas.scroll_offset + _canvas.size * 0.5) / _canvas.zoom)

func _show_add_dialog_at(graph_position: Vector2) -> void:
    _pending_scene_position = graph_position
    _scene_id_field.text = ""
    _scene_title_field.text = ""
    _add_dialog.popup_centered(Vector2i(430, 245))
    _scene_id_field.grab_focus()

func _on_add_scene_confirmed() -> void:
    var created = _controller.create_scene(
        _scene_id_field.text.strip_edges(),
        _scene_title_field.text.strip_edges(),
        _pending_scene_position,
    )
    if created == null:
        call_deferred("_reopen_add_dialog")
    else:
        _controller.select_object("scene", created.node_id)

func _reopen_add_dialog() -> void:
    _add_dialog.popup_centered(Vector2i(430, 245))
    _scene_id_field.grab_focus()

func _confirm_scene_deletion(node_ids: Array) -> void:
    _pending_delete_ids = node_ids.duplicate()
    _delete_dialog.dialog_text = "Delete %d Scene node(s) and all connected routes?" % node_ids.size()
    _delete_dialog.popup_centered(Vector2i(430, 160))

func _on_delete_confirmed() -> void:
    for node_id in _pending_delete_ids:
        if not _controller.remove_scene(str(node_id)):
            break
    _pending_delete_ids.clear()

func _apply_scene_draft(draft: Dictionary) -> void:
    var node_id := str(draft.get("nodeId", ""))
    var node = _controller.get_scene(node_id)
    if node == null:
        _on_operation_failed("Scene does not exist")
        return
    if not node.rename_scene(str(draft.get("sceneId", ""))):
        _on_operation_failed(node.last_error)
        return
    node.set_title(str(draft.get("title", "")))
    if not node.set_main_script(str(draft.get("mainScript", ""))):
        _on_operation_failed(node.last_error)
        return
    var parsed_exits := _parse_exits(str(draft.get("exits", "")))
    if not parsed_exits["ok"]:
        _on_operation_failed(str(parsed_exits["message"]))
        return
    for port in node.get_exits():
        node.remove_exit(port.port_id)
    for port in parsed_exits["ports"]:
        if not node.add_exit(port):
            _on_operation_failed(node.last_error)
            return
    if not _controller.update_scene(node):
        return
    _controller.set_entry_scene(node_id, bool(draft.get("entry", false)))

func _apply_wrapper_draft(draft: Dictionary) -> void:
    var node_id := str(draft.get("nodeId", ""))
    var wrapper_id := str(draft.get("wrapperId", ""))
    var node = _controller.get_scene(node_id)
    var tree = node.get_condition_tree() if node != null else null
    var wrapper = tree.get_wrapper(wrapper_id) if tree != null else null
    if wrapper == null:
        _on_operation_failed("Wrapper does not exist")
        return
    var updated: ConditionWrapper
    if wrapper is IfWrapper:
        var value := wrapper as IfWrapper
        updated = IfWrapper.new(wrapper_id, str(draft.get("variableKey", "")), value.true_branch_id, value.false_branch_id)
    elif wrapper is SwitchCaseWrapper:
        var value := wrapper as SwitchCaseWrapper
        var parsed := _parse_switch_cases(str(draft.get("cases", "")), tree, value)
        if not parsed["ok"]:
            _on_operation_failed(str(parsed["message"]))
            return
        for branch_draft in parsed["branches"]:
            if not tree.update_branch_value(
                    str(branch_draft["branchId"]), str(branch_draft["label"]),
                    bool(branch_draft["hasMatchValue"]), branch_draft.get("matchValue")):
                _on_operation_failed(tree.last_error)
                return
        updated = SwitchCaseWrapper.new(
            wrapper_id, str(draft.get("variableKey", "")),
            parsed["caseIds"], value.default_branch_id,
        )
    elif wrapper is NumericCompareWrapper:
        var value := wrapper as NumericCompareWrapper
        var left := _parse_operand(str(draft.get("leftOperand", "")))
        var right := _parse_operand(str(draft.get("rightOperand", "")))
        if not left["ok"] or not right["ok"]:
            _on_operation_failed("Numeric operands must be var:key or finite numbers")
            return
        updated = NumericCompareWrapper.new(
            wrapper_id, left["operand"], right["operand"],
            value.less_branch_id, value.equal_branch_id, value.greater_branch_id,
        )
    if updated == null or not tree.update_wrapper(updated):
        _on_operation_failed(tree.last_error if tree != null else "Invalid wrapper draft")
        return
    if not node.set_condition_tree(tree):
        _on_operation_failed(node.last_error)
        return
    _controller.update_scene(node)

func _apply_branch_draft(draft: Dictionary) -> void:
    var match_value: Variant = null
    if bool(draft.get("hasMatchValue", false)):
        var parsed := _parse_json_scalar(str(draft.get("matchValue", "")))
        if not parsed["ok"]:
            _on_operation_failed("Case value must be valid scalar JSON")
            return
        match_value = parsed["value"]
    _controller.update_branch(
        str(draft.get("nodeId", "")), str(draft.get("branchId", "")),
        str(draft.get("label", "")), bool(draft.get("hasMatchValue", false)), match_value,
    )

func _parse_exits(source: String) -> Dictionary:
    var ports: Array = []
    for raw_line in source.split("\n"):
        var line := raw_line.strip_edges()
        if line.is_empty():
            continue
        var separator := line.find("=")
        if separator <= 0:
            return {"ok": false, "message": "Each exit must use port_id = name"}
        var port := ExitPort.new(
            line.substr(0, separator).strip_edges(),
            line.substr(separator + 1).strip_edges(),
        )
        var errors := port.validate_self()
        if not errors.is_empty():
            return {"ok": false, "message": errors[0]}
        ports.append(port)
    return {"ok": true, "ports": ports}

func _parse_switch_cases(source: String, tree: ConditionTree, wrapper: SwitchCaseWrapper) -> Dictionary:
    var case_ids: Array = []
    var branches: Array = []
    var saw_default := false
    for raw_line in source.split("\n"):
        var line := raw_line.strip_edges()
        if line.is_empty():
            continue
        var equal := line.find("=")
        var pipe := line.find("|", equal + 1)
        if equal <= 0 or pipe < 0:
            return {"ok": false, "message": "Each case must use branch_id = JSON/default | label"}
        var branch_id := line.substr(0, equal).strip_edges()
        if tree.get_branch(branch_id) == null:
            return {"ok": false, "message": "Unknown branch_id '%s'" % branch_id}
        var value_text := line.substr(equal + 1, pipe - equal - 1).strip_edges()
        var label := line.substr(pipe + 1).strip_edges()
        if branch_id == wrapper.default_branch_id:
            if value_text != "default":
                return {"ok": false, "message": "Default branch value must be 'default'"}
            branches.append({"branchId": branch_id, "label": label, "hasMatchValue": false})
            saw_default = true
        else:
            if not wrapper.case_branch_ids.has(branch_id):
                return {"ok": false, "message": "Cannot add case IDs in this inspector version"}
            var parsed := _parse_json_scalar(value_text)
            if not parsed["ok"]:
                return {"ok": false, "message": "Case '%s' has invalid scalar JSON" % branch_id}
            case_ids.append(branch_id)
            branches.append({
                "branchId": branch_id, "label": label,
                "hasMatchValue": true, "matchValue": parsed["value"],
            })
    if not saw_default:
        return {"ok": false, "message": "Switch default branch is required"}
    if case_ids.size() != wrapper.case_branch_ids.size():
        return {"ok": false, "message": "Delete cases with the Branch inspector"}
    return {"ok": true, "caseIds": case_ids, "branches": branches}

func _parse_json_scalar(source: String) -> Dictionary:
    var json := JSON.new()
    if json.parse(source) != OK:
        return {"ok": false}
    var value = json.data
    if value != null and not [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING].has(typeof(value)):
        return {"ok": false}
    if typeof(value) == TYPE_FLOAT and (is_nan(value) or is_inf(value)):
        return {"ok": false}
    return {"ok": true, "value": value}

func _parse_operand(source: String) -> Dictionary:
    var value := source.strip_edges()
    if value.begins_with("var:"):
        var operand := NumericOperand.variable(value.trim_prefix("var:").strip_edges())
        return {"ok": operand.validate_self().is_empty(), "operand": operand}
    if not value.is_valid_float():
        return {"ok": false}
    var number := value.to_float()
    if is_nan(number) or is_inf(number):
        return {"ok": false}
    return {"ok": true, "operand": NumericOperand.constant(number)}

func _create_add_dialog() -> void:
    _add_dialog = ConfirmationDialog.new()
    _add_dialog.title = "Add Scene"
    _add_dialog.ok_button_text = "Create"
    var form := VBoxContainer.new()
    form.add_theme_constant_override("separation", 8)
    var id_label := Label.new()
    id_label.text = "Scene ID  (^[a-z][a-z0-9_.-]*$)"
    form.add_child(id_label)
    _scene_id_field = LineEdit.new()
    _scene_id_field.placeholder_text = "prologue"
    form.add_child(_scene_id_field)
    var title_label := Label.new()
    title_label.text = "Title  (optional)"
    form.add_child(title_label)
    _scene_title_field = LineEdit.new()
    _scene_title_field.placeholder_text = "Prologue"
    form.add_child(_scene_title_field)
    form.position = Vector2(18, 18)
    form.size = Vector2(394, 158)
    _add_dialog.add_child(form)
    _add_dialog.confirmed.connect(_on_add_scene_confirmed)
    add_child(_add_dialog)

func _create_delete_dialog() -> void:
    _delete_dialog = ConfirmationDialog.new()
    _delete_dialog.title = "Delete Scene"
    _delete_dialog.ok_button_text = "Delete"
    _delete_dialog.confirmed.connect(_on_delete_confirmed)
    add_child(_delete_dialog)

func _add_toolbar_button(parent: HBoxContainer, text: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = text
    button.pressed.connect(callback)
    parent.add_child(button)

func _add_toolbar_separator(parent: HBoxContainer) -> void:
    var separator := VSeparator.new()
    separator.custom_minimum_size.x = 8
    parent.add_child(separator)
