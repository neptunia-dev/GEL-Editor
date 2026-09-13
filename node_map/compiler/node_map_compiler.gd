extends RefCounted
class_name NodeMapCompiler

## 将编辑器 Node Map 的纯快照编译为 GEL Runtime Package v1。
##
## 编译器不读写磁盘，也不依赖 GraphEdit 或其他视图对象。它只消费
## NodeMapDocument 的只读快照并返回 manifest + Lua 文本；文件系统边界由
## RuntimePackageWriter 处理。这样导出逻辑可在 Godot headless 测试中独立验证。

const PACKAGE_FORMAT_VERSION := 1
const DEFAULT_PACKAGE_ID := "untitled.story"
const DEFAULT_PACKAGE_VERSION := "0.1.0"
const DEFAULT_SAVE_SCHEMA_VERSION := 1
const DEFAULT_TITLE := "Untitled Story"
const DEFAULT_ENGINE_MIN_VERSION := "0.1.0"

const EXECUTABLE_NODE_TYPES := [
	"gel.dialogue",
	"gel.if",
	"gel.choice",
	"gel.graph_output",
	"gel.end_story",
]
const DATA_ONLY_NODE_TYPES := ["gel.boolean"]

## 编译一个完整文档。
##
## 成功时返回：
## {
##   ok: true,
##   diagnostics: [],
##   manifest: Runtime Package v1 DTO,
##   scripts: { "scenes/<scene-id>/main.lua": String }
## }
##
## 失败时 manifest/scripts 均为空，调用方不得写出半成品包。
func compile(document, options: Dictionary = {}) -> Dictionary:
	var diagnostics: Array = []
	if document == null or not document.has_method("get_snapshot") or not document.has_method("validate_self"):
		diagnostics.append(_error("invalid_document", "Compiler requires a NodeMapDocument-compatible value."))
		return _failure(diagnostics)

	var structural_errors: Array = document.validate_self()
	if not structural_errors.is_empty():
		for item in structural_errors:
			diagnostics.append(item.duplicate(true) if item is Dictionary else _error("invalid_document", str(item)))
		return _failure(diagnostics)

	var config := _normalize_options(options, diagnostics)
	if _has_errors(diagnostics):
		return _failure(diagnostics)

	var snapshot: Dictionary = document.get_snapshot()
	var graphs := _index_graphs(snapshot, diagnostics)
	if _has_errors(diagnostics):
		return _failure(diagnostics)

	var root_graph_id := str(snapshot.get("rootGraphId", ""))
	var root: Dictionary = graphs.get(root_graph_id, {})
	if root.is_empty() or root.get("kind", "") != "root":
		diagnostics.append(_error("missing_root", "Document does not contain its declared root graph.", root_graph_id))
		return _failure(diagnostics)

	var scene_nodes := _scene_nodes(root)
	if scene_nodes.is_empty():
		diagnostics.append(_error("missing_scene", "Runtime export requires at least one Scene node.", root_graph_id))
		return _failure(diagnostics)

	var scenes_by_node: Dictionary = {}
	var scenes_by_id: Dictionary = {}
	for scene_node in scene_nodes:
		var scene_id := _scene_id(scene_node)
		var node_id := str(scene_node.get("id", ""))
		if scene_id.is_empty() or node_id.is_empty():
			diagnostics.append(_error("invalid_scene", "Scene node is missing a stable runtime scene ID.", root_graph_id, node_id))
			continue
		if not _matches(scene_id, "^[a-z][a-z0-9_.-]*$"):
			diagnostics.append(_error("invalid_scene_id", "Runtime scene ID must match ^[a-z][a-z0-9_.-]*$.", root_graph_id, node_id))
			continue
		if scenes_by_id.has(scene_id):
			diagnostics.append(_error("duplicate_scene_id", "Runtime scene IDs must be unique: '" + scene_id + "'.", root_graph_id, node_id))
			continue
		scenes_by_node[node_id] = scene_node
		scenes_by_id[scene_id] = scene_node
	if _has_errors(diagnostics):
		return _failure(diagnostics)

	var entry_scene_id := _compile_entry_scene(root, scenes_by_node, diagnostics)
	if not config.entry_scene.is_empty() and not entry_scene_id.is_empty() and config.entry_scene != entry_scene_id:
		diagnostics.append(_error("entry_scene_mismatch", "Project entryScene must match the Scene connected from Project Start.", root_graph_id))
	var routes: Dictionary = {}
	var scene_definitions: Array = []
	var scripts: Dictionary = {}

	for scene_node in scene_nodes:
		var scene_id := _scene_id(scene_node)
		var node_id := str(scene_node.get("id", ""))
		var scene_graph_id := _child_graph_id(scene_node)
		var scene_graph: Dictionary = graphs.get(scene_graph_id, {})
		if scene_graph.is_empty() or scene_graph.get("kind", "") != "scene":
			diagnostics.append(_error("missing_scene_graph", "Scene '" + scene_id + "' does not reference a valid scene graph.", root_graph_id, node_id))
			continue

		var outputs := _ordered_graph_outputs(scene_graph)
		var exits: Array = []
		for output in outputs:
			var interface_id := _interface_id(output)
			if interface_id.is_empty():
				diagnostics.append(_error("invalid_output", "Scene output is missing a stable interface ID.", scene_graph_id, str(output.get("id", ""))))
				continue
			if not _matches(interface_id, "^[a-z][a-z0-9_.-]*$"):
				diagnostics.append(_error("invalid_output", "Scene output ID must match ^[a-z][a-z0-9_.-]*$.", scene_graph_id, str(output.get("id", ""))))
				continue
			exits.append(interface_id)
			var route_target := _compile_output_route(root, scene_node, output, scenes_by_node, diagnostics)
			if not route_target.is_empty():
				if not routes.has(scene_id):
					routes[scene_id] = {}
				routes[scene_id][interface_id] = route_target

		var script := _compile_scene_script(scene_graph, diagnostics)
		if script.is_empty() and not _has_errors(diagnostics):
			# 空脚本只可能来自内部逻辑错误；保留明确诊断而非写出非法包。
			diagnostics.append(_error("empty_script", "Scene '" + scene_id + "' did not produce Lua source.", scene_graph_id, node_id))
		var script_path := "scenes/" + scene_id + "/main.lua"
		scripts[script_path] = script
		var scene_definition := {
			"id": scene_id,
			"mainScript": script_path,
			"cast": [],
			"exits": exits,
		}
		var title := _scene_title(scene_node)
		if not title.is_empty():
			scene_definition["title"] = title
		scene_definitions.append(scene_definition)

	_validate_root_links(root, scenes_by_node, diagnostics)
	if entry_scene_id.is_empty():
		diagnostics.append(_error("missing_entry_scene", "Project Start must connect to exactly one Scene entry.", root_graph_id))
	if _has_errors(diagnostics):
		return _failure(diagnostics)

	var manifest := {
		"formatVersion": PACKAGE_FORMAT_VERSION,
		"packageId": config.package_id,
		"packageVersion": config.package_version,
		"saveSchemaVersion": config.save_schema_version,
		"entryScene": entry_scene_id,
		"engine": {"minVersion": config.engine_min_version},
		"metadata": {"title": config.title},
		"assets": [],
		"characters": [],
		"variables": [],
		"scenes": scene_definitions,
		"routes": routes,
	}
	return {"ok": true, "diagnostics": diagnostics, "manifest": manifest, "scripts": scripts}

