extends SceneTree

const APPLICATION_SCENE := preload("res://app/node_map_application.tscn")
const DEMO_FACTORY := preload("res://app/demo_map_factory.gd")

var _checks: int = 0
var _failures: int = 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var application = APPLICATION_SCENE.instantiate()
    root.add_child(application)
    await process_frame
    await process_frame

    var controller = application.get_controller()
    var canvas = application.get_node_map_canvas()
    _check(application.get_scene_map().get_node_count() == 0, "standalone app starts with an empty map")

    var first = controller.create_scene("first", "", Vector2(80, 90))
    _check(first != null, "controller creates a Scene")
    _check(controller.get_scene_map().get_entry_node_id() == first.node_id, "first Scene becomes entry")
    _check(canvas.get_view_count() == 1, "canvas synchronizes created Scene")
    var first_view = canvas.get_scene_view(first.node_id)
    _check(first_view.title == "first", "empty title falls back to scene_id")
    _check(first_view.get_input_port_count() == 1, "Scene has a common input port")
    controller.select_object("scene", first.node_id)
    await process_frame
    _check(application.get_inspector()._fields.has("title"), "selecting a Scene builds the runtime Inspector")

    var source = controller.get_scene(first.node_id)
    source.add_exit(ExitPort.new("continue-id", "continue"))
    _check(controller.update_scene(source), "Scene exit update commits through controller")
    var target = controller.create_scene("target", "Target", Vector2(480, 90))
    first_view = canvas.get_scene_view(first.node_id)
    var target_view = canvas.get_scene_view(target.node_id)
    var endpoint = first_view.get_output_endpoint(0)
    _check(endpoint["kind"] == RouteEdge.SOURCE_SCENE_EXIT and endpoint["portId"] == "continue-id", "explicit slot restores stable port_id")
    var output_center = first_view.position + first_view.get_output_port_position(0)
    var input_center = target_view.position + target_view.get_input_port_position(0)
    _check(canvas._is_in_output_hotzone(first_view, 0, output_center), "output dot center is inside its expanded hotzone")
    _check(canvas._is_in_input_hotzone(target_view, 0, input_center), "input dot center is inside its expanded hotzone")
    first_view.update_port_hover(first_view.get_output_port_position(0))
    _check(first_view.get_hovered_output_port() == 0, "mouse over an output dot enables port highlight")
    _check(first_view.get_output_port_color(0) == first_view.PORT_HOVER_COLOR, "highlight changes the visible output port color")
    first_view.update_port_hover(Vector2(-100, -100))
    _check(first_view.get_hovered_output_port() == -1, "moving away clears output port highlight")
    canvas._on_connection_request(StringName(first.node_id), 0, StringName(target.node_id), 0)
    var edge = controller.get_scene_map().get_routes()[0]
    _check(edge != null and edge.source_kind == RouteEdge.SOURCE_SCENE_EXIT, "GraphEdit request creates a scene_exit RouteEdge")
    _check(controller.connect_endpoint(endpoint, target.node_id) == null, "occupied source endpoint rejects a second route")
    _check(controller.get_scene_map().get_route_count() == 1, "rejected duplicate route does not pollute model")

    source = controller.get_scene(first.node_id)
    source.add_exit(ExitPort.new("reverse-id", "reverse drag"))
    _check(controller.update_scene(source), "second output is available for reverse drag")
    first_view = canvas.get_scene_view(first.node_id)
    var reverse_port = first_view.find_output_port({
        "kind": RouteEdge.SOURCE_SCENE_EXIT,
        "nodeId": first.node_id,
        "portId": "reverse-id",
    })
    canvas._on_connection_drag_started(StringName(target.node_id), 0, false)
    canvas._on_connection_request(StringName(target.node_id), 0, StringName(first.node_id), reverse_port)
    canvas._on_connection_drag_ended()
    var reverse_edge: RouteEdge
    for candidate in controller.get_scene_map().get_routes():
        if candidate.source_port_id == "reverse-id":
            reverse_edge = candidate
            break
    _check(reverse_edge != null and reverse_edge.target_node_id == target.node_id, "dragging input to output creates the same directed route")

    var positions := {
        first.node_id: Vector2(150, 180),
        target.node_id: Vector2(620, 210),
    }
    _check(controller.commit_node_positions(positions), "multi-node positions commit as one operation")
    _check(controller.get_scene(first.node_id).position == Vector2(150, 180), "first moved position persisted")
    _check(controller.get_scene(target.node_id).position == Vector2(620, 210), "second moved position persisted")

    var before_invalid = controller.get_scene(first.node_id)
    application._apply_scene_draft({
        "nodeId": first.node_id,
        "title": "Corrupted",
        "sceneId": "Invalid Scene ID",
        "mainScript": before_invalid.main_script,
        "entry": true,
        "exits": "continue-id = continue",
    })
    _check(controller.get_scene(first.node_id).scene_id == "first", "invalid Inspector draft leaves model unchanged")
    _check(controller.get_scene(first.node_id).title == "", "invalid Inspector draft does not leak partial title")

    controller.set_scene_map(DEMO_FACTORY.create())
    await process_frame
    var demo_map = controller.get_scene_map()
    var demo_view = canvas.get_scene_view("node-start")
    _check(demo_map.get_node_count() == 6 and demo_map.get_route_count() == 6, "acceptance demo loads full in-memory graph")
    _check(demo_view.get_condition_output_count() == 5, "only five terminal condition branches create ports")
    _check(demo_view.get_output_port_count() == 6, "explicit exit and condition leaves coexist")
    _check(demo_view.find_output_port({
        "kind": RouteEdge.SOURCE_CONDITION_BRANCH,
        "nodeId": "node-start",
        "wrapperId": "wrapper-score",
        "branchId": "score-less",
    }) >= 0, "nested condition leaf restores wrapper/branch IDs")
    _check(demo_view.find_output_port({
        "kind": RouteEdge.SOURCE_CONDITION_BRANCH,
        "nodeId": "node-start",
        "wrapperId": "wrapper-met",
        "branchId": "met-true",
    }) == -1, "non-leaf branch has no output port")

    var continue_port = demo_view.find_output_port({
        "kind": RouteEdge.SOURCE_SCENE_EXIT,
        "nodeId": "node-start",
        "portId": "exit-continue",
    })
    var hover_point = (
        (demo_view.position_offset + demo_view.get_output_port_position(continue_port))
        * canvas.zoom - canvas.scroll_offset + Vector2(2, 0)
    )
    canvas._update_hover(hover_point)
    _check(canvas.get_hover_edge_id() == "edge-continue", "closest-connection hover resolves the stable RouteEdge ID")
    _check(canvas.tooltip_text == "continue → chapter-hub", "hover tooltip describes source and target Scenes")
    var edge_click := InputEventMouseButton.new()
    edge_click.button_index = MOUSE_BUTTON_LEFT
    edge_click.pressed = true
    edge_click.position = hover_point
    canvas._gui_input(edge_click)
    await process_frame
    _check(canvas.get_selected_edge_id() == "edge-continue", "clicking the hovered connection selects its RouteEdge")
    _check(application.get_inspector()._selection_kind == "edge", "connection selection opens the Edge Inspector")

    var route_snapshot = demo_map.to_editor_dict()["edges"]
    demo_view.set_wrapper_expanded(false)
    await process_frame
    _check(demo_view.get_condition_output_count() == 5, "collapsed wrapper keeps compact leaf ports")
    _check(controller.get_scene_map().to_editor_dict()["edges"] == route_snapshot, "wrapper collapse does not modify route identities")
    demo_view.set_wrapper_expanded(true)
    await process_frame

    _check(controller.remove_exit("node-start", "exit-continue"), "atomic exit deletion succeeds")
    _check(controller.get_scene_map().get_route("edge-continue") == null, "exit deletion cleans its route")
    _check(canvas.get_scene_view("node-start").get_output_port_count() == 5, "canvas drops deleted exit slot")

    _check(controller.remove_condition_branch("node-start", "mood-happy"), "switch case subtree deletion succeeds")
    var after_branch_delete = controller.get_scene_map()
    _check(after_branch_delete.get_route("edge-low") == null, "deleted nested less branch route is cleaned")
    _check(after_branch_delete.get_route("edge-equal") == null, "deleted nested equal branch route is cleaned")
    _check(after_branch_delete.get_route("edge-high") == null, "deleted nested greater branch route is cleaned")
    _check(canvas.get_scene_view("node-start").get_condition_output_count() == 2, "canvas refreshes after condition subtree deletion")

    _check(controller.remove_scene("node-hub"), "Scene deletion succeeds")
    _check(controller.get_scene_map().get_route("edge-not-met") == null, "Scene deletion cleans incoming route")
    _check(canvas.get_scene_view("node-hub") == null, "canvas removes deleted Scene view")

    var leaked_copy = controller.get_scene_map()
    leaked_copy.remove_node("node-low")
    _check(controller.get_scene("node-low") != null, "controller map getter returns an ownership-safe copy")

    application.queue_free()
    await process_frame
    if _failures == 0:
        print("PASS: %d runtime UI checks" % _checks)
        quit(0)
    else:
        push_error("FAIL: %d of %d runtime UI checks failed" % [_failures, _checks])
        quit(1)

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if condition:
        return
    _failures += 1
    push_error("CHECK FAILED: %s" % message)
