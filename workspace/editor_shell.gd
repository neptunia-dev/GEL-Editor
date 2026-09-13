extends Control
class_name EditorShell

## GEL 编辑器 Shell。
##
## 具体节点和视觉布局全部保存在 editor_shell.tscn；工程菜单只负责把文件
## 选择和编辑器工程 API 连接起来，不把 Node Map 领域逻辑放进 Shell。

const BOTTOM_COLLAPSED_HEIGHT := 34
const BOTTOM_EXPANDED_HEIGHT := 190
const MENU_NEW_PROJECT := 100
const MENU_OPEN_PROJECT := 101
const MENU_SAVE_PROJECT := 102
const MENU_SAVE_PROJECT_AS := 103
const MENU_PROJECT_SETTINGS := 104
const MENU_EDIT_UNDO := 200
const MENU_EDIT_REDO := 201
const MENU_MAIN_QUIT := 300
const PROJECT_FILTER := "*.gelproj ; GEL Editor Project"
const UNSAVED_ACTION_DISCARD := "discard_changes"

@onready var _main_split: HSplitContainer = $EditorRoot/DockHSplitMain
@onready var _center_split: VSplitContainer = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter
@onready var _bottom_panel: TabContainer = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/EditorBottomPanel
@onready var _dock_toggle: Button = $EditorRoot/EditorTitleBar/TitleBarRow/ToggleDocks
@onready var _bottom_toggle: Button = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace/WorkspaceToolbar/ToolbarRow/ToggleBottomPanel
@onready var _left_region: Control = $EditorRoot/DockHSplitMain/DockVSplitLeft
@onready var _right_region: Control = $EditorRoot/DockHSplitMain/DockVSplitRight
@onready var _node_map_editor = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/MainWorkspace/WorkspaceCanvas/CanvasRoot/NodeMapWorkspace/NodeMapEditor
@onready var _explorer_panel = $EditorRoot/DockHSplitMain/DockVSplitLeft/LeftLower/Explorer
@onready var _document_tab: Button = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/DocumentTabs/DocumentTabRow/Untitled
@onready var _document_state: Label = $EditorRoot/DockHSplitMain/CenterRegion/DockVSplitCenter/TopWorkspaceSplit/DocumentTabs/DocumentTabRow/DocumentState
@onready var _history_list: ItemList = $EditorRoot/DockHSplitMain/DockVSplitRight/RightLower/History/HistoryContent/Status
@onready var _inspector = $EditorRoot/DockHSplitMain/DockVSplitRight/RightUpper/Inspector

var _docks_visible := true
var _bottom_expanded := false
var _project_dialog: FileDialog
var _project_dialog_mode := FileDialog.FILE_MODE_OPEN_FILE
var _unsaved_changes_dialog: ConfirmationDialog
var _discard_changes_button: Button
var _project_settings_dialog: ConfirmationDialog
var _project_settings_fields: Dictionary = {}
var _pending_destructive_action := ""
var _save_then_destructive_action := ""

func _ready() -> void:
	_configure_menus()
	_configure_project_dialog()
	_configure_unsaved_changes_dialog()
	_configure_project_settings_dialog()
	_dock_toggle.pressed.connect(_on_toggle_docks)
	_bottom_toggle.pressed.connect(_on_toggle_bottom)
	_bottom_panel.tab_changed.connect(_on_bottom_tab_changed)
	_node_map_editor.project_state_changed.connect(_on_project_state_changed)
	_node_map_editor.project_save_as_requested.connect(_open_save_project_dialog)
	_node_map_editor.graph.selection_changed.connect(_on_node_map_selection_changed)
	_explorer_panel.entry_activated.connect(_on_explorer_entry_activated)
	_explorer_panel.set_document(_node_map_editor.document)
	_inspector.configure(_node_map_editor.document, _node_map_editor.controller, _node_map_editor.registry)
	_inspector.scene_requested.connect(_node_map_editor.show_graph)
	_node_map_editor.document.changed.connect(func(_change): _inspector.refresh())
	add_to_group("node_map_navigation")
	_node_map_editor.controller.history_changed.connect(_refresh_history)
	_history_list.item_selected.connect(_on_history_item_selected)

	_center_split.set_dragger_visibility(SplitContainer.DRAGGER_VISIBLE)
	_set_bottom_expanded(false)
	_set_docks_visible(true)
	_on_project_state_changed(_node_map_editor.get_project_path(), _node_map_editor.is_project_dirty())
	_refresh_history()

func _on_node_map_selection_changed() -> void:
	var selected: Array = _node_map_editor.graph.get_selected_ids()
	_inspector.show_node(str(selected[0]) if not selected.is_empty() else "")