func _normalize_options(options: Dictionary, diagnostics: Array) -> Dictionary:
	var allowed := ["package_id", "package_version", "save_schema_version", "title", "engine_min_version", "entry_scene"]
	for key in options:
		if not key is String or not allowed.has(key):
			diagnostics.append(_error("invalid_compile_option", "Unknown compiler option '" + str(key) + "'."))
	var package_id: Variant = options.get("package_id", DEFAULT_PACKAGE_ID)
	var package_version: Variant = options.get("package_version", DEFAULT_PACKAGE_VERSION)
	var save_schema_version: Variant = options.get("save_schema_version", DEFAULT_SAVE_SCHEMA_VERSION)
	var title_value: Variant = options.get("title", DEFAULT_TITLE)
	var engine_min_version: Variant = options.get("engine_min_version", DEFAULT_ENGINE_MIN_VERSION)
	var entry_scene: Variant = options.get("entry_scene", "")
	if not package_id is String or not _matches(package_id, "^[a-z][a-z0-9_.-]*$"):
		diagnostics.append(_error("invalid_compile_option", "package_id must match ^[a-z][a-z0-9_.-]*$."))
	if not package_version is String or not _matches(package_version, "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$"):
		diagnostics.append(_error("invalid_compile_option", "package_version must be a semantic version."))
	if not (save_schema_version is int and save_schema_version >= 0):
		diagnostics.append(_error("invalid_compile_option", "save_schema_version must be a non-negative integer."))
	if not title_value is String or title_value.strip_edges().is_empty() or title_value.strip_edges() != title_value:
		diagnostics.append(_error("invalid_compile_option", "title must be non-empty text without surrounding whitespace."))
	if not engine_min_version is String or not _matches(engine_min_version, "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$"):
		diagnostics.append(_error("invalid_compile_option", "engine_min_version must be a semantic version."))
	if not entry_scene is String or (not entry_scene.is_empty() and not _matches(entry_scene, "^[a-z][a-z0-9_.-]*$")):
		diagnostics.append(_error("invalid_compile_option", "entry_scene must be empty or match ^[a-z][a-z0-9_.-]*$."))
	return {
		"package_id": package_id if package_id is String else "",
		"package_version": package_version if package_version is String else "",
		"save_schema_version": save_schema_version,
		"title": title_value if title_value is String else "",
		"engine_min_version": engine_min_version if engine_min_version is String else "",
		"entry_scene": entry_scene if entry_scene is String else "",
	}

