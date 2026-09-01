extends RefCounted
class_name EditorLayoutManager

## 编辑器布局状态的 UI 无关管理器。
##
## EditorLayoutManager 只负责管理描述对象、逻辑槽位以及布局状态转换，不创建、
## 不移动任何 Godot Control。未来的渲染器应订阅这里发出的信号，再将逻辑状态
## 投影到 SplitContainer、TabContainer 和具体工作区控件上。这样布局规则可以在
## 没有窗口的情况下独立测试，UI 也不会反向成为布局模型的依赖。

signal layout_changed(state: Dictionary)
signal dock_registered(dock_id: String)
signal dock_unregistered(dock_id: String)
signal dock_opened(dock_id: String)
signal dock_closed(dock_id: String)
signal dock_moved(dock_id: String, slot_id: String)
signal dock_tab_changed(slot_id: String, dock_id: String)
signal workspace_registered(workspace_id: String)
signal workspace_unregistered(workspace_id: String)
signal workspace_changed(workspace_id: String)
signal split_offset_changed(split_id: String, offsets: Array)
signal bottom_panel_changed(expanded: bool, dock_id: String)
signal docks_visibility_changed(visible: bool)

const LAYOUT_DEFINITION_SCRIPT := preload("res://workspace/layout/layout_definition.gd")
const LAYOUT_STATE_SCRIPT := preload("res://workspace/layout/layout_state.gd")
const LAYOUT_SERIALIZER_SCRIPT := preload("res://workspace/layout/layout_serializer.gd")
const DOCK_SLOT_STATE_SCRIPT := preload("res://workspace/layout/dock_slot_state.gd")

var definition
var last_error: String = ""

var _state
var _docks: Dictionary = {}
var _workspaces: Dictionary = {}
var _batch_depth: int = 0
var _pending_layout_changed: bool = false

func _init(p_definition = null) -> void:
    if p_definition == null:
        definition = LAYOUT_DEFINITION_SCRIPT.standard()
    else:
        definition = p_definition.duplicate_definition()
    var definition_errors: Array = definition.validate_self()
    if not definition_errors.is_empty():
        definition = LAYOUT_DEFINITION_SCRIPT.standard()
    _state = LAYOUT_STATE_SCRIPT.from_definition(definition)

## 返回布局拓扑的副本，防止调用方通过返回值直接改写管理器内部的拓扑定义。
func get_definition():
    return definition.duplicate_definition()

## 返回当前可变布局状态的深副本，调用方可以安全地修改临时副本而不影响管理器。
func get_state():
    return _state.duplicate_state()

func get_state_dict() -> Dictionary:
    return _state.to_dict()

func get_default_state():
    return _build_default_state()

func get_default_state_dict() -> Dictionary:
    return _build_default_state().to_dict()

func get_dock_ids() -> Array:
    return _sorted_dock_ids()

func get_workspace_ids() -> Array:
    return _sorted_workspace_ids()

func get_dock_descriptor(dock_id: String):
    return _docks[dock_id].duplicate_descriptor() if _docks.has(dock_id) else null

func get_workspace_descriptor(workspace_id: String):
    return _workspaces[workspace_id].duplicate_descriptor() if _workspaces.has(workspace_id) else null

func get_slot_tabs(slot_id: String) -> Array:
    return _state.get_slot_tabs(slot_id) if definition.has_slot(slot_id) else []

func get_slot_active_tab(slot_id: String) -> String:
    return _state.get_slot_active_tab(slot_id) if definition.has_slot(slot_id) else ""

func get_dock_location(dock_id: String) -> Dictionary:
    if not _docks.has(dock_id):
        return {}
    var slot_id = _find_open_slot(dock_id)
    if not slot_id.is_empty():
        return {"open": true, "slot": slot_id, "index": _state.get_slot_tabs(slot_id).find(dock_id)}
    var restore = _state.dock_restore.get(dock_id, {})
    return {
        "open": false,
        "slot": str(restore.get("slot", _docks[dock_id].default_slot)) if restore is Dictionary else _docks[dock_id].default_slot,
        "index": int(restore.get("index", _docks[dock_id].default_order)) if restore is Dictionary else _docks[dock_id].default_order,
    }

