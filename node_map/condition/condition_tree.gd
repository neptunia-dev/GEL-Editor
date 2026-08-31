extends RefCounted
class_name ConditionTree

const RUNTIME_PORT_PREFIX := "__gel.condition."

var root_wrapper_id: String
var last_error: String = ""
var last_removed_branch_ids: Array = []

var _wrappers: Dictionary = {}
var _branches: Dictionary = {}
var _duplicate_wrapper_ids: Array = []
var _duplicate_branch_ids: Array = []

func _init(
        p_root_wrapper_id: String = "",
        p_wrappers: Array = [],
        p_branches: Array = [],
) -> void:
    root_wrapper_id = p_root_wrapper_id
    for wrapper in p_wrappers:
        if wrapper is ConditionWrapper:
            if _wrappers.has(wrapper.wrapper_id):
                _duplicate_wrapper_ids.append(wrapper.wrapper_id)
            else:
                _wrappers[wrapper.wrapper_id] = (wrapper as ConditionWrapper).duplicate_wrapper()
    for branch in p_branches:
        if branch is ConditionBranch:
            if _branches.has(branch.branch_id):
                _duplicate_branch_ids.append(branch.branch_id)
            else:
                _branches[branch.branch_id] = (branch as ConditionBranch).duplicate_branch()

func add_wrapper(wrapper: ConditionWrapper) -> bool:
    if wrapper == null:
        return _fail("wrapper must not be null")
    var errors := wrapper.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    if _wrappers.has(wrapper.wrapper_id):
        return _fail("wrapper_id '%s' already exists" % wrapper.wrapper_id)
    if not (wrapper is IfWrapper or wrapper is SwitchCaseWrapper or wrapper is NumericCompareWrapper):
        return _fail("unsupported wrapper type")
    _wrappers[wrapper.wrapper_id] = wrapper.duplicate_wrapper()
    _clear_error()
    return true

func add_branch(branch: ConditionBranch) -> bool:
    if branch == null:
        return _fail("branch must not be null")
    var errors := branch.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    if _branches.has(branch.branch_id):
        return _fail("branch_id '%s' already exists" % branch.branch_id)
    _branches[branch.branch_id] = branch.duplicate_branch()
    _clear_error()
    return true

func set_root(wrapper_id: String) -> bool:
    if not _wrappers.has(wrapper_id):
        return _fail("root wrapper '%s' does not exist" % wrapper_id)
    root_wrapper_id = wrapper_id
    _clear_error()
    return true

func get_wrapper(wrapper_id: String) -> ConditionWrapper:
    if not _wrappers.has(wrapper_id):
        return null
    return (_wrappers[wrapper_id] as ConditionWrapper).duplicate_wrapper()

func get_branch(branch_id: String) -> ConditionBranch:
    if not _branches.has(branch_id):
        return null
    return (_branches[branch_id] as ConditionBranch).duplicate_branch()

func get_wrappers() -> Array:
    var result: Array = []
    for wrapper_id in _sorted_wrapper_ids():
        result.append((_wrappers[wrapper_id] as ConditionWrapper).duplicate_wrapper())
    return result

func get_branches() -> Array:
    var result: Array = []
    for branch_id in _sorted_branch_ids():
        result.append((_branches[branch_id] as ConditionBranch).duplicate_branch())
    return result

func get_all_branch_ids() -> Array:
    return _sorted_branch_ids()

func find_owner_wrapper_id(branch_id: String) -> String:
    for wrapper_id in _sorted_wrapper_ids():
        var wrapper := _wrappers[wrapper_id] as ConditionWrapper
        if wrapper.get_branch_ids().has(branch_id):
            return wrapper_id
    return ""

func is_leaf_branch(wrapper_id: String, branch_id: String) -> bool:
    if not _wrappers.has(wrapper_id) or not _branches.has(branch_id):
        return false
    var wrapper := _wrappers[wrapper_id] as ConditionWrapper
    if not wrapper.get_branch_ids().has(branch_id):
        return false
    return (_branches[branch_id] as ConditionBranch).is_terminal()

