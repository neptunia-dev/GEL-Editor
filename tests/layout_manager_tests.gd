extends SceneTree

const MANAGER_SCRIPT := preload("res://workspace/layout/layout_manager.gd")
const DEFINITION_SCRIPT := preload("res://workspace/layout/layout_definition.gd")
const STATE_SCRIPT := preload("res://workspace/layout/layout_state.gd")
const SERIALIZER_SCRIPT := preload("res://workspace/layout/layout_serializer.gd")
const DOCK_SCRIPT := preload("res://workspace/layout/dock_descriptor.gd")
const WORKSPACE_SCRIPT := preload("res://workspace/layout/workspace_descriptor.gd")

const LEFT_UPPER := "left.upper"
const LEFT_LOWER := "left.lower"
const RIGHT_UPPER := "right.upper"
const RIGHT_LOWER := "right.lower"
const BOTTOM := "bottom"
const MAIN_SPLIT := "main"

var _checks: int = 0
var _failures: int = 0
var _layout_events: int = 0
var _workspace_events: int = 0
var _dock_events: int = 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_definition_and_state_shape()
    _test_descriptor_validation()
    _test_registration_and_default_layout()
    _test_dock_lifecycle_and_restore()
    _test_dock_movement_and_tabs()
    _test_workspace_lifecycle()
    _test_bottom_panel_state()
    _test_split_offsets()
    _test_serialization_and_reconciliation()
    _test_transactions_and_signal_boundaries()
    _test_ownership_isolation()

    if _failures == 0:
        print("PASS: %d layout manager checks" % _checks)
        quit(0)
    else:
        push_error("FAIL: %d of %d layout manager checks failed" % [_failures, _checks])
        quit(1)

func _test_definition_and_state_shape() -> void:
    var definition = DEFINITION_SCRIPT.standard()
    _check(definition.validate_self().is_empty(), "standard layout definition validates")
    _check(definition.slot_ids == [LEFT_UPPER, LEFT_LOWER, RIGHT_UPPER, RIGHT_LOWER, BOTTOM], "standard definition exposes five logical slots")
    _check(definition.split_ids == ["main", "left", "right", "center"], "standard definition exposes four logical splits")
    _check(definition.get_split_offset_count(MAIN_SPLIT) == 2, "main split has two offsets")
    _check(definition.get_split_offset_count("left") == 1, "left split has one offset")
    _check(definition.split_metadata[MAIN_SPLIT]["orientation"] == "horizontal", "main split is horizontal")
    _check(definition.split_metadata["center"]["children"] == ["workspace", BOTTOM], "center split owns workspace and bottom slot")

    var state = STATE_SCRIPT.from_definition(definition)
    _check(state.validate_self(definition).is_empty(), "empty state created from definition validates")
    _check(state.get_split_offsets(MAIN_SPLIT) == [260, -340], "standard state has the planned main split defaults")
    _check(state.get_split_offsets("left") == [0], "standard state initializes side split offsets")
    _check(state.get_slot_tabs(BOTTOM).is_empty(), "empty state has no bottom tabs")
    _check(not state.bottom_expanded, "bottom panel starts collapsed")