func is_dock_open(dock_id: String) -> bool:
    return not _find_open_slot(dock_id).is_empty()

func is_docks_visible() -> bool:
    return _state.docks_visible

func get_active_workspace_id() -> String:
    return _state.active_workspace

func get_bottom_panel_active_tab() -> String:
    return _state.bottom_active_tab

func is_bottom_panel_expanded() -> bool:
    return _state.bottom_expanded

func get_bottom_panel_tab_offset(dock_id: String) -> int:
    return int(_state.bottom_tab_offsets.get(dock_id, 0))

func register_dock(descriptor) -> bool:
    if descriptor == null:
        return _fail("dock descriptor must not be null")
    if not descriptor.has_method("validate_self") or not descriptor.has_method("duplicate_descriptor"):
        return _fail("dock descriptor has an invalid interface")
    var errors: Array = descriptor.validate_self(definition.slot_ids)
    if not errors.is_empty():
        return _fail(str(errors[0]))
    var dock_id = str(descriptor.dock_id)
    if _docks.has(dock_id):
        return _fail("dock '%s' is already registered" % dock_id)

    _docks[dock_id] = descriptor.duplicate_descriptor()
    _state = _reconcile_state(_state)
    _clear_error()
    dock_registered.emit(dock_id)
    _mark_layout_changed()
    return true

func unregister_dock(dock_id: String) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    _docks.erase(dock_id)
    _state = _reconcile_state(_state)
    _clear_error()
    dock_unregistered.emit(dock_id)
    _mark_layout_changed()
    return true

func register_workspace(descriptor) -> bool:
    if descriptor == null:
        return _fail("workspace descriptor must not be null")
    if not descriptor.has_method("validate_self") or not descriptor.has_method("duplicate_descriptor"):
        return _fail("workspace descriptor has an invalid interface")
    var errors: Array = descriptor.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    var workspace_id = str(descriptor.workspace_id)
    if _workspaces.has(workspace_id):
        return _fail("workspace '%s' is already registered" % workspace_id)

    _workspaces[workspace_id] = descriptor.duplicate_descriptor()
    var previous = _state.active_workspace
    if previous.is_empty() or not _workspaces.has(previous):
        _state.active_workspace = _default_workspace_id()
    _clear_error()
    workspace_registered.emit(workspace_id)
    if previous != _state.active_workspace:
        workspace_changed.emit(_state.active_workspace)
    _mark_layout_changed()
    return true

func unregister_workspace(workspace_id: String) -> bool:
    if not _workspaces.has(workspace_id):
        return _fail("workspace '%s' is not registered" % workspace_id)
    var was_active = _state.active_workspace == workspace_id
    _workspaces.erase(workspace_id)
    if was_active:
        _state.active_workspace = _default_workspace_id()
    _clear_error()
    workspace_unregistered.emit(workspace_id)
    if was_active:
        workspace_changed.emit(_state.active_workspace)
    _mark_layout_changed()
    return true

func activate_workspace(workspace_id: String) -> bool:
    if not _workspaces.has(workspace_id):
        return _fail("workspace '%s' is not registered" % workspace_id)
    if _state.active_workspace == workspace_id:
        return true
    _state.active_workspace = workspace_id
    _clear_error()
    workspace_changed.emit(workspace_id)
    _mark_layout_changed()
    return true

