extends RefCounted
class_name StoryIrApplier

## 把 gel.story-ir 变成 NodeMapDocument 命令。校验仍由 document.execute 负责。

func apply_story(controller, story: Dictionary) -> Dictionary:
	if controller == null or not story is Dictionary:
		return {"ok": false, "diagnostics": [_error("invalid_ir", "Story IR is missing.")]}
	return controller.transact(func():
		return _apply(controller.document, story)
	)

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
			ports[str(ir.get("interfaceId", ""))] = output.interface_id
			var renamed: Dictionary = document.execute({"op": "set_parameter", "node_id": output.node_id, "parameter_id": "display_name", "value": str(ir.get("interfaceId", output.display_name))})
			if not renamed.ok:
				return renamed
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

func _find_type(document, graph_id: String, type_id: String) -> String:
	for node in document.get_nodes(graph_id):
		if node.node_type == type_id:
			return node.node_id
	return ""

func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "severity": "error", "graph_id": "", "node_id": "", "port_id": "", "link_id": ""}

func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "diagnostics": [_error(code, message)]}
