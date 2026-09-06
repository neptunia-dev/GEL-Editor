extends SceneTree

var checks := 0
var failures := 0
var ui: NodeMapEditor

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == text: return child
		var found := button(child, text)
		if found != null: return found
	return null

func press(text: String, parent: Node = null) -> void:
	var target := button(ui if parent == null else parent, text)
	check(target != null, "Button exists: " + text)
	if target != null: target.pressed.emit()

func connect_port(source: String, port: int, target: String) -> void:
	ui.graph_edit.connection_request.emit(ui.graph_nodes[source].name, port, ui.graph_nodes[target].name, 0)

func _run() -> void:
	root.size = Vector2i(1440, 900)
	ui = load("res://node_map/editor/node_map_editor.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	press("Add Scene")
	var a: String = ui._selected_view().model_node_id
	press("Add Scene")
	var b: String = ui._selected_view().model_node_id
	check(ui.scene_map.get_node_count() == 2 and ui.document.is_dirty, "Create marks dirty")
	ui.select_node(a)
	ui.graph_edit.node_selected.emit(ui.graph_nodes[a])
	check(ui.scene_id_edit.text == ui.scene_map.get_node(a).scene_id, "Selection inspector")
	var source_view: SceneGraphNodeView = ui.graph_nodes[a]
	for name in ["one", "two", "three"]:
		ui.exit_name_edit.text = name
		press("Add Exit")
	check(ui.graph_nodes[a] == source_view, "Refresh retains graph node identity")
	check(source_view.get_output_port_count() == 3, "Three output ports")
	for index in 3:
		check(source_view.get_output_port_type(index) == 0, "Output type compatible with input")
		connect_port(a, index, b)
	check(ui.graph_edit.get_connection_list().size() == 3, "Three visible routes")
	check(ui.scene_map.get_route_count() == 3, "Three model routes")
	var count := ui.history._undo_stack.size()
	connect_port(a, 1, b)
	check(ui.history._undo_stack.size() == count, "Rejected duplicate does not record history")
	var port_id := source_view.get_exit_port_id(1)
	source_view.refresh_ports()
	check(source_view.get_exit_port_id(1) == port_id, "Port refresh retains mapping")
	ui._refresh_graph()
	check(ui.graph_edit.get_connection_list().size() == 3, "Refresh restores connections")
	ui.graph_edit.disconnection_request.emit(source_view.name, 1, ui.graph_nodes[b].name, 0)
	check(ui.scene_map.get_route_count() == 2, "Disconnect removes model route")
	ui.undo()
	check(ui.scene_map.get_route_count() == 3, "Undo disconnect")
	ui.redo()
	check(ui.scene_map.get_route_count() == 2, "Redo disconnect")
	ui.title_edit.text_submitted.emit("Changed")
	check(ui.scene_map.get_node(a).title == "Changed", "Inspector title applied")
	check(ui.history._redo_stack.is_empty(), "New action clears redo")
	press("Set Entry")
	check(ui.scene_map.get_entry_node_id() == a, "Entry set")
	count = ui.history._undo_stack.size()
	ui.graph_edit.begin_node_move.emit()
	for index in 10:
		source_view.position_offset = Vector2(index * 20, index * 10)
	check(ui.history._undo_stack.size() == count, "No intermediate drag snapshots")
	ui.graph_edit.end_node_move.emit()
	check(ui.history._undo_stack.size() == count + 1, "One snapshot per drag")
	check(ui.scene_map.get_node(a).position == source_view.position_offset, "Drag persisted")
	ui.document_path_edit.text = "user://node-map-ui-test.json"
	check(ui.save_document() and not ui.document.is_dirty, "Save establishes clean point")
	ui.title_edit.text_submitted.emit("After save")
	check(ui.document.is_dirty, "Edit after save dirty")
	ui.undo()
	check(not ui.document.is_dirty, "Undo back to save point clean")
	ui.redo()
	check(ui.document.is_dirty, "Redo away from save point dirty")
	ui.undo()
	# Cast controls use actual model fields, not a synthetic alias/overrides schema.
	var add_cast := button(ui.advanced, "Add Cast")
	var cast_row := add_cast.get_parent()
	cast_row.get_child(0).text = "hero"
	cast_row.get_child(1).text = "lead"
	cast_row.get_child(2).text = "Ada"
	add_cast.pressed.emit()
	check(ui.scene_map.get_node(a).get_cast_member("hero").display_name == "Ada", "Add Cast through UI")
	var update_cast := button(ui.advanced, "Update Cast")
	update_cast.get_parent().get_child(1).text = "guide"
	update_cast.pressed.emit()
	check(ui.scene_map.get_node(a).get_cast_member("hero").role == "guide", "Update Cast through UI")
	press("Delete Cast", ui.advanced)
	check(ui.scene_map.get_node(a).get_cast().is_empty(), "Delete Cast through UI")
	ui.undo()
	press("Add If", ui.advanced)
	var tree := ui.scene_map.get_node(a).get_condition_tree()
	check(tree != null and tree.get_leaf_endpoints().size() == 2, "Create If tree")
	var if_id := tree.root_wrapper_id
	var true_id: String = tree.get_wrapper(if_id).true_branch_id
	var false_id: String = tree.get_wrapper(if_id).false_branch_id
	var key := "%s::condition::%s::%s" % [a, if_id, true_id]
	connect_port(a, source_view.find_port_index(key), b)
	check(ui.scene_map.get_route_count() == 3, "Condition route created")
	count = ui.history._undo_stack.size()
	ui.advanced.add_wrapper("Switch", true_id)
	check(ui.history._undo_stack.size() == count, "Connected leaf structure change rejected without history")
	check(ui.scene_map.get_node(a).get_condition_tree().is_leaf_branch(if_id, true_id), "Rejected edit leaves model intact")
	ui.advanced.add_wrapper("Switch", false_id)
	tree = ui.scene_map.get_node(a).get_condition_tree()
	var switch_id := tree.get_branch(false_id).child_wrapper_id
	check(tree.get_wrapper(switch_id) is SwitchCaseWrapper, "Nested Switch attached")
	var add_case := button(ui.advanced, "Add Case")
	add_case.get_parent().get_child(0).text = "null"
	add_case.pressed.emit()
	tree = ui.scene_map.get_node(a).get_condition_tree()
	var case_id: String = tree.get_wrapper(switch_id).case_branch_ids[0]
	check(tree.get_branch(case_id).has_match_value and tree.get_branch(case_id).match_value == null, "Null case retained")
	var case_key := "%s::condition::%s::%s" % [a, switch_id, case_id]
	connect_port(a, source_view.find_port_index(case_key), b)
	press("Delete Case", ui.advanced)
	check(ui.scene_map.get_route_count() == 3, "Case deletion cascades route")
	ui.undo()
	check(ui.scene_map.get_route_count() == 4 and source_view.find_port_index(case_key) >= 0, "Undo case restores route and port")
	ui.redo()
	tree = ui.scene_map.get_node(a).get_condition_tree()
	var default_id: String = tree.get_wrapper(switch_id).default_branch_id
	ui.advanced.add_wrapper("Numeric", default_id)
	tree = ui.scene_map.get_node(a).get_condition_tree()
	var numeric_id := tree.get_branch(default_id).child_wrapper_id
	check(tree.get_wrapper(numeric_id) is NumericCompareWrapper, "Nested Numeric attached")
	var operands := button(ui.advanced, "Apply Operands (< / = / >)")
	operands.get_parent().get_child(0).text = '{"kind":"constant","value":5.25}'
	operands.get_parent().get_child(1).text = '{"kind":"variable","variableKey":"reputation"}'
	operands.pressed.emit()
	tree = ui.scene_map.get_node(a).get_condition_tree()
	check(tree.get_wrapper(numeric_id).left_operand.constant_value == 5.25, "Numeric operand editing")
	var numeric_leaf: String = tree.get_wrapper(numeric_id).less_branch_id
	connect_port(a, source_view.find_port_index("%s::condition::%s::%s" % [a, numeric_id, numeric_leaf]), b)
	check(ui.save_document(), "Save complete document")
	var saved := NodeMapSerializer.serialize(ui.scene_map)
	check(ui.load_document(), "Load clean document")
	check(NodeMapSerializer.serialize(ui.scene_map) == saved, "Full JSON roundtrip including cast, nested conditions and routes")
	ui.select_node(a)
	ui.remove_condition("wrapper", numeric_id)
	check(ui.scene_map.get_route_count() == 3, "Wrapper deletion cascades routes")
	ui.undo()
	check(NodeMapSerializer.serialize(ui.scene_map) == saved, "Undo wrapper restores complete document")
	press("Clear Condition Tree", ui.advanced)
	check(ui.scene_map.get_route_count() == 2, "Clear tree cascades all condition routes")
	ui.undo()
	# Focus-protected keyboard input must not delete graph data while typing.
	ui.title_edit.grab_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_DELETE
	event.pressed = true
	ui._unhandled_key_input(event)
	check(ui.scene_map.get_node_count() == 2, "Text focus protects Delete")
	event.keycode = KEY_Z
	event.ctrl_pressed = true
	count = ui.history._undo_stack.size()
	ui._unhandled_key_input(event)
	check(ui.history._undo_stack.size() == count, "Text focus protects Undo")
	ui.graph_edit.grab_focus()
	ui.focus_nodes()
	check(ui.graph_edit.scroll_offset.is_finite(), "Focus all finite")
	# Cycle and unreachable node exercise BFS termination and separate placement.
	ui.select_node(b)
	ui.exit_name_edit.text = "back"
	press("Add Exit")
	connect_port(b, 0, a)
	press("Add Scene")
	var unreachable: String = ui._selected_view().model_node_id
	count = ui.history._undo_stack.size()
	var routes := ui.scene_map.get_route_count()
	ui.auto_layout()
	check(ui.history._undo_stack.size() == count + 1, "Layout one snapshot")
	check(ui.scene_map.get_node(unreachable).position.x < 0, "Unreachable separate region")
	check(ui.scene_map.get_route_count() == routes, "Cyclic layout retains routes")
	ui.undo()
	ui.select_node(b)
	press("Delete Scene")
	check(ui.scene_map.get_route_count() == 0, "Node deletion cascades incoming and outgoing routes")
	ui.undo()
	check(ui.scene_map.get_route_count() == routes, "Undo node deletion restores routes")
	# Dirty load/close are actual modal operations with cancellation and discard.
	var before := ui.scene_map.to_editor_dict()
	check(not ui.load_document() and ui.unsaved_dialog.visible, "Dirty load asks confirmation")
	ui.unsaved_dialog.canceled.emit()
	ui.unsaved_dialog.hide()
	check(ui.scene_map.to_editor_dict() == before, "Cancel load preserves document")
	check(not ui.close_document() and ui.unsaved_dialog.visible, "Dirty close asks confirmation")
	ui.unsaved_dialog.canceled.emit()
	ui.unsaved_dialog.hide()
	check(ui.scene_map.to_editor_dict() == before, "Cancel close preserves document")
	ui.load_document()
	ui.unsaved_dialog.confirmed.emit()
	ui.unsaved_dialog.hide()
	check(NodeMapSerializer.serialize(ui.scene_map) == saved and not ui.document.is_dirty, "Discard then load works")
	ui.document_path_edit.text = "user://missing-map-file.json"
	check(not ui.load_document() and NodeMapSerializer.serialize(ui.scene_map) == saved, "Failed load preserves document")
	ui._show_file_dialog(false)
	check(ui.file_dialog.visible and ui.file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE, "Real open file dialog")
	ui.file_dialog.hide()
	ui._show_file_dialog(true)
	check(ui.file_dialog.visible and ui.file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "Real save file dialog")
	ui.file_dialog.hide()
	_test_invalid(saved)
	# Save failure must preserve history, clean point and original document path.
	var clean_path: String = ui.document.file_path
	ui.document_path_edit.text = "user://nonexistent-directory/map.json"
	count = ui.history._undo_stack.size()
	check(not ui.save_document(), "Unwritable save rejected")
	check(ui.document.file_path == clean_path and ui.history._undo_stack.size() == count, "Failed save preserves path and history")
	var invalid_file := FileAccess.open("user://node-map-invalid.json", FileAccess.WRITE)
	invalid_file.store_string('{"nodes": [')
	invalid_file.close()
	ui.document_path_edit.text = "user://node-map-invalid.json"
	check(not ui.load_document() and NodeMapSerializer.serialize(ui.scene_map) == saved, "Malformed JSON file preserves document")
	ui.select_node(a)
	ui.title_edit.text_submitted.emit("Save before open")
	ui.document_path_edit.text = "user://node-map-invalid.json"
	ui.load_document()
	ui.unsaved_dialog.custom_action.emit("save")
	check(ui.document.file_path == clean_path and not ui.document.is_dirty, "Save before open writes current file, not target")
	check(not NodeMapSerializer.load_file("user://node-map-invalid.json").ok, "Save before open does not overwrite requested target")
	# Actual viewport mouse input exercises button hit testing, not just handlers.
	ui.bind_scene_map(SceneMap.new())
	await process_frame
	await process_frame
	var add_button := button(ui, "Add Scene")
	for down in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = down
		mouse.position = add_button.get_global_rect().get_center()
		root.push_input(mouse, true)
		await process_frame
	check(ui.scene_map.get_node_count() == 1, "Viewport mouse click creates Scene")
	var large := SceneMap.new()
	for index in 150:
		large.add_node(SceneNode.new("perf-%d" % index, "perf-%d" % index, "", "", [], [], Vector2(index % 15 * 300, index / 15 * 200)))
	ui.bind_scene_map(large)
	await process_frame
	ui.select_node("perf-0")
	var untouched: GraphNode = ui.graph_nodes["perf-149"]
	var untouched_label: Node = untouched.get_child(0)
	var started := Time.get_ticks_usec()
	ui.title_edit.text_submitted.emit("Local change")
	var elapsed := Time.get_ticks_usec() - started
	check(ui.graph_nodes["perf-149"] == untouched and untouched.get_child(0) == untouched_label, "150-node property edit retains unrelated controls")
	print("150-node property edit: %.2f ms" % (elapsed / 1000.0))
	ui.queue_free()
	await process_frame
	var shell = load("res://workspace/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	check(not shell.find_child("CanvasOverlay", true, false).visible, "Shell placeholder overlay hidden")
	check(shell.find_child("NodeMapEditor", true, false).graph_edit.size.y > 0, "Shell graph visible area")
	shell.queue_free()
	await process_frame
	print("Node Map UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_invalid(saved: Dictionary) -> void:
	for value in [null, [], 3, "bad", true]:
		check(not NodeMapSerializer.deserialize(value).ok, "Reject wrong root type")
	for field in ["formatVersion", "moduleVersion", "entryNodeId", "nodes", "edges"]:
		var data := saved.duplicate(true)
		data[field] = {}
		check(not NodeMapSerializer.deserialize(data).ok, "Reject bad top-level " + field)
	for field in ["nodeId", "sceneId", "title", "mainScript", "position", "cast", "exits", "conditionTree"]:
		var data := saved.duplicate(true)
		data.nodes[0][field] = 12
		check(not NodeMapSerializer.deserialize(data).ok, "Reject bad node " + field)
	for mutation in [
		func(d): d.nodes[0].cast = [false],
		func(d): d.nodes[0].exits = [null],
		func(d): d.nodes[0].position.x = INF,
		func(d): d.nodes[0].conditionTree.wrappers[0].type = "unknown",
		func(d): d.nodes[0].conditionTree.branches[0].matchValue = [],
		func(d): d.nodes[0].cast[0].alias = "not supported",
		func(d): d.nodes[0].extra = "must not disappear",
		func(d): d.edges[0].sourceKind = "unknown",
		func(d): d.nodes.append(d.nodes[0].duplicate(true)),
		func(d): d.edges.append(d.edges[0].duplicate(true)),
		func(d): d.moduleVersion = 999,
		func(d): d.formatVersion = 1.5,
	]:
		var data := saved.duplicate(true)
		mutation.call(data)
		check(not NodeMapSerializer.deserialize(data).ok, "Reject malformed data without crash")