## 在 Dock 上次记住的槽位和 Tab 索引处重新打开一个已关闭的 Dock。
## p_focus 为 true 时，重新打开的 Dock 会成为所在槽位的活动 Tab；如果它位于
## bottom 槽位，还会同时展开底部面板。
func open_dock(dock_id: String, p_focus: bool = true) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    var current_slot = _find_open_slot(dock_id)
    if not current_slot.is_empty():
        if p_focus:
            return focus_dock(dock_id)
        return true

    var descriptor = _docks[dock_id]
    var location = _restore_location(dock_id, descriptor)
    var slot_id = str(location["slot"])
    var index = int(location["index"])
    _remove_closed_id(dock_id)
    _insert_into_slot(_state, dock_id, slot_id, index, p_focus)
    _remember_location(dock_id, slot_id, _state.get_slot_tabs(slot_id).find(dock_id))
    _sync_bottom_state(p_focus and slot_id == LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    _clear_error()
    dock_opened.emit(dock_id)
    if p_focus:
        dock_tab_changed.emit(slot_id, dock_id)
    _mark_layout_changed()
    return true

func close_dock(dock_id: String) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    var descriptor = _docks[dock_id]
    if not descriptor.closable:
        return _fail("dock '%s' is not closable" % dock_id)
    var slot_id = _find_open_slot(dock_id)
    if slot_id.is_empty():
        return true
    var slot_state = DOCK_SLOT_STATE_SCRIPT.from_dict(slot_id, _state.slot_tabs.get(slot_id, {}))
    var index = slot_state.tabs.find(dock_id)
    slot_state.remove_tab(dock_id)
    _state.slot_tabs[slot_id] = slot_state.to_dict()
    _remember_location(dock_id, slot_id, index)
    if not _state.closed_docks.has(dock_id):
        _state.closed_docks.append(dock_id)
    _sync_bottom_state(false)
    _clear_error()
    dock_closed.emit(dock_id)
    _mark_layout_changed()
    return true

func focus_dock(dock_id: String) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    if _find_open_slot(dock_id).is_empty():
        return open_dock(dock_id, true)
    var slot_id = _find_open_slot(dock_id)
    var changed = _state.get_slot_active_tab(slot_id) != dock_id
    _state.set_slot_tabs(slot_id, _state.get_slot_tabs(slot_id), dock_id)
    if slot_id == LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM:
        changed = changed or _state.bottom_active_tab != dock_id or not _state.bottom_expanded
        _state.bottom_active_tab = dock_id
        _state.bottom_expanded = true
    _clear_error()
    dock_tab_changed.emit(slot_id, dock_id)
    if changed:
        _mark_layout_changed()
    return true

func move_dock(dock_id: String, target_slot_id: String, target_index: int = -1, p_focus: bool = true) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    if not definition.has_slot(target_slot_id):
        return _fail("slot '%s' does not exist" % target_slot_id)
    var descriptor = _docks[dock_id]
    if not descriptor.allows_slot(target_slot_id):
        return _fail("dock '%s' cannot use slot '%s'" % [dock_id, target_slot_id])
    var source_slot_id = _find_open_slot(dock_id)
    if source_slot_id.is_empty():
        return _fail("dock '%s' is closed" % dock_id)

    var source_state = DOCK_SLOT_STATE_SCRIPT.from_dict(source_slot_id, _state.slot_tabs.get(source_slot_id, {}))
    var source_index = source_state.remove_tab(dock_id)
    _state.slot_tabs[source_slot_id] = source_state.to_dict()
    var adjusted_index := target_index
    if source_slot_id == target_slot_id and adjusted_index > source_index:
        adjusted_index -= 1
    var actual_index = _insert_into_slot(_state, dock_id, target_slot_id, adjusted_index, p_focus)
    _remember_location(dock_id, target_slot_id, actual_index)
    _sync_bottom_state(p_focus and target_slot_id == LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    _clear_error()
    dock_moved.emit(dock_id, target_slot_id)
    if p_focus:
        dock_tab_changed.emit(target_slot_id, dock_id)
    _mark_layout_changed()
    return source_index >= 0

func reorder_dock(dock_id: String, target_index: int) -> bool:
    var slot_id = _find_open_slot(dock_id)
    if slot_id.is_empty():
        return _fail("dock '%s' is closed or not registered" % dock_id)
    return move_dock(dock_id, slot_id, target_index, false)

func set_slot_active_tab(slot_id: String, dock_id: String) -> bool:
    if not definition.has_slot(slot_id):
        return _fail("slot '%s' does not exist" % slot_id)
    var tabs = _state.get_slot_tabs(slot_id)
    if not dock_id.is_empty() and not tabs.has(dock_id):
        return _fail("dock '%s' is not in slot '%s'" % [dock_id, slot_id])
    if _state.get_slot_active_tab(slot_id) == dock_id:
        return true
    _state.set_slot_tabs(slot_id, tabs, dock_id)
    if slot_id == LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM:
        _state.bottom_active_tab = dock_id
        if dock_id.is_empty():
            _state.bottom_expanded = false
    _clear_error()
    dock_tab_changed.emit(slot_id, dock_id)
    _mark_layout_changed()
    return true

func set_bottom_panel_tab(dock_id: String, p_expand: bool = true) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    if _find_open_slot(dock_id) != LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM:
        return _fail("dock '%s' is not open in the bottom slot" % dock_id)
    _state.set_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM, _state.get_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM), dock_id)
    _state.bottom_active_tab = dock_id
    _state.bottom_expanded = p_expand
    _clear_error()
    dock_tab_changed.emit(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM, dock_id)
    bottom_panel_changed.emit(_state.bottom_expanded, dock_id)
    _mark_layout_changed()
    return true

