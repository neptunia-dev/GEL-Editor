extends RefCounted
class_name NodeMapController

signal scene_map_changed
signal selection_changed(kind: String, stable_id: Variant)
signal operation_failed(message: String)

var _scene_map: SceneMap = SceneMap.new()
var _selection_kind: String = "none"
var _selection_id: Variant = ""
var last_error: String = ""

func set_scene_map(scene_map: SceneMap) -> void:
    _scene_map = scene_map.duplicate_map() if scene_map != null else SceneMap.new()
    clear_selection()
    _clear_error()
    scene_map_changed.emit()

## 返回副本，避免 runtime View 绕过控制器修改聚合根。
func get_scene_map() -> SceneMap:
    return _scene_map.duplicate_map()

func get_scene(node_id: String) -> SceneNode:
    return _scene_map.get_node(node_id)

func get_route(edge_id: String) -> RouteEdge:
    return _scene_map.get_route(edge_id)

func create_scene(scene_id: String, title: String, position: Vector2) -> SceneNode:
    var node := SceneNode.new(_new_id("node"), scene_id, title.strip_edges(), "", [], [], position)
    if not _scene_map.add_node(node):
        _fail(_scene_map.last_error)
        return null
    if _scene_map.get_node_count() == 1 and not _scene_map.set_entry_node(node.node_id):
        _fail(_scene_map.last_error)
        return null
    _changed()
    return _scene_map.get_node(node.node_id)

func update_scene(node: SceneNode) -> bool:
    if not _scene_map.update_node(node):
        return _fail(_scene_map.last_error)
    _changed()
    return true

func remove_scene(node_id: String) -> bool:
    if not _scene_map.remove_node(node_id):
        return _fail(_scene_map.last_error)
    if _selection_kind == "scene" and str(_selection_id) == node_id:
        clear_selection()
    _changed()
    return true

func connect_endpoint(endpoint: Dictionary, target_node_id: String) -> RouteEdge:
    var source_node_id := str(endpoint.get("nodeId", ""))
    var edge_id := _new_id("edge")
    var edge: RouteEdge
    if str(endpoint.get("kind", "")) == RouteEdge.SOURCE_SCENE_EXIT:
        edge = RouteEdge.new(
            edge_id, source_node_id, str(endpoint.get("portId", "")), target_node_id,
        )
    elif str(endpoint.get("kind", "")) == RouteEdge.SOURCE_CONDITION_BRANCH:
        edge = RouteEdge.from_condition_branch(
            edge_id, source_node_id,
            str(endpoint.get("wrapperId", "")),
            str(endpoint.get("branchId", "")),
            target_node_id,
        )
    else:
        _fail("unsupported route endpoint")
        return null
    if not _scene_map.add_route(edge):
        _fail(_scene_map.last_error)
        return null
    _changed()
    return _scene_map.get_route(edge_id)

func remove_route(edge_id: String) -> bool:
    if not _scene_map.remove_route(edge_id):
        return _fail(_scene_map.last_error)
    if _selection_kind == "edge" and str(_selection_id) == edge_id:
        clear_selection()
    _changed()
    return true

## 所有位置先在 Map 副本上更新，全部成功后一次提交并只发一个 changed 信号。
func commit_node_positions(positions: Dictionary) -> bool:
    var candidate := _scene_map.duplicate_map()
    for node_id in positions:
        var node := candidate.get_node(str(node_id))
        if node == null or not positions[node_id] is Vector2:
            return _fail("invalid node position draft for '%s'" % node_id)
        node.set_position(positions[node_id])
        if not candidate.update_node(node):
            return _fail(candidate.last_error)
    _scene_map = candidate
    _changed()
    return true

func set_entry_scene(node_id: String, enabled: bool) -> bool:
    if enabled:
        if not _scene_map.set_entry_node(node_id):
            return _fail(_scene_map.last_error)
    elif _scene_map.get_entry_node_id() == node_id:
        _scene_map.clear_entry_node()
    _changed()
    return true

func remove_exit(node_id: String, port_id: String) -> bool:
    if not _scene_map.remove_exit(node_id, port_id):
        return _fail(_scene_map.last_error)
    _changed()
    return true

func remove_condition_branch(node_id: String, branch_id: String) -> bool:
    if not _scene_map.remove_condition_branch(node_id, branch_id):
        return _fail(_scene_map.last_error)
    _changed()
    return true

func remove_condition_wrapper(node_id: String, wrapper_id: String) -> bool:
    if not _scene_map.remove_condition_wrapper(node_id, wrapper_id):
        return _fail(_scene_map.last_error)
    _changed()
    return true

func update_wrapper(node_id: String, wrapper: ConditionWrapper) -> bool:
    var node := _scene_map.get_node(node_id)
    if node == null or not node.has_condition_tree():
        return _fail("condition tree does not exist")
    var tree := node.get_condition_tree()
    if not tree.update_wrapper(wrapper):
        return _fail(tree.last_error)
    if not node.set_condition_tree(tree):
        return _fail(node.last_error)
    return update_scene(node)

func update_branch(
        node_id: String,
        branch_id: String,
        label: String,
        has_match_value: bool,
        match_value: Variant = null,
) -> bool:
    var node := _scene_map.get_node(node_id)
    if node == null or not node.has_condition_tree():
        return _fail("condition tree does not exist")
    var tree := node.get_condition_tree()
    if not tree.update_branch_value(branch_id, label, has_match_value, match_value):
        return _fail(tree.last_error)
    if not node.set_condition_tree(tree):
        return _fail(node.last_error)
    return update_scene(node)

