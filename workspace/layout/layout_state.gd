extends RefCounted
class_name EditorLayoutState

## 用户当前编辑器布局的可变、UI 无关快照。
##
## 这里保存的所有引用都使用注册表中的稳定 ID。ControlPath、数组索引和显示标题
## 都只是实现细节或可变文本，不能被当作持久化身份；这样面板改名、控件重建或
## Tab 顺序调整后，布局文件仍然可以正确恢复。

const SCHEMA_VERSION := 1
const DEFINITION_SCRIPT := preload("res://workspace/layout/layout_definition.gd")
const SLOT_STATE_SCRIPT := preload("res://workspace/layout/dock_slot_state.gd")

var schema_version: int = SCHEMA_VERSION
var active_workspace: String = ""
var split_offsets: Dictionary = {}
var slot_tabs: Dictionary = {}
var closed_docks: Array = []
var dock_restore: Dictionary = {}
## 左右侧 Dock 区域是否可见。Bottom Panel 是中央区域的独立布局，因此使用自己
## 的展开状态，不与左右 Dock 的总可见性混用。
var docks_visible: bool = true
var bottom_active_tab: String = ""
var bottom_expanded: bool = false
var bottom_tab_offsets: Dictionary = {}

static func from_definition(definition):
    var result = load("res://workspace/layout/layout_state.gd").new()
    if definition == null:
        return result
    for split_id in definition.split_ids:
        var key := str(split_id)
        var metadata = definition.split_metadata.get(key, {})
        var defaults = metadata.get("default_offsets", []) if metadata is Dictionary else []
        result.split_offsets[key] = defaults.duplicate() if defaults is Array else []
        if (result.split_offsets[key] as Array).is_empty():
            var offset_count: int = definition.get_split_offset_count(key)
            var zeroes: Array = []
            for _i in range(offset_count):
                zeroes.append(0)
            result.split_offsets[key] = zeroes
    for slot_id in definition.slot_ids:
        var slot = SLOT_STATE_SCRIPT.new(str(slot_id))
        result.slot_tabs[str(slot_id)] = slot.to_dict()
    return result

func duplicate_state():
    var result = get_script().new()
    result.schema_version = schema_version
    result.active_workspace = active_workspace
    result.split_offsets = split_offsets.duplicate(true)
    result.slot_tabs = slot_tabs.duplicate(true)
    result.closed_docks = closed_docks.duplicate()
    result.dock_restore = dock_restore.duplicate(true)
    result.docks_visible = docks_visible
    result.bottom_active_tab = bottom_active_tab
    result.bottom_expanded = bottom_expanded
    result.bottom_tab_offsets = bottom_tab_offsets.duplicate(true)
    return result

func get_slot_tabs(slot_id: String) -> Array:
    var raw_slot = slot_tabs.get(slot_id, {})
    if raw_slot is Object and raw_slot.has_method("to_dict"):
        var object_state = raw_slot.to_dict()
        var object_tabs = object_state.get("tabs", []) if object_state is Dictionary else []
        return object_tabs.duplicate() if object_tabs is Array else []
    if not raw_slot is Dictionary:
        return []
    var tabs = raw_slot.get("tabs", [])
    return tabs.duplicate() if tabs is Array else []

func get_slot_active_tab(slot_id: String) -> String:
    var raw_slot = slot_tabs.get(slot_id, {})
    if raw_slot is Object and raw_slot.has_method("to_dict"):
        var object_state = raw_slot.to_dict()
        return str(object_state.get("active", "")) if object_state is Dictionary else ""
    return str(raw_slot.get("active", "")) if raw_slot is Dictionary else ""

func set_slot_tabs(slot_id: String, tabs: Array, active: String = "") -> void:
    var slot = SLOT_STATE_SCRIPT.new(slot_id)
    slot.set_tabs(tabs, active)
    slot_tabs[slot_id] = slot.to_dict()

func get_split_offsets(split_id: String) -> Array:
    var offsets = split_offsets.get(split_id, [])
    if offsets is Array:
        return offsets.duplicate()
    # 兼容早期开发快照中把单个 Split 偏移写成数字的临时格式；正式格式使用数组，
    # 这样一个包含多个子节点的 Split 可以保存多个分隔线位置。
    return [int(offsets)] if offsets is int or offsets is float else []

func set_split_offsets(split_id: String, offsets: Array) -> void:
    split_offsets[split_id] = offsets.duplicate()

func to_dict() -> Dictionary:
    var slots: Dictionary = {}
    for slot_id in slot_tabs:
        var raw_slot = slot_tabs[slot_id]
        if raw_slot is Object and raw_slot.has_method("to_dict"):
            slots[str(slot_id)] = raw_slot.to_dict()
        elif raw_slot is Dictionary:
            slots[str(slot_id)] = raw_slot.duplicate(true)
    return {
        "schemaVersion": schema_version,
        "activeWorkspace": active_workspace,
        "splits": split_offsets.duplicate(true),
        "slots": slots,
        "closedDocks": closed_docks.duplicate(),
        "dockRestore": dock_restore.duplicate(true),
        "docksVisible": docks_visible,
        "bottom": {
            "active": bottom_active_tab,
            "expanded": bottom_expanded,
            "offsets": bottom_tab_offsets.duplicate(true),
        },
    }

