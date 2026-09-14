extends MarginContainer

const BRIDGE := preload("res://node_map/integration/agent_cli_bridge.gd")
const APPLIER := preload("res://node_map/compiler/story_ir_applier.gd")
signal status_changed(message: String)
signal llm_state_changed(state: String, message: String)
signal llm_progress

const STEP_NAMES: PackedStringArray = ["1. Outline", "2. Scenes", "3. Scripts", "4. Review", "5. IR"]
const STEP_FILE_PREFIXES: PackedStringArray = ["outline", "scenes/", "scripts/", "review/", "ir/"]
const STEP_ACTIONS: PackedStringArray = ["▶ Generate Scenes", "▶ Generate Scripts", "▶ Review", "▶ Generate IR", "▶ Apply to Canvas"]
const STEP_STAGES: PackedStringArray = ["scenes", "scripts", "review", "ir", ""]

const ACCENT_BLUE := Color(0.341176, 0.588235, 0.901961, 1)
const TEXT_BRIGHT := Color(0.835294, 0.835294, 0.835294, 1)
const TEXT_MUTED := Color(0.572549, 0.572549, 0.572549, 1)
const TEXT_GREEN := Color(0.4, 0.8, 0.45, 1)
const TEXT_RED := Color(0.95, 0.58, 0.54, 1)

var directory := ""
var current_file := ""
var _dirty := false
var _bridge = BRIDGE.new()
var _poll: Timer
var _busy := false
var _pending_stage := ""
var _chain: PackedStringArray = PackedStringArray()
var _stream_offset := 0
var _activity_key := ""
var _llm_state_key := ""
var _ir_session: Dictionary = {}
var _stream_applier = null
var _current_step := 0
var _step_states: PackedStringArray = PackedStringArray(["current", "pending", "pending", "pending", "pending"])
var _status_style: StyleBoxFlat

const STEP_DIRS: PackedStringArray = ["", "scenes", "scripts", "review", "ir"]

@onready var _files: ItemList = $Content/Body/Split/FilesPane/Files
@onready var _editor: TextEdit = $Content/Body/Split/Editor
@onready var _status_banner: PanelContainer = $Content/StatusBanner
@onready var _status_label: Label = $Content/StatusBanner/StatusLabel
@onready var _prompt_row: HBoxContainer = $Content/PromptRow
@onready var _prompt: LineEdit = $Content/PromptRow/Prompt
@onready var _stage_button: Button = $Content/ActionBar/ActionRow/StageButton
@onready var _continue_button: Button = $Content/ActionBar/ActionRow/Continue
@onready var _dir_dialog: FileDialog = $DirectoryDialog
@onready var _add_dialog: FileDialog = $AddFileDialog
@onready var _confirm_delete: ConfirmationDialog = $ConfirmDelete

func _ready() -> void:
	$Content/HeaderRow/Open.pressed.connect(_open_dialog)
	$Content/HeaderRow/Init.pressed.connect(_init_directory)
	$Content/Body/Split/FilesPane/FileHeader/Add.pressed.connect(_add_file_dialog)
	$Content/Body/Split/FilesPane/FileHeader/Delete.pressed.connect(_delete_current)
	$Content/Body/Split/FilesPane/FileHeader/Save.pressed.connect(save_current)
	$Content/ActionBar/ActionRow/Validate.pressed.connect(_validate_directory)
	_add_dialog.files_selected.connect(_add_files)
	_confirm_delete.confirmed.connect(_confirm_delete_current)
	_stage_button.pressed.connect(_on_stage_action)
	_continue_button.pressed.connect(_skip_review)
	$Content/PromptRow/Regen.pressed.connect(regenerate_current)
	for i in 5:
		var step_button: Button = $Content/StepBar/StepRow.get_child(i)
		step_button.pressed.connect(_on_step_pressed.bind(i))
	_files.item_selected.connect(_on_file_selected)
	_editor.text_changed.connect(func(): _dirty = true)
	_dir_dialog.dir_selected.connect(set_directory)
	_status_style = StyleBoxFlat.new()
	_status_style.content_margin_left = 10
	_status_style.content_margin_top = 5
	_status_style.content_margin_right = 10
	_status_style.content_margin_bottom = 5
	_status_style.bg_color = Color(0.086275, 0.086275, 0.086275, 1)
	_status_style.border_width_left = 3
	_status_style.corner_radius_top_left = 2
	_status_style.corner_radius_top_right = 2
	_status_style.corner_radius_bottom_right = 2
	_status_style.corner_radius_bottom_left = 2
	_status_style.border_color = Color(0.4, 0.4, 0.4, 1)
	_status_banner.add_theme_stylebox_override("panel", _status_style)
	_poll = Timer.new()
	_poll.wait_time = 0.15
	_poll.timeout.connect(_on_poll)
	add_child(_poll)
	_refresh_step_bar()
	_refresh_action_bar()
	_set_status("Init creates the workspace next to your project.")