func _test_descriptor_validation() -> void:
    var valid = DOCK_SCRIPT.new("scene", "Scene", LEFT_UPPER, [LEFT_UPPER, LEFT_LOWER])
    _check(valid.validate_self([LEFT_UPPER, LEFT_LOWER]).is_empty(), "valid dock descriptor validates")

    var bad_id = DOCK_SCRIPT.new("Scene", "Scene", LEFT_UPPER, [LEFT_UPPER])
    _check(not bad_id.validate_self([LEFT_UPPER]).is_empty(), "dock IDs must use stable lowercase identifiers")

    var bad_slot = DOCK_SCRIPT.new("scene", "Scene", "missing", ["missing"])
    _check(_contains(bad_slot.validate_self([LEFT_UPPER]), "unknown slot"), "dock descriptor rejects unknown slots")

    var missing_default = DOCK_SCRIPT.new("scene", "Scene", LEFT_UPPER, [LEFT_LOWER])
    _check(_contains(missing_default.validate_self([LEFT_UPPER, LEFT_LOWER]), "default_slot must be included"), "default slot must be allowed")

    var duplicate_slot = DOCK_SCRIPT.new("scene", "Scene", LEFT_UPPER, [LEFT_UPPER, LEFT_UPPER])
    _check(_contains(duplicate_slot.validate_self([LEFT_UPPER]), "duplicate allowed slot"), "duplicate allowed slots are rejected")

    var bad_workspace = WORKSPACE_SCRIPT.new("Map", "Map")
    _check(not bad_workspace.validate_self().is_empty(), "workspace IDs must use stable lowercase identifiers")
    var empty_title = WORKSPACE_SCRIPT.new("map", " ")
    _check(_contains(empty_title.validate_self(), "title must not be empty"), "workspace title cannot be empty")

func _test_registration_and_default_layout() -> void:
    var manager = _new_manager()
    _check(manager.get_active_workspace_id() == "map", "default workspace becomes active after registration")
    _check(manager.get_dock_ids() == ["history", "import", "inspector", "locked", "output", "problems", "scene"], "registered dock IDs are returned deterministically")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["scene", "import"], "default-open left docks use default order")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "scene", "first left dock is initially active")
    _check(manager.get_slot_tabs(RIGHT_UPPER) == ["inspector", "history"], "default-open right docks use default order")
    _check(manager.get_slot_tabs(BOTTOM) == ["output", "problems"], "default-open bottom docks occupy the bottom slot")
    _check(manager.get_bottom_panel_active_tab() == "output", "first bottom dock is remembered as active")
    _check(not manager.is_bottom_panel_expanded(), "bottom panel is collapsed in the default layout")
    _check(not manager.is_dock_open("locked"), "default-closed dock is not placed in a slot")
    _check(manager.get_dock_location("locked")["slot"] == LEFT_LOWER, "closed dock remembers its default slot")
    _check(manager.get_default_state_dict()["activeWorkspace"] == "map", "default state includes the active workspace")
    _check(manager.get_default_state_dict()["splits"][MAIN_SPLIT] == [260, -340], "default state includes planned main offsets")

    _check(not manager.register_dock(DOCK_SCRIPT.new("scene", "Duplicate", LEFT_UPPER, [LEFT_UPPER])), "duplicate dock registration is rejected")
    _check(manager.last_error.contains("already registered"), "duplicate dock error is retained")
    _check(not manager.register_dock(DOCK_SCRIPT.new("bad", "Bad", "missing", ["missing"])), "invalid dock registration is rejected")
    _check(manager.register_workspace(WORKSPACE_SCRIPT.new("preview", "Preview")), "additional workspace registers")
    _check(manager.get_active_workspace_id() == "map", "registering a non-default workspace does not switch the active workspace")

func _test_dock_lifecycle_and_restore() -> void:
    var manager = _new_manager()
    _check(manager.close_dock("import"), "closable dock can be closed")
    _check(not manager.is_dock_open("import"), "closed dock leaves its slot")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["scene"], "closing a dock removes only that dock")
    var closed_location: Dictionary = manager.get_dock_location("import")
    _check(not bool(closed_location["open"]) and closed_location["slot"] == LEFT_UPPER, "closed dock keeps its previous slot")
    _check(int(closed_location["index"]) == 1, "closed dock keeps its previous tab index")

    _check(manager.open_dock("import", false), "closed dock can be reopened without focus")
    _check(manager.is_dock_open("import"), "reopened dock is open")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["scene", "import"], "reopened dock returns to its remembered tab position")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "scene", "reopening without focus preserves the active tab")
    _check(manager.focus_dock("import"), "open dock can be focused")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "import", "focusing a dock selects its tab")

    _check(not manager.close_dock("locked"), "non-closable dock cannot be closed")
    _check(manager.last_error.contains("not closable"), "non-closable dock error is retained")
    _check(not manager.open_dock("missing"), "unknown dock cannot be opened")
    _check(not manager.close_dock("missing"), "unknown dock cannot be closed")

    _check(manager.close_dock("scene"), "active dock can be closed")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "import", "closing the active tab selects an adjacent tab")
    _check(manager.open_dock("scene", true), "closed active dock can be reopened with focus")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "scene", "reopened dock can become active")