func _index_graphs(snapshot: Dictionary, diagnostics: Array) -> Dictionary:
	var graphs: Dictionary = {}
	var raw_graphs: Variant = snapshot.get("graphs", [])
	if not raw_graphs is Array:
		diagnostics.append(_error("invalid_snapshot", "Document snapshot graphs must be an array."))
		return graphs
	for raw_graph in raw_graphs:
		if not raw_graph is Dictionary:
			diagnostics.append(_error("invalid_snapshot", "Document snapshot contains an invalid graph record."))
			continue
		var graph_id := str(raw_graph.get("graphId", ""))
		if graph_id.is_empty() or graphs.has(graph_id):
			diagnostics.append(_error("invalid_snapshot", "Document snapshot contains a missing or duplicate graph ID.", graph_id))
			continue
		graphs[graph_id] = raw_graph
	return graphs

func _scene_nodes(root: Dictionary) -> Array:
	var result: Array = []
	for node in root.get("nodes", []):
		if node is Dictionary and node.get("type", "") == "gel.scene":
			result.append(node)
	return result

func _compile_entry_scene(root: Dictionary, scenes_by_node: Dictionary, diagnostics: Array) -> String:
	var starts: Array = []
	for node in root.get("nodes", []):
		if node is Dictionary and node.get("type", "") == "gel.project_start":
			starts.append(node)
	if starts.size() != 1:
		diagnostics.append(_error("invalid_project_start", "Root graph must contain exactly one Project Start node.", str(root.get("graphId", ""))))
		return ""
	var start: Dictionary = starts[0]
	var target_id := _required_next(root, start, "out", scenes_by_node, diagnostics)
	if target_id.is_empty():
		return ""
	var target: Dictionary = scenes_by_node.get(target_id, {})
	if target.is_empty():
		return ""
	return _scene_id(target)

func _compile_output_route(root: Dictionary, source_scene: Dictionary, output: Dictionary, scenes_by_node: Dictionary, diagnostics: Array) -> String:
	var source_node_id := str(source_scene.get("id", ""))
	var output_id := _interface_id(output)
	var target_id := _required_next(root, source_scene, output_id, scenes_by_node, diagnostics)
	if target_id.is_empty():
		return ""
	var target: Dictionary = scenes_by_node.get(target_id, {})
	if target.is_empty():
		return ""
	return _scene_id(target)