func _on_explorer_entry_activated(entry_id: String) -> void:
	var model = _explorer_panel.get_model()
	if model == null:
		return
	var entry = model.get_entry(entry_id)
	if entry == null or not entry.metadata.has("graph_id"):
		return
	_node_map_editor.show_graph(str(entry.metadata.graph_id))

func _refresh_history() -> void:
	_history_list.clear()
	var history: Array = _node_map_editor.controller.get_history()
	var cursor: int = _node_map_editor.controller.get_history_cursor()
	for index in history.size():
		var item: Dictionary = history[index]
		var marker := "" if index < cursor else "[redo] "
		_history_list.add_item("%d  %s%s" % [index + 1, marker, _format_history_operation(str(item.operation))])
		_history_list.set_item_metadata(index, index)
	if history.is_empty():
		_history_list.add_item("No recent edits")
		_history_list.set_item_disabled(0, true)

func _format_history_operation(operation: String) -> String:
	match operation:
		"create_node": return "Add node"
		"remove_nodes": return "Delete node"
		"duplicate_nodes": return "Duplicate node"
		"move_nodes": return "Move node"
		"connect": return "Connect nodes"
		"disconnect": return "Disconnect nodes"
		"set_input": return "Edit input"
		"clear_input": return "Clear input"
		"set_parameter": return "Edit parameter"
		"set_node_flags": return "Change node state"
		_: return operation.capitalize()

func _on_history_item_selected(index: int) -> void:
	if _history_list.is_item_disabled(index):
		return
	var target: int = int(_history_list.get_item_metadata(index)) + 1
	_node_map_editor.controller.jump_to_history(target)

func _configure_menus() -> void:
	var main_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/MainMenu.get_popup()
	main_popup.clear()
	main_popup.add_item("Project", MENU_PROJECT_SETTINGS)
	main_popup.add_item("Editor Settings", MENU_PROJECT_SETTINGS + 1)
	main_popup.add_separator()
	main_popup.add_item("Quit", MENU_MAIN_QUIT)
	if not main_popup.id_pressed.is_connected(_on_main_menu_pressed):
		main_popup.id_pressed.connect(_on_main_menu_pressed)

	var project_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/ProjectMenu.get_popup()
	project_popup.clear()
	project_popup.add_item("New Project", MENU_NEW_PROJECT)
	project_popup.add_item("Open Project", MENU_OPEN_PROJECT)
	project_popup.add_item("Save Project", MENU_SAVE_PROJECT)
	project_popup.add_item("Save Project As", MENU_SAVE_PROJECT_AS)
	project_popup.add_separator()
	project_popup.add_item("Project Settings", MENU_PROJECT_SETTINGS)
	if not project_popup.id_pressed.is_connected(_on_project_menu_pressed):
		project_popup.id_pressed.connect(_on_project_menu_pressed)

	var edit_popup: PopupMenu = $EditorRoot/EditorTitleBar/TitleBarRow/EditMenu.get_popup()
	edit_popup.clear()
	edit_popup.add_item("Undo", MENU_EDIT_UNDO)
	edit_popup.add_item("Redo", MENU_EDIT_REDO)
	if not edit_popup.id_pressed.is_connected(_on_edit_menu_pressed):
		edit_popup.id_pressed.connect(_on_edit_menu_pressed)

func _configure_project_dialog() -> void:
	_project_dialog = FileDialog.new()
	_project_dialog.name = "ProjectFileDialog"
	_project_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_project_dialog.filters = PackedStringArray([PROJECT_FILTER])
	_project_dialog.size = Vector2i(760, 520)
	_project_dialog.file_selected.connect(_on_project_file_selected)
	_project_dialog.canceled.connect(_on_project_file_dialog_canceled)
	add_child(_project_dialog)

func _configure_unsaved_changes_dialog() -> void:
	_unsaved_changes_dialog = ConfirmationDialog.new()
	_unsaved_changes_dialog.name = "UnsavedChangesDialog"
	_unsaved_changes_dialog.title = "Unsaved Changes"
	_unsaved_changes_dialog.dialog_text = "This project has unsaved changes. Save them before continuing?"
	_unsaved_changes_dialog.ok_button_text = "Save"
	_discard_changes_button = _unsaved_changes_dialog.add_button("Discard", true, UNSAVED_ACTION_DISCARD)
	_discard_changes_button.tooltip_text = "Continue without saving the current project"
	_unsaved_changes_dialog.confirmed.connect(_on_save_changes_confirmed)
	_unsaved_changes_dialog.custom_action.connect(_on_unsaved_changes_custom_action)
	_unsaved_changes_dialog.canceled.connect(_on_unsaved_changes_canceled)
	add_child(_unsaved_changes_dialog)