func _test_dock_movement_and_tabs() -> void:
    var manager = _new_manager()
    _check(manager.reorder_dock("import", 0), "dock tabs can be reordered")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["import", "scene"], "reordering changes tab order without duplication")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "scene", "reordering without focus preserves active tab")
    _check(manager.reorder_dock("import", 99), "reordering clamps an oversized index")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["scene", "import"], "reordering to the end is clamped safely")

    _check(manager.move_dock("scene", LEFT_LOWER, 0, true), "dock can move to an allowed slot")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["import"], "source slot is cleaned after a move")
    _check(manager.get_slot_tabs(LEFT_LOWER) == ["scene"], "target slot receives the moved dock")
    _check(manager.get_slot_active_tab(LEFT_LOWER) == "scene", "focused moved dock becomes active")
    _check(manager.get_dock_location("scene")["slot"] == LEFT_LOWER, "moved dock reports its new location")

    _check(manager.move_dock("scene", LEFT_UPPER, 0, false), "dock can move back without focus")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["scene", "import"], "moving back restores the requested position")
    _check(manager.get_slot_active_tab(LEFT_UPPER) == "import", "moving without focus preserves target active tab")

    var before_invalid: Dictionary = manager.get_state_dict()
    _check(not manager.move_dock("output", LEFT_UPPER), "dock rejects a slot outside its allowed locations")
    _check(manager.get_state_dict() == before_invalid, "rejected move does not partially modify layout")
    _check(not manager.move_dock("locked", LEFT_UPPER), "closed dock cannot be moved")

    _check(manager.move_dock("inspector", RIGHT_LOWER, 0, true), "right dock can move to another allowed right slot")
    _check(manager.get_slot_tabs(RIGHT_UPPER) == ["history"], "right source slot is cleaned")
    _check(manager.get_slot_tabs(RIGHT_LOWER) == ["inspector"], "right target slot receives the dock")

func _test_workspace_lifecycle() -> void:
    var manager = _new_manager()
    _check(manager.get_active_workspace_id() == "map", "map is initially active")
    var before: Dictionary = manager.get_state_dict()
    _check(manager.activate_workspace("script"), "registered workspace can be activated")
    _check(manager.get_active_workspace_id() == "script", "workspace activation updates state")
    _check(manager.get_state_dict()["slots"] == before["slots"], "workspace switching does not alter dock slots")
    _check(not manager.activate_workspace("missing"), "unknown workspace cannot be activated")
    _check(manager.register_workspace(WORKSPACE_SCRIPT.new("preview", "Preview", true)), "default-active workspace can register")
    _check(manager.get_active_workspace_id() == "script", "late default-active workspace does not steal focus")
    _check(manager.unregister_workspace("script"), "active workspace can be unregistered")
    _check(manager.get_active_workspace_id() == "map", "unregistering active workspace falls back safely")
    _check(not manager.unregister_workspace("missing"), "unknown workspace cannot be unregistered")

