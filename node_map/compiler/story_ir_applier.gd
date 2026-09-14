extends RefCounted
class_name StoryIrApplier

## 把 gel.story-ir 变成 NodeMapDocument 命令。校验仍由 document.execute 负责。

func apply_story(controller, story: Dictionary) -> Dictionary:
	if controller == null or not story is Dictionary:
		return {"ok": false, "diagnostics": [_error("invalid_ir", "Story IR is missing.")]}
	return controller.transact(func():
		return _apply(controller.document, story)
	)

func create_session() -> Dictionary:
	return {
		"entry_scene": "",
		"scene_nodes": {},
		"scene_ports": {},
		"current_scene_id": "",
		"current_scene_node_id": "",
		"ids": {},
		"choice_ports": {},
		"ports": {},
		"cursor": Vector2(350, 80),
		"column": 0,
		"output_index": 0,
		"saw_output": false,
	}

func apply_event(document, session: Dictionary, event: Dictionary) -> Dictionary:
	match str(event.get("op", "")):
		"story":
			session.entry_scene = str(event.get("entryScene", ""))
			return {"ok": true, "diagnostics": []}
		"scene":
			var closed: Dictionary = _close_scene(document, session)
			if not closed.ok:
				return closed
			return _open_scene(document, session, event)
		"node":
			return _stream_node(document, session, event)
		"link":
			return _stream_link(document, session, event)
		"route":
			var after_scene: Dictionary = _close_scene(document, session)
			if not after_scene.ok:
				return after_scene
			return _stream_route(document, session, event)
		"done":
			var finished: Dictionary = _close_scene(document, session)
			if not finished.ok:
				return finished
			return _connect_start(document, session)
		_:
			return _fail("invalid_ir_event", "Unknown IR event.")
func _apply(document, story: Dictionary) -> Dictionary:
	var scenes: Variant = story.get("scenes", [])
	var routes: Variant = story.get("routes", {})
	var entry := str(story.get("entryScene", ""))
	if not scenes is Array or not routes is Dictionary or entry.is_empty():
		return _fail("invalid_ir", "Story IR requires entryScene, scenes, and routes.")
	var scene_nodes: Dictionary = {}
	var scene_ports: Dictionary = {}
	var cursor := Vector2(350, 80)
	for scene in scenes:
		if not scene is Dictionary:
			return _fail("invalid_ir", "Scene entry must be an object.")
		var created: Dictionary = document.execute({"op": "create_node", "type_id": "gel.scene", "graph_id": document.root_graph_id, "position": cursor})
		if not created.ok:
			return created
		cursor.x += 400
		var node_id := str(created.created_node_id)
		var scene_id := str(scene.get("sceneId", ""))
		var title := str(scene.get("title", scene_id))
		var named: Dictionary = document.execute({"op": "set_parameter", "node_id": node_id, "parameter_id": "scene_id", "value": scene_id})
		if not named.ok:
			return named
		var titled: Dictionary = document.execute({"op": "set_parameter", "node_id": node_id, "parameter_id": "display_name", "value": title})
		if not titled.ok:
			return titled
		var filled: Dictionary = _fill_scene(document, node_id, scene)
		if not filled.ok:
			return filled
		scene_nodes[scene_id] = node_id
		scene_ports[scene_id] = filled.ports
	if not scene_nodes.has(entry):
		return _fail("missing_scene", "entryScene is not in scenes.")
	var start_id := _find_type(document, document.root_graph_id, "gel.project_start")
	var linked: Dictionary = document.execute({
		"op": "connect",
		"graph_id": document.root_graph_id,
		"source_node_id": start_id,
		"source_port_id": "out",
		"target_node_id": scene_nodes[entry],
		"target_port_id": "enter",
	})
	if not linked.ok:
		return linked
	for source_id in routes:
		var mapping: Variant = routes[source_id]
		if not mapping is Dictionary:
			return _fail("invalid_route", "Route mapping must be an object.")
		for exit_id in mapping:
			var port := str((scene_ports.get(str(source_id), {}) as Dictionary).get(str(exit_id), ""))
			var target_id := str(scene_nodes.get(str(mapping[exit_id]), ""))
			if port.is_empty() or target_id.is_empty():
				return _fail("invalid_route", "Route '" + str(source_id) + "." + str(exit_id) + "' is missing.")
			var routed: Dictionary = document.execute({
				"op": "connect",
				"graph_id": document.root_graph_id,
				"source_node_id": scene_nodes[str(source_id)],
				"source_port_id": port,
				"target_node_id": target_id,
				"target_port_id": "enter",
			})
			if not routed.ok:
				return routed
	return {"ok": true, "diagnostics": []}

