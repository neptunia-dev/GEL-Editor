extends RefCounted
class_name EditorLayoutDefinition

const DEFINITION_SCRIPT := preload("res://workspace/layout/layout_definition.gd")
const ID_PATTERN := "^[a-z][a-z0-9_.-]*$"
const ORIENTATION_HORIZONTAL := "horizontal"
const ORIENTATION_VERTICAL := "vertical"

## 按约定只读的编辑器布局拓扑定义。
##
## 该对象描述编辑器中有哪些逻辑槽位、哪些 Split 以及它们之间的父子关系，
## 同时记录每个 Split 的方向和默认偏移。它不保存用户当前的布局状态，也不
## 创建或引用任何 Godot Control；用户修改后的宽度、Tab 顺序和可见性属于
## EditorLayoutState。

const SLOT_LEFT_UPPER := "left.upper"
const SLOT_LEFT_LOWER := "left.lower"
const SLOT_RIGHT_UPPER := "right.upper"
const SLOT_RIGHT_LOWER := "right.lower"
const SLOT_BOTTOM := "bottom"

const SPLIT_MAIN := "main"
const SPLIT_LEFT := "left"
const SPLIT_RIGHT := "right"
const SPLIT_CENTER := "center"

const SIDE_LEFT := "left"
const SIDE_RIGHT := "right"
const SIDE_CENTER := "center"
const SIDE_BOTTOM := "bottom"

var slot_ids: Array
var split_ids: Array
var slot_metadata: Dictionary
var split_metadata: Dictionary

func _init(
        p_slot_ids: Array = [],
        p_split_ids: Array = [],
        p_slot_metadata: Dictionary = {},
        p_split_metadata: Dictionary = {},
) -> void:
    slot_ids = p_slot_ids.duplicate()
    split_ids = p_split_ids.duplicate()
    slot_metadata = p_slot_metadata.duplicate(true)
    split_metadata = p_split_metadata.duplicate(true)

static func standard():
    return DEFINITION_SCRIPT.new(
        [
            SLOT_LEFT_UPPER,
            SLOT_LEFT_LOWER,
            SLOT_RIGHT_UPPER,
            SLOT_RIGHT_LOWER,
            SLOT_BOTTOM,
        ],
        [SPLIT_MAIN, SPLIT_LEFT, SPLIT_RIGHT, SPLIT_CENTER],
        {
            SLOT_LEFT_UPPER: {"side": SIDE_LEFT, "region": "upper", "orientation": ORIENTATION_VERTICAL},
            SLOT_LEFT_LOWER: {"side": SIDE_LEFT, "region": "lower", "orientation": ORIENTATION_VERTICAL},
            SLOT_RIGHT_UPPER: {"side": SIDE_RIGHT, "region": "upper", "orientation": ORIENTATION_VERTICAL},
            SLOT_RIGHT_LOWER: {"side": SIDE_RIGHT, "region": "lower", "orientation": ORIENTATION_VERTICAL},
            SLOT_BOTTOM: {"side": SIDE_BOTTOM, "region": "bottom", "orientation": ORIENTATION_HORIZONTAL},
        },
        {
            SPLIT_MAIN: {
                "orientation": ORIENTATION_HORIZONTAL,
                "children": [SPLIT_LEFT, SPLIT_CENTER, SPLIT_RIGHT],
                "default_offsets": [260, -340],
            },
            SPLIT_LEFT: {
                "orientation": ORIENTATION_VERTICAL,
                "children": [SLOT_LEFT_UPPER, SLOT_LEFT_LOWER],
                "default_offsets": [0],
            },
            SPLIT_RIGHT: {
                "orientation": ORIENTATION_VERTICAL,
                "children": [SLOT_RIGHT_UPPER, SLOT_RIGHT_LOWER],
                "default_offsets": [0],
            },
            SPLIT_CENTER: {
                "orientation": ORIENTATION_VERTICAL,
                "children": ["workspace", SLOT_BOTTOM],
                "default_offsets": [0],
            },
        },
    )

func duplicate_definition():
    return DEFINITION_SCRIPT.new(slot_ids, split_ids, slot_metadata, split_metadata)

func has_slot(slot_id: String) -> bool:
    return slot_ids.has(slot_id)

func has_split(split_id: String) -> bool:
    return split_ids.has(split_id)

func get_split_child_count(split_id: String) -> int:
    var metadata = split_metadata.get(split_id, {})
    if not metadata is Dictionary:
        return 0
    var children = metadata.get("children", [])
    return children.size() if children is Array else 0

func get_split_offset_count(split_id: String) -> int:
    return maxi(0, get_split_child_count(split_id) - 1)