func _test_bottom_panel_state() -> void:
    var manager = _new_manager()
    _check(manager.set_bottom_panel_expanded(true), "bottom panel can be expanded")
    _check(manager.is_bottom_panel_expanded(), "bottom panel expansion is stored")
    _check(manager.get_bottom_panel_active_tab() == "output", "expanding selects the first bottom tab")
    _check(manager.set_bottom_panel_tab("problems"), "bottom tab can be selected")
    _check(manager.get_bottom_panel_active_tab() == "problems", "bottom active tab changes")
    _check(manager.is_bottom_panel_expanded(), "selecting a bottom tab keeps panel expanded")
    _check(manager.set_bottom_panel_tab_offset("problems", 240), "bottom tab height can be stored")
    _check(manager.get_bottom_panel_tab_offset("problems") == 240, "bottom tab height is readable")
    _check(not manager.set_bottom_panel_tab("scene"), "non-bottom dock cannot become a bottom tab")

    _check(manager.set_bottom_panel_expanded(false), "bottom panel can be collapsed")
    _check(not manager.is_bottom_panel_expanded(), "collapse preserves a reusable active tab")
    _check(manager.get_bottom_panel_active_tab() == "problems", "collapse keeps the last bottom tab")
    _check(manager.toggle_bottom_panel(), "bottom panel can be toggled open")
    _check(manager.is_bottom_panel_expanded(), "toggle expands the panel")

    _check(manager.close_dock("problems"), "active bottom dock can be closed")
    _check(manager.get_bottom_panel_active_tab() == "output", "closing one bottom tab selects the remaining tab")
    _check(manager.is_bottom_panel_expanded(), "remaining bottom tab keeps panel expanded")
    _check(manager.close_dock("output"), "last bottom dock can be closed")
    _check(manager.get_bottom_panel_active_tab().is_empty(), "closing the last bottom dock clears active tab")
    _check(not manager.is_bottom_panel_expanded(), "closing the last bottom dock collapses panel")
    _check(manager.open_dock("output", true), "bottom dock can be reopened")
    _check(manager.is_bottom_panel_expanded(), "focusing a reopened bottom dock expands panel")

func _test_split_offsets() -> void:
    var manager = _new_manager()
    _check(manager.set_split_offsets(MAIN_SPLIT, [280, -360]), "main split accepts the correct number of offsets")
    _check(manager.get_state().get_split_offsets(MAIN_SPLIT) == [280, -360], "main split offsets persist")
    _check(manager.set_split_offset("left", 0, 120), "individual split offset can be changed")
    _check(manager.get_state().get_split_offsets("left") == [120], "individual split offset persists")
    var before: Dictionary = manager.get_state_dict()
    _check(not manager.set_split_offsets(MAIN_SPLIT, [1]), "wrong split offset count is rejected")
    _check(manager.get_state_dict() == before, "wrong offset count does not modify state")
    _check(not manager.set_split_offsets("missing", [0]), "unknown split is rejected")
    _check(not manager.set_split_offset(MAIN_SPLIT, 9, 0), "invalid split offset index is rejected")
    _check(not manager.set_split_offsets("left", ["not-a-number"]), "non-numeric split offset is rejected")