func _fill_scene(document, scene_node_id: String, scene: Dictionary) -> Dictionary:
	var graph_id: String = document.get_node(scene_node_id).child_graph_id
	for link in document.get_links(graph_id):
		var disconnected: Dictionary = document.execute({"op": "disconnect", "link_id": link.link_id})
		if not disconnected.ok:
			return disconnected
	var ids: Dictionary = {"entry": _find_type(document, graph_id, "gel.graph_input")}
	var choice_ports: Dictionary = {}
	var ports: Dictionary = {}
	var outputs: Array = []
	for node in scene.get("nodes", []):
		if node is Dictionary and str(node.get("type", "")) == "gel.graph_output":
			outputs.append(node)
	var existing_outputs: Array = []
	for node in document.get_nodes(graph_id):
		if node.node_type == "gel.graph_output":
			existing_outputs.append(node)
	if outputs.is_empty():
		for node in existing_outputs:
			var removed: Dictionary = document.execute({"op": "remove_nodes", "node_ids": [node.node_id]})
			if not removed.ok:
				return removed
	else:
		while existing_outputs.size() < outputs.size():
			var added: Dictionary = document.execute({"op": "add_output", "node_id": scene_node_id, "display_name": str(outputs[existing_outputs.size()].get("interfaceId", "out"))})
			if not added.ok:
				return added
			existing_outputs.append(document.get_node(str(added.created_node_id)))
		while existing_outputs.size() > outputs.size():
			var extra = existing_outputs.pop_back()
			var removed: Dictionary = document.execute({"op": "remove_nodes", "node_ids": [extra.node_id]})
			if not removed.ok:
				return removed
		for index in outputs.size():
			var ir: Dictionary = outputs[index]
			var output = existing_outputs[index]
			ids[str(ir.id)] = output.node_id
			var interface_id := str(ir.get("interfaceId", ""))
			var bound: Dictionary = _bind_output(document, output, interface_id)
			if not bound.ok:
				return bound
			ports[interface_id] = interface_id
	var column := 0
	for node in scene.get("nodes", []):
		if not node is Dictionary:
			continue
		var type_id := str(node.get("type", ""))
		if type_id == "gel.graph_output":
			continue
		var created: Dictionary = document.execute({"op": "create_node", "type_id": type_id, "graph_id": graph_id, "position": Vector2(280 * column, 80 if type_id != "gel.boolean" else 360)})
		if not created.ok:
			return created
		column += 1
		var node_id := str(created.created_node_id)
		ids[str(node.id)] = node_id
		var configured: Dictionary = _configure_node(document, node_id, node, choice_ports)
		if not configured.ok:
			return configured
	for link in scene.get("links", []):
		if not link is Array or link.size() != 4:
			return _fail("invalid_link", "Link must have four parts.")
		var source_key := str(link[0]) + ":" + str(link[1])
		var source_id := str(ids.get(str(link[0]), ""))
		var source_port := str(choice_ports.get(source_key, link[1]))
		var target_id := str(ids.get(str(link[2]), ""))
		if source_id.is_empty() or target_id.is_empty():
			return _fail("missing_node", "Link endpoint is missing.")
		var connected: Dictionary = document.execute({
			"op": "connect",
			"graph_id": graph_id,
			"source_node_id": source_id,
			"source_port_id": source_port,
			"target_node_id": target_id,
			"target_port_id": str(link[3]),
		})
		if not connected.ok:
			return connected
	return {"ok": true, "diagnostics": [], "ports": ports}

