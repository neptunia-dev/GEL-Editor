extends Control
class_name EditorShell

## 工作区占位 Shell。
##
## 具体节点和视觉布局全部保存在 editor_shell.tscn，方便直接在 Godot 编辑器中查看
## 和调整。脚本只处理少量交互状态，不在运行时创建布局节点。

const BOTTOM_COLLAPSED_HEIGHT := 34
const BOTTOM_EXPANDED_HEIGHT := 190

@onready var _main_split: HSplitContainer = $EditorRoot/DockHSplitMain
@onready var _center_split: VSplitContainer = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter
@onready var _bottom_panel: TabContainer = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/EditorBottomPanel
@onready var _dock_toggle: Button = $EditorRoot/EditorTitleBar/TitleBarRow/ToggleDocks
@onready var _bottom_toggle: Button = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace/WorkspaceToolbar/ToolbarRow/ToggleBottomPanel
@onready var _left_region: Control = $EditorRoot/DockHSplitMain/DockVSplitLeft
@onready var _right_region: Control = $EditorRoot/DockHSplitMain/DockVSplitRight

var _docks_visible := true
var _bottom_expanded := false

func _ready() -> void:
	_configure_menus()
	_dock_toggle.pressed.connect(_on_toggle_docks)
	_bottom_toggle.pressed.connect(_on_toggle_bottom)
	_bottom_panel.tab_changed.connect(_on_bottom_tab_changed)

	_center_split.set_dragger_visibility(SplitContainer.DRAGGER_VISIBLE)
	_set_bottom_expanded(false)
	_set_docks_visible(true)

func _configure_menus() -> void:
	var main_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/MainMenu.get_popup()
	main_popup.add_item("Project")
	main_popup.add_item("Editor Settings")
	main_popup.add_separator()
	main_popup.add_item("Quit")

	var project_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/ProjectMenu.get_popup()
	project_popup.add_item("Open Project")
	project_popup.add_item("Project Settings")

	var edit_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/EditMenu.get_popup()
	edit_popup.add_item("Undo")
	edit_popup.add_item("Redo")

func _on_toggle_docks() -> void:
	_set_docks_visible(not _docks_visible)

func _set_docks_visible(visible: bool) -> void:
	_docks_visible = visible
	_left_region.visible = visible
	_right_region.visible = visible
	_dock_toggle.text = "Docks" if visible else "Show Docks"

func _on_toggle_bottom() -> void:
	_set_bottom_expanded(not _bottom_expanded)

func _on_bottom_tab_changed(tab_index: int) -> void:
	if tab_index >= 0 and not _bottom_expanded:
		_set_bottom_expanded(true)

func _set_bottom_expanded(expanded: bool) -> void:
	_bottom_expanded = expanded
	_bottom_panel.custom_minimum_size.y = BOTTOM_EXPANDED_HEIGHT if expanded else BOTTOM_COLLAPSED_HEIGHT
	_bottom_panel.set_current_tab(0 if expanded else -1)
	_bottom_toggle.text = "Collapse" if expanded else "Expand"
