extends RefCounted
class_name RouteEdge

const SOURCE_SCENE_EXIT := "scene_exit"
const SOURCE_CONDITION_BRANCH := "condition_branch"

var edge_id: String
var source_node_id: String
var source_kind: String
var source_port_id: String
var source_wrapper_id: String
var source_branch_id: String
var target_node_id: String
var last_error: String = ""

## 前四个参数保持旧式 Scene exit RouteEdge.new(...) 调用兼容。
func _init(
        p_edge_id: String = "",
        p_source_node_id: String = "",
        p_source_port_id: String = "",
        p_target_node_id: String = "",
        p_source_kind: String = SOURCE_SCENE_EXIT,
        p_source_wrapper_id: String = "",
        p_source_branch_id: String = "",
) -> void:
    edge_id = p_edge_id
    source_node_id = p_source_node_id
    source_port_id = p_source_port_id
    target_node_id = p_target_node_id
    source_kind = p_source_kind
    source_wrapper_id = p_source_wrapper_id
    source_branch_id = p_source_branch_id

static func from_condition_branch(
        p_edge_id: String,
        p_source_node_id: String,
        p_source_wrapper_id: String,
        p_source_branch_id: String,
        p_target_node_id: String,
) -> RouteEdge:
    return RouteEdge.new(
        p_edge_id, p_source_node_id, "", p_target_node_id,
        SOURCE_CONDITION_BRANCH, p_source_wrapper_id, p_source_branch_id,
    )

func duplicate_edge() -> RouteEdge:
    return RouteEdge.new(
        edge_id, source_node_id, source_port_id, target_node_id,
        source_kind, source_wrapper_id, source_branch_id,
    )

func validate_self(path: String = "edge") -> Array:
    var errors: Array = []
    for field in [
        ["edge_id", edge_id],
        ["source_node_id", source_node_id],
        ["target_node_id", target_node_id],
    ]:
        var value := str(field[1])
        if value.is_empty():
            errors.append("%s.%s must not be empty" % [path, field[0]])
        elif value != value.strip_edges():
            errors.append("%s.%s must not have surrounding whitespace" % [path, field[0]])

    if source_kind == SOURCE_SCENE_EXIT:
        if source_port_id.is_empty():
            errors.append("%s.source_port_id must not be empty for scene_exit" % path)
        if not source_wrapper_id.is_empty() or not source_branch_id.is_empty():
            errors.append("%s scene_exit must not use condition endpoint fields" % path)
    elif source_kind == SOURCE_CONDITION_BRANCH:
        if source_wrapper_id.is_empty():
            errors.append("%s.source_wrapper_id must not be empty for condition_branch" % path)
        if source_branch_id.is_empty():
            errors.append("%s.source_branch_id must not be empty for condition_branch" % path)
        if not source_port_id.is_empty():
            errors.append("%s condition_branch must not use source_port_id" % path)
    else:
        errors.append("%s.source_kind must be 'scene_exit' or 'condition_branch'" % path)
    return errors

func references_node(node_id: String) -> bool:
    return source_node_id == node_id or target_node_id == node_id

func starts_at_scene_exit(source_id: String, port_id: String) -> bool:
    return source_kind == SOURCE_SCENE_EXIT and source_node_id == source_id and source_port_id == port_id

func starts_at_condition_branch(source_id: String, wrapper_id: String, branch_id: String) -> bool:
    return (
        source_kind == SOURCE_CONDITION_BRANCH
        and source_node_id == source_id
        and source_wrapper_id == wrapper_id
        and source_branch_id == branch_id
    )

func source_endpoint_key() -> String:
    if source_kind == SOURCE_CONDITION_BRANCH:
        return "%s::condition::%s::%s" % [source_node_id, source_wrapper_id, source_branch_id]
    return "%s::exit::%s" % [source_node_id, source_port_id]

func to_editor_dict() -> Dictionary:
    var result: Dictionary = {
        "edgeId": edge_id,
        "sourceNodeId": source_node_id,
        "sourceKind": source_kind,
        "targetNodeId": target_node_id,
    }
    if source_kind == SOURCE_CONDITION_BRANCH:
        result["sourceWrapperId"] = source_wrapper_id
        result["sourceBranchId"] = source_branch_id
    else:
        result["sourcePortId"] = source_port_id
    return result