static func from_dict(source: Dictionary, definition):
    var state_script = load("res://workspace/layout/layout_state.gd")
    var result = state_script.from_definition(definition)
    result.schema_version = int(source.get("schemaVersion", SCHEMA_VERSION))
    result.active_workspace = str(source.get("activeWorkspace", ""))
    result.docks_visible = bool(source.get("docksVisible", true))

    var source_splits = source.get("splits", {})
    if source_splits is Dictionary and definition != null:
        for split_id in definition.split_ids:
            var key := str(split_id)
            if not source_splits.has(key):
                continue
            var offsets = source_splits[key]
            if offsets is Array:
                result.split_offsets[key] = offsets.duplicate()
            elif offsets is int or offsets is float:
                result.split_offsets[key] = [int(offsets)]

    var source_slots = source.get("slots", {})
    if source_slots is Dictionary and definition != null:
        for slot_id in definition.slot_ids:
            var key := str(slot_id)
            if not source_slots.has(key):
                continue
            var slot = SLOT_STATE_SCRIPT.new(key)
            var raw_slot = source_slots[key]
            if raw_slot is Dictionary:
                var source_tabs = raw_slot.get("tabs", [])
                if source_tabs is Array:
                    slot.set_tabs(source_tabs, str(raw_slot.get("active", "")))
            result.slot_tabs[key] = slot.to_dict()

    var closed = source.get("closedDocks", [])
    if closed is Array:
        result.closed_docks = closed.duplicate()

    var restore = source.get("dockRestore", {})
    if restore is Dictionary:
        result.dock_restore = restore.duplicate(true)

    var bottom = source.get("bottom", {})
    if bottom is Dictionary:
        result.bottom_active_tab = str(bottom.get("active", ""))
        result.bottom_expanded = bool(bottom.get("expanded", false))
        var offsets = bottom.get("offsets", {})
        if offsets is Dictionary:
            result.bottom_tab_offsets = offsets.duplicate(true)
    return result

func validate_self(definition, dock_ids: Array = [], workspace_ids: Array = []) -> Array:
    var errors: Array = []
    if schema_version <= 0:
        errors.append("schemaVersion must be positive")
    if definition == null:
        errors.append("layout definition must not be null")
        return errors

    for split_id in definition.split_ids:
        var offsets: Array = get_split_offsets(str(split_id))
        var expected: int = definition.get_split_offset_count(str(split_id))
        if offsets.size() != expected:
            errors.append("split '%s' must contain %d offsets" % [split_id, expected])
        for value in offsets:
            if not (value is int or value is float):
                errors.append("split '%s' offsets must contain numbers" % split_id)

    if not active_workspace.is_empty() and not workspace_ids.is_empty() and not workspace_ids.has(active_workspace):
        errors.append("active workspace '%s' is not registered" % active_workspace)

    var seen_docks: Dictionary = {}
    for slot_id in slot_tabs:
        var slot_key := str(slot_id)
        if not definition.has_slot(slot_key):
            errors.append("state references unknown slot '%s'" % slot_key)
            continue
        var tabs := get_slot_tabs(slot_key)
        for raw_dock_id in tabs:
            var dock_id := str(raw_dock_id)
            if dock_id.is_empty():
                errors.append("slot '%s' contains an empty dock ID" % slot_key)
                continue
            if not dock_ids.is_empty() and not dock_ids.has(dock_id):
                errors.append("slot '%s' references unknown dock '%s'" % [slot_key, dock_id])
            if seen_docks.has(dock_id):
                errors.append("dock '%s' appears in multiple slots" % dock_id)
            seen_docks[dock_id] = true
        var active := get_slot_active_tab(slot_key)
        if not active.is_empty() and not tabs.has(active):
            errors.append("slot '%s' active dock '%s' is not in its tabs" % [slot_key, active])

    var seen_closed: Dictionary = {}
    for raw_dock_id in closed_docks:
        var dock_id := str(raw_dock_id)
        if dock_id.is_empty():
            errors.append("closedDocks contains an empty dock ID")
            continue
        if not dock_ids.is_empty() and not dock_ids.has(dock_id):
            errors.append("closedDocks references unknown dock '%s'" % dock_id)
        if seen_closed.has(dock_id):
            errors.append("dock '%s' appears more than once in closedDocks" % dock_id)
        if seen_docks.has(dock_id):
            errors.append("dock '%s' is both open and closed" % dock_id)
        seen_closed[dock_id] = true

    for raw_dock_id in dock_restore:
        var dock_id := str(raw_dock_id)
        if not dock_ids.is_empty() and not dock_ids.has(dock_id):
            errors.append("dockRestore references unknown dock '%s'" % dock_id)
        var location = dock_restore[raw_dock_id]
        if not location is Dictionary:
            errors.append("dockRestore entry '%s' must be a dictionary" % dock_id)
            continue
        var slot_id := str(location.get("slot", ""))
        if not definition.has_slot(slot_id):
            errors.append("dockRestore entry '%s' references unknown slot '%s'" % [dock_id, slot_id])
        var restore_index = location.get("index", 0)
        if not (restore_index is int or restore_index is float) or int(restore_index) < 0:
            errors.append("dockRestore entry '%s' index must be a non-negative number" % dock_id)

    var bottom_tabs := get_slot_tabs(DEFINITION_SCRIPT.SLOT_BOTTOM)
    if not bottom_active_tab.is_empty() and not bottom_tabs.has(bottom_active_tab):
        errors.append("bottom active dock '%s' is not in the bottom slot" % bottom_active_tab)
    if bottom_expanded and bottom_active_tab.is_empty():
        errors.append("expanded bottom panel must have an active dock")
    if not bottom_active_tab.is_empty() and get_slot_active_tab(DEFINITION_SCRIPT.SLOT_BOTTOM) != bottom_active_tab:
        errors.append("bottom active dock '%s' must match the bottom slot active tab" % bottom_active_tab)
    for raw_dock_id in bottom_tab_offsets:
        if not str(raw_dock_id).is_empty() and not dock_ids.is_empty() and not dock_ids.has(str(raw_dock_id)):
            errors.append("bottom offsets reference unknown dock '%s'" % raw_dock_id)
    return errors