func authoring_dir_for_project(project_path: String) -> String:
	if project_path.strip_edges().is_empty():
		return ProjectSettings.globalize_path("user://untitled.authoring")
	return project_path.get_basename() + ".authoring"

func set_directory(path: String) -> void:
	directory = path.simplify_path()
	current_file = ""
	_dirty = false
	_current_step = 0
	_step_states = PackedStringArray(["current", "pending", "pending", "pending", "pending"])
	refresh_files()
	if _files.item_count > 0:
		_files.select(0)
		_on_file_selected(0)
	_refresh_step_bar()
	_refresh_action_bar()
	_set_status("Opened " + directory)

func list_relative_files() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if directory.is_empty() or not DirAccess.dir_exists_absolute(directory):
		return found
	_collect_files(directory, "", found)
	found.sort()
	return found

func refresh_files() -> void:
	_files.clear()
	var prefix := STEP_FILE_PREFIXES[_current_step]
	for relative in list_relative_files():
		if prefix.is_empty() or relative.begins_with(prefix) or (prefix == "outline" and relative == "outline.md"):
			_files.add_item(relative)

func load_relative(relative: String) -> String:
	var path := directory.path_join(relative)
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""

func save_relative(relative: String, text: String) -> bool:
	var path := directory.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true

func save_current() -> void:
	if directory.is_empty() or current_file.is_empty():
		_set_status("No file selected.", "info")
		return
	if save_relative(current_file, _editor.text):
		_dirty = false
		_set_status("Saved " + current_file, "success")
	else:
		_set_status("Could not save " + current_file, "error")

func _open_dialog() -> void:
	_dir_dialog.popup_centered_ratio(0.5)

func _init_directory() -> void:
	var target := directory
	if target.is_empty():
		var editor = get_parent().get_node_or_null("NodeMapEditor")
		var project_path := str(editor.get_project_path()) if editor != null else ""
		target = authoring_dir_for_project(project_path)
	var result: Dictionary = _bridge.init_directory(target)
	_show_bridge(result, "Initialized " + target)
	if result.ok:
		set_directory(target)
func _validate_directory() -> void:
	if directory.is_empty():
		_set_status("No authoring directory.", "error")
		return
	save_current()
	_show_bridge(_bridge.validate_directory(directory), "Authoring files are valid.")

func _start_stage(stage: String, extra: Array = []) -> void:
	if directory.is_empty() or _busy:
		_set_status("Open an authoring directory first." if directory.is_empty() else "Authoring command already running.", "info")
		return
	save_current()
	var started: Dictionary = _bridge.start_author(stage, directory, extra)
	if not started.ok:
		_show_bridge(started, "")
		return
	_busy = true
	_pending_stage = stage
	if stage == "ir":
		_begin_ir_preview()
		_step_states[_current_step] = "done"
		_current_step = 4
		_step_states[4] = "current"
		refresh_files()
		_refresh_step_bar()
		_refresh_action_bar()
	elif stage == "scenes" or stage == "scripts":
		if get_parent() is TabContainer:
			get_parent().current_tab = get_parent().get_tab_count() - 1
	_set_status("Running " + stage + "...", "running")
	_activity_key = ""
	_emit_llm_state("working", "Running " + stage + "...")
	_refresh_action_bar()
	_poll.start()