func validate_self() -> Array:
    var errors: Array = []
    var seen_slots: Dictionary = {}
    for raw_slot in slot_ids:
        if not raw_slot is String:
            errors.append("slot_ids must contain strings")
            continue
        var slot_id := str(raw_slot)
        if not _is_valid_id(slot_id):
            errors.append("slot '%s' must match %s" % [slot_id, ID_PATTERN])
        if seen_slots.has(slot_id):
            errors.append("duplicate slot '%s'" % slot_id)
        seen_slots[slot_id] = true
        if not slot_metadata.has(slot_id):
            errors.append("slot '%s' has no metadata" % slot_id)
        elif not slot_metadata[slot_id] is Dictionary:
            errors.append("slot '%s' metadata must be a dictionary" % slot_id)

    var seen_splits: Dictionary = {}
    for raw_split in split_ids:
        if not raw_split is String:
            errors.append("split_ids must contain strings")
            continue
        var split_id := str(raw_split)
        if not _is_valid_id(split_id):
            errors.append("split '%s' must match %s" % [split_id, ID_PATTERN])
        if seen_splits.has(split_id):
            errors.append("duplicate split '%s'" % split_id)
        seen_splits[split_id] = true
        if not split_metadata.has(split_id):
            errors.append("split '%s' has no metadata" % split_id)
        elif not split_metadata[split_id] is Dictionary:
            errors.append("split '%s' metadata must be a dictionary" % split_id)

    for slot_id in slot_metadata:
        if not has_slot(str(slot_id)):
            errors.append("metadata references unknown slot '%s'" % slot_id)
    for split_id in split_metadata:
        if not has_split(str(split_id)):
            errors.append("metadata references unknown split '%s'" % split_id)

    var referenced_splits: Dictionary = {}
    for split_id in split_ids:
        var metadata = split_metadata.get(split_id, {})
        if not metadata is Dictionary:
            continue
        var orientation := str(metadata.get("orientation", ""))
        if not [ORIENTATION_HORIZONTAL, ORIENTATION_VERTICAL].has(orientation):
            errors.append("split '%s' has invalid orientation '%s'" % [split_id, orientation])
        var children = metadata.get("children", [])
        if not children is Array or children.size() < 2:
            errors.append("split '%s' must have at least two children" % split_id)
            continue

        var seen_children: Dictionary = {}
        for child in children:
            if not child is String:
                errors.append("split '%s' children must contain strings" % split_id)
                continue
            var child_id := str(child)
            if seen_children.has(child_id):
                errors.append("split '%s' contains duplicate child '%s'" % [split_id, child_id])
            seen_children[child_id] = true
            if child_id == "workspace":
                continue
            if has_split(child_id):
                referenced_splits[child_id] = true
            elif not has_slot(child_id):
                errors.append("split '%s' references unknown child '%s'" % [split_id, child_id])

        var default_offsets = metadata.get("default_offsets", [])
        var expected_offsets: int = int(children.size()) - 1
        if not default_offsets is Array or default_offsets.size() != expected_offsets:
            errors.append("split '%s' must contain %d default offsets" % [split_id, expected_offsets])
        elif not _all_finite_numbers(default_offsets):
            errors.append("split '%s' default offsets must contain finite numbers" % split_id)

    var cycle_errors := _validate_split_cycles()
    errors.append_array(cycle_errors)
    return errors

func _validate_split_cycles() -> Array:
    var errors: Array = []
    var visiting: Dictionary = {}
    var visited: Dictionary = {}
    for split_id in split_ids:
        var key := str(split_id)
        if not visited.has(key):
            _visit_split(key, visiting, visited, errors)
    return errors

func _visit_split(split_id: String, visiting: Dictionary, visited: Dictionary, errors: Array) -> void:
    if visiting.has(split_id):
        errors.append("split topology contains a cycle at '%s'" % split_id)
        return
    if visited.has(split_id):
        return
    visiting[split_id] = true
    var metadata = split_metadata.get(split_id, {})
    if metadata is Dictionary:
        var children = metadata.get("children", [])
        if children is Array:
            for child in children:
                var child_id := str(child)
                if has_split(child_id):
                    _visit_split(child_id, visiting, visited, errors)
    visiting.erase(split_id)
    visited[split_id] = true

func _all_finite_numbers(values: Array) -> bool:
    for value in values:
        if not (value is int or value is float):
            return false
        var number := float(value)
        if is_nan(number) or is_inf(number):
            return false
    return true

static func _is_valid_id(value: String) -> bool:
    var regex := RegEx.new()
    return regex.compile(ID_PATTERN) == OK and regex.search(value) != null
