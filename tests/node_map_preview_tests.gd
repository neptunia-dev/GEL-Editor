extends SceneTree

const SHELL := preload("res://workspace/editor_shell.tscn")
const WORKSPACE_PATH := "EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace"
const PREVIEW_PATH := WORKSPACE_PATH + "/WorkspaceCanvas/CanvasRoot/NodeMapWorkspace/PlaceholderNodeMap"

var _checks := 0
var _failures := 0
var _shell: Control
var _preview
var _screenshots := false

func _init() -> void:
	_screenshots = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	_shell = SHELL.instantiate()
	root.add_child(_shell)
	await _settle()
	_preview = _shell.get_node(PREVIEW_PATH)
	_preview.get_parent().current_tab = 1
	await _settle()
	_check(_preview.active_graph_key == "root", "root graph is initially visible")
	_check(_preview.get_node("Toolbar/Row/Back").disabled, "back is disabled at root")
	await _test_graphs()
	await _test_navigation()
	await _test_pointer_input()
	_test_connections()
	await _test_layouts()
	_shell.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: %d node map preview checks" % _checks)
	else:
		push_error("FAIL: %d of %d node map preview checks failed" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)

func _settle() -> void:
	for frame in range(5):
		await process_frame

func _test_graphs() -> void:
	var expected := {"root": Vector2i(4, 4), "prologue": Vector2i(6, 5), "chapter-one": Vector2i(5, 5), "ending": Vector2i(3, 2)}
	for key in expected:
		_preview.show_graph(key)
		await _settle()
		var graph = _preview.get_active_graph()
		_check(graph.get_graph_nodes().size() == expected[key].x, "%s node count" % key)
		_check(graph.get_connection_list().size() == expected[key].y, "%s link count" % key)
		for link in graph.get_connection_list():
			var source: GraphNode = graph.get_node(NodePath(link.from_node))
			var target: GraphNode = graph.get_node(NodePath(link.to_node))
			_check(link.from_port < source.get_output_port_count(), "source port exists")
			_check(link.to_port < target.get_input_port_count(), "target port exists")
			_check(source.get_output_port_type(link.from_port) == target.get_input_port_type(link.to_port), "fixture port types match")
		_check_layout(graph)
		await _capture("%s-1440" % key)
	_preview.show_graph("ending")
	_check(_preview.get_active_graph().get_node("EndStory").get_output_port_count() == 0, "End Story has no output")

func _test_navigation() -> void:
	_preview.show_graph("root")
	await _settle()
	var graph = _preview.get_active_graph()
	var prologue: GraphNode = graph.get_node("Prologue")
	prologue.position_offset += Vector2(20, 40)
	graph.zoom = 0.75
	graph.scroll_offset = Vector2(40, 50)
	var position_before := prologue.position_offset
	var scroll_before: Vector2 = graph.scroll_offset
	prologue.get_node("OpenScene").pressed.emit()
	await _settle()
	_check(_preview.active_graph_key == "prologue", "open scene navigates to child graph")
	_check(not graph.visible, "root graph is hidden in child view")
	_check(_preview.get_node("Toolbar/Row/Breadcrumb").text == "Root Graph / Prologue", "breadcrumb follows navigation")
	_preview.get_node("Toolbar/Row/Back").pressed.emit()
	await _settle()
	_check(_preview.active_graph_key == "root", "back returns to root")
	_check(prologue.position_offset == position_before, "navigation preserves node positions")
	_check(is_equal_approx(graph.zoom, 0.75), "navigation preserves zoom")
	_check(graph.scroll_offset.is_equal_approx(scroll_before), "navigation preserves pan")
	_preview.show_graph("missing")
	_check(_preview.active_graph_key == "root", "invalid destination is ignored")
	graph.set_selected(prologue)
	await _settle()
	_check(_preview.get_node("Status/Selection").text == "Prologue", "selection is displayed")
	var size_before := prologue.size
	graph.set_selected(graph.get_node("Ending"))
	await _settle()
	_check(prologue.size == size_before, "selection does not change node dimensions")
	_preview.get_node("Toolbar/Row/Reset").pressed.emit()
	_check(prologue.position_offset == Vector2(290, 100), "reset restores initial positions")
	_check(graph.get_connection_list().size() == 4, "reset restores initial links")
	_check(_preview.get_node("Status/Selection").text.is_empty(), "reset clears selection")