func _on_poll() -> void:
	var status: Dictionary = _bridge.read_status(directory)
	var stage := str(status.get("stage", ""))
	var state := str(status.get("state", ""))
	if stage != _pending_stage:
		_set_status("Running " + _pending_stage + "...", "running")
		_emit_llm_state("working", "Running " + _pending_stage + "...")
		return
	_refresh_preview(str(status.get("previewFile", "")))
	if _pending_stage == "ir":
		_consume_ir_stream()
	var message := str(status.get("message", ""))
	var text := message if not message.is_empty() else "Running " + _pending_stage + "..."
	var preview_file := str(status.get("previewFile", ""))
	var key := "%s|%s|%d|%d|%d" % [message, preview_file, _file_size(preview_file), _file_size("activity"), _stream_offset + _file_size("ir/stream.jsonl")]
	if key != _activity_key:
		_activity_key = key
		llm_progress.emit()
	if state != "done":
		_set_status(text, "running")
		_emit_llm_state("working", text)
		return
	_poll.stop()
	_busy = false
	refresh_files()
	if bool(status.get("ok", false)):
		_emit_llm_state("idle", "")
		_advance_step()
		if stage == "scenes":
			_set_status("Review scenes/*.md, then generate scripts.", "success")
		elif stage == "scripts":
			if _chain.size() > 0:
				var next := _chain[0]
				_chain.remove_at(0)
				_start_stage(next)
				return
			_set_status("Review is optional. Continue skips it.", "success")
		elif stage == "review":
			_set_status("Review finished. Generate IR when ready.", "success")
		elif stage == "ir":
			_finish_ir_preview(true)
			_save_and_export()
			_refresh_step_bar()
			_refresh_action_bar()
			return
		else:
			_set_status("Finished " + stage + ".", "success")
	else:
		_chain.clear()
		if _pending_stage == "ir":
			_finish_ir_preview(false)
		var diagnostics: Array = status.get("diagnostics", [])
		var error_message := str(diagnostics[0].get("message", "Authoring command failed")) if not diagnostics.is_empty() else str(status.get("message", "Authoring command failed"))
		_set_status(error_message, "error")
		_emit_llm_state("error", error_message)
		_mark_step_error()
	_refresh_step_bar()
	_refresh_action_bar()

func _on_file_selected(index: int) -> void:
	if _dirty and not current_file.is_empty():
		save_relative(current_file, _editor.text)
	current_file = _files.get_item_text(index)
	_editor.text = load_relative(current_file)
	_dirty = false
	_refresh_action_bar()

func _collect_files(root: String, prefix: String, found: PackedStringArray) -> void:
	var access := DirAccess.open(root if prefix.is_empty() else root.path_join(prefix))
	if access == null:
		return
	access.list_dir_begin()
	var name := access.get_next()
	while name != "":
		if name.begins_with("."):
			name = access.get_next()
			continue
		var relative := name if prefix.is_empty() else prefix.path_join(name)
		if access.current_is_dir():
			if name != "runtime-package":
				_collect_files(root, relative, found)
		elif name != "status.json" and name != "activity":
			found.append(relative)
		name = access.get_next()
	access.list_dir_end()

func _show_bridge(result: Dictionary, success: String) -> void:
	if result.ok:
		_set_status(success, "success")
		return
	var diagnostics: Array = result.get("diagnostics", [])
	_set_status(str(diagnostics[0].get("message", "Authoring command failed")) if not diagnostics.is_empty() else "Authoring command failed", "error")


func _add_file_dialog() -> void:
	if directory.is_empty():
		_set_status("Init or open an authoring directory first.", "info")
		return
	_add_dialog.popup_centered_ratio(0.5)