## 对 root 的流程目标额外要求 Scene 输入端口为 enter；对子图目标则由
## _compile_scene_script 的节点类型检查保证。
func _required_next(graph: Dictionary, source: Dictionary, port_id: String, allowed_targets: Dictionary, diagnostics: Array) -> String:
	var graph_id := str(graph.get("graphId", ""))
	var source_id := str(source.get("id", ""))
	var links := _outgoing_links(graph, source_id, port_id)
	if links.is_empty():
		diagnostics.append(_error("missing_flow_link", "Flow output '" + port_id + "' must connect to exactly one target.", graph_id, source_id, port_id))
		return ""
	if links.size() != 1:
		diagnostics.append(_error("ambiguous_flow_link", "Flow output '" + port_id + "' has more than one target.", graph_id, source_id, port_id))
		return ""
	var link: Dictionary = links[0]
	var target_id := str(link.get("targetNodeId", ""))
	var target: Dictionary = allowed_targets.get(target_id, {})
	if target.is_empty() or str(link.get("targetPortId", "")) != "enter":
		diagnostics.append(_error("invalid_scene_route", "Root flow must connect a Scene output to another Scene enter port.", graph_id, source_id, port_id, str(link.get("linkId", ""))))
		return ""
	return target_id

func _compile_scene_script(graph: Dictionary, diagnostics: Array) -> String:
	var graph_id := str(graph.get("graphId", ""))
	var nodes_by_id := _index_nodes(graph, diagnostics)
	if _has_errors(diagnostics):
		return ""
	var entries: Array = []
	for node in graph.get("nodes", []):
		if node is Dictionary and node.get("type", "") == "gel.graph_input":
			entries.append(node)
	if entries.size() != 1:
		diagnostics.append(_error("invalid_scene_entry", "Each scene graph must contain exactly one Entry node.", graph_id))
		return ""
	var entry: Dictionary = entries[0]
	var initial_node_id := _required_scene_next(graph, entry, "out", nodes_by_id, diagnostics)
	if initial_node_id.is_empty():
		return ""
	var reachable := _reachable_executable_nodes(graph, initial_node_id, nodes_by_id, diagnostics)
	if _has_errors(diagnostics):
		return ""
	var terminal_nodes: Dictionary = {}
	for node_id in reachable:
		var node: Dictionary = nodes_by_id[node_id]
		if node.get("type", "") in ["gel.graph_output", "gel.end_story"]:
			terminal_nodes[node_id] = true
	if terminal_nodes.is_empty():
		diagnostics.append(_error("missing_terminal", "Reachable scene flow must lead to Graph Output or End Story.", graph_id, initial_node_id))
		return ""
	_validate_terminating_flow(graph, reachable, terminal_nodes, nodes_by_id, diagnostics)
	if _has_errors(diagnostics):
		return ""

	var cases: Array = []
	for node in graph.get("nodes", []):
		if not node is Dictionary:
			continue
		var node_type := str(node.get("type", ""))
		match node_type:
			"gel.graph_input":
				pass
			"gel.dialogue":
				cases.append_array(_compile_dialogue_case(graph, node, nodes_by_id, diagnostics))
			"gel.if":
				cases.append_array(_compile_if_case(graph, node, nodes_by_id, diagnostics))
			"gel.choice":
				cases.append_array(_compile_choice_case(graph, node, nodes_by_id, diagnostics))
			"gel.graph_output":
				cases.append_array(_compile_output_case(node, graph_id, diagnostics))
			"gel.end_story":
				cases.append_array(_compile_end_case(node))
			"gel.boolean":
				# Boolean is a compile-time data source for If.condition; it has no flow case.
				pass
			_:
				diagnostics.append(_error("unsupported_node_type", "Node type '" + node_type + "' is not supported by Runtime Package v1 export.", graph_id, str(node.get("id", ""))))
	if _has_errors(diagnostics):
		return ""
	if cases.is_empty():
		diagnostics.append(_error("empty_scene", "Scene graph has no executable story nodes.", graph_id))
		return ""
	return _render_scene_lua(initial_node_id, cases)

func _reachable_executable_nodes(graph: Dictionary, initial_node_id: String, nodes_by_id: Dictionary, diagnostics: Array) -> Dictionary:
	var graph_id := str(graph.get("graphId", ""))
	var reachable: Dictionary = {}
	var queue: Array = [initial_node_id]
	var cursor := 0
	while cursor < queue.size():
		var node_id: String = queue[cursor]
		cursor += 1
		if reachable.has(node_id):
			continue
		var node: Dictionary = nodes_by_id.get(node_id, {})
		if node.is_empty() or not EXECUTABLE_NODE_TYPES.has(node.get("type", "")):
			diagnostics.append(_error("invalid_flow_target", "Reachable flow references a non-executable node.", graph_id, node_id))
			continue
		reachable[node_id] = true
		for port_id in _flow_output_ids(node):
			var next_id := _required_scene_next(graph, node, port_id, nodes_by_id, diagnostics)
			if not next_id.is_empty():
				queue.append(next_id)
	return reachable

