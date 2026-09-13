extends RefCounted

## Node Map 到通用 Explorer 的只读投影。Explorer 本身不依赖 Node Map；只有这个
## 整合层知道如何把 Scene 节点转换成 Explorer 条目。
const MODEL_SCRIPT := preload("res://workspace/explorer/explorer_model.gd")
const ENTRY_SCRIPT := preload("res://workspace/explorer/explorer_entry.gd")

signal changed

var document
var model

func _init(p_document = null) -> void:
	model = MODEL_SCRIPT.new()
	set_document(p_document)

func set_document(p_document) -> void:
	if document != null and document.has_signal("changed") and document.changed.is_connected(_on_document_changed):
		document.changed.disconnect(_on_document_changed)
	document = p_document
	if document != null and document.has_signal("changed"):
		document.changed.connect(_on_document_changed)
	_refresh()

func get_model():
	return model

func refresh() -> void:
	_refresh()

func _on_document_changed(_change: Dictionary) -> void:
	_refresh()

func _refresh() -> void:
	if document == null:
		model.clear()
		changed.emit()
		return
	var entries: Array = [ENTRY_SCRIPT.root("project", "Project", ["gel project"])]
	entries.append(ENTRY_SCRIPT.container("scenes", "Scenes", "project", ["scene collection"]))
	for scene in document.get_nodes(document.root_graph_id):
		if scene.node_type != "gel.scene":
			continue
		var scene_entry_id: String = "scene:" + str(scene.node_id)
		var title := str(scene.get_parameter_values().get("display_name", "Scene"))
		if title.strip_edges().is_empty():
			title = "Scene"
		entries.append(ENTRY_SCRIPT.container(
			scene_entry_id,
			title,
			"scenes",
			[title, str(scene.scene_id)],
			{
				"source_kind": "scene",
				"node_id": scene.node_id,
				"scene_id": scene.scene_id,
				"graph_id": scene.child_graph_id,
			},
		))
		entries.append(ENTRY_SCRIPT.document(
			"scene-script:" + str(scene.node_id),
			"main.lua",
			scene_entry_id,
			["scenes/" + str(scene.scene_id) + "/main.lua", "scene script"],
			{
				"source_kind": "scene_script",
				"node_id": scene.node_id,
				"graph_id": scene.child_graph_id,
			},
		))
	if not model.set_entries(entries, "project"):
		return
	changed.emit()
