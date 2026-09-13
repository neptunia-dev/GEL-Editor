extends RefCounted
class_name EditorModuleDescriptor

const DESCRIPTOR_SCRIPT := preload("res://workspace/modules/module_descriptor.gd")
const ID_PATTERN := "^[a-z][a-z0-9_.-]*$"

## 工作区模块的静态描述。
##
## 描述对象只记录模块身份、布局类型和内容创建方式，不创建 Control，也不保存
## 当前 Tab、Split 偏移或打开状态。那些可变数据全部由 EditorLayoutManager 管理。
## content_scene 和 content_factory 都是可选的，方便在 UI 尚未实现时先注册布局模块。

const KIND_WORKSPACE := "workspace"
const KIND_DOCK := "dock"

var module_id: String
var title: String
var kind: String
var content_scene: PackedScene
var content_factory: Callable

var default_active: bool
var default_order: int

var default_slot: String
var allowed_slots: Array
var default_open: bool
var closable: bool
var transient: bool
var icon_name: StringName

func _init(
        p_module_id: String = "",
        p_title: String = "",
        p_kind: String = KIND_DOCK,
        p_default_slot: String = "",
        p_content_scene: PackedScene = null,
        p_content_factory: Callable = Callable(),
        p_allowed_slots: Array = [],
        p_default_open: bool = true,
        p_closable: bool = true,
        p_transient: bool = false,
        p_default_order: int = 0,
        p_default_active: bool = false,
        p_icon_name: StringName = &"",
) -> void:
    module_id = p_module_id
    title = p_title
    kind = p_kind
    content_scene = p_content_scene
    content_factory = p_content_factory
    default_slot = p_default_slot
    allowed_slots = p_allowed_slots.duplicate()
    default_open = p_default_open
    closable = p_closable
    transient = p_transient
    default_order = p_default_order
    default_active = p_default_active
    icon_name = p_icon_name

    if allowed_slots.is_empty() and kind == KIND_DOCK and not default_slot.is_empty():
        allowed_slots.append(default_slot)

## 使用命名参数式的静态工厂，避免调用方记忆 Workspace 和 Dock 的不同参数顺序。
static func workspace(
        p_module_id: String,
        p_title: String,
        p_content_scene: PackedScene = null,
        p_content_factory: Callable = Callable(),
        p_default_active: bool = false,
        p_default_order: int = 0,
):
    return DESCRIPTOR_SCRIPT.new(
        p_module_id, p_title, KIND_WORKSPACE,
        "", p_content_scene, p_content_factory,
        [], true, true, false, p_default_order, p_default_active,
    )

static func dock(
        p_module_id: String,
        p_title: String,
        p_default_slot: String,
        p_content_scene: PackedScene = null,
        p_content_factory: Callable = Callable(),
        p_allowed_slots: Array = [],
        p_default_open: bool = true,
        p_closable: bool = true,
        p_default_order: int = 0,
        p_icon_name: StringName = &"",
):
    return DESCRIPTOR_SCRIPT.new(
        p_module_id, p_title, KIND_DOCK,
        p_default_slot, p_content_scene, p_content_factory,
        p_allowed_slots, p_default_open, p_closable, false, p_default_order, false, p_icon_name,
    )

func duplicate_descriptor():
    return DESCRIPTOR_SCRIPT.new(
        module_id, title, kind,
        default_slot, content_scene, content_factory,
        allowed_slots, default_open, closable, transient, default_order, default_active, icon_name,
    )

func validate_self(known_slots: Array = []) -> Array:
    var errors: Array = []
    if not _is_valid_id(module_id):
        errors.append("module_id must match %s" % ID_PATTERN)
    if title.strip_edges().is_empty():
        errors.append("module '%s' title must not be empty" % module_id)
    if not [KIND_WORKSPACE, KIND_DOCK].has(kind):
        errors.append("module '%s' kind must be workspace or dock" % module_id)
        return errors
    if content_scene != null and not content_factory.is_null():
        errors.append("module '%s' must choose content_scene or content_factory, not both" % module_id)
    elif not content_factory.is_null() and not content_factory.is_valid():
        errors.append("module '%s' content_factory must be valid" % module_id)

    if kind == KIND_WORKSPACE:
        if not default_slot.is_empty():
            errors.append("workspace module '%s' must not declare a dock slot" % module_id)
        if not allowed_slots.is_empty():
            errors.append("workspace module '%s' must not declare allowed dock slots" % module_id)
    else:
        if default_slot.is_empty():
            errors.append("dock module '%s' default_slot must not be empty" % module_id)
        if allowed_slots.is_empty():
            errors.append("dock module '%s' must allow at least one slot" % module_id)
        elif not allowed_slots.has(default_slot):
            errors.append("dock module '%s' default_slot must be included in allowed_slots" % module_id)

        var seen_slots: Dictionary = {}
        for raw_slot in allowed_slots:
            if not raw_slot is String:
                errors.append("dock module '%s' allowed_slots must contain strings" % module_id)
                continue
            var slot_id := str(raw_slot)
            if seen_slots.has(slot_id):
                errors.append("dock module '%s' contains duplicate allowed slot '%s'" % [module_id, slot_id])
                continue
            seen_slots[slot_id] = true
            if not known_slots.is_empty() and not known_slots.has(slot_id):
                errors.append("dock module '%s' references unknown slot '%s'" % [module_id, slot_id])

        if not known_slots.is_empty() and not known_slots.has(default_slot):
            errors.append("dock module '%s' default_slot '%s' does not exist" % [module_id, default_slot])
    return errors

func has_content_provider() -> bool:
    return content_scene != null or (not content_factory.is_null() and content_factory.is_valid())

static func _is_valid_id(value: String) -> bool:
    var regex := RegEx.new()
    return regex.compile(ID_PATTERN) == OK and regex.search(value) != null
