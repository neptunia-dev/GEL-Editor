extends RefCounted
class_name EditorModuleRegistry

const MODULE_SCRIPT := preload("res://workspace/modules/module_descriptor.gd")
const LAYOUT_MANAGER_SCRIPT := preload("res://workspace/layout/layout_manager.gd")
const WORKSPACE_DESCRIPTOR_SCRIPT := preload("res://workspace/layout/workspace_descriptor.gd")
const DOCK_DESCRIPTOR_SCRIPT := preload("res://workspace/layout/dock_descriptor.gd")

## 工作区模块的轻量注册表。
##
## 注册表只保存模块描述，并把其中的布局元数据转交给 EditorLayoutManager。
## 它不创建 Control，不调用 content_factory，也不管理模块生命周期。未来需要
## 增加模块时，调用方只需构造一个 EditorModuleDescriptor 并注册即可。

signal module_registered(module_id: String)
signal module_unregistered(module_id: String)

var last_error: String = ""
var _layout_manager
var _modules: Dictionary = {}

func _init(p_layout_manager = null) -> void:
    if (
            p_layout_manager != null
            and p_layout_manager.has_method("register_workspace")
            and p_layout_manager.has_method("register_dock")
            and p_layout_manager.has_method("get_definition")
    ):
        _layout_manager = p_layout_manager
    else:
        _layout_manager = LAYOUT_MANAGER_SCRIPT.new()

func get_layout_manager():
    return _layout_manager

func register_module(descriptor) -> bool:
    if descriptor == null:
        return _fail("module descriptor must not be null")
    if not descriptor.has_method("validate_self") or not descriptor.has_method("duplicate_descriptor"):
        return _fail("module descriptor has an invalid interface")

    var module_id := str(descriptor.module_id)
    if _modules.has(module_id):
        return _fail("module '%s' is already registered" % module_id)
    if (
            _layout_manager.get_workspace_descriptor(module_id) != null
            or _layout_manager.get_dock_descriptor(module_id) != null
    ):
        return _fail("module '%s' conflicts with an existing layout descriptor" % module_id)

    var errors: Array = descriptor.validate_self(_layout_manager.get_definition().slot_ids)
    if not errors.is_empty():
        return _fail(str(errors[0]))

    var stored = descriptor.duplicate_descriptor()
    if stored == null:
        return _fail("module '%s' could not be duplicated" % module_id)

    if not _register_layout_descriptor(descriptor):
        var layout_error := str(_layout_manager.last_error)
        return _fail(layout_error if not layout_error.is_empty() else "module '%s' could not be registered in the layout" % module_id)

    _modules[module_id] = stored
    _clear_error()
    module_registered.emit(module_id)
    return true

func unregister_module(module_id: String) -> bool:
    if not _modules.has(module_id):
        return _fail("module '%s' is not registered" % module_id)

    var descriptor = _modules[module_id]
    if not _unregister_layout_descriptor(descriptor):
        var layout_error := str(_layout_manager.last_error)
        return _fail(layout_error if not layout_error.is_empty() else "module '%s' could not be removed from the layout" % module_id)

    _modules.erase(module_id)
    _clear_error()
    module_unregistered.emit(module_id)
    return true

func has_module(module_id: String) -> bool:
    return _modules.has(module_id)

func get_module(module_id: String):
    return _modules[module_id].duplicate_descriptor() if _modules.has(module_id) else null

func get_module_ids() -> Array:
    var ids := _modules.keys()
    ids.sort()
    return ids

func get_module_count() -> int:
    return _modules.size()

func get_workspace_modules() -> Array:
    return _get_modules_by_kind(MODULE_SCRIPT.KIND_WORKSPACE)

func get_dock_modules() -> Array:
    return _get_modules_by_kind(MODULE_SCRIPT.KIND_DOCK)

func _register_layout_descriptor(descriptor) -> bool:
    if descriptor.kind == MODULE_SCRIPT.KIND_WORKSPACE:
        var workspace = WORKSPACE_DESCRIPTOR_SCRIPT.new(
            descriptor.module_id,
            descriptor.title,
            descriptor.default_active,
            descriptor.default_order,
        )
        return _layout_manager.register_workspace(workspace)

    if descriptor.kind == MODULE_SCRIPT.KIND_DOCK:
        var dock = DOCK_DESCRIPTOR_SCRIPT.new(
            descriptor.module_id,
            descriptor.title,
            descriptor.default_slot,
            descriptor.allowed_slots,
            descriptor.default_open,
            descriptor.closable,
            descriptor.transient,
            descriptor.default_order,
            descriptor.icon_name,
        )
        return _layout_manager.register_dock(dock)

    return false

func _unregister_layout_descriptor(descriptor) -> bool:
    if descriptor.kind == MODULE_SCRIPT.KIND_WORKSPACE:
        return _layout_manager.unregister_workspace(descriptor.module_id)
    if descriptor.kind == MODULE_SCRIPT.KIND_DOCK:
        return _layout_manager.unregister_dock(descriptor.module_id)
    return false

func _get_modules_by_kind(kind: String) -> Array:
    var result: Array = []
    for module_id in get_module_ids():
        var descriptor = _modules[module_id]
        if descriptor.kind == kind:
            result.append(descriptor.duplicate_descriptor())
    return result

func _fail(message: String) -> bool:
    last_error = message
    return false

func _clear_error() -> void:
    last_error = ""