func get_leaf_endpoints() -> Array:
    if not _wrappers.has(root_wrapper_id):
        return []
    var result: Array = []
    _collect_leaf_endpoints(root_wrapper_id, result, {})
    return result

func runtime_port(wrapper_id: String, branch_id: String) -> String:
    return "%s%s.%s" % [RUNTIME_PORT_PREFIX, wrapper_id, branch_id]

## 更新 switch case 的展示和值；稳定 branch_id 和所有 RouteEdge 都保持不变。
func update_switch_case(branch_id: String, value: Variant, label: String) -> bool:
    if not _branches.has(branch_id):
        return _fail("branch_id '%s' does not exist" % branch_id)
    var owner_id := find_owner_wrapper_id(branch_id)
    if owner_id.is_empty() or not (_wrappers[owner_id] is SwitchCaseWrapper):
        return _fail("branch '%s' is not a switch case" % branch_id)
    var wrapper := _wrappers[owner_id] as SwitchCaseWrapper
    if wrapper.default_branch_id == branch_id:
        return _fail("the switch default branch has no match value")
    var candidate := ConditionBranch.new(
        branch_id, label.strip_edges(),
        (_branches[branch_id] as ConditionBranch).child_wrapper_id,
        true, value,
    )
    var candidate_errors := candidate.validate_self()
    if not candidate_errors.is_empty():
        return _fail(str(candidate_errors[0]))
    var key := ConditionBranch.scalar_key(value)
    for other_id in wrapper.case_branch_ids:
        if other_id == branch_id or not _branches.has(other_id):
            continue
        var other := _branches[other_id] as ConditionBranch
        if other.has_match_value and ConditionBranch.scalar_key(other.match_value) == key:
            return _fail("switch contains duplicate case value")
    _branches[branch_id] = candidate
    _clear_error()
    return true

## 在指定 switch 的 default 之前追加一个稳定 case branch。
func add_switch_case(wrapper_id: String, branch: ConditionBranch) -> bool:
    if not _wrappers.has(wrapper_id) or not (_wrappers[wrapper_id] is SwitchCaseWrapper):
        return _fail("wrapper '%s' is not a switch" % wrapper_id)
    if branch == null or not branch.has_match_value:
        return _fail("switch case branch must have a match value")
    var candidate := duplicate_tree()
    if not candidate.add_branch(branch):
        return _fail(candidate.last_error)
    var wrapper := candidate._wrappers[wrapper_id] as SwitchCaseWrapper
    wrapper.case_branch_ids.append(branch.branch_id)
    var errors := candidate.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    _copy_from(candidate)
    _clear_error()
    return true

## 用同一稳定 ID 的完整 wrapper 替换现有定义。分支引用必须继续组成合法树。
func update_wrapper(wrapper: ConditionWrapper) -> bool:
    if wrapper == null or not _wrappers.has(wrapper.wrapper_id):
        return _fail("wrapper does not exist")
    if not (wrapper is IfWrapper or wrapper is SwitchCaseWrapper or wrapper is NumericCompareWrapper):
        return _fail("unsupported wrapper type")
    var candidate := duplicate_tree()
    candidate._wrappers[wrapper.wrapper_id] = wrapper.duplicate_wrapper()
    var errors := candidate.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    _copy_from(candidate)
    _clear_error()
    return true

## 更新 branch 草稿，同时保留 branch_id、child wrapper 和 RouteEdge 身份。
func update_branch_value(
        branch_id: String,
        label: String,
        has_match_value: bool,
        match_value: Variant = null,
) -> bool:
    if not _branches.has(branch_id):
        return _fail("branch_id '%s' does not exist" % branch_id)
    var existing := _branches[branch_id] as ConditionBranch
    var candidate_branch := ConditionBranch.new(
        branch_id, label.strip_edges(), existing.child_wrapper_id,
        has_match_value, match_value,
    )
    var candidate := duplicate_tree()
    candidate._branches[branch_id] = candidate_branch
    var errors := candidate.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    _copy_from(candidate)
    _clear_error()
    return true