## 运行期 Lua 是一个明确的状态机；每个执行步都必须缩短到终点的距离。
## 这拒绝任何可从入口抵达的流程环，即使该环另有一条可选的终点分支，避免
## 生成的 while true 在常量条件或玩家选择下永远不 yield。
func _validate_terminating_flow(graph: Dictionary, reachable: Dictionary, terminal_nodes: Dictionary, nodes_by_id: Dictionary, diagnostics: Array) -> void:
	var graph_id := str(graph.get("graphId", ""))
	var predecessors: Dictionary = {}
	for node_id in reachable:
		predecessors[node_id] = []
	for node_id in reachable:
		var node: Dictionary = nodes_by_id[node_id]
		for port_id in _flow_output_ids(node):
			var links := _outgoing_links(graph, node_id, port_id)
			if links.size() != 1:
				continue
			var target_id := str(links[0].get("targetNodeId", ""))
			if reachable.has(target_id):
				predecessors[target_id].append(node_id)
	var can_finish: Dictionary = {}
	var queue: Array = terminal_nodes.keys()
	var cursor := 0
	while cursor < queue.size():
		var node_id: String = queue[cursor]
		cursor += 1
		if can_finish.has(node_id):
			continue
		can_finish[node_id] = true
		for predecessor in predecessors.get(node_id, []):
			queue.append(predecessor)
	for node_id in reachable:
		if not can_finish.has(node_id):
			diagnostics.append(_error("non_terminating_flow", "Flow node cannot reach Graph Output or End Story.", graph_id, node_id))

	# Kahn's algorithm identifies all remaining cycles without relying on canvas
	# position or node creation order.
	var indegrees: Dictionary = {}
	var adjacency: Dictionary = {}
	for node_id in reachable:
		indegrees[node_id] = 0
		adjacency[node_id] = []
	for node_id in reachable:
		var node: Dictionary = nodes_by_id[node_id]
		for port_id in _flow_output_ids(node):
			var links := _outgoing_links(graph, node_id, port_id)
			if links.size() != 1:
				continue
			var target_id := str(links[0].get("targetNodeId", ""))
			if reachable.has(target_id):
				adjacency[node_id].append(target_id)
				indegrees[target_id] += 1
	var roots: Array = []
	for node_id in indegrees:
		if indegrees[node_id] == 0:
			roots.append(node_id)
	var visited := 0
	var cursor2 := 0
	while cursor2 < roots.size():
		var node_id: String = roots[cursor2]
		cursor2 += 1
		visited += 1
		for target_id in adjacency[node_id]:
			indegrees[target_id] -= 1
			if indegrees[target_id] == 0:
				roots.append(target_id)
	if visited != reachable.size():
		for node_id in reachable:
			if indegrees[node_id] > 0:
				diagnostics.append(_error("flow_cycle", "Reachable runtime flow must not contain a cycle.", graph_id, node_id))

func _flow_output_ids(node: Dictionary) -> Array:
	match node.get("type", ""):
		"gel.dialogue": return ["next"]
		"gel.if": return ["true", "false"]
		"gel.choice":
			var ports: Array = []
			for item in (node.get("data", {}) as Dictionary).get("choices", []):
				if item is Dictionary:
					ports.append(str(item.get("choice_id", "")))
			return ports
		"gel.graph_output", "gel.end_story": return []
	return []

func _compile_dialogue_case(graph: Dictionary, node: Dictionary, nodes_by_id: Dictionary, diagnostics: Array) -> Array:
	var graph_id := str(graph.get("graphId", ""))
	var node_id := str(node.get("id", ""))
	var text_result := _resolve_input(graph, node, "text", "string", false, nodes_by_id, diagnostics)
	var speaker_result := _resolve_input(graph, node, "speaker", "character", true, nodes_by_id, diagnostics)
	var next_id := _required_scene_next(graph, node, "next", nodes_by_id, diagnostics)
	if not bool(text_result.get("ok", false)) or not bool(speaker_result.get("ok", false)) or next_id.is_empty():
		return []
	var lines: Array = [_case_head(node_id)]
	var speaker: Variant = speaker_result.value
	if speaker == null:
		lines.append("      ctx.dialogue:narrate(" + _lua_string(str(text_result.value)) + ")")
	else:
		# 角色工程、CharacterRegistry 和 scene.cast 尚未在 Godot 项目模型中
		# 建立。若此处静默生成 say("alice", ...) ，引擎会收到一个未声明
		# 的说话人，包级校验无法保证其合法性。因此 V1 导出只接受 narration。
		diagnostics.append(_error("unsupported_speaker", "Character dialogue requires exported character and scene cast definitions; use an empty speaker for narration in this export profile.", graph_id, node_id, "speaker"))
		return []
	lines.append("      node = " + _lua_string(next_id))
	return lines