func set_bottom_panel_expanded(expanded: bool) -> bool:
    if expanded and _state.bottom_active_tab.is_empty():
        var bottom_tabs = _state.get_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
        if bottom_tabs.is_empty():
            return _fail("bottom panel has no open tabs")
        _state.bottom_active_tab = str(bottom_tabs[0])
        _state.set_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM, bottom_tabs, _state.bottom_active_tab)
    if _state.bottom_expanded == expanded:
        return true
    _state.bottom_expanded = expanded
    _clear_error()
    bottom_panel_changed.emit(expanded, _state.bottom_active_tab)
    _mark_layout_changed()
    return true

func set_bottom_panel_tab_offset(dock_id: String, offset: int) -> bool:
    if not _docks.has(dock_id):
        return _fail("dock '%s' is not registered" % dock_id)
    if _find_open_slot(dock_id) != LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM:
        return _fail("dock '%s' is not open in the bottom slot" % dock_id)
    if _state.bottom_tab_offsets.get(dock_id, 0) == offset:
        return true
    _state.bottom_tab_offsets[dock_id] = offset
    _clear_error()
    _mark_layout_changed()
    return true

func toggle_bottom_panel() -> bool:
    return set_bottom_panel_expanded(not _state.bottom_expanded)

func set_docks_visible(visible: bool) -> bool:
    if _state.docks_visible == visible:
        return true
    _state.docks_visible = visible
    _clear_error()
    docks_visibility_changed.emit(visible)
    _mark_layout_changed()
    return true

func set_split_offsets(split_id: String, offsets: Array) -> bool:
    if not definition.has_split(split_id):
        return _fail("split '%s' does not exist" % split_id)
    var expected = definition.get_split_offset_count(split_id)
    if offsets.size() != expected:
        return _fail("split '%s' requires %d offsets" % [split_id, expected])
    var normalized: Array = []
    for value in offsets:
        if not (value is int or value is float):
            return _fail("split '%s' offsets must contain numbers" % split_id)
        normalized.append(int(value))
    if _state.get_split_offsets(split_id) == normalized:
        return true
    _state.set_split_offsets(split_id, normalized)
    _clear_error()
    split_offset_changed.emit(split_id, normalized.duplicate())
    _mark_layout_changed()
    return true

func set_split_offset(split_id: String, index: int, offset: int) -> bool:
    var offsets = _state.get_split_offsets(split_id)
    if index < 0 or index >= offsets.size():
        return _fail("split '%s' offset index '%d' is invalid" % [split_id, index])
    offsets[index] = offset
    return set_split_offsets(split_id, offsets)

