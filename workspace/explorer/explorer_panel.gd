@tool
extends VBoxContainer
class_name EditorExplorerPanel

## 通用 Explorer 面板。
##
## 面板只组合标题、筛选框和 EditorExplorerTree，不创建或解释业务数据。调用方
## 通过 set_model() 提供条目模型，未来可以替换为 SceneMap、文件系统或混合数据源。

signal entry_selected(entry_id: String)
signal entry_activated(entry_id: String)
signal refresh_requested()

@onready var _heading: Label = $ExplorerToolbar/Heading
@onready var _filter: LineEdit = $ExplorerToolbar/Filter
@onready var _tree = $ExplorerTree
@onready var _refresh_button: Button = $ExplorerToolbar/Refresh

var _model
var _pending_heading: String = ""
var _pending_filter_query: String = ""

func _ready() -> void:
    _filter.text_changed.connect(_on_filter_text_changed)
    _refresh_button.pressed.connect(_on_refresh_pressed)
    _tree.entry_selected.connect(_on_entry_selected)
    _tree.entry_activated.connect(_on_entry_activated)
    if not _pending_heading.is_empty():
        _heading.text = _pending_heading
    _filter.text = _pending_filter_query
    if _model != null:
        _tree.set_model(_model)
    _tree.set_filter_query(_pending_filter_query)

func set_heading(text: String) -> void:
    _pending_heading = text
    if is_instance_valid(_heading):
        _heading.text = text

func set_model(model) -> void:
    _model = model
    if is_node_ready():
        _tree.set_model(_model)

func get_model():
    return _model

func get_tree_control() -> Tree:
    return _tree

func set_filter_query(query: String) -> void:
    _pending_filter_query = query
    if not is_node_ready():
        return
    _filter.text = query
    _tree.set_filter_query(query)

func _on_filter_text_changed(text: String) -> void:
    _pending_filter_query = text
    _tree.set_filter_query(text)

func _on_refresh_pressed() -> void:
    refresh_requested.emit()
    if _model != null:
        _tree.rebuild()

func _on_entry_selected(entry_id: String) -> void:
    entry_selected.emit(entry_id)

func _on_entry_activated(entry_id: String) -> void:
    entry_activated.emit(entry_id)