func add_root_wrapper(node_id: String, wrapper_kind: String) -> bool:
    var node := _scene_map.get_node(node_id)
    if node == null:
        return _fail("Scene does not exist")
    if node.has_condition_tree():
        return _fail("Scene already has a root wrapper")
    var bundle := _create_wrapper_bundle(wrapper_kind)
    if bundle.is_empty():
        return _fail("unsupported wrapper type '%s'" % wrapper_kind)
    var wrapper := bundle["wrapper"] as ConditionWrapper
    var tree := ConditionTree.new(wrapper.wrapper_id, [wrapper], bundle["branches"])
    var errors := tree.validate_self()
    if not errors.is_empty():
        return _fail(str(errors[0]))
    if not node.set_condition_tree(tree):
        return _fail(node.last_error)
    return update_scene(node)

func add_switch_case(node_id: String, wrapper_id: String) -> bool:
    var node := _scene_map.get_node(node_id)
    if node == null or not node.has_condition_tree():
        return _fail("condition tree does not exist")
    var tree := node.get_condition_tree()
    var wrapper := tree.get_wrapper(wrapper_id)
    if not wrapper is SwitchCaseWrapper:
        return _fail("wrapper is not a switch")
    var switch_wrapper := wrapper as SwitchCaseWrapper
    var case_number := switch_wrapper.case_branch_ids.size() + 1
    var match_value: Variant = "new_case_%d" % case_number
    while _switch_has_value(tree, switch_wrapper, match_value):
        case_number += 1
        match_value = "new_case_%d" % case_number
    var branch := ConditionBranch.new(
        _new_id("branch"), "New case %d" % case_number, "", true, match_value,
    )
    if not tree.add_switch_case(wrapper_id, branch):
        return _fail(tree.last_error)
    if not node.set_condition_tree(tree):
        return _fail(node.last_error)
    return update_scene(node)

func add_child_wrapper(node_id: String, branch_id: String, wrapper_kind: String) -> bool:
    var node := _scene_map.get_node(node_id)
    if node == null or not node.has_condition_tree():
        return _fail("condition tree does not exist")
    var tree := node.get_condition_tree()
    var bundle := _create_wrapper_bundle(wrapper_kind)
    if bundle.is_empty():
        return _fail("unsupported wrapper type '%s'" % wrapper_kind)
    var wrapper := bundle["wrapper"] as ConditionWrapper
    var branches := bundle["branches"] as Array

    if not tree.attach_child_wrapper(branch_id, wrapper, branches):
        return _fail(tree.last_error)
    if not node.set_condition_tree(tree):
        return _fail(node.last_error)
    return update_scene(node)

func _create_wrapper_bundle(wrapper_kind: String) -> Dictionary:
    var wrapper_id := _new_id("wrapper")
    var wrapper: ConditionWrapper
    var branches: Array = []
    if wrapper_kind == "if":
        var true_id := _new_id("branch")
        var false_id := _new_id("branch")
        wrapper = IfWrapper.new(wrapper_id, "flags.condition", true_id, false_id)
        branches = [ConditionBranch.new(true_id, "true"), ConditionBranch.new(false_id, "false")]
    elif wrapper_kind == "switch":
        var case_id := _new_id("branch")
        var default_id := _new_id("branch")
        wrapper = SwitchCaseWrapper.new(wrapper_id, "state.value", [case_id], default_id)
        branches = [
            ConditionBranch.new(case_id, "case", "", true, "value"),
            ConditionBranch.new(default_id, "default"),
        ]
    elif wrapper_kind == "numeric_compare":
        var less_id := _new_id("branch")
        var equal_id := _new_id("branch")
        var greater_id := _new_id("branch")
        wrapper = NumericCompareWrapper.new(
            wrapper_id, NumericOperand.constant(0), NumericOperand.constant(0),
            less_id, equal_id, greater_id,
        )
        branches = [
            ConditionBranch.new(less_id, "<"),
            ConditionBranch.new(equal_id, "="),
            ConditionBranch.new(greater_id, ">"),
        ]
    else:
        return {}
    return {"wrapper": wrapper, "branches": branches}

func _switch_has_value(tree: ConditionTree, wrapper: SwitchCaseWrapper, value: Variant) -> bool:
    var key := ConditionBranch.scalar_key(value)
    for branch_id in wrapper.case_branch_ids:
        var branch := tree.get_branch(str(branch_id))
        if branch != null and branch.has_match_value and ConditionBranch.scalar_key(branch.match_value) == key:
            return true
    return false

func remove_branch_subtree(node_id: String, branch_id: String) -> bool:
    var node := _scene_map.get_node(node_id)
    if node == null or not node.has_condition_tree():
        return _fail("condition tree does not exist")
    var branch := node.get_condition_tree().get_branch(branch_id)
    if branch == null or branch.child_wrapper_id.is_empty():
        return _fail("branch has no child wrapper")
    return remove_condition_wrapper(node_id, branch.child_wrapper_id)

func select_object(kind: String, stable_id: Variant) -> void:
    _selection_kind = kind
    _selection_id = stable_id
    selection_changed.emit(kind, stable_id)

func clear_selection() -> void:
    _selection_kind = "none"
    _selection_id = ""
    selection_changed.emit(_selection_kind, _selection_id)

func _new_id(prefix: String) -> String:
    var bytes := Crypto.new().generate_random_bytes(16)
    return "%s-%s" % [prefix, bytes.hex_encode()]

func _changed() -> void:
    _clear_error()
    scene_map_changed.emit()

func _fail(message: String) -> bool:
    last_error = message
    operation_failed.emit(message)
    return false

func _clear_error() -> void:
    last_error = ""