func _test_pointer_input() -> void:
	_preview.show_graph("root")
	var graph = _preview.get_active_graph()
	graph.frame_all()
	await _settle()
	var node: GraphNode = graph.get_node("Prologue")
	var initial_position := node.position_offset
	var title_position := node.get_global_transform() * Vector2(90, 18)
	_mouse_button(title_position, true)
	var motion := InputEventMouseMotion.new()
	motion.position = title_position + Vector2(40, 40)
	motion.relative = Vector2(40, 40)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	_mouse_button(motion.position, false)
	await _settle()
	_check(node.position_offset.distance_to(initial_position) > 10, "pointer drag moves node")
	graph.reset_preview()
	await _settle()
	var button: Button = node.get_node("OpenScene")
	var button_position := button.get_global_rect().get_center()
	_mouse_button(button_position, true)
	_mouse_button(button_position, false)
	await _settle()
	_check(_preview.active_graph_key == "prologue", "pointer click opens scene")
	var back: Button = _preview.get_node("Toolbar/Row/Back")
	_mouse_button(back.get_global_rect().get_center(), true)
	_mouse_button(back.get_global_rect().get_center(), false)
	await _settle()
	_check(_preview.active_graph_key == "root", "pointer click returns to root")
	for cycle in range(3):
		title_position = node.get_global_transform() * Vector2(90, 18)
		initial_position = node.position_offset
		_mouse_button(title_position, true)
		_mouse_button(title_position, false)
		_mouse_button(title_position, true, true)
		await _settle()
		_check(_preview.active_graph_key == "root", "double click waits for mouse release")
		_mouse_button(title_position, false)
		await _settle()
		_check(_preview.active_graph_key == "prologue", "title double click opens scene after release")
		var back_position := back.get_global_rect().get_center()
		_mouse_motion(back_position, back_position - title_position)
		_mouse_button(back_position, true)
		_mouse_button(back_position, false)
		await _settle()
		_check(_preview.active_graph_key == "root", "pointer returns after title double click")
		_mouse_motion(title_position, title_position - back_position)
		_mouse_motion(title_position + Vector2(30, 20), Vector2(30, 20))
		await _settle()
		_check(node.position_offset.is_equal_approx(initial_position), "returning does not leave a node following the pointer")
		_mouse_button(title_position, true)
		_mouse_motion(title_position + Vector2(40, 40), Vector2(40, 40), MOUSE_BUTTON_MASK_LEFT)
		_mouse_button(title_position + Vector2(40, 40), false)
		await _settle()
		_check(node.position_offset.distance_to(initial_position) > 10, "node can still be dragged after returning")
		var released_position := node.position_offset
		_mouse_motion(title_position + Vector2(80, 60), Vector2(40, 20))
		await _settle()
		_check(node.position_offset.is_equal_approx(released_position), "drag ends on release after returning")
		graph.reset_preview()
		await _settle()
	graph.reset_preview()

