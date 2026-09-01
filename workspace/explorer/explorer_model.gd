@tool
extends RefCounted
class_name EditorExplorerModel

const ENTRY_SCRIPT := preload("res://workspace/explorer/explorer_entry.gd")

## 通用 Explorer 的 UI 无关条目模型。
##
## 模型只保存外部数据源提供的条目树。set_entries() 会先校验完整候选树，再原子
## 替换内部状态。它不解释 metadata，不依赖 SceneMap、磁盘文件或具体业务类型。

signal changed(revision: int)

var last_error: String = ""
var _revision: int = 0
var _entries: Dictionary = {}
var _children: Dictionary = {}
var _root_id: String = ""

func set_entries(entries: Array, root_id: String = "") -> bool:
    var candidate: Dictionary = {}
    var errors: Array = []
    for raw_entry in entries:
        if not (raw_entry is RefCounted) or raw_entry.get_script() != ENTRY_SCRIPT:
            errors.append("explorer entries must be EditorExplorerEntry instances")
            continue
        var entry = raw_entry
        var entry_errors: Array = entry.validate_self()
        if not entry_errors.is_empty():
            errors.append_array(entry_errors)
            continue
        if candidate.has(entry.entry_id):
            errors.append("duplicate entry_id '%s'" % entry.entry_id)
            continue
        candidate[entry.entry_id] = entry.duplicate_entry()

    if errors.is_empty() and candidate.is_empty():
        errors.append("explorer model must contain at least one entry")

    var resolved_root_id := root_id
    if resolved_root_id.is_empty() and not candidate.is_empty():
        for entry_id in candidate:
            if str(candidate[entry_id].parent_id).is_empty():
                resolved_root_id = str(entry_id)
                break
    if errors.is_empty() and not candidate.has(resolved_root_id):
        errors.append("root entry '%s' does not exist" % resolved_root_id)
    elif errors.is_empty() and not candidate[resolved_root_id].is_container:
        errors.append("root entry '%s' must be a container" % resolved_root_id)
    elif errors.is_empty() and not str(candidate[resolved_root_id].parent_id).is_empty():
        errors.append("root entry '%s' must not have a parent" % resolved_root_id)

    var candidate_children: Dictionary = {}
    for entry_id in candidate:
        candidate_children[entry_id] = []
    for entry_id in candidate:
        var entry = candidate[entry_id]
        var parent_id := str(entry.parent_id)
        if parent_id.is_empty():
            if entry_id != resolved_root_id:
                errors.append("entry '%s' has no parent but is not the root" % entry_id)
            continue
        if not candidate.has(parent_id):
            errors.append("entry '%s' references missing parent '%s'" % [entry_id, parent_id])
            continue
        var parent = candidate[parent_id]
        if not parent.is_container:
            errors.append("entry '%s' parent '%s' is not a container" % [entry_id, parent_id])
            continue
        (candidate_children[parent_id] as Array).append(entry_id)

    if errors.is_empty():
        for parent_id in candidate_children:
            var child_ids: Array = candidate_children[parent_id]
            child_ids.sort_custom(Callable(self, "_compare_entry_ids_for_candidate").bind(candidate))
        errors.append_array(_validate_tree(candidate, candidate_children, resolved_root_id))

    if not errors.is_empty():
        return _fail(str(errors[0]))

    _entries = candidate
    _children = candidate_children
    _root_id = resolved_root_id
    _revision += 1
    _clear_error()
    changed.emit(_revision)
    return true

func clear() -> void:
    _entries.clear()
    _children.clear()
    _root_id = ""
    _revision += 1
    _clear_error()
    changed.emit(_revision)

func get_revision() -> int:
    return _revision

func get_root_id() -> String:
    return _root_id

func get_root():
    return get_entry(_root_id)

func get_entry(entry_id: String):
    return _entries[entry_id].duplicate_entry() if _entries.has(entry_id) else null

func has_entry(entry_id: String) -> bool:
    return _entries.has(entry_id)

func get_entry_count() -> int:
    return _entries.size()

func matches_entry(entry_id: String, query: String) -> bool:
    if not _entries.has(entry_id):
        return false
    return (_entries[entry_id] as EditorExplorerEntry).matches_query(query)

func get_children(entry_id: String) -> Array:
    if not _children.has(entry_id):
        return []
    var result: Array = []
    for child_id in _children[entry_id]:
        result.append((_entries[child_id] as EditorExplorerEntry).duplicate_entry())
    return result

func find(query: String) -> Array:
    var result: Array = []
    for entry_id in _entries:
        var entry: EditorExplorerEntry = _entries[entry_id]
        if entry.matches_query(query):
            result.append(entry.duplicate_entry())
    result.sort_custom(Callable(self, "_compare_entries"))
    return result

func _validate_tree(entries: Dictionary, children: Dictionary, root_id: String) -> Array:
    var errors: Array = []
    var reachable: Dictionary = {}
    _visit_reachable(root_id, children, reachable)
    for entry_id in entries:
        if not reachable.has(entry_id):
            errors.append("entry '%s' is unreachable from root '%s'" % [entry_id, root_id])

    var visiting: Dictionary = {}
    var visited: Dictionary = {}
    for entry_id in entries:
        _visit_for_cycles(str(entry_id), children, visiting, visited, errors)
    return errors

func _visit_reachable(entry_id: String, children: Dictionary, reachable: Dictionary) -> void:
    if reachable.has(entry_id):
        return
    reachable[entry_id] = true
    for child_id in children.get(entry_id, []):
        _visit_reachable(str(child_id), children, reachable)

func _visit_for_cycles(entry_id: String, children: Dictionary, visiting: Dictionary, visited: Dictionary, errors: Array) -> void:
    if visiting.has(entry_id):
        errors.append("explorer tree contains a cycle at '%s'" % entry_id)
        return
    if visited.has(entry_id):
        return
    visiting[entry_id] = true
    for child_id in children.get(entry_id, []):
        _visit_for_cycles(str(child_id), children, visiting, visited, errors)
    visiting.erase(entry_id)
    visited[entry_id] = true

func _compare_entry_ids_for_candidate(left_id: String, right_id: String, candidate: Dictionary) -> bool:
    var left = candidate[left_id]
    var right = candidate[right_id]
    if left.is_container != right.is_container:
        return left.is_container
    var left_title: String = str(left.title).to_lower()
    var right_title: String = str(right.title).to_lower()
    if left_title != right_title:
        return left_title < right_title
    return str(left.entry_id) < str(right.entry_id)

func _compare_entries(left, right) -> bool:
    var left_title: String = str(left.title).to_lower()
    var right_title: String = str(right.title).to_lower()
    if left_title != right_title:
        return left_title < right_title
    return str(left.entry_id) < str(right.entry_id)

func _fail(message: String) -> bool:
    last_error = message
    return false

func _clear_error() -> void:
    last_error = ""