func _add_files(paths: PackedStringArray) -> void:
	var added: PackedStringArray = PackedStringArray()
	for source in paths:
		var target_name := "outline.md" if _current_step == 0 else source.get_file()
		var relative := target_name if STEP_DIRS[_current_step].is_empty() else STEP_DIRS[_current_step].path_join(target_name)
		var error := DirAccess.copy_absolute(source, directory.path_join(relative))
		if error == OK:
			added.append(relative)
		else:
			_set_status("Could not add " + source + " (error %d)" % error, "error")
			return
	refresh_files()
	if not added.is_empty():
		_select_file(added[-1])
		_set_status("Added " + "\n".join(added), "success")

func _delete_current() -> void:
	if current_file.is_empty():
		_set_status("No file selected.", "info")
		return
	_confirm_delete.dialog_text = "Delete " + current_file + "?"
	_confirm_delete.popup_centered()

func _confirm_delete_current() -> void:
	if current_file.is_empty():
		return
	var removed := current_file
	var error := DirAccess.remove_absolute(directory.path_join(removed))
	if error != OK:
		_set_status("Could not delete " + removed + " (error %d)" % error, "error")
		return
	current_file = ""
	_editor.text = ""
	_dirty = false
	refresh_files()
	if _files.item_count > 0:
		_files.select(0)
		_on_file_selected(0)
	_set_status("Deleted " + removed, "success")

func _select_file(relative: String) -> void:
	for index in _files.item_count:
		if _files.get_item_text(index) == relative:
			_files.select(index)
			_on_file_selected(index)
			return

func regenerate_current() -> void:
	save_current()
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	var scene_id := _target_scene_id(editor)
	if scene_id.is_empty():
		_set_status("Select a scene file or open a scene graph.", "info")
		return
	var prompt := _prompt.text.strip_edges()
	var focus := prompt
	if editor != null:
		var selected := _selection_focus(editor)
		if not selected.is_empty():
			focus = (focus + "\n" + selected).strip_edges()
	save_relative("review/focus.txt", focus)
	if not focus.is_empty() or current_file.begins_with("scenes/"):
		_chain = PackedStringArray(["ir"])
		_start_stage("scripts", ["--scene", scene_id])
	else:
		_chain.clear()
		_start_stage("ir")

func _target_scene_id(editor) -> String:
	if current_file.begins_with("scenes/") or current_file.begins_with("scripts/") or current_file.begins_with("ir/"):
		return current_file.get_file().get_basename()
	if editor == null:
		return ""
	var graph = editor.document.get_graph(editor.graph.graph_id)
	if graph != null and str(graph.kind) == "scene":
		var owner_node = editor.document.get_node(graph.owner_node_id)
		if owner_node != null:
			return str(owner_node.get_parameter_values().get("scene_id", ""))
	for node_id in editor.graph.get_selected_ids():
		var node = editor.document.get_node(node_id)
		if node != null and node.node_type == "gel.scene":
			return str(node.get_parameter_values().get("scene_id", ""))
	return ""

func _selection_focus(editor) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for node_id in editor.graph.get_selected_ids():
		var node = editor.document.get_node(node_id)
		if node == null:
			continue
		lines.append("%s %s" % [node.node_type, str(node.get_parameter_values())])
	return "\n".join(lines)


func _begin_ir_preview() -> void:
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	if editor == null:
		return
	editor.new_project()
	editor.controller.begin_external_batch()
	_stream_applier = APPLIER.new()
	_ir_session = _stream_applier.create_session()
	_stream_offset = 0
	if get_parent() is TabContainer:
		get_parent().current_tab = 0

func _finish_ir_preview(ok: bool) -> void:
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	if editor == null:
		return
	if ok:
		editor.controller.commit_external_batch()
	else:
		editor.controller.abort_external_batch()
	_stream_applier = null
	_ir_session = {}