## 在一次完整事务中替换当前布局状态。读取时会忽略当前进程未注册的 Dock 和 Workspace，
## 无法使用的字段会回退到布局定义中的默认值；只有完整候选状态通过校验后才会提交，避免产生半更新布局。
func apply_state(source) -> bool:
    var incoming
    if source is Dictionary:
        var decoded = LAYOUT_SERIALIZER_SCRIPT.new().deserialize(source, definition)
        if not bool(decoded["ok"]):
            return _fail(str(decoded["errors"][0]))
        incoming = decoded["state"]
    elif source != null and source.has_method("duplicate_state"):
        incoming = source.duplicate_state()
    else:
        return _fail("layout state must be a dictionary or EditorLayoutState")

    if int(incoming.schema_version) > int(LAYOUT_STATE_SCRIPT.SCHEMA_VERSION):
        return _fail("layout schema version '%s' is newer than supported version '%s'" % [incoming.schema_version, LAYOUT_STATE_SCRIPT.SCHEMA_VERSION])
    var candidate = _reconcile_state(incoming)
    var errors: Array = candidate.validate_self(definition, _docks.keys(), _workspaces.keys())
    if not errors.is_empty():
        return _fail(str(errors[0]))
    _state = candidate
    _clear_error()
    _mark_layout_changed()
    return true

## 解码并应用一段 JSON 布局数据。
## JSON 格式错误时，默认恢复由当前注册对象组成的默认布局，同时返回 false 并
## 保留 last_error，供上层显示诊断；将 p_reset_on_failure 设为 false 时则保留
## 原有布局，只报告错误。
func load_json(text: String, p_reset_on_failure: bool = true) -> bool:
    var decoded: Dictionary = LAYOUT_SERIALIZER_SCRIPT.new().decode_json(text, definition)
    if bool(decoded["ok"]):
        return apply_state(decoded["state"])
    var message = str(decoded["errors"][0])
    if p_reset_on_failure:
        _replace_with_default(false)
    return _fail(message)

func encode_json() -> String:
    return LAYOUT_SERIALIZER_SCRIPT.new().encode_json(_state)

func reset_layout() -> bool:
    _replace_with_default(true)
    return true

func begin_update() -> void:
    _batch_depth += 1

func end_update() -> bool:
    if _batch_depth <= 0:
        return _fail("layout update transaction is not open")
    _batch_depth -= 1
    if _batch_depth == 0 and _pending_layout_changed:
        _pending_layout_changed = false
        layout_changed.emit(get_state_dict())
    return true

func _replace_with_default(clear_error: bool) -> void:
    _state = _build_default_state()
    if clear_error:
        _clear_error()
    _mark_layout_changed()

func _build_default_state():
    var result = LAYOUT_STATE_SCRIPT.from_definition(definition)
    result.docks_visible = true
    result.active_workspace = _default_workspace_id()
    for dock_id in _sorted_dock_ids():
        var descriptor = _docks[dock_id]
        result.dock_restore[dock_id] = {"slot": descriptor.default_slot, "index": descriptor.default_order}
        if descriptor.default_open:
            _insert_into_slot(result, dock_id, descriptor.default_slot, -1, false, true)
        else:
            result.closed_docks.append(dock_id)
    for slot_id in definition.slot_ids:
        var slot_key := str(slot_id)
        var tabs: Array = result.get_slot_tabs(slot_key)
        var active := str(tabs[0]) if not tabs.is_empty() else ""
        result.set_slot_tabs(slot_key, tabs, active)

    var bottom_tabs = result.get_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    result.bottom_active_tab = str(bottom_tabs[0]) if not bottom_tabs.is_empty() else ""
    result.bottom_expanded = false
    _refresh_open_locations(result)
    return result