## 将一个完整的新 wrapper 挂到现有叶子 branch；失败时不改变原树。
func attach_child_wrapper(
        parent_branch_id: String,
        wrapper: ConditionWrapper,
        branches: Array,
) -> bool:
    if not _branches.has(parent_branch_id):
        return _fail("branch_id '%s' does not exist" % parent_branch_id)
    if not (_branches[parent_branch_id] as ConditionBranch).is_terminal():
        return _fail("branch '%s' already has a child wrapper" % parent_branch_id)
    if wrapper == null:
        return _fail("wrapper must not be null")

    var candidate := duplicate_tree()
    if not candidate.add_wrapper(wrapper):
        return _fail(candidate.last_error)
    for branch in branches:
        if not branch is ConditionBranch:
            return _fail("child wrapper branches must be ConditionBranch values")
        if not candidate.add_branch(branch):
            return _fail(candidate.last_error)
    (candidate._branches[parent_branch_id] as ConditionBranch).child_wrapper_id = wrapper.wrapper_id
    var errors := candidate.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    _copy_from(candidate)
    _clear_error()
    return true

## 仅 switch case 可以单独删除；固定分支和 default 必须随 wrapper 一起删除。
func remove_branch(branch_id: String) -> bool:
    last_removed_branch_ids = []
    if not _branches.has(branch_id):
        return _fail("branch_id '%s' does not exist" % branch_id)
    var owner_id := find_owner_wrapper_id(branch_id)
    if owner_id.is_empty() or not (_wrappers[owner_id] is SwitchCaseWrapper):
        return _fail("only a switch case branch can be removed independently")
    var owner := _wrappers[owner_id] as SwitchCaseWrapper
    if owner.default_branch_id == branch_id:
        return _fail("the switch default branch cannot be removed")

    var branch := _branches[branch_id] as ConditionBranch
    if not branch.child_wrapper_id.is_empty():
        _remove_wrapper_subtree(branch.child_wrapper_id)
    owner.remove_case_branch(branch_id)
    _branches.erase(branch_id)
    last_removed_branch_ids.append(branch_id)
    _clear_error()
    return true

## 删除非根 wrapper 及其子树；父分支保留并变为需要连接目标 Scene 的叶子。
func remove_wrapper(wrapper_id: String) -> bool:
    last_removed_branch_ids = []
    if not _wrappers.has(wrapper_id):
        return _fail("wrapper_id '%s' does not exist" % wrapper_id)
    if wrapper_id == root_wrapper_id:
        return _fail("the root wrapper cannot be removed; clear the condition tree instead")

    var parent_branch_id := ""
    for branch_id in _sorted_branch_ids():
        if (_branches[branch_id] as ConditionBranch).child_wrapper_id == wrapper_id:
            parent_branch_id = branch_id
            break
    if parent_branch_id.is_empty():
        return _fail("wrapper '%s' is not attached to the root tree" % wrapper_id)

    (_branches[parent_branch_id] as ConditionBranch).child_wrapper_id = ""
    _remove_wrapper_subtree(wrapper_id)
    _clear_error()
    return true

func duplicate_tree() -> ConditionTree:
    var result := ConditionTree.new(root_wrapper_id, get_wrappers(), get_branches())
    result._duplicate_wrapper_ids = _duplicate_wrapper_ids.duplicate()
    result._duplicate_branch_ids = _duplicate_branch_ids.duplicate()
    return result

