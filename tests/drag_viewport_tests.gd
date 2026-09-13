extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var shell = load("res://workspace/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await create_timer(0.3).timeout
	var editor = shell._node_map_editor
	var graph = editor.graph
	var view = graph.get_graph_nodes()[0]
	view.selected = true
	graph.selection_changed.emit()
	await create_timer(0.2).timeout
	var offset: Vector2 = graph.scroll_offset
	var canvas_size: Vector2 = graph.size
	var position: Vector2 = view.position_offset
	var inspector_count: int = shell._inspector.get_node("InspectorContent").get_child_count()
	view.position_offset += Vector2(12, 8)
	graph._move_finished()
	var ok: bool = shell._inspector.get_node("InspectorContent").get_child_count() == inspector_count
	for frame in range(12):
		await process_frame
		ok = ok and graph.scroll_offset.is_equal_approx(offset) and graph.size.is_equal_approx(canvas_size)
	ok = ok and editor.document.get_node(view.node_id).position.is_equal_approx(position + Vector2(12, 8))
	editor.controller.undo()
	await process_frame
	ok = ok and editor.document.get_node(view.node_id).position.is_equal_approx(position)
	if not ok:
		push_error("Drag changed viewport/layout or broke position/undo")
	else:
		print("PASS: drag preserves viewport and layout; position and undo work")
	shell.queue_free()
	await process_frame
	quit(0 if ok else 1)