func _configure_project_settings_dialog() -> void:
	_project_settings_dialog = ConfirmationDialog.new()
	_project_settings_dialog.name = "ProjectSettingsDialog"
	_project_settings_dialog.title = "Project Settings"
	_project_settings_dialog.ok_button_text = "Apply"
	_project_settings_dialog.size = Vector2i(560, 440)
	add_child(_project_settings_dialog)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	var form := GridContainer.new()
	form.name = "Form"
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 8)
	content.add_child(form)
	_add_project_text_field(form, "Project ID", "project_id")
	_add_project_text_field(form, "Title", "title")
	_add_project_text_field(form, "Author", "author")
	_add_project_text_field(form, "Language", "language")
	_add_project_text_field(form, "Package ID", "package_id")
	_add_project_text_field(form, "Package Version", "package_version")
	_add_project_schema_field(form)
	_add_project_text_field(form, "Engine Min Version", "engine_min_version")
	_add_project_text_field(form, "Entry Scene", "entry_scene")
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 16
	content.offset_top = 16
	content.offset_right = -16
	content.offset_bottom = -52
	_project_settings_dialog.add_child(content)
	_project_settings_dialog.confirmed.connect(_apply_project_settings)

func _add_project_text_field(form: GridContainer, label_text: String, field_key: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	form.add_child(label)
	var input := LineEdit.new()
	input.name = field_key
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(input)
	_project_settings_fields[field_key] = input

func _add_project_schema_field(form: GridContainer) -> void:
	var label := Label.new()
	label.text = "Save Schema Version"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	form.add_child(label)
	var input := SpinBox.new()
	input.name = "save_schema_version"
	input.min_value = 0
	input.max_value = 2147483647
	input.step = 1
	input.allow_greater = false
	input.rounded = true
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(input)
	_project_settings_fields["save_schema_version"] = input

func _on_main_menu_pressed(id: int) -> void:
	match id:
		MENU_PROJECT_SETTINGS:
			_open_project_settings_dialog()
		MENU_MAIN_QUIT:
			_request_destructive_project_action("quit")

func _on_project_menu_pressed(id: int) -> void:
	match id:
		MENU_NEW_PROJECT:
			_request_destructive_project_action("new_project")
		MENU_OPEN_PROJECT:
			_request_destructive_project_action("open_project")
		MENU_SAVE_PROJECT:
			if _node_map_editor.get_project_path().is_empty():
				_open_save_project_dialog()
			else:
				_node_map_editor.save_project()
		MENU_SAVE_PROJECT_AS:
			_open_save_project_dialog()
		MENU_PROJECT_SETTINGS:
			_open_project_settings_dialog()

func _on_edit_menu_pressed(id: int) -> void:
	match id:
		MENU_EDIT_UNDO:
			_node_map_editor.undo_project_edit()
		MENU_EDIT_REDO:
			_node_map_editor.redo_project_edit()

func _open_project_dialog() -> void:
	_project_dialog_mode = FileDialog.FILE_MODE_OPEN_FILE
	_project_dialog.file_mode = _project_dialog_mode
	_project_dialog.current_file = ""
	_project_dialog.popup_centered()

func _open_save_project_dialog() -> void:
	_project_dialog_mode = FileDialog.FILE_MODE_SAVE_FILE
	_project_dialog.file_mode = _project_dialog_mode
	_project_dialog.current_file = "untitled" + ".gelproj"
	_project_dialog.popup_centered()

func _on_project_file_selected(path: String) -> void:
	# FileDialog emits file_selected before every host has completed its own
	# close handling. Release this window before Save As resumes an Open action.
	_project_dialog.hide()
	var selected := path
	if _project_dialog_mode == FileDialog.FILE_MODE_SAVE_FILE and selected.get_extension().is_empty():
		selected += ".gelproj"
	if _project_dialog_mode == FileDialog.FILE_MODE_SAVE_FILE:
		var saved: Dictionary = _node_map_editor.save_project_as(selected)
		var next_action := _save_then_destructive_action
		_save_then_destructive_action = ""
		if bool(saved.get("ok", false)):
			_pending_destructive_action = ""
			if not next_action.is_empty():
				call_deferred("_perform_destructive_project_action", next_action)
		elif not next_action.is_empty():
			_pending_destructive_action = next_action
			call_deferred("_reopen_unsaved_changes_dialog")
	else:
		_node_map_editor.open_project(selected)

func _on_project_file_dialog_canceled() -> void:
	# Canceling Save As also cancels the deferred destructive action. A future
	# menu request will establish a fresh confirmation context.
	_save_then_destructive_action = ""
	_pending_destructive_action = ""

func _open_project_settings_dialog() -> void:
	var project: Dictionary = _node_map_editor.get_project_metadata()
	var metadata: Dictionary = project.get("metadata", {})
	var package: Dictionary = project.get("package", {})
	(_project_settings_fields["project_id"] as LineEdit).text = str(project.get("project_id", ""))
	(_project_settings_fields["title"] as LineEdit).text = str(metadata.get("title", ""))
	(_project_settings_fields["author"] as LineEdit).text = str(metadata.get("author", ""))
	(_project_settings_fields["language"] as LineEdit).text = str(metadata.get("language", ""))
	(_project_settings_fields["package_id"] as LineEdit).text = str(package.get("package_id", ""))
	(_project_settings_fields["package_version"] as LineEdit).text = str(package.get("package_version", ""))
	(_project_settings_fields["save_schema_version"] as SpinBox).value = int(package.get("save_schema_version", 0))
	(_project_settings_fields["engine_min_version"] as LineEdit).text = str(package.get("engine_min_version", ""))
	(_project_settings_fields["entry_scene"] as LineEdit).text = str(project.get("entry_scene", ""))
	_project_settings_dialog.popup_centered()

func _apply_project_settings() -> void:
	var metadata := {
		"project_id": (_project_settings_fields["project_id"] as LineEdit).text,
		"metadata": {
			"title": (_project_settings_fields["title"] as LineEdit).text,
			"author": (_project_settings_fields["author"] as LineEdit).text,
			"language": (_project_settings_fields["language"] as LineEdit).text,
		},
		"package": {
			"package_id": (_project_settings_fields["package_id"] as LineEdit).text,
			"package_version": (_project_settings_fields["package_version"] as LineEdit).text,
			"save_schema_version": int((_project_settings_fields["save_schema_version"] as SpinBox).value),
			"engine_min_version": (_project_settings_fields["engine_min_version"] as LineEdit).text,
		},
		"entry_scene": (_project_settings_fields["entry_scene"] as LineEdit).text,
	}
	var result: Dictionary = _node_map_editor.set_project_metadata(metadata)
	if not bool(result.get("ok", false)):
		call_deferred("_reopen_project_settings_after_validation_failure")

func _reopen_project_settings_after_validation_failure() -> void:
	_project_settings_dialog.popup_centered()

func _request_destructive_project_action(action: String) -> void:
	if not _node_map_editor.is_project_dirty():
		_perform_destructive_project_action(action)
		return
	_pending_destructive_action = action
	_save_then_destructive_action = ""
	_unsaved_changes_dialog.popup_centered()

func _on_save_changes_confirmed() -> void:
	var action := _pending_destructive_action
	if action.is_empty():
		return
	# ConfirmationDialog is an exclusive child window. Hide it before opening
	# FileDialog so an untitled Save can safely transition into Save As.
	_unsaved_changes_dialog.hide()
	if _node_map_editor.get_project_path().is_empty():
		_save_then_destructive_action = action
		_pending_destructive_action = ""
		call_deferred("_open_save_project_dialog")
		return
	var saved: Dictionary = _node_map_editor.save_project()
	if bool(saved.get("ok", false)):
		_pending_destructive_action = ""
		_perform_destructive_project_action(action)
	else:
		call_deferred("_reopen_unsaved_changes_dialog")

func _on_unsaved_changes_custom_action(action: StringName) -> void:
	if action != UNSAVED_ACTION_DISCARD:
		return
	var next_action := _pending_destructive_action
	_clear_pending_destructive_actions()
	_unsaved_changes_dialog.hide()
	if not next_action.is_empty():
		_perform_destructive_project_action(next_action)

func _on_unsaved_changes_canceled() -> void:
	_clear_pending_destructive_actions()

func _reopen_unsaved_changes_dialog() -> void:
	if not _pending_destructive_action.is_empty() and _node_map_editor.is_project_dirty():
		_unsaved_changes_dialog.popup_centered()

func _clear_pending_destructive_actions() -> void:
	_pending_destructive_action = ""
	_save_then_destructive_action = ""

func _perform_destructive_project_action(action: String) -> void:
	match action:
		"new_project":
			_node_map_editor.new_project()
		"open_project":
			_open_project_dialog()
		"quit":
			get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_node_ready():
			_request_destructive_project_action("quit")
		else:
			get_tree().quit()

func _on_project_state_changed(path: String, dirty: bool) -> void:
	var caption := "Untitled" if path.is_empty() else path.get_file()
	_document_tab.text = caption
	_document_tab.tooltip_text = "Unsaved project" if path.is_empty() else path
	_document_state.text = "modified" if dirty else "saved"
	_document_state.tooltip_text = "Project has unsaved changes" if dirty else "Project is saved"
	get_window().title = "GEL Editor - " + caption + (" *" if dirty else "")

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
	if expanded:
		_bottom_panel.set_current_tab(0)
	elif _bottom_panel.get_current_tab() >= 0:
		_bottom_panel.set_current_tab(-1)
	_bottom_toggle.text = "Collapse" if expanded else "Expand"