func _test_serialization_and_reconciliation() -> void:
    var manager = _new_manager()
    manager.activate_workspace("script")
    manager.reorder_dock("import", 0)
    manager.move_dock("inspector", RIGHT_LOWER, 0, true)
    manager.set_bottom_panel_expanded(true)
    manager.set_bottom_panel_tab("problems")
    manager.set_bottom_panel_tab_offset("problems", 225)
    manager.set_split_offsets(MAIN_SPLIT, [275, -350])
    manager.close_dock("history")

    var encoded: String = manager.encode_json()
    var restored = _new_manager()
    _check(restored.load_json(encoded), "serialized layout can be loaded")
    _check(restored.get_state_dict() == manager.get_state_dict(), "layout JSON round-trip preserves state")

    var serializer = SERIALIZER_SCRIPT.new()
    var decoded: Dictionary = serializer.deserialize(manager.get_state_dict(), manager.get_definition())
    _check(bool(decoded["ok"]), "serializer accepts a current state dictionary")
    _check(serializer.validate(decoded["state"], manager.get_definition(), manager.get_dock_ids(), manager.get_workspace_ids()).is_empty(), "deserialized state validates against registries")
    _check(not serializer.deserialize("not-a-dictionary", manager.get_definition())["ok"], "serializer rejects non-dictionary input")
    _check(not serializer.deserialize({"schemaVersion": 99}, manager.get_definition())["ok"], "serializer rejects a newer schema")
    _check(not serializer.deserialize({"schemaVersion": 0}, manager.get_definition())["ok"], "serializer rejects an invalid schema")
    _check(not serializer.decode_json("{broken", manager.get_definition())["ok"], "serializer rejects malformed JSON")

    var with_unknown: Dictionary = manager.get_state_dict()
    (with_unknown["slots"][LEFT_UPPER]["tabs"] as Array).append("ghost")
    with_unknown["closedDocks"].append("ghost")
    with_unknown["dockRestore"]["ghost"] = {"slot": LEFT_UPPER, "index": 0}
    with_unknown["unknownField"] = "ignored"
    var unknown_manager = _new_manager()
    _check(unknown_manager.apply_state(with_unknown), "unknown layout entries are reconciled safely")
    _check(not unknown_manager.get_state_dict()["slots"][LEFT_UPPER].has("ghost"), "unknown dock is not rendered into a slot")
    _check(not unknown_manager.get_state_dict()["closedDocks"].has("ghost"), "unknown dock is not retained as closed")

    var missing_fields = _new_manager()
    _check(missing_fields.apply_state({"schemaVersion": 1}), "missing layout fields receive defaults")
    _check(missing_fields.get_state_dict() == missing_fields.get_default_state_dict(), "missing fields resolve to the registered default layout")

    var duplicate_state: Dictionary = manager.get_default_state_dict()
    duplicate_state["slots"][LEFT_LOWER]["tabs"] = ["scene"]
    duplicate_state["slots"][LEFT_LOWER]["active"] = "scene"
    var duplicate_manager = _new_manager()
    _check(duplicate_manager.apply_state(duplicate_state), "duplicate dock entries are reconciled safely")
    var scene_occurrences: int = _count_dock_occurrences(duplicate_manager.get_state_dict(), "scene")
    _check(scene_occurrences == 1, "reconciled state contains each dock at most once")

    var future_state: Dictionary = manager.get_state_dict()
    future_state["schemaVersion"] = 99
    var before_future: Dictionary = restored.get_state_dict()
    _check(not restored.apply_state(future_state), "manager rejects a future layout schema")
    _check(restored.get_state_dict() == before_future, "future schema rejection preserves current state")

    var malformed = _new_manager()
    malformed.activate_workspace("script")
    _check(not malformed.load_json("{broken"), "malformed JSON returns failure")
    _check(malformed.get_state_dict() == malformed.get_default_state_dict(), "malformed JSON resets to default when requested")
    _check(not malformed.last_error.is_empty(), "malformed JSON keeps a diagnostic error")

func _test_transactions_and_signal_boundaries() -> void:
    var manager = _new_manager()
    manager.layout_changed.connect(_on_layout_changed)
    manager.workspace_changed.connect(_on_workspace_changed)
    manager.dock_opened.connect(_on_dock_event)
    manager.dock_closed.connect(_on_dock_event)
    manager.dock_moved.connect(_on_dock_moved)
    _layout_events = 0
    _workspace_events = 0
    _dock_events = 0

    manager.begin_update()
    manager.begin_update()
    _check(manager.set_split_offsets(MAIN_SPLIT, [300, -380]), "transaction accepts split update")
    _check(manager.activate_workspace("script"), "transaction accepts workspace update")
    _check(manager.set_docks_visible(false), "transaction accepts dock visibility update")
    _check(_layout_events == 0, "nested transaction defers aggregate layout signal")
    _check(manager.end_update(), "inner transaction closes")
    _check(_layout_events == 0, "inner transaction does not emit aggregate signal")
    _check(manager.end_update(), "outer transaction closes")
    _check(_layout_events == 1, "outer transaction emits exactly one aggregate layout signal")
    _check(_workspace_events == 1, "specific workspace signal still describes the transition")
    _check(not manager.is_docks_visible(), "transaction commits dock visibility")

    _layout_events = 0
    _check(manager.close_dock("history"), "post-transaction dock operation succeeds")
    _check(_dock_events == 1, "specific dock signal is emitted once")
    _check(_layout_events == 1, "post-transaction operation emits one layout signal")
    _check(not manager.end_update(), "unmatched transaction end is rejected")