func validate_self(path: String = "condition_tree") -> Array:
    var errors: Array = []
    for wrapper_id in _duplicate_wrapper_ids:
        errors.append("%s contains duplicate wrapper_id '%s'" % [path, wrapper_id])
    for branch_id in _duplicate_branch_ids:
        errors.append("%s contains duplicate branch_id '%s'" % [path, branch_id])
    if root_wrapper_id.is_empty():
        errors.append("%s.root_wrapper_id must not be empty" % path)
    elif not _wrappers.has(root_wrapper_id):
        errors.append("%s root wrapper '%s' does not exist" % [path, root_wrapper_id])

    var branch_owners: Dictionary = {}
    var child_incoming: Dictionary = {}
    for wrapper_id in _sorted_wrapper_ids():
        var wrapper := _wrappers[wrapper_id] as ConditionWrapper
        errors.append_array(wrapper.validate_self("%s.wrappers.%s" % [path, wrapper_id]))
        for branch_id in wrapper.get_branch_ids():
            if not _branches.has(branch_id):
                errors.append("%s wrapper '%s' references missing branch '%s'" % [path, wrapper_id, branch_id])
                continue
            if branch_owners.has(branch_id):
                errors.append("%s branch '%s' is shared by wrappers '%s' and '%s'" % [path, branch_id, branch_owners[branch_id], wrapper_id])
            else:
                branch_owners[branch_id] = wrapper_id

            var branch := _branches[branch_id] as ConditionBranch
            if not branch.child_wrapper_id.is_empty():
                if not _wrappers.has(branch.child_wrapper_id):
                    errors.append("%s branch '%s' references missing child wrapper '%s'" % [path, branch_id, branch.child_wrapper_id])
                else:
                    child_incoming[branch.child_wrapper_id] = int(child_incoming.get(branch.child_wrapper_id, 0)) + 1

        if wrapper is SwitchCaseWrapper:
            var switch_wrapper := wrapper as SwitchCaseWrapper
            var case_values: Dictionary = {}
            for branch_id in switch_wrapper.case_branch_ids:
                if not _branches.has(branch_id):
                    continue
                var branch := _branches[branch_id] as ConditionBranch
                if not branch.has_match_value:
                    errors.append("%s switch case branch '%s' is missing match_value" % [path, branch_id])
                    continue
                var case_key := ConditionBranch.scalar_key(branch.match_value)
                if case_values.has(case_key):
                    errors.append("%s switch '%s' contains duplicate case value" % [path, wrapper_id])
                case_values[case_key] = true
            if _branches.has(switch_wrapper.default_branch_id):
                var default_branch := _branches[switch_wrapper.default_branch_id] as ConditionBranch
                if default_branch.has_match_value:
                    errors.append("%s switch default branch '%s' must not have match_value" % [path, switch_wrapper.default_branch_id])
        else:
            for branch_id in wrapper.get_branch_ids():
                if _branches.has(branch_id) and (_branches[branch_id] as ConditionBranch).has_match_value:
                    errors.append("%s non-switch branch '%s' must not have match_value" % [path, branch_id])

    for branch_id in _sorted_branch_ids():
        var branch := _branches[branch_id] as ConditionBranch
        errors.append_array(branch.validate_self("%s.branches.%s" % [path, branch_id]))
        if not branch_owners.has(branch_id):
            errors.append("%s branch '%s' is not owned by a wrapper" % [path, branch_id])

    for wrapper_id in child_incoming:
        if int(child_incoming[wrapper_id]) > 1:
            errors.append("%s wrapper '%s' is shared by multiple branches" % [path, wrapper_id])
    if child_incoming.has(root_wrapper_id):
        errors.append("%s root wrapper '%s' must not be a child" % [path, root_wrapper_id])

    if _wrappers.has(root_wrapper_id):
        var visit_state: Dictionary = {}
        var reachable: Dictionary = {}
        _validate_dfs(root_wrapper_id, visit_state, reachable, errors, path)
        for wrapper_id in _sorted_wrapper_ids():
            if not reachable.has(wrapper_id):
                errors.append("%s wrapper '%s' is not reachable from the root" % [path, wrapper_id])
    return errors