func _configure_node(document, node_id: String, node: Dictionary, choice_ports: Dictionary) -> Dictionary:
	match str(node.get("type", "")):
		"gel.dialogue":
			return document.execute({"op": "set_input", "node_id": node_id, "port_id": "text", "value": str(node.get("text", ""))})
		"gel.boolean":
			return document.execute({"op": "set_parameter", "node_id": node_id, "parameter_id": "value", "value": bool(node.get("value", false))})
		"gel.choice":
			for item in node.get("choices", []):
				if not item is Dictionary:
					return _fail("invalid_choice", "Choice option must be an object.")
				var added: Dictionary = document.execute({"op": "add_choice", "node_id": node_id, "label": str(item.get("label", ""))})
				if not added.ok:
					return added
				choice_ports[str(node.id) + ":" + str(item.get("id", ""))] = str(added.created_item_id)
			return {"ok": true, "diagnostics": []}
		_:
			return {"ok": true, "diagnostics": []}
func _bind_output(document, output, interface_id: String) -> Dictionary:
	if output == null or interface_id.is_empty():
		return {"ok": true, "diagnostics": []}
	return document.bind_graph_output(output.node_id, interface_id)

 

func _open_scene(document, session: Dictionary, event: Dictionary) -> Dictionary:
	var scene_id := str(event.get("sceneId", ""))
	var title := str(event.get("title", scene_id))
	var node_id := str(session.scene_nodes.get(scene_id, ""))
	if node_id.is_empty():
		var created: Dictionary = document.execute({"op": "create_node", "type_id": "gel.scene", "graph_id": document.root_graph_id, "position": session.cursor})
		if not created.ok:
			return created
		session.cursor = Vector2(session.cursor.x + 400, session.cursor.y)
		node_id = str(created.created_node_id)
		var named: Dictionary = document.execute({"op": "set_parameter", "node_id": node_id, "parameter_id": "scene_id", "value": scene_id})
		if not named.ok:
			return named
		session.scene_nodes[scene_id] = node_id
	var titled: Dictionary = document.execute({"op": "set_parameter", "node_id": node_id, "parameter_id": "display_name", "value": title})
	if not titled.ok:
		return titled
	var graph_id: String = document.get_node(node_id).child_graph_id
	for link in document.get_links(graph_id):
		var disconnected: Dictionary = document.execute({"op": "disconnect", "link_id": link.link_id})
		if not disconnected.ok:
			return disconnected
	for node in document.get_nodes(graph_id):
		if node.node_type == "gel.graph_output":
			var removed: Dictionary = document.execute({"op": "remove_nodes", "node_ids": [node.node_id]})
			if not removed.ok:
				return removed
	session.current_scene_id = scene_id
	session.current_scene_node_id = node_id
	session.ids = {"entry": _find_type(document, graph_id, "gel.graph_input")}
	session.choice_ports = {}
	session.ports = {}
	session.column = 0
	session.output_index = 0
	session.saw_output = false
	return {"ok": true, "diagnostics": []}

func _close_scene(document, session: Dictionary) -> Dictionary:
	var scene_id := str(session.get("current_scene_id", ""))
	if scene_id.is_empty():
		return {"ok": true, "diagnostics": []}
	if not bool(session.saw_output):
		var graph_id: String = document.get_node(str(session.current_scene_node_id)).child_graph_id
		for node in document.get_nodes(graph_id):
			if node.node_type == "gel.graph_output":
				var removed: Dictionary = document.execute({"op": "remove_nodes", "node_ids": [node.node_id]})
				if not removed.ok:
					return removed
	session.scene_ports[scene_id] = session.ports.duplicate(true)
	session.current_scene_id = ""
	session.current_scene_node_id = ""
	return {"ok": true, "diagnostics": []}