func _compile_if_case(graph: Dictionary, node: Dictionary, nodes_by_id: Dictionary, diagnostics: Array) -> Array:
	var condition_result := _resolve_input(graph, node, "condition", "boolean", false, nodes_by_id, diagnostics)
	var true_id := _required_scene_next(graph, node, "true", nodes_by_id, diagnostics)
	var false_id := _required_scene_next(graph, node, "false", nodes_by_id, diagnostics)
	if not bool(condition_result.get("ok", false)) or true_id.is_empty() or false_id.is_empty():
		return []
	var lines: Array = [_case_head(str(node.get("id", "")))]
	lines.append("      if " + ("true" if bool(condition_result.value) else "false") + " then")
	lines.append("        node = " + _lua_string(true_id))
	lines.append("      else")
	lines.append("        node = " + _lua_string(false_id))
	lines.append("      end")
	return lines

func _compile_choice_case(graph: Dictionary, node: Dictionary, nodes_by_id: Dictionary, diagnostics: Array) -> Array:
	var graph_id := str(graph.get("graphId", ""))
	var node_id := str(node.get("id", ""))
	var data: Dictionary = node.get("data", {})
	var choices: Variant = data.get("choices", [])
	if not choices is Array or choices.is_empty():
		diagnostics.append(_error("empty_choice", "Choice node must contain at least one option.", graph_id, node_id))
		return []
	var routes: Array = []
	for item in choices:
		if not item is Dictionary:
			diagnostics.append(_error("invalid_choice", "Choice node contains an invalid option.", graph_id, node_id))
			continue
		var choice_id := str(item.get("choice_id", ""))
		var label: Variant = item.get("label", null)
		if choice_id.is_empty() or not label is String:
			diagnostics.append(_error("invalid_choice", "Choice option requires a stable ID and text label.", graph_id, node_id))
			continue
		var target_id := _required_scene_next(graph, node, choice_id, nodes_by_id, diagnostics)
		if not target_id.is_empty():
			routes.append({"id": choice_id, "label": label, "target": target_id})
	if _has_errors(diagnostics):
		return []
	var lines: Array = [_case_head(node_id), "      local selected = ctx.dialogue:choice({"]
	for route in routes:
		lines.append("        { id = " + _lua_string(route.id) + ", text = " + _lua_string(route.label) + " },")
	lines.append("      })")
	for index in range(routes.size()):
		var route: Dictionary = routes[index]
		lines.append(("      if " if index == 0 else "      elseif ") + "selected == " + _lua_string(route.id) + " then")
		lines.append("        node = " + _lua_string(route.target))
	lines.append("      else")
	lines.append("        error(\"Choice response did not match a compiled option\")")
	lines.append("      end")
	return lines

func _compile_output_case(node: Dictionary, graph_id: String, diagnostics: Array) -> Array:
	var interface_id := _interface_id(node)
	if interface_id.is_empty():
		diagnostics.append(_error("invalid_output", "Scene output is missing a stable interface ID.", graph_id, str(node.get("id", ""))))
		return []
	return [_case_head(str(node.get("id", ""))), "      return ctx.flow:exit(" + _lua_string(interface_id) + ")"]

func _compile_end_case(node: Dictionary) -> Array:
	return [_case_head(str(node.get("id", ""))), "      return ctx.flow:end_story()"]

