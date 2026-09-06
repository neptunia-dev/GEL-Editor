extends Control
class_name EditorShell

## 工作区占位 Shell。
##
## 具体节点和视觉布局全部保存在 editor_shell.tscn，方便直接在 Godot 编辑器中查看
## 和调整。脚本只处理少量交互状态，不在运行时创建布局节点。

const BOTTOM_COLLAPSED_HEIGHT := 34
const BOTTOM_EXPANDED_HEIGHT := 190
const WINDOW_BOTTOM := 6
const WINDOW_SHOW_ALL := 7

@onready var _main_split: HSplitContainer = $EditorRoot/DockHSplitMain
@onready var _center_split: VSplitContainer = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter
@onready var _bottom_panel: TabContainer = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/EditorBottomPanel
@onready var _dock_toggle: Button = $EditorRoot/EditorTitleBar/TitleBarRow/ToggleDocks
@onready var _bottom_toggle: Button = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace/WorkspaceToolbar/ToolbarRow/ToggleBottomPanel
@onready var _left_region: Control = $EditorRoot/DockHSplitMain/DockVSplitLeft
@onready var _right_region: Control = $EditorRoot/DockHSplitMain/DockVSplitRight
@onready var _windows_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/WindowsMenu.get_popup()

var _docks_visible := true
var _bottom_expanded := false
var _bottom_last_tab := 0
var _window_panels: Array[Control] = []

func _ready() -> void:
	_configure_menus()
	_dock_toggle.pressed.connect(_on_toggle_docks)
	_bottom_toggle.pressed.connect(_on_toggle_bottom)
	_bottom_panel.tab_changed.connect(_on_bottom_tab_changed)

	_center_split.set_dragger_visibility(SplitContainer.DRAGGER_VISIBLE)
	_set_bottom_expanded(false)
	_set_docks_visible(true)

func _configure_menus() -> void:
	var node_map := find_child("NodeMapEditor", true, false)
	_window_panels.assign([
		_left_region.get_node("LeftUpper"),
		_left_region.get_node("LeftLower"),
		_right_region.get_node("RightUpper"),
		_right_region.get_node("RightLower"),
		node_map.get_node("Layout/InspectorScroll"),
		node_map.get_node("Layout/Diagnostics"),
	])
	var labels := [
		"Left Upper Dock (Scene / Import)",
		"Left Lower Dock (Explorer)",
		"Right Upper Dock (Inspector / Node)",
		"Right Lower Dock (History / Signals)",
		"NodeMap Inspector",
		"NodeMap Diagnostics",
	]
	for index in _window_panels.size():
		_windows_popup.add_check_item(labels[index], index)
		_window_panels[index].visibility_changed.connect(_sync_windows_menu)
	_windows_popup.add_check_item("Bottom Panel (Output / Problems / Debugger)", WINDOW_BOTTOM)
	_windows_popup.add_separator()
	_windows_popup.add_item("Show All", WINDOW_SHOW_ALL)
	_windows_popup.about_to_popup.connect(_sync_windows_menu)
	_windows_popup.id_pressed.connect(_on_window_action)

	var main_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/MainMenu.get_popup()
	main_popup.add_item("Project")
	main_popup.add_item("Editor Settings")
	main_popup.add_separator()
	main_popup.add_item("Quit")
	main_popup.id_pressed.connect(func(id):
		if id == 3: find_child("NodeMapEditor", true, false).request_quit())

	var project_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/ProjectMenu.get_popup()
	project_popup.add_item("Open Project")
	project_popup.add_item("Project Settings")

	var edit_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/EditMenu.get_popup()
	edit_popup.add_item("Undo", 100)
	edit_popup.add_item("Redo", 101)
	edit_popup.add_separator()
	edit_popup.add_item("Focus Selected", 102)
	edit_popup.add_item("Focus All", 103)
	edit_popup.add_item("Auto Layout", 104)
	edit_popup.add_separator()
	edit_popup.add_item("Save As", 105)
	edit_popup.add_item("Open", 106)
	edit_popup.add_item("New", 107)
	edit_popup.id_pressed.connect(_on_edit_action)

func _on_edit_action(id: int) -> void:
	var node_map := get_node_or_null("EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace/WorkspaceCanvas/CanvasRoot/NodeMapEditor")
	if node_map == null:
		return
	if id == 100:
		node_map.undo()
	elif id == 101:
		node_map.redo()
	elif id == 102:
		node_map.focus_nodes(true)
	elif id == 103:
		node_map.focus_nodes(false)
	elif id == 104:
		node_map.auto_layout()
	elif id == 105:
		node_map._show_file_dialog(true)
	elif id == 106:
		node_map._show_file_dialog(false)
	elif id == 107:
		node_map.close_document()

func _on_toggle_docks() -> void:
	_set_docks_visible(not _docks_visible)

func _set_docks_visible(visible: bool) -> void:
	for index in 4:
		_window_panels[index].visible = visible
	_sync_windows_menu()

func _on_window_action(id: int) -> void:
	if id == WINDOW_BOTTOM:
		_on_toggle_bottom()
	elif id == WINDOW_SHOW_ALL:
		for panel in _window_panels:
			panel.show()
		_set_bottom_expanded(true)
	elif id >= 0 and id < _window_panels.size():
		_window_panels[id].visible = not _window_panels[id].visible
	_sync_windows_menu()

func _sync_windows_menu() -> void:
	# Hide empty split regions too, so their minimum widths do not reserve space.
	_left_region.visible = _window_panels[0].visible or _window_panels[1].visible
	_right_region.visible = _window_panels[2].visible or _window_panels[3].visible
	_docks_visible = _left_region.visible or _right_region.visible
	_dock_toggle.text = "Docks" if _docks_visible else "Show Docks"
	for index in _window_panels.size():
		_windows_popup.set_item_checked(_windows_popup.get_item_index(index), _window_panels[index].is_visible_in_tree())
	_windows_popup.set_item_checked(_windows_popup.get_item_index(WINDOW_BOTTOM), _bottom_expanded)

func _on_toggle_bottom() -> void:
	_set_bottom_expanded(not _bottom_expanded)

func _on_bottom_tab_changed(tab_index: int) -> void:
	if tab_index >= 0:
		_bottom_last_tab = tab_index
	if _bottom_expanded != (tab_index >= 0):
		_set_bottom_expanded(tab_index >= 0)

func _set_bottom_expanded(expanded: bool) -> void:
	_bottom_expanded = expanded
	_bottom_panel.custom_minimum_size.y = BOTTOM_EXPANDED_HEIGHT if expanded else BOTTOM_COLLAPSED_HEIGHT
	if expanded:
		_bottom_panel.set_current_tab(_bottom_last_tab)
	elif _bottom_panel.get_current_tab() >= 0:
		_bottom_panel.set_current_tab(-1)
	_bottom_toggle.text = "Collapse" if expanded else "Expand"
	_sync_windows_menu()