func _refresh_preview(relative: String) -> void:
	if relative.is_empty() or not _busy:
		return
	var text := load_relative(relative)
	if _editor.text != text or current_file != relative:
		var follow := current_file != relative or _editor_at_bottom()
		var saved := _editor.scroll_vertical
		_editor.text = text
		current_file = relative
		_dirty = false
		if follow:
			var last := maxi(_editor.get_line_count() - 1, 0)
			_editor.set_caret_line(last)
			_editor.set_caret_column(_editor.get_line(last).length())
			_editor.scroll_vertical = _editor.get_line_count()
		else:
			_editor.scroll_vertical = saved
	var keep := current_file
	refresh_files()
	for index in _files.item_count:
		if _files.get_item_text(index) == keep:
			_files.select(index)
			break

func _editor_at_bottom() -> bool:
	var bar := _editor.get_v_scroll_bar()
	if bar == null or bar.max_value <= bar.page:
		return true
	return bar.value >= bar.max_value - bar.page - 4.0

func _consume_ir_stream() -> void:
	if _stream_applier == null:
		return
	var path := directory.path_join("ir").path_join("stream.jsonl")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	file.seek(_stream_offset)
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	if editor == null:
		return
	while file.get_position() < file.get_length():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var json := JSON.new()
		if json.parse(line) != OK or not json.data is Dictionary:
			continue
		var applied: Dictionary = _stream_applier.apply_event(editor.document, _ir_session, json.data)
		if not applied.ok:
			_set_status(str(applied.get("diagnostics", [{}])[0].get("message", "IR event failed") if not applied.get("diagnostics", []).is_empty() else "IR event failed"), "error")
			break
	_stream_offset = file.get_position()
	if editor != null:
		editor.graph.request_refresh()

func _save_and_export() -> void:
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	if editor == null:
		return
	editor.save_project(_project_path())
	var exported: Dictionary = editor.export_runtime_package(directory.path_join("runtime-package"))
	if exported.ok:
		_set_status("Applied IR, saved project, exported Runtime Package.", "success")
	else:
		var diagnostics: Array = exported.get("diagnostics", [])
		_set_status(str(diagnostics[0].get("message", "Export failed")) if not diagnostics.is_empty() else "Export failed", "error")

func apply_current_ir() -> Dictionary:
	if directory.is_empty():
		_set_status("No authoring directory.", "error")
		return {"ok": false}
	var path := directory.path_join("ir").path_join("story.json")
	if not FileAccess.file_exists(path):
		_set_status("Missing ir/story.json", "error")
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if file == null or json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_set_status("Invalid ir/story.json", "error")
		return {"ok": false}
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	if editor == null:
		_set_status("Node Map editor is missing.", "error")
		return {"ok": false}
	editor.new_project()
	var applied: Dictionary = APPLIER.new().apply_story(editor.controller, json.data)
	if not applied.ok:
		var diagnostics: Array = applied.get("diagnostics", [])
		_set_status(str(diagnostics[0].get("message", "IR apply failed")) if not diagnostics.is_empty() else "IR apply failed", "error")
		return applied
	var project_path := _project_path()
	editor.save_project(project_path)
	var exported: Dictionary = editor.export_runtime_package(directory.path_join("runtime-package"))
	if get_parent() is TabContainer:
		get_parent().current_tab = 0
	if exported.ok:
		_set_status("Applied IR, saved project, exported Runtime Package.", "success")
	else:
		var diagnostics: Array = exported.get("diagnostics", [])
		_set_status(str(diagnostics[0].get("message", "Export failed")) if not diagnostics.is_empty() else "Export failed", "error")
	return {"ok": exported.ok, "applied": applied, "exported": exported}

func _project_path() -> String:
	if directory.ends_with(".authoring"):
		return directory.substr(0, directory.length() - ".authoring".length()) + ".gelproj"
	return directory.path_join("story.gelproj")

func _set_status(message: String, level := "info") -> void:
	_status_label.text = message
	match level:
		"error":
			_status_style.border_color = TEXT_RED
			_status_label.add_theme_color_override("font_color", TEXT_RED)
		"running":
			_status_style.border_color = ACCENT_BLUE
			_status_label.add_theme_color_override("font_color", TEXT_BRIGHT)
		"success":
			_status_style.border_color = TEXT_GREEN
			_status_label.add_theme_color_override("font_color", TEXT_GREEN)
		_:
			_status_style.border_color = Color(0.4, 0.4, 0.4, 1)
			_status_label.add_theme_color_override("font_color", TEXT_MUTED)
	status_changed.emit(message)