func _required_scene_next(graph: Dictionary, source: Dictionary, port_id: String, nodes_by_id: Dictionary, diagnostics: Array) -> String:
	var graph_id := str(graph.get("graphId", ""))
	var source_id := str(source.get("id", ""))
	var links := _outgoing_links(graph, source_id, port_id)
	if links.is_empty():
		diagnostics.append(_error("missing_flow_link", "Flow output '" + port_id + "' must connect to exactly one target.", graph_id, source_id, port_id))
		return ""
	if links.size() != 1:
		diagnostics.append(_error("ambiguous_flow_link", "Flow output '" + port_id + "' has more than one target.", graph_id, source_id, port_id))
		return ""
	var link: Dictionary = links[0]
	var target_id := str(link.get("targetNodeId", ""))
	var target: Dictionary = nodes_by_id.get(target_id, {})
	if target.is_empty() or not EXECUTABLE_NODE_TYPES.has(target.get("type", "")):
		diagnostics.append(_error("invalid_flow_target", "Flow output '" + port_id + "' must target an executable story node.", graph_id, source_id, port_id, str(link.get("linkId", ""))))
		return ""
	return target_id

func _resolve_input(graph: Dictionary, node: Dictionary, port_id: String, value_type: String, optional: bool, nodes_by_id: Dictionary, diagnostics: Array) -> Dictionary:
	var graph_id := str(graph.get("graphId", ""))
	var node_id := str(node.get("id", ""))
	var links := _incoming_links(graph, node_id, port_id)
	if links.size() > 1:
		diagnostics.append(_error("ambiguous_data_link", "Data input '" + port_id + "' has more than one source.", graph_id, node_id, port_id))
		return {"ok": false}
	if links.size() == 1:
		var link: Dictionary = links[0]
		var source_id := str(link.get("sourceNodeId", ""))
		var source: Dictionary = nodes_by_id.get(source_id, {})
		if value_type == "boolean" and source.get("type", "") == "gel.boolean" and str(link.get("sourcePortId", "")) == "value":
			var source_data: Dictionary = source.get("data", {})
			var source_value: Variant = source_data.get("value", null)
			if source_value is bool:
				return {"ok": true, "value": source_value}
		diagnostics.append(_error("unsupported_data_link", "Input '" + port_id + "' only supports a local value" + (" or a Boolean node" if value_type == "boolean" else "") + ".", graph_id, node_id, port_id, str(link.get("linkId", ""))))
		return {"ok": false}

	var inputs: Dictionary = node.get("inputs", {})
	if not inputs.has(port_id):
		if optional:
			return {"ok": true, "value": null}
		diagnostics.append(_error("missing_required_input", "Node requires a local value or data connection for '" + port_id + "'.", graph_id, node_id, port_id))
		return {"ok": false}
	var value: Variant = inputs[port_id]
	if not _matches_value_type(value, value_type):
		diagnostics.append(_error("invalid_input_value", "Input '" + port_id + "' has an invalid " + value_type + " value.", graph_id, node_id, port_id))
		return {"ok": false}
	return {"ok": true, "value": value}

func _validate_root_links(root: Dictionary, scenes_by_node: Dictionary, diagnostics: Array) -> void:
	var graph_id := str(root.get("graphId", ""))
	for link in root.get("links", []):
		if not link is Dictionary:
			continue
		var source_id := str(link.get("sourceNodeId", ""))
		var target_id := str(link.get("targetNodeId", ""))
		if scenes_by_node.has(source_id):
			var source: Dictionary = scenes_by_node[source_id]
			var child_graph_id := _child_graph_id(source)
			# The structural document validation already guarantees projected ports. The
			# compiler still verifies the target is a Scene enter so a restored or
			# externally-created snapshot cannot create a malformed Runtime route.
			if not scenes_by_node.has(target_id) or str(link.get("targetPortId", "")) != "enter":
				diagnostics.append(_error("invalid_scene_route", "Scene routes must target another Scene enter port.", graph_id, source_id, str(link.get("sourcePortId", "")), str(link.get("linkId", ""))))
			if child_graph_id.is_empty():
				diagnostics.append(_error("invalid_scene", "Scene route source has no child graph.", graph_id, source_id))

func _ordered_graph_outputs(graph: Dictionary) -> Array:
	var outputs: Array = []
	for node in graph.get("nodes", []):
		if node is Dictionary and node.get("type", "") == "gel.graph_output":
			outputs.append(node)
	outputs.sort_custom(func(left, right):
		var left_order := int((left.get("data", {}) as Dictionary).get("order", 0))
		var right_order := int((right.get("data", {}) as Dictionary).get("order", 0))
		return left_order < right_order if left_order != right_order else str(left.get("id", "")) < str(right.get("id", ""))
	)
	return outputs