func to_editor_dict() -> Dictionary:
    var wrappers_data: Array = []
    for wrapper_id in _sorted_wrapper_ids():
        wrappers_data.append((_wrappers[wrapper_id] as ConditionWrapper).to_editor_dict())
    var branches_data: Array = []
    for branch_id in _sorted_branch_ids():
        branches_data.append((_branches[branch_id] as ConditionBranch).to_editor_dict())
    return {
        "rootWrapperId": root_wrapper_id,
        "wrappers": wrappers_data,
        "branches": branches_data,
    }

func _validate_dfs(
        wrapper_id: String,
        visit_state: Dictionary,
        reachable: Dictionary,
        errors: Array,
        path: String,
) -> void:
    if int(visit_state.get(wrapper_id, 0)) == 1:
        errors.append("%s contains a wrapper cycle at '%s'" % [path, wrapper_id])
        return
    if int(visit_state.get(wrapper_id, 0)) == 2:
        return
    visit_state[wrapper_id] = 1
    reachable[wrapper_id] = true
    var wrapper := _wrappers[wrapper_id] as ConditionWrapper
    for branch_id in wrapper.get_branch_ids():
        if not _branches.has(branch_id):
            continue
        var child_id := (_branches[branch_id] as ConditionBranch).child_wrapper_id
        if not child_id.is_empty() and _wrappers.has(child_id):
            _validate_dfs(child_id, visit_state, reachable, errors, path)
    visit_state[wrapper_id] = 2

func _collect_leaf_endpoints(wrapper_id: String, result: Array, visited: Dictionary) -> void:
    if visited.has(wrapper_id) or not _wrappers.has(wrapper_id):
        return
    visited[wrapper_id] = true
    var wrapper := _wrappers[wrapper_id] as ConditionWrapper
    for branch_id in wrapper.get_branch_ids():
        if not _branches.has(branch_id):
            continue
        var branch := _branches[branch_id] as ConditionBranch
        if branch.is_terminal():
            result.append({
                "wrapperId": wrapper_id,
                "branchId": branch_id,
                "port": runtime_port(wrapper_id, branch_id),
            })
        else:
            _collect_leaf_endpoints(branch.child_wrapper_id, result, visited)

func _remove_wrapper_subtree(wrapper_id: String) -> void:
    if not _wrappers.has(wrapper_id):
        return
    var wrapper := _wrappers[wrapper_id] as ConditionWrapper
    for branch_id in wrapper.get_branch_ids():
        if not _branches.has(branch_id):
            continue
        var child_id := (_branches[branch_id] as ConditionBranch).child_wrapper_id
        if not child_id.is_empty():
            _remove_wrapper_subtree(child_id)
        _branches.erase(branch_id)
        last_removed_branch_ids.append(branch_id)
    _wrappers.erase(wrapper_id)

func _sorted_wrapper_ids() -> Array:
    var ids := _wrappers.keys()
    ids.sort()
    return ids

func _sorted_branch_ids() -> Array:
    var ids := _branches.keys()
    ids.sort()
    return ids

func _copy_from(other: ConditionTree) -> void:
    root_wrapper_id = other.root_wrapper_id
    _wrappers = {}
    _branches = {}
    for wrapper in other.get_wrappers():
        _wrappers[wrapper.wrapper_id] = wrapper.duplicate_wrapper()
    for branch in other.get_branches():
        _branches[branch.branch_id] = branch.duplicate_branch()
    _duplicate_wrapper_ids = other._duplicate_wrapper_ids.duplicate()
    _duplicate_branch_ids = other._duplicate_branch_ids.duplicate()

func _fail(message: String) -> bool:
    last_error = message
    return false

func _clear_error() -> void:
    last_error = ""