## 将持久化状态与当前进程实际注册的描述对象进行对账。
## 这里负责安全丢弃未知的插件 Dock、去除重复 Dock、检查 Dock 是否允许目标槽位，
## 并为新增 Dock、缺失 Split 或缺失 Workspace 字段补上默认值。
func _reconcile_state(source_state):
    var candidate = LAYOUT_STATE_SCRIPT.from_definition(definition)
    candidate.docks_visible = bool(source_state.docks_visible)
    candidate.active_workspace = str(source_state.active_workspace) if _workspaces.has(str(source_state.active_workspace)) else _default_workspace_id()

    for split_id in definition.split_ids:
        var key = str(split_id)
        var incoming = source_state.get_split_offsets(key)
        if incoming.size() == definition.get_split_offset_count(key) and _all_numeric(incoming):
            var values: Array = []
            for value in incoming:
                values.append(int(value))
            candidate.set_split_offsets(key, values)

    var occurrences: Dictionary = {}
    var source_order: Dictionary = {}
    for slot_id in definition.slot_ids:
        var slot_key = str(slot_id)
        source_order[slot_key] = []
        for raw_dock_id in source_state.get_slot_tabs(slot_key):
            var dock_id = str(raw_dock_id)
            if not _docks.has(dock_id) or occurrences.has(dock_id):
                continue
            var descriptor = _docks[dock_id]
            if not descriptor.allows_slot(slot_key):
                continue
            occurrences[dock_id] = {"slot": slot_key, "sourceIndex": source_order[slot_key].size()}
            (source_order[slot_key] as Array).append(dock_id)

    var closed: Dictionary = {}
    var closed_order: Array = []
    for raw_dock_id in source_state.closed_docks:
        var dock_id = str(raw_dock_id)
        if _docks.has(dock_id) and not occurrences.has(dock_id) and not closed.has(dock_id):
            closed[dock_id] = true
            closed_order.append(dock_id)

    var open_lists: Dictionary = {}
    for slot_id in definition.slot_ids:
        open_lists[str(slot_id)] = (source_order[str(slot_id)] as Array).duplicate()

    for dock_id in _sorted_dock_ids():
        var descriptor = _docks[dock_id]
        if occurrences.has(dock_id) or closed.has(dock_id):
            continue
        if descriptor.default_open:
            var target = descriptor.default_slot
            _insert_id_by_default_order(open_lists[target], dock_id)
        else:
            if not closed.has(dock_id):
                closed[dock_id] = true
                closed_order.append(dock_id)

    for slot_id in definition.slot_ids:
        var slot_key = str(slot_id)
        var tabs: Array = open_lists[slot_key]
        var requested_active = source_state.get_slot_active_tab(slot_key)
        var active = requested_active if tabs.has(requested_active) else (str(tabs[0]) if not tabs.is_empty() else "")
        candidate.set_slot_tabs(slot_key, tabs, active)

    for dock_id in _sorted_dock_ids():
        var descriptor = _docks[dock_id]
        if occurrences.has(dock_id):
            var slot_key = str(occurrences[dock_id]["slot"])
            var actual_index = candidate.get_slot_tabs(slot_key).find(dock_id)
            candidate.dock_restore[dock_id] = {"slot": slot_key, "index": actual_index}
        elif closed.has(dock_id):
            var location = _source_restore_location(source_state, dock_id, descriptor)
            candidate.dock_restore[dock_id] = location

    candidate.closed_docks = closed_order.duplicate()

    var bottom_tabs = candidate.get_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    var requested_bottom = str(source_state.bottom_active_tab)
    candidate.bottom_active_tab = requested_bottom if bottom_tabs.has(requested_bottom) else candidate.get_slot_active_tab(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    if not candidate.bottom_active_tab.is_empty():
        candidate.set_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM, bottom_tabs, candidate.bottom_active_tab)
    candidate.bottom_expanded = bool(source_state.bottom_expanded) and not candidate.bottom_active_tab.is_empty()

    _refresh_open_locations(candidate)

    for raw_dock_id in source_state.bottom_tab_offsets:
        var dock_id = str(raw_dock_id)
        if not _docks.has(dock_id):
            continue
        var value = source_state.bottom_tab_offsets[raw_dock_id]
        if value is int or value is float:
            candidate.bottom_tab_offsets[dock_id] = int(value)
    return candidate

func _source_restore_location(source_state, dock_id: String, descriptor) -> Dictionary:
    var raw = source_state.dock_restore.get(dock_id, {})
    if raw is Dictionary:
        var slot_id = str(raw.get("slot", ""))
        if definition.has_slot(slot_id) and descriptor.allows_slot(slot_id):
            return {"slot": slot_id, "index": maxi(0, int(raw.get("index", descriptor.default_order)))}
    return {"slot": descriptor.default_slot, "index": maxi(0, descriptor.default_order)}

