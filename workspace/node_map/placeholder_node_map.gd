@tool
extends VBoxContainer

## 使用静态场景预览节点图，独立于领域模型和工程文件。
const GRAPH_NAMES := {"root": "RootGraph", "prologue": "PrologueGraph", "chapter-one": "ChapterGraph", "ending": "EndingGraph"}
const GRAPH_TITLES := {"root": "Root Graph", "prologue": "Root Graph / Prologue", "chapter-one": "Root Graph / Chapter One", "ending": "Root Graph / Ending"}

@onready var _back: Button = $Toolbar/Row/Back
@onready var _breadcrumb: Label = $Toolbar/Row/Breadcrumb
@onready var _counts: Label = $Status/Counts
@onready var _selection: Label = $Status/Selection

var active_graph_key := "root"
var _visited: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_back.pressed.connect(show_graph.bind("root"))
	$Toolbar/Row/FrameAll.pressed.connect(_frame_active)
	$Toolbar/Row/Reset.pressed.connect(_reset_active)
	for key in GRAPH_NAMES:
		var graph = $GraphStack.get_node(GRAPH_NAMES[key])
		graph.scene_requested.connect(show_graph)
		graph.connections_changed.connect(_on_connections_changed)
		graph.selection_changed.connect(_on_selection_changed)
	show_graph("root")

func get_active_graph() -> GraphEdit:
	return $GraphStack.get_node(GRAPH_NAMES[active_graph_key])

func show_graph(scene_key: String) -> void:
	if not GRAPH_NAMES.has(scene_key):
		return
	active_graph_key = scene_key
	for key in GRAPH_NAMES:
		$GraphStack.get_node(GRAPH_NAMES[key]).visible = key == scene_key
	_breadcrumb.text = GRAPH_TITLES[scene_key]
	_back.disabled = scene_key == "root"
	_selection.text = ""
	for node in get_active_graph().get_graph_nodes():
		if node.selected:
			_selection.text = node.title
	_update_counts()
	if not _visited.has(scene_key):
		_frame_after_layout(scene_key)

func _frame_after_layout(scene_key: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if active_graph_key == scene_key:
		_visited[scene_key] = true
		_frame_active()

func _frame_active() -> void:
	get_active_graph().frame_all()

func _reset_active() -> void:
	get_active_graph().reset_preview()

func _on_connections_changed(_count: int) -> void:
	_update_counts()

func _update_counts() -> void:
	var graph = get_active_graph()
	_counts.text = "%d nodes   %d links" % [graph.get_graph_nodes().size(), graph.get_connection_list().size()]

func _on_selection_changed(title: String) -> void:
	_selection.text = title