func _mouse_motion(position: Vector2, relative: Vector2, button_mask := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = button_mask
	root.push_input(event)

func _mouse_button(position: Vector2, pressed: bool, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.double_click = double_click
	root.push_input(event)

func _test_connections() -> void:
	_preview.show_graph("root")
	var graph = _preview.get_active_graph()
	graph.connection_request.emit(&"Start", 0, &"Ending", 0)
	_check(graph.get_connection_list().size() == 4, "flow output cannot fan out")
	graph.disconnection_request.emit(&"Start", 0, &"Prologue", 0)
	_check(graph.get_connection_list().size() == 3, "preview connection can be removed")
	_check(_preview.get_node("Status/Counts").text == "4 nodes   3 links", "link counter follows changes")
	graph.connection_request.emit(&"Start", 0, &"Ending", 0)
	_check(graph.is_node_connected(&"Start", 0, &"Ending", 0), "flow input accepts multiple predecessors")
	graph.connection_request.emit(&"Start", 0, &"Ending", 0)
	_check(graph.get_connection_list().size() == 4, "duplicate connection is ignored")
	graph.connection_request.emit(&"Start", 99, &"Ending", 0)
	graph.connection_request.emit(&"Missing", 0, &"Ending", 0)
	_check(graph.get_connection_list().size() == 4, "invalid endpoints are ignored")
	_preview.get_node("Toolbar/Row/Reset").pressed.emit()
	_check(graph.is_node_connected(&"Start", 0, &"Prologue", 0), "reset restores original route")
	_check(not graph.is_node_connected(&"Start", 0, &"Ending", 0), "reset removes temporary route")
	_preview.show_graph("prologue")
	graph = _preview.get_active_graph()
	graph.disconnection_request.emit(&"Variable", 0, &"If", 1)
	graph.connection_request.emit(&"Variable", 0, &"If", 0)
	graph.connection_request.emit(&"Variable", 0, &"Dialogue", 2)
	_check(graph.get_connection_list().size() == 4, "boolean cannot connect to flow or string")
	graph.connection_request.emit(&"Variable", 0, &"If", 1)
	_check(graph.get_connection_list().size() == 5, "boolean data connection can be restored")
	graph.reset_preview()

func _test_layouts() -> void:
	for window_size in [Vector2i(1024, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		await _settle()
		for key in ["root", "prologue"]:
			_preview.show_graph(key)
			await _settle()
			_preview.get_node("Toolbar/Row/FrameAll").pressed.emit()
			await _settle()
			_check_layout(_preview.get_active_graph())
			_check(_preview.get_global_rect().end.x <= _shell.size.x, "canvas remains within shell width")
			var row: Control = _preview.get_node("Toolbar/Row")
			_check(row.get_node("Reset").get_global_rect().end.x <= row.get_global_rect().end.x + 1, "toolbar fits available width")
			await _capture("%s-%d" % [key, window_size.x])
	_shell.get_node(WORKSPACE_PATH + "/WorkspaceToolbar/ToolbarRow/ToggleBottomPanel").pressed.emit()
	await _settle()
	_check(_preview.get_active_graph().size.y > 200, "bottom panel leaves a usable canvas")
	_shell.get_node("EditorRoot/EditorTitleBar/TitleBarRow/ToggleDocks").pressed.emit()
	await _settle()
	_check(_preview.get_active_graph().size.x > 1500, "dock toggle expands canvas")

func _check_layout(graph: GraphEdit) -> void:
	var nodes: Array = graph.get_graph_nodes()
	for index in range(nodes.size()):
		var node: GraphNode = nodes[index]
		var rect := Rect2(node.position_offset * graph.zoom - graph.scroll_offset, node.size * graph.zoom)
		_check(Rect2(Vector2.ZERO, graph.size).encloses(rect), "%s is framed" % node.name)
		_check_node_content(node)
		for next_index in range(index + 1, nodes.size()):
			var next: GraphNode = nodes[next_index]
			_check(not Rect2(node.position_offset, node.size).intersects(Rect2(next.position_offset, next.size)), "node bounds do not overlap")
	for link in graph.get_connection_list():
		var source: GraphNode = graph.get_node(NodePath(link.from_node))
		var target: GraphNode = graph.get_node(NodePath(link.to_node))
		var from := (source.position_offset + source.get_output_port_position(link.from_port)) * graph.zoom
		var to := (target.position_offset + target.get_input_port_position(link.to_port)) * graph.zoom
		var points := graph.get_connection_line(from, to)
		var translation := Vector2(173, -91)
		var translated_points := graph.get_connection_line(from + translation, to + translation)
		var translated_start := translated_points[0] - translation
		var translated_end := translated_points[translated_points.size() - 1] - translation
		_check(points[0].distance_to(translated_start) < 0.01 and points[points.size() - 1].distance_to(translated_end) < 0.01, "line endpoints are consistent in minimap and drag preview")
		var line_bounds := _points_bounds(points)
		var translated_bounds := _points_bounds(translated_points)
		_check(line_bounds.size.distance_to(translated_bounds.size) < 0.01, "line extent is consistent in minimap and drag preview")
		var clear := true
		var framed := true
		for point in points:
			if not Rect2(Vector2.ZERO, graph.size).has_point(point - graph.scroll_offset):
				framed = false
		for node in nodes:
			var body := Rect2(node.position_offset * graph.zoom, node.size * graph.zoom).grow(-2)
			for point in points:
				if body.has_point(point):
					clear = false
		_check(clear, "%s -> %s avoids node bodies" % [source.name, target.name])
		_check(framed, "%s -> %s line is framed" % [source.name, target.name])

func _check_node_content(parent: Control) -> void:
	for child in parent.get_children():
		if not child is Control or not child.is_visible_in_tree():
			continue
		_check(Rect2(Vector2.ZERO, parent.size).grow(1).encloses(child.get_rect()), "%s content fits parent" % child.name)
		if child is Label:
			_check(child.get_visible_line_count() >= child.get_line_count(), "%s text is not vertically clipped" % child.name)
		_check_node_content(child)

func _points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

func _capture(filename: String) -> void:
	if not _screenshots or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty(), "rendered viewport is nonempty")
	var base := image.get_pixel(0, 0)
	var varied := 0
	for y in range(0, image.get_height(), 20):
		for x in range(0, image.get_width(), 20):
			if image.get_pixel(x, y) != base:
				varied += 1
	_check(varied > 100, "rendered viewport contains visible content")
	var canvas: GraphEdit = _preview.get_active_graph()
	var canvas_rect := Rect2i(canvas.get_global_rect())
	var canvas_image := image.get_region(canvas_rect)
	var canvas_base := canvas_image.get_pixel(0, canvas_image.get_height() / 2)
	var node_pixels := 0
	for y in range(0, canvas_image.get_height(), 4):
		for x in range(0, canvas_image.get_width(), 4):
			var pixel := canvas_image.get_pixel(x, y)
			if pixel.get_luminance() > canvas_base.get_luminance() + 0.12:
				node_pixels += 1
	_check(node_pixels > 100, "graph region contains rendered nodes and text")
	var directory := ProjectSettings.globalize_path("res://.godot/node-map-preview")
	DirAccess.make_dir_recursive_absolute(directory)
	_check(image.save_png(directory.path_join(filename + ".png")) == OK, "preview screenshot saved")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK FAILED: %s" % message)
