extends HSplitContainer

const BRIDGE := preload("res://node_map/integration/agent_cli_bridge.gd")
const APPLIER := preload("res://node_map/compiler/story_ir_applier.gd")
signal status_changed(message: String)

var directory := ""
var current_file := ""
var _dirty := false
var _bridge = BRIDGE.new()
var _poll: Timer
var _busy := false
var _pending_stage := ""
var _chain: PackedStringArray = PackedStringArray()

@onready var _files: ItemList = $Files
@onready var _editor: TextEdit = $Main/Editor
@onready var _status: Label = $Main/Status
@onready var _prompt: LineEdit = $Main/Prompt
@onready var _dir_dialog: FileDialog = $DirectoryDialog

func _ready() -> void:
	$Main/Toolbar/Open.pressed.connect(_open_dialog)
	$Main/Toolbar/Init.pressed.connect(_init_directory)
	$Main/Toolbar/Save.pressed.connect(save_current)
	$Main/Toolbar/Validate.pressed.connect(_validate_directory)
	$Main/Toolbar/Scenes.pressed.connect(func(): _start_stage("scenes"))
	$Main/Toolbar/Scripts.pressed.connect(func(): _start_stage("scripts"))
	$Main/Toolbar/Review.pressed.connect(func(): _start_stage("review"))
	$Main/Toolbar/IR.pressed.connect(func(): _start_stage("ir"))
	$Main/Toolbar/Apply.pressed.connect(apply_current_ir)
	$Main/Toolbar/Regen.pressed.connect(regenerate_current)
	_files.item_selected.connect(_on_file_selected)
	_editor.text_changed.connect(func(): _dirty = true)
	_dir_dialog.dir_selected.connect(set_directory)
	_poll = Timer.new()
	_poll.wait_time = 0.5
	_poll.timeout.connect(_on_poll)
	add_child(_poll)
	_set_status("Open or init an authoring directory.")

func authoring_dir_for_project(project_path: String) -> String:
	if project_path.strip_edges().is_empty():
		return ProjectSettings.globalize_path("user://untitled.authoring")
	return project_path.get_basename() + ".authoring"

func set_directory(path: String) -> void:
	directory = path.simplify_path()
	current_file = ""
	_dirty = false
	refresh_files()
	if _files.item_count > 0:
		_files.select(0)
		_on_file_selected(0)
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
	for relative in list_relative_files():
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
		_set_status("No file selected.")
		return
	if save_relative(current_file, _editor.text):
		_dirty = false
		_set_status("Saved " + current_file)
	else:
		_set_status("Could not save " + current_file)

func _open_dialog() -> void:
	_dir_dialog.popup_centered_ratio(0.5)

func _init_directory() -> void:
	if directory.is_empty():
		_open_dialog()
		return
	var result: Dictionary = _bridge.init_directory(directory)
	_show_bridge(result, "Initialized " + directory)
	if result.ok:
		set_directory(directory)

func _validate_directory() -> void:
	if directory.is_empty():
		_set_status("No authoring directory.")
		return
	save_current()
	_show_bridge(_bridge.validate_directory(directory), "Authoring files are valid.")

func _start_stage(stage: String, extra: Array = []) -> void:
	if directory.is_empty() or _busy:
		_set_status("Open an authoring directory first." if directory.is_empty() else "Authoring command already running.")
		return
	save_current()
	var started: Dictionary = _bridge.start_author(stage, directory, extra)
	if not started.ok:
		_show_bridge(started, "")
		return
	_busy = true
	_pending_stage = stage
	_set_status("Running " + stage + "...")
	_poll.start()

func _on_poll() -> void:
	var status: Dictionary = _bridge.read_status(directory)
	if str(status.get("stage", "")) != _pending_stage or str(status.get("state", "")) != "done":
		var message := str(status.get("message", ""))
		_set_status(message if not message.is_empty() else "Running " + _pending_stage + "...")
		return
	_poll.stop()
	_busy = false
	refresh_files()
	if bool(status.get("ok", false)):
		var stage := str(status.get("stage", ""))
		if stage == "scenes":
			_set_status("Review scenes/*.md, then generate scripts.")
		elif stage == "scripts":
			if _chain.size() > 0:
				var next := _chain[0]
				_chain.remove_at(0)
				_start_stage(next)
				return
			_set_status("Review scripts/*.md, then run Review.")
		elif stage == "review":
			_set_status("Review finished. Generate IR when ready.")
		elif stage == "ir":
			apply_current_ir()
			return
		else:
			_set_status("Finished " + stage + ".")
	else:
		_chain.clear()
		var diagnostics: Array = status.get("diagnostics", [])
		_set_status(str(diagnostics[0].get("message", "Authoring command failed")) if not diagnostics.is_empty() else str(status.get("message", "Authoring command failed")))

func _on_file_selected(index: int) -> void:
	if _dirty and not current_file.is_empty():
		save_relative(current_file, _editor.text)
	current_file = _files.get_item_text(index)
	_editor.text = load_relative(current_file)
	_dirty = false

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
		elif name != "status.json":
			found.append(relative)
		name = access.get_next()
	access.list_dir_end()

func _show_bridge(result: Dictionary, success: String) -> void:
	if result.ok:
		_set_status(success)
		return
	var diagnostics: Array = result.get("diagnostics", [])
	_set_status(str(diagnostics[0].get("message", "Authoring command failed")) if not diagnostics.is_empty() else "Authoring command failed")


func regenerate_current() -> void:
	save_current()
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	var scene_id := _target_scene_id(editor)
	if scene_id.is_empty():
		_set_status("Select a scene file or open a scene graph.")
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

func apply_current_ir() -> Dictionary:
	if directory.is_empty():
		_set_status("No authoring directory.")
		return {"ok": false}
	var path := directory.path_join("ir").path_join("story.json")
	if not FileAccess.file_exists(path):
		_set_status("Missing ir/story.json")
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if file == null or json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_set_status("Invalid ir/story.json")
		return {"ok": false}
	var editor = get_parent().get_node_or_null("NodeMapEditor")
	if editor == null:
		_set_status("Node Map editor is missing.")
		return {"ok": false}
	editor.new_project()
	var applied: Dictionary = APPLIER.new().apply_story(editor.controller, json.data)
	if not applied.ok:
		var diagnostics: Array = applied.get("diagnostics", [])
		_set_status(str(diagnostics[0].get("message", "IR apply failed")) if not diagnostics.is_empty() else "IR apply failed")
		return applied
	var project_path := _project_path()
	editor.save_project(project_path)
	var exported: Dictionary = editor.export_runtime_package(directory.path_join("runtime-package"))
	if get_parent() is TabContainer:
		get_parent().current_tab = 0
	if exported.ok:
		_set_status("Applied IR, saved project, exported Runtime Package.")
	else:
		var diagnostics: Array = exported.get("diagnostics", [])
		_set_status(str(diagnostics[0].get("message", "Export failed")) if not diagnostics.is_empty() else "Export failed")
	return {"ok": exported.ok, "applied": applied, "exported": exported}

func _project_path() -> String:
	if directory.ends_with(".authoring"):
		return directory.substr(0, directory.length() - ".authoring".length()) + ".gelproj"
	return directory.path_join("story.gelproj")

func _set_status(message: String) -> void:
	_status.text = message
	status_changed.emit(message)