func _stream_node(document, session: Dictionary, event: Dictionary) -> Dictionary:
	var type_id := str(event.get("type", ""))
	var scene_node_id := str(session.current_scene_node_id)
	if scene_node_id.is_empty():
		return _fail("invalid_ir_event", "node event before scene")
	var graph_id: String = document.get_node(scene_node_id).child_graph_id
	if type_id == "gel.graph_output":
		var outputs: Array = []
		for node in document.get_nodes(graph_id):
			if node.node_type == "gel.graph_output":
				outputs.append(node)
		var output
		if int(session.output_index) < outputs.size():
			output = outputs[int(session.output_index)]
		else:
			var added: Dictionary = document.execute({"op": "add_output", "node_id": scene_node_id, "display_name": str(event.get("interfaceId", "out"))})
			if not added.ok:
				return added
			output = document.get_node(str(added.created_node_id))
		session.output_index = int(session.output_index) + 1
		session.saw_output = true
		session.ids[str(event.get("id", ""))] = output.node_id
		var interface_id := str(event.get("interfaceId", ""))
		var bound: Dictionary = _bind_output(document, output, interface_id)
		if not bound.ok:
			return bound
		session.ports[interface_id] = interface_id
		return document.execute({"op": "set_parameter", "node_id": output.node_id, "parameter_id": "display_name", "value": interface_id if not interface_id.is_empty() else output.display_name})
	var created: Dictionary = document.execute({"op": "create_node", "type_id": type_id, "graph_id": graph_id, "position": Vector2(280 * int(session.column), 80 if type_id != "gel.boolean" else 360)})
	if not created.ok:
		return created
	session.column = int(session.column) + 1
	var node_id := str(created.created_node_id)
	session.ids[str(event.get("id", ""))] = node_id
	return _configure_node(document, node_id, event, session.choice_ports)

func _stream_link(document, session: Dictionary, event: Dictionary) -> Dictionary:
	var source: Variant = event.get("from", [])
	var target: Variant = event.get("to", [])
	if not source is Array or source.size() != 2 or not target is Array or target.size() != 2:
		return _fail("invalid_link", "Link must have from and to pairs.")
	var scene_node_id := str(session.current_scene_node_id)
	if scene_node_id.is_empty():
		return _fail("invalid_ir_event", "link event before scene")
	var graph_id: String = document.get_node(scene_node_id).child_graph_id
	var source_key := str(source[0]) + ":" + str(source[1])
	var source_id := str(session.ids.get(str(source[0]), ""))
	var source_port := str(session.choice_ports.get(source_key, source[1]))
	var target_id := str(session.ids.get(str(target[0]), ""))
	if source_id.is_empty() or target_id.is_empty():
		return _fail("missing_node", "Link endpoint is missing.")
	return document.execute({
		"op": "connect",
		"graph_id": graph_id,
		"source_node_id": source_id,
		"source_port_id": source_port,
		"target_node_id": target_id,
		"target_port_id": str(target[1]),
	})

func _stream_route(document, session: Dictionary, event: Dictionary) -> Dictionary:
	var source_id := str(event.get("from", ""))
	var exit_id := str(event.get("exit", ""))
	var target_key := str(event.get("to", ""))
	var port := str((session.scene_ports.get(source_id, {}) as Dictionary).get(exit_id, ""))
	var target_id := str(session.scene_nodes.get(target_key, ""))
	if port.is_empty() or target_id.is_empty():
		return _fail("invalid_route", "Route '" + source_id + "." + exit_id + "' is missing.")
	return document.execute({
		"op": "connect",
		"graph_id": document.root_graph_id,
		"source_node_id": session.scene_nodes[source_id],
		"source_port_id": port,
		"target_node_id": target_id,
		"target_port_id": "enter",
	})

func _connect_start(document, session: Dictionary) -> Dictionary:
	var entry := str(session.entry_scene)
	var target_id := str(session.scene_nodes.get(entry, ""))
	if target_id.is_empty():
		return _fail("missing_scene", "entryScene is not in scenes.")
	var start_id := _find_type(document, document.root_graph_id, "gel.project_start")
	return document.execute({
		"op": "connect",
		"graph_id": document.root_graph_id,
		"source_node_id": start_id,
		"source_port_id": "out",
		"target_node_id": target_id,
		"target_port_id": "enter",
	})

func _find_type(document, graph_id: String, type_id: String) -> String:
	for node in document.get_nodes(graph_id):
		if node.node_type == type_id:
			return node.node_id
	return ""

func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "severity": "error", "graph_id": "", "node_id": "", "port_id": "", "link_id": ""}

func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "diagnostics": [_error(code, message)]}
