extends RefCounted
class_name EditorDockSlotState

const SLOT_STATE_SCRIPT := preload("res://workspace/layout/dock_slot_state.gd")

## 一个逻辑 Dock 槽位的可变状态。
##
## 槽位只负责保存稳定 Dock ID 的有序列表以及当前活动 Dock ID，不负责拥有
## Dock 描述对象，也不直接持有任何 Godot Control。布局管理器可以把同一个槽位
## 状态投影到不同的 TabContainer，而不改变这里保存的逻辑数据。

var slot_id: String
var tabs: Array = []
var active_tab: String = ""

func _init(p_slot_id: String = "") -> void:
    slot_id = p_slot_id

func duplicate_state():
    var result = SLOT_STATE_SCRIPT.new(slot_id)
    result.tabs = tabs.duplicate()
    result.active_tab = active_tab
    return result

func contains(dock_id: String) -> bool:
    return tabs.has(dock_id)

## 替换当前槽位的 Tab 列表。默认情况下，非空列表会自动把第一个 Tab 设为活动项；
## 读取持久化布局时可以关闭这个回退行为，从而保留“列表非空但没有活动 Tab”的
## 明确状态。这个状态用于表示底部面板已经收起，但下次展开时仍然可以恢复原有 Tab。
func set_tabs(p_tabs: Array, p_active_tab: String = "", p_default_to_first: bool = true) -> void:
    tabs = p_tabs.duplicate()
    if tabs.is_empty():
        active_tab = ""
    elif tabs.has(p_active_tab):
        active_tab = p_active_tab
    elif p_default_to_first:
        active_tab = str(tabs[0])
    else:
        active_tab = ""

func set_active_tab(p_active_tab: String, p_allow_empty: bool = false) -> bool:
    if p_active_tab.is_empty():
        if tabs.is_empty() or p_allow_empty:
            active_tab = ""
            return true
        return false
    if not tabs.has(p_active_tab):
        return false
    active_tab = p_active_tab
    return true

func remove_tab(dock_id: String) -> int:
    var index := tabs.find(dock_id)
    if index < 0:
        return -1
    tabs.remove_at(index)
    if active_tab == dock_id:
        active_tab = str(tabs[mini(index, tabs.size() - 1)]) if not tabs.is_empty() else ""
    return index

func insert_tab(dock_id: String, index: int = -1) -> int:
    if tabs.has(dock_id):
        return tabs.find(dock_id)
    var target := tabs.size() if index < 0 else clampi(index, 0, tabs.size())
    tabs.insert(target, dock_id)
    if active_tab.is_empty():
        active_tab = dock_id
    return target

func validate_self() -> Array:
    var errors: Array = []
    var seen: Dictionary = {}
    for raw_dock_id in tabs:
        var dock_id := str(raw_dock_id)
        if dock_id.is_empty():
            errors.append("slot '%s' contains an empty dock ID" % slot_id)
        if seen.has(dock_id):
            errors.append("slot '%s' contains duplicate dock '%s'" % [slot_id, dock_id])
        seen[dock_id] = true
    if not active_tab.is_empty() and not tabs.has(active_tab):
        errors.append("slot '%s' active dock '%s' is not in its tabs" % [slot_id, active_tab])
    return errors

func to_dict() -> Dictionary:
    return {"tabs": tabs.duplicate(), "active": active_tab}

static func from_dict(p_slot_id: String, source: Variant):
    var result = SLOT_STATE_SCRIPT.new(p_slot_id)
    if not source is Dictionary:
        return result
    var source_tabs = source.get("tabs", [])
    if source_tabs is Array:
        var has_active: bool = source.has("active")
        result.set_tabs(source_tabs, str(source.get("active", "")), not has_active)
    return result