func _emit_llm_state(state: String, message: String) -> void:
	var key := state + "|" + message
	if key == _llm_state_key:
		return
	_llm_state_key = key
	llm_state_changed.emit(state, message)

func _file_size(relative: String) -> int:
	if relative.is_empty() or directory.is_empty():
		return 0
	var path := directory.path_join(relative)
	if not FileAccess.file_exists(path):
		return 0
	var size := FileAccess.get_size(path)
	return size if size >= 0 else 0

# --- Step bar ---

func _on_step_pressed(index: int) -> void:
	if index == _current_step:
		return
	_current_step = index
	if _step_states[index] == "pending":
		_step_states[index] = "current"
	refresh_files()
	_refresh_step_bar()
	_refresh_action_bar()

func _advance_step() -> void:
	if _current_step >= 4:
		return
	_step_states[_current_step] = "done"
	_current_step += 1
	_step_states[_current_step] = "current"
	refresh_files()

func _mark_step_error() -> void:
	_step_states[_current_step] = "error"

func _refresh_step_bar() -> void:
	for i in 5:
		var button: Button = $Content/StepBar/StepRow.get_child(i)
		var prefix := ""
		match _step_states[i]:
			"done":
				prefix = "✓ "
			"error":
				prefix = "✗ "
			_:
				prefix = ""
		button.text = prefix + STEP_NAMES[i]
		button.button_pressed = (i == _current_step)
		match _step_states[i]:
			"current":
				button.add_theme_color_override("font_color", ACCENT_BLUE)
				button.add_theme_color_override("font_pressed_color", ACCENT_BLUE)
				button.add_theme_color_override("font_hover_color", ACCENT_BLUE)
			"done":
				button.add_theme_color_override("font_color", TEXT_GREEN)
				button.add_theme_color_override("font_pressed_color", TEXT_GREEN)
				button.add_theme_color_override("font_hover_color", TEXT_GREEN)
			"error":
				button.add_theme_color_override("font_color", TEXT_RED)
				button.add_theme_color_override("font_pressed_color", TEXT_RED)
				button.add_theme_color_override("font_hover_color", TEXT_RED)
			_:
				button.add_theme_color_override("font_color", TEXT_MUTED)
				button.add_theme_color_override("font_pressed_color", TEXT_MUTED)
				button.add_theme_color_override("font_hover_color", TEXT_MUTED)
		button.disabled = (_step_states[i] == "pending")

# --- Action bar ---

func _refresh_action_bar() -> void:
	_stage_button.text = STEP_ACTIONS[_current_step]
	_stage_button.disabled = _busy or (_current_step == 4 and not FileAccess.file_exists(directory.path_join("ir").path_join("story.json")))
	_prompt_row.visible = (_current_step == 2)
	_continue_button.visible = (_current_step == 2)
	_continue_button.disabled = _busy
	$Content/Body/Split/FilesPane/FileHeader/Add.disabled = directory.is_empty()
	$Content/Body/Split/FilesPane/FileHeader/Delete.disabled = current_file.is_empty()
	$Content/Body/Split/FilesPane/FileHeader/Save.disabled = current_file.is_empty()

func _skip_review() -> void:
	if _busy or directory.is_empty() or _current_step != 2:
		return
	_step_states[2] = "done"
	_current_step = 3
	if _step_states[3] == "pending":
		_step_states[3] = "current"
	refresh_files()
	_refresh_step_bar()
	_refresh_action_bar()
	_set_status("Skipped review. Generate IR when ready.", "info")

func _on_stage_action() -> void:
	if _current_step >= 4:
		apply_current_ir()
		return
	_start_stage(STEP_STAGES[_current_step])