func _index_nodes(graph: Dictionary, diagnostics: Array) -> Dictionary:
	var nodes: Dictionary = {}
	var graph_id := str(graph.get("graphId", ""))
	for node in graph.get("nodes", []):
		if not node is Dictionary:
			diagnostics.append(_error("invalid_snapshot", "Scene graph contains an invalid node record.", graph_id))
			continue
		var node_id := str(node.get("id", ""))
		if node_id.is_empty() or nodes.has(node_id):
			diagnostics.append(_error("invalid_snapshot", "Scene graph contains a missing or duplicate node ID.", graph_id, node_id))
			continue
		nodes[node_id] = node
	return nodes

func _outgoing_links(graph: Dictionary, source_id: String, source_port_id: String) -> Array:
	var result: Array = []
	for raw_link in graph.get("links", []):
		if raw_link is Dictionary and raw_link.get("sourceNodeId", "") == source_id and raw_link.get("sourcePortId", "") == source_port_id:
			result.append(raw_link)
	return result

func _incoming_links(graph: Dictionary, target_id: String, target_port_id: String) -> Array:
	var result: Array = []
	for raw_link in graph.get("links", []):
		if raw_link is Dictionary and raw_link.get("targetNodeId", "") == target_id and raw_link.get("targetPortId", "") == target_port_id:
			result.append(raw_link)
	return result

func _scene_id(node: Dictionary) -> String:
	var data: Dictionary = node.get("data", {})
	return str(data.get("sceneId", ""))

func _child_graph_id(node: Dictionary) -> String:
	var data: Dictionary = node.get("data", {})
	return str(data.get("childGraphId", ""))

func _scene_title(node: Dictionary) -> String:
	var data: Dictionary = node.get("data", {})
	return str(data.get("displayName", "")).strip_edges()

func _interface_id(node: Dictionary) -> String:
	var data: Dictionary = node.get("data", {})
	return str(data.get("interfaceId", ""))

func _case_head(node_id: String) -> String:
	return "    if node == " + _lua_string(node_id) + " then"

func _render_scene_lua(initial_node_id: String, cases: Array) -> String:
	var lines: Array = [
		"-- Generated by GEL Node Map. Do not edit this file directly.",
		"return function(ctx)",
		"  local node = " + _lua_string(initial_node_id),
		"  while true do",
	]
	for index in range(cases.size()):
		var line := str(cases[index])
		if line.begins_with("    if node == ") and index > 0:
			line = "    elseif" + line.trim_prefix("    if")
		lines.append(line)
	lines.append("    else")
	lines.append("      error(\"Unknown compiled flow node\")")
	lines.append("    end")
	lines.append("  end")
	lines.append("end")
	return "\n".join(lines) + "\n"

## 生成 Lua 5.3 兼容的双引号字符串。Runtime Package 允许 UTF-8 文本；控制
## 字符使用 Lua 十进制转义，避免 JSON 的 \\uXXXX 转义在 Lua 中失去语义。
func _lua_string(value: String) -> String:
	var output := "\""
	for index in range(value.length()):
		var code := value.unicode_at(index)
		match code:
			34: output += "\\\"" # "
			92: output += "\\\\" # \\
			10: output += "\\n"
			13: output += "\\r"
			9: output += "\\t"
			0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31:
				output += "\\%03d" % code
			_:
				output += char(code)
	return output + "\""

func _matches_value_type(value: Variant, value_type: String) -> bool:
	match value_type:
		"boolean": return value is bool
		"string": return value is String
		"character": return value == null or value is String
	return false

func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null

func _error(code: String, message: String, graph_id: String = "", node_id: String = "", port_id: String = "", link_id: String = "") -> Dictionary:
	return {
		"code": code,
		"message": message,
		"severity": "error",
		"graph_id": graph_id,
		"node_id": node_id,
		"port_id": port_id,
		"link_id": link_id,
	}

func _has_errors(diagnostics: Array) -> bool:
	for diagnostic in diagnostics:
		if not diagnostic is Dictionary or diagnostic.get("severity", "error") == "error":
			return true
	return false

func _failure(diagnostics: Array) -> Dictionary:
	return {"ok": false, "diagnostics": diagnostics, "manifest": {}, "scripts": {}}
