@tool
extends Tree
class_name EditorExplorerTree

## 通用 Explorer Tree。
##
## Tree 只负责把 EditorExplorerModel 的条目投影为 Godot TreeItem，并维护显示层的
## 展开、筛选、选择和激活状态。它不理解 Scene、磁盘文件或其他业务类型。

signal entry_selected(entry_id: String)
signal entry_activated(entry_id: String)

var _model
var _filter_query: String = ""
var _selected_entry_id: String = ""
var _is_rebuilding: bool = false
var _has_built_once: bool = false

func _ready() -> void:
    hide_root = false
    columns = 1
    allow_reselect = true
    item_selected.connect(_on_item_selected)
    item_activated.connect(_on_item_activated)
    if _model != null:
        rebuild()

func set_model(model) -> void:
    if _model != null and _model.has_signal("changed") and _model.changed.is_connected(_on_model_changed):
        _model.changed.disconnect(_on_model_changed)
    _model = model
    if _model != null and _model.has_signal("changed"):
        _model.changed.connect(_on_model_changed)
    if is_node_ready():
        rebuild()

func get_model():
    return _model

func set_filter_query(query: String) -> void:
    var normalized := query.strip_edges().to_lower()
    if _filter_query == normalized:
        return
    _filter_query = normalized
    if is_node_ready():
        rebuild()

func get_filter_query() -> String:
    return _filter_query

func get_selected_entry_id() -> String:
    return _selected_entry_id

func select_entry(entry_id: String) -> bool:
    if _model == null or not _model.has_entry(entry_id):
        return false
    var item: TreeItem = _find_tree_item(get_root(), entry_id)
    if item == null:
        return false
    _selected_entry_id = entry_id
    item.select(0)
    return true

func rebuild() -> void:
    var expanded_ids := _collect_expanded_ids()
    var selected_id := _selected_entry_id
    var has_previous_state := _has_built_once
    _is_rebuilding = true
    clear()

    if _model == null:
        _selected_entry_id = ""
        _has_built_once = true
        _is_rebuilding = false
        return

    var root_entry = _model.get_root()
    if root_entry == null:
        _selected_entry_id = ""
        _has_built_once = true
        _is_rebuilding = false
        return

    var matches: Dictionary = {}
    var root_item: TreeItem = create_item()
    _populate_item(root_item, root_entry.entry_id, matches, expanded_ids, has_previous_state)
    _restore_selection(root_item, selected_id)
    _has_built_once = true
    _is_rebuilding = false

func _populate_item(item: TreeItem, entry_id: String, matches: Dictionary, expanded_ids: Dictionary, has_previous_state: bool) -> void:
    var entry = _model.get_entry(entry_id)
    if entry == null:
        return

    item.set_text(0, entry.title)
    item.set_metadata(0, entry.entry_id)
    var icon = _get_entry_icon(entry.icon_hint)
    if icon != null:
        item.set_icon(0, icon)

    for child_entry in _model.get_children(entry_id):
        if not _entry_matches_filter(child_entry.entry_id, matches):
            continue
        var child_item: TreeItem = create_item(item)
        _populate_item(child_item, child_entry.entry_id, matches, expanded_ids, has_previous_state)

    if entry.is_container:
        if not _filter_query.is_empty() or not has_previous_state:
            item.collapsed = false
        else:
            item.collapsed = not expanded_ids.has(entry.entry_id)
    else:
        item.collapsed = false

func _entry_matches_filter(entry_id: String, matches: Dictionary) -> bool:
    if matches.has(entry_id):
        return bool(matches[entry_id])
    if _model == null or not _model.has_entry(entry_id):
        matches[entry_id] = false
        return false
    if _model.matches_entry(entry_id, _filter_query):
        matches[entry_id] = true
        return true
    for child_entry in _model.get_children(entry_id):
        if _entry_matches_filter(child_entry.entry_id, matches):
            matches[entry_id] = true
            return true
    matches[entry_id] = false
    return false

func _collect_expanded_ids() -> Dictionary:
    var result: Dictionary = {}
    if not _has_built_once:
        return result
    _collect_expanded_ids_from_item(get_root(), result)
    return result

func _collect_expanded_ids_from_item(item: TreeItem, result: Dictionary) -> void:
    if item == null:
        return
    var entry_id := str(item.get_metadata(0))
    if not item.collapsed and not entry_id.is_empty():
        result[entry_id] = true
    var child := item.get_first_child()
    while child != null:
        _collect_expanded_ids_from_item(child, result)
        child = child.get_next()

func _restore_selection(root_item: TreeItem, selected_id: String) -> void:
    if selected_id.is_empty():
        _selected_entry_id = ""
        return
    var selected_item: TreeItem = _find_tree_item(root_item, selected_id)
    if selected_item == null:
        _selected_entry_id = ""
        return
    _selected_entry_id = selected_id
    selected_item.select(0)

func _find_tree_item(item: TreeItem, entry_id: String) -> TreeItem:
    if item == null:
        return null
    if str(item.get_metadata(0)) == entry_id:
        return item
    var child := item.get_first_child()
    while child != null:
        var result: TreeItem = _find_tree_item(child, entry_id)
        if result != null:
            return result
        child = child.get_next()
    return null

func _on_model_changed(_revision: int) -> void:
    if is_node_ready():
        rebuild()

func _on_item_selected() -> void:
    if _is_rebuilding:
        return
    var item: TreeItem = get_selected()
    if item == null:
        _selected_entry_id = ""
        return
    _selected_entry_id = str(item.get_metadata(0))
    if not _selected_entry_id.is_empty():
        entry_selected.emit(_selected_entry_id)

func _on_item_activated() -> void:
    if _is_rebuilding:
        return
    var item: TreeItem = get_selected()
    if item == null:
        return
    var entry_id := str(item.get_metadata(0))
    if not entry_id.is_empty():
        entry_activated.emit(entry_id)

func _get_entry_icon(icon_hint: String):
    if icon_hint == "container":
        if has_theme_icon("Folder", "EditorIcons"):
            return get_theme_icon("Folder", "EditorIcons")
        if has_theme_icon("folder", "FileDialog"):
            return get_theme_icon("folder", "FileDialog")
    elif icon_hint == "document":
        if has_theme_icon("File", "EditorIcons"):
            return get_theme_icon("File", "EditorIcons")
        if has_theme_icon("file", "FileDialog"):
            return get_theme_icon("file", "FileDialog")
    return null