func _test_ownership_isolation() -> void:
    var manager = _new_manager()
    var state = manager.get_state()
    state.active_workspace = "corrupted"
    state.get_slot_tabs(LEFT_UPPER).clear()
    state.split_offsets[MAIN_SPLIT] = [999, 999]
    _check(manager.get_active_workspace_id() == "map", "state getter returns an ownership-safe copy")
    _check(manager.get_slot_tabs(LEFT_UPPER) == ["scene", "import"], "mutating copied slot tabs does not affect manager")
    _check(manager.get_state().get_split_offsets(MAIN_SPLIT) == [260, -340], "mutating copied split offsets does not affect manager")

    var definition = manager.get_definition()
    definition.slot_ids.clear()
    definition.slot_metadata.clear()
    _check(manager.get_definition().has_slot(LEFT_UPPER), "definition getter returns an ownership-safe copy")

func _new_manager():
    var manager = MANAGER_SCRIPT.new()
    manager.register_workspace(WORKSPACE_SCRIPT.new("map", "Map", true, 0))
    manager.register_workspace(WORKSPACE_SCRIPT.new("script", "Script", false, 1))
    manager.register_dock(DOCK_SCRIPT.new("scene", "Scene", LEFT_UPPER, [LEFT_UPPER, LEFT_LOWER], true, true, false, 0))
    manager.register_dock(DOCK_SCRIPT.new("import", "Import", LEFT_UPPER, [LEFT_UPPER, LEFT_LOWER], true, true, false, 1))
    manager.register_dock(DOCK_SCRIPT.new("inspector", "Inspector", RIGHT_UPPER, [RIGHT_UPPER, RIGHT_LOWER], true, true, false, 0))
    manager.register_dock(DOCK_SCRIPT.new("history", "History", RIGHT_UPPER, [RIGHT_UPPER, RIGHT_LOWER], true, true, false, 1))
    manager.register_dock(DOCK_SCRIPT.new("locked", "Locked", LEFT_LOWER, [LEFT_LOWER], false, false, false, 0))
    manager.register_dock(DOCK_SCRIPT.new("output", "Output", BOTTOM, [BOTTOM], true, true, true, 0))
    manager.register_dock(DOCK_SCRIPT.new("problems", "Problems", BOTTOM, [BOTTOM], true, true, true, 1))
    return manager

func _count_dock_occurrences(state_dict: Dictionary, dock_id: String) -> int:
    var count := 0
    var slots: Dictionary = state_dict.get("slots", {})
    for slot_id in slots:
        var slot = slots[slot_id]
        if slot is Dictionary and (slot.get("tabs", []) as Array).has(dock_id):
            count += 1
    if (state_dict.get("closedDocks", []) as Array).has(dock_id):
        count += 1
    return count

func _on_layout_changed(_state: Dictionary) -> void:
    _layout_events += 1

func _on_workspace_changed(_workspace_id: String) -> void:
    _workspace_events += 1

func _on_dock_event(_dock_id: String) -> void:
    _dock_events += 1

func _on_dock_moved(_dock_id: String, _slot_id: String) -> void:
    _dock_events += 1

func _contains(values: Array, needle: String) -> bool:
    for value in values:
        if str(value).contains(needle):
            return true
    return false

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if condition:
        return
    _failures += 1
    push_error("CHECK FAILED: %s" % message)
