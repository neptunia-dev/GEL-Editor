extends SceneTree

const MODULE_SCRIPT := preload("res://workspace/modules/module_descriptor.gd")
const REGISTRY_SCRIPT := preload("res://workspace/modules/module_registry.gd")
const LAYOUT_MANAGER_SCRIPT := preload("res://workspace/layout/layout_manager.gd")
const DOCK_SCRIPT := preload("res://workspace/layout/dock_descriptor.gd")

const LEFT_UPPER := "left.upper"
const LEFT_LOWER := "left.lower"

var _checks: int = 0
var _failures: int = 0
var _factory_calls: int = 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_descriptor_helpers()
    _test_dock_registration()
    _test_workspace_registration()
    _test_registration_validation_is_atomic()
    _test_layout_collision_is_atomic()
    _test_unregistration()

    if _failures == 0:
        print("PASS: %d module registry checks" % _checks)
        quit(0)
    else:
        push_error("FAIL: %d of %d module registry checks failed" % [_failures, _checks])
        quit(1)

func _test_descriptor_helpers() -> void:
    var dock = MODULE_SCRIPT.dock(
        "gel.sample_dock", "Sample Dock", LEFT_LOWER,
        null, Callable(self, "_content_factory"), [LEFT_LOWER, LEFT_UPPER],
    )
    _check(dock.kind == MODULE_SCRIPT.KIND_DOCK, "dock helper sets dock kind")
    _check(dock.allowed_slots == [LEFT_LOWER, LEFT_UPPER], "dock helper keeps allowed slots")
    _check(dock.validate_self([LEFT_UPPER, LEFT_LOWER]).is_empty(), "sample dock descriptor validates")
    _check(dock.has_content_provider(), "dock keeps delayed content factory")

    var workspace = MODULE_SCRIPT.workspace("gel.node_map", "Node Map")
    _check(workspace.kind == MODULE_SCRIPT.KIND_WORKSPACE, "workspace helper sets workspace kind")
    _check(workspace.validate_self([LEFT_UPPER, LEFT_LOWER]).is_empty(), "workspace descriptor validates without content")

    var copy = dock.duplicate_descriptor()
    copy.allowed_slots.append("right.upper")
    _check(dock.allowed_slots == [LEFT_LOWER, LEFT_UPPER], "descriptor copies do not share slot arrays")

func _test_dock_registration() -> void:
    var manager = LAYOUT_MANAGER_SCRIPT.new()
    var registry = REGISTRY_SCRIPT.new(manager)
    var descriptor = MODULE_SCRIPT.dock(
        "gel.sample_dock", "Sample Dock", LEFT_LOWER,
        null, Callable(self, "_content_factory"), [LEFT_LOWER, LEFT_UPPER],
        true, true, 4,
    )
    _check(registry.register_module(descriptor), "sample dock registers")
    _check(registry.has_module("gel.sample_dock"), "registered dock is queryable")
    _check(manager.get_dock_ids() == ["gel.sample_dock"], "dock metadata reaches layout manager")
    _check(manager.get_dock_descriptor("gel.sample_dock").default_slot == LEFT_LOWER, "default slot reaches layout manager")
    _check(manager.get_dock_location("gel.sample_dock")["slot"] == LEFT_LOWER, "default layout places dock in its slot")
    _check(_factory_calls == 0, "registration does not call content factory")

    var returned = registry.get_module("gel.sample_dock")
    returned.title = "Changed Copy"
    _check(registry.get_module("gel.sample_dock").title == "Sample Dock", "module queries return copies")
    _check(registry.get_module_ids() == ["gel.sample_dock"], "module IDs are stable and sorted")
    _check(registry.get_dock_modules().size() == 1 and registry.get_workspace_modules().is_empty(), "modules can be filtered by kind")

func _test_workspace_registration() -> void:
    var manager = LAYOUT_MANAGER_SCRIPT.new()
    var registry = REGISTRY_SCRIPT.new(manager)
    _check(registry.register_module(MODULE_SCRIPT.workspace("gel.preview", "Preview")), "workspace module registers")
    _check(manager.get_workspace_ids() == ["gel.preview"], "workspace metadata reaches layout manager")
    _check(manager.get_active_workspace_id() == "gel.preview", "first workspace becomes active")

    var second = MODULE_SCRIPT.workspace("gel.script", "Script", null, Callable(), true)
    _check(registry.register_module(second), "second workspace registers")
    _check(manager.get_active_workspace_id() == "gel.preview", "late workspace does not steal active workspace")

func _test_registration_validation_is_atomic() -> void:
    var manager = LAYOUT_MANAGER_SCRIPT.new()
    var registry = REGISTRY_SCRIPT.new(manager)
    _check(registry.register_module(MODULE_SCRIPT.dock("gel.valid", "Valid", LEFT_UPPER)), "valid module registers before atomicity checks")
    var before_state: Dictionary = manager.get_state_dict()
    var before_ids: Array = manager.get_dock_ids()

    var invalid = MODULE_SCRIPT.dock("gel.invalid", "Invalid", "missing", null, Callable(), ["missing"])
    _check(not registry.register_module(invalid), "unknown slot rejects module")
    _check(not registry.has_module("gel.invalid"), "rejected module is absent from registry")
    _check(manager.get_dock_ids() == before_ids, "rejected module does not reach layout manager")
    _check(manager.get_state_dict() == before_state, "rejected module does not change layout state")

    var duplicate = MODULE_SCRIPT.workspace("gel.valid", "Duplicate")
    _check(not registry.register_module(duplicate), "duplicate module ID rejects across kinds")
    _check(not registry.has_module("gel.valid") or registry.get_module("gel.valid").kind == MODULE_SCRIPT.KIND_DOCK, "duplicate rejection preserves original module")

func _test_layout_collision_is_atomic() -> void:
    var manager = LAYOUT_MANAGER_SCRIPT.new()
    var registry = REGISTRY_SCRIPT.new(manager)
    _check(manager.register_dock(DOCK_SCRIPT.new("gel.occupied", "Occupied", LEFT_UPPER, [LEFT_UPPER])), "pre-existing layout dock registers")
    var before_ids: Array = manager.get_dock_ids()
    var descriptor = MODULE_SCRIPT.dock("gel.occupied", "Occupied Copy", LEFT_UPPER)
    _check(not registry.register_module(descriptor), "layout ID collision rejects module")
    _check(registry.last_error.contains("existing layout descriptor"), "layout collision reports its source")
    _check(not registry.has_module("gel.occupied"), "layout collision leaves registry empty")
    _check(manager.get_dock_ids() == before_ids, "layout collision leaves existing layout unchanged")

func _test_unregistration() -> void:
    var manager = LAYOUT_MANAGER_SCRIPT.new()
    var registry = REGISTRY_SCRIPT.new(manager)
    _check(registry.register_module(MODULE_SCRIPT.dock("gel.sample_dock", "Sample Dock", LEFT_UPPER)), "module registers before removal")
    _check(registry.unregister_module("gel.sample_dock"), "module unregisters")
    _check(not registry.has_module("gel.sample_dock"), "unregistered module is removed from registry")
    _check(manager.get_dock_ids().is_empty(), "unregistered module is removed from layout manager")
    _check(not registry.unregister_module("gel.sample_dock"), "unknown module cannot unregister")

func _content_factory():
    _factory_calls += 1
    return null

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if condition:
        return
    _failures += 1
    push_error("CHECK FAILED: %s" % message)