func _restore_location(dock_id: String, descriptor) -> Dictionary:
    return _source_restore_location(_state, dock_id, descriptor)

func _insert_into_slot(state, dock_id: String, slot_id: String, requested_index: int, p_focus: bool, by_default_order: bool = false) -> int:
    var tabs = state.get_slot_tabs(slot_id)
    var index = tabs.size() if requested_index < 0 else clampi(requested_index, 0, tabs.size())
    if by_default_order:
        index = tabs.size()
        for i in range(tabs.size()):
            if _dock_order(dock_id) < _dock_order(str(tabs[i])):
                index = i
                break
    tabs.insert(index, dock_id)
    var active = dock_id if p_focus else state.get_slot_active_tab(slot_id)
    if active.is_empty() or p_focus:
        active = dock_id
    state.set_slot_tabs(slot_id, tabs, active)
    return index

func _insert_id_by_default_order(tabs: Array, dock_id: String) -> void:
    var index = tabs.size()
    for i in range(tabs.size()):
        if _dock_order(dock_id) < _dock_order(str(tabs[i])):
            index = i
            break
    tabs.insert(index, dock_id)

func _remove_closed_id(dock_id: String) -> void:
    var index = _state.closed_docks.find(dock_id)
    if index >= 0:
        _state.closed_docks.remove_at(index)

func _remember_location(dock_id: String, slot_id: String, index: int) -> void:
    _state.dock_restore[dock_id] = {"slot": slot_id, "index": maxi(0, index)}

func _sync_bottom_state(expand: bool) -> void:
    var bottom_tabs = _state.get_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    var active = _state.get_slot_active_tab(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM)
    _state.bottom_active_tab = active
    if active.is_empty() and not bottom_tabs.is_empty():
        _state.bottom_active_tab = str(bottom_tabs[0])
        _state.set_slot_tabs(LAYOUT_DEFINITION_SCRIPT.SLOT_BOTTOM, bottom_tabs, _state.bottom_active_tab)
    if _state.bottom_active_tab.is_empty():
        _state.bottom_expanded = false
    elif expand:
        _state.bottom_expanded = true

func _find_open_slot(dock_id: String) -> String:
    for slot_id in definition.slot_ids:
        if _state.get_slot_tabs(str(slot_id)).has(dock_id):
            return str(slot_id)
    return ""

func _state_contains_dock(state, dock_id: String) -> bool:
    for slot_id in definition.slot_ids:
        if state.get_slot_tabs(str(slot_id)).has(dock_id):
            return true
    return state.closed_docks.has(dock_id)

func _default_workspace_id() -> String:
    for workspace_id in _sorted_workspace_ids():
        if bool(_workspaces[workspace_id].default_active):
            return workspace_id
    var ids = _sorted_workspace_ids()
    return str(ids[0]) if not ids.is_empty() else ""

func _sorted_dock_ids() -> Array:
    var ids = _docks.keys()
    ids.sort()
    return ids

func _sorted_workspace_ids() -> Array:
    var ids = _workspaces.keys()
    ids.sort()
    return ids

func _dock_order(dock_id: String) -> int:
    return int(_docks[dock_id].default_order) if _docks.has(dock_id) else 2147483647

func _all_numeric(values: Array) -> bool:
    for value in values:
        if not (value is int or value is float):
            return false
    return true

func _refresh_open_locations(state) -> void:
    for slot_id in definition.slot_ids:
        var slot_key := str(slot_id)
        var tabs: Array = state.get_slot_tabs(slot_key)
        for index in range(tabs.size()):
            var dock_id := str(tabs[index])
            if _docks.has(dock_id):
                state.dock_restore[dock_id] = {"slot": slot_key, "index": index}

func _mark_layout_changed() -> void:
    _refresh_open_locations(_state)
    if _batch_depth > 0:
        _pending_layout_changed = true
    else:
        layout_changed.emit(get_state_dict())

func _fail(message: String) -> bool:
    last_error = message
    return false

func _clear_error() -> void:
    last_error = ""
