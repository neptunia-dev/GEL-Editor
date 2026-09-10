extends VBoxContainer

## 当前会话中的正式模型编辑器。工程文件通过 NodeMapProjectFile 保存完整
## Node Map 快照和项目包配置；Runtime Package 导出仍只消费纯编译 DTO。
const BUILTINS := preload("res://node_map/registry/builtin_nodes.gd")
const DOCUMENT := preload("res://node_map/model/node_map_document.gd")
const COMPILER := preload("res://node_map/compiler/node_map_compiler.gd")
const PACKAGE_WRITER := preload("res://node_map/compiler/runtime_package_writer.gd")
const ENGINE_CLI := preload("res://node_map/integration/engine_cli_bridge.gd")
const PROJECT_CODEC := preload("res://node_map/serialization/project_file_codec.gd")
const PROJECT_FILE := preload("res://node_map/serialization/node_map_project_file.gd")
const CONTROLLER := preload("res://workspace/node_map/node_map_controller.gd")
const WIDGETS := preload("res://workspace/node_map/widgets/node_widget_registry.gd")
const PRESENTATIONS := preload("res://workspace/node_map/node_presentation_registry.gd")
const BUILTIN_PRESENTATIONS := preload("res://workspace/node_map/builtin_node_presentations.gd")
const SAMPLE := preload("res://workspace/node_map/sample_document.gd")

signal project_state_changed(path: String, dirty: bool)
signal project_save_as_requested

var registry
var document
var controller
var widgets
var presentations
var project_path := ""
var project_metadata: Dictionary = {}
var project_dirty := false
var _saved_project_snapshot: Dictionary = {}
var _saved_project_metadata: Dictionary = {}
var _saved_project_editor_state: Dictionary = {}
var _restoring_project := false
var _suppress_editor_state_dirty := false
var _editor_state_dirty_update_queued := false
var _clean_after_automatic_frame_graph_id := ""
var _graph_states: Dictionary = {}
var _add_position := Vector2.ZERO

@onready var graph = $Graph
@onready var _picker: PopupPanel = $NodePicker
@onready var _search: LineEdit = $NodePicker/Contents/Search
@onready var _types: ItemList = $NodePicker/Contents/Types
@onready var _status: Label = $Status/Diagnostic

func _ready() -> void:
	registry = BUILTINS.create_registry()
	document = DOCUMENT.new(registry)
	controller = CONTROLLER.new(document)
	project_metadata = PROJECT_CODEC.default_metadata()
	widgets = WIDGETS.standard()
	presentations = PRESENTATIONS.new()
	BUILTIN_PRESENTATIONS.configure(presentations)
	# 保留无工程启动时的示例，兼容现有画布演示和测试。正式工程只能通过
	# open_project() 显式替换，避免读取失败时覆盖当前创作内容。
	SAMPLE.populate(document)
	graph.configure(document, registry, widgets, presentations)
	graph.command_requested.connect(_execute)
	graph.scene_requested.connect(show_graph)
	graph.selection_changed.connect(_update_toolbar)
	graph.popup_request.connect(_open_picker_at)
	graph.scroll_offset_changed.connect(_on_graph_viewport_changed)
	graph.gui_input.connect(_on_graph_gui_input)
	document.changed.connect(_document_changed)
	controller.history_changed.connect(_update_toolbar)
	controller.diagnostics_changed.connect(_show_diagnostics)
	$Toolbar/Back.pressed.connect(func(): show_graph(document.root_graph_id))
	$Toolbar/Add.pressed.connect(_open_picker)
	$Toolbar/Undo.pressed.connect(_undo)
	$Toolbar/Redo.pressed.connect(_redo)
	$Toolbar/Save.pressed.connect(_save_toolbar_project)
	$Toolbar/Duplicate.pressed.connect(graph.duplicate_selection)
	$Toolbar/Delete.pressed.connect(graph.delete_selection)
	$Toolbar/Frame.pressed.connect(graph.frame_all)
	$Toolbar/Export.pressed.connect(_export_default_package)
	$Toolbar/Validate.pressed.connect(_validate_default_package)
	$Toolbar/Run.pressed.connect(_run_default_package)
	_search.text_changed.connect(func(_text): _populate_types())
	_search.text_submitted.connect(func(_text): _add_selected_type())
	_types.item_activated.connect(func(_index): _add_selected_type())
	$NodePicker/Contents/Add.pressed.connect(_add_selected_type)
	# The initial empty state is framed asynchronously; its resulting viewport
	# becomes the clean baseline rather than an unsaved user edit.
	_clean_after_automatic_frame_graph_id = document.root_graph_id
	show_graph(document.root_graph_id)
	_mark_project_clean()

func show_graph(id: String) -> void:
	if document.get_graph(id) == null or graph.graph_id == id:
		return
	if not graph.graph_id.is_empty():
		# Selection is session-only across graph navigation. Project editorState
		# deliberately persists only the stable viewport, not transient selection.
		_graph_states[graph.graph_id] = {"zoom": graph.zoom, "scroll": graph.scroll_offset, "selected": graph.get_selected_ids()}
	graph.show_graph(id)
	if _graph_states.has(id):
		graph.zoom = _graph_states[id].zoom
		graph.scroll_offset = _graph_states[id].scroll
		for selected in _graph_states[id].selected:
			var view = graph.get_node_view(selected)
			if view != null:
				view.selected = true
	else:
		_frame_after_layout(id)
	_update_toolbar()
	if not _restoring_project:
		_update_project_dirty()

func _frame_after_layout(id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if graph.graph_id == id:
		# Automatic first framing makes a newly shown graph inspectable; it is not
		# an edit the user needs to save as a project-state change.
		var mark_clean_after_frame := _clean_after_automatic_frame_graph_id == id
		if mark_clean_after_frame:
			_clean_after_automatic_frame_graph_id = ""
		_suppress_editor_state_dirty = true
		graph.frame_all()
		await get_tree().process_frame
		_suppress_editor_state_dirty = false
		if mark_clean_after_frame:
			_mark_project_clean()
	elif _clean_after_automatic_frame_graph_id == id:
		_clean_after_automatic_frame_graph_id = ""

func _execute(command: Dictionary) -> void:
	controller.execute(command)
	graph.request_refresh()

func _document_changed(_change: Dictionary) -> void:
	if _restoring_project:
		_update_toolbar()
		return
	if document.get_graph(graph.graph_id) == null:
		call_deferred("show_graph", document.root_graph_id)
	else:
		graph.request_refresh()
	_update_project_dirty()
	_update_toolbar()

func _on_graph_viewport_changed(_offset: Vector2) -> void:
	_schedule_editor_state_dirty_update()

func _on_graph_gui_input(_event: InputEvent) -> void:
	# Zoom does not expose its own GraphEdit signal. A deferred refresh observes
	# the post-input zoom and active-view state after GraphEdit processes it.
	_schedule_editor_state_dirty_update()

func _schedule_editor_state_dirty_update() -> void:
	if _restoring_project or _suppress_editor_state_dirty or _editor_state_dirty_update_queued:
		return
	_editor_state_dirty_update_queued = true
	call_deferred("_flush_editor_state_dirty_update")

func _flush_editor_state_dirty_update() -> void:
	_editor_state_dirty_update_queued = false
	if not _restoring_project and not _suppress_editor_state_dirty:
		_update_project_dirty()

func _update_toolbar() -> void:
	if controller == null:
		return
	$Toolbar/Undo.disabled = not controller.can_undo()
	$Toolbar/Redo.disabled = not controller.can_redo()
	$Toolbar/Back.disabled = graph.graph_id == document.root_graph_id
	var selected: Array = graph.get_selected_ids()
	$Toolbar/Delete.disabled = selected.is_empty()
	$Toolbar/Duplicate.disabled = selected.is_empty()
	var current = document.get_graph(graph.graph_id)
	var caption := "Root Graph"
	if current != null and current.kind == "scene":
		var owner_node = document.get_node(current.owner_node_id)
		if owner_node != null:
			caption += " / " + str(owner_node.get_parameter_values().get("display_name", "Scene"))
	$Toolbar/Breadcrumb.text = caption
	$Status/Counts.text = "%d nodes   %d links" % [document.get_nodes(graph.graph_id).size(), document.get_links(graph.graph_id).size()]

func _show_diagnostics(items: Array) -> void:
	_status.text = "" if items.is_empty() else str(items[0].get("message", "Invalid change"))
	_status.tooltip_text = _status.text

func _undo() -> void:
	graph.finish_edits()
	controller.undo()

func _redo() -> void:
	graph.finish_edits()
	controller.redo()

func _save_toolbar_project() -> void:
	if project_path.is_empty():
		project_save_as_requested.emit()
	else:
		save_project()

func request_save_project_as() -> void:
	project_save_as_requested.emit()

func undo_project_edit() -> bool:
	_undo()
	return true

func redo_project_edit() -> bool:
	_redo()
	return true

## 返回当前工程配置的深副本。工程元数据与 Runtime Package manifest 分开
## 保存，但通过 PROJECT_CODEC.to_compile_options() 在导出边界转换。
func get_project_metadata() -> Dictionary:
	return project_metadata.duplicate(true)

func get_project_path() -> String:
	return project_path

func is_project_dirty() -> bool:
	return project_dirty

func set_project_metadata(value: Dictionary) -> Dictionary:
	var normalized := PROJECT_CODEC.normalize_metadata(value)
	if not bool(normalized.get("ok", false)):
		_show_diagnostics(normalized.get("diagnostics", []))
		return {"ok": false, "diagnostics": normalized.get("diagnostics", [])}
	project_metadata = normalized.metadata.duplicate(true)
	_update_project_dirty()
	return {"ok": true, "diagnostics": [], "metadata": project_metadata.duplicate(true)}

## 将当前文档写成独立的编辑器工程文件。保存不清空撤销栈；用户仍可以
## 在保存点之后撤销，dirty 状态通过快照比较恢复为准确值。
func save_project(path: String = "") -> Dictionary:
	graph.finish_edits()
	var target := path if not path.is_empty() else project_path
	if target.is_empty():
		var missing := [_project_error("project_path_required", "Save Project requires a file path.")]
		_show_diagnostics(missing)
		return {"ok": false, "diagnostics": missing, "path": ""}
	var result: Dictionary = PROJECT_FILE.save(document, project_metadata, target, _serialize_editor_state())
	if not bool(result.get("ok", false)):
		_show_diagnostics(result.get("diagnostics", []))
		return result
	project_path = str(result.get("path", target))
	project_metadata = result.get("metadata", project_metadata).duplicate(true)
	_mark_project_clean()
	_status.text = "Saved Project: " + project_path
	_status.tooltip_text = project_path
	return result

func save_project_as(path: String) -> Dictionary:
	return save_project(path)

## 先由 NodeMapProjectFile 在 detached document 中完成全部解析和模型校验，
## 成功后才恢复到当前 document 实例，因此 GraphView、Controller 和信号订阅
## 不会悬空，失败也不会破坏用户正在编辑的工程。
func open_project(path: String) -> Dictionary:
	graph.finish_edits()
	var loaded: Dictionary = PROJECT_FILE.load(registry, path)
	if not bool(loaded.get("ok", false)):
		_show_diagnostics(loaded.get("diagnostics", []))
		return loaded
	var candidate = loaded.get("document", null)
	if candidate == null or not candidate.has_method("get_snapshot"):
		var invalid := [_project_error("invalid_project_document", "Loaded project did not produce a document.")]
		_show_diagnostics(invalid)
		return {"ok": false, "diagnostics": invalid, "path": path}
	_restoring_project = true
	var restored: Dictionary = document.restore_snapshot(candidate.get_snapshot())
	if not bool(restored.get("ok", false)):
		_restoring_project = false
		_show_diagnostics(restored.get("diagnostics", []))
		return {"ok": false, "diagnostics": restored.get("diagnostics", []), "path": path}
	project_path = str(loaded.get("path", path))
	project_metadata = loaded.get("metadata", PROJECT_CODEC.default_metadata()).duplicate(true)
	_graph_states.clear()
	controller.clear_history()
	# show_graph() intentionally no-ops when the ID is unchanged; force a fresh
	# view selection after replacing the aggregate contents.
	graph.graph_id = ""
	var active_graph := _restore_editor_state(loaded.get("editor_state", {}))
	_clean_after_automatic_frame_graph_id = active_graph if not _graph_states.has(active_graph) else ""
	show_graph(active_graph)
	_restoring_project = false
	_mark_project_clean()
	_status.text = "Opened Project: " + project_path
	_status.tooltip_text = project_path
	return {"ok": true, "diagnostics": [], "path": project_path, "metadata": project_metadata.duplicate(true)}

## 创建一个空白、结构有效的 Node Map 文档。它保留固定 Project Start，
## 不自动填充示例；示例只作为无工程启动时的兼容 fallback。
func new_project() -> Dictionary:
	graph.finish_edits()
	var fresh = DOCUMENT.new(registry)
	_restoring_project = true
	var restored: Dictionary = document.restore_snapshot(fresh.get_snapshot())
	if not bool(restored.get("ok", false)):
		_restoring_project = false
		_show_diagnostics(restored.get("diagnostics", []))
		return {"ok": false, "diagnostics": restored.get("diagnostics", [])}
	project_path = ""
	project_metadata = PROJECT_CODEC.default_metadata()
	_graph_states.clear()
	controller.clear_history()
	graph.graph_id = ""
	_clean_after_automatic_frame_graph_id = document.root_graph_id
	show_graph(document.root_graph_id)
	_restoring_project = false
	_mark_project_clean()
	_status.text = "New Project"
	_status.tooltip_text = ""
	return {"ok": true, "diagnostics": [], "path": "", "metadata": project_metadata.duplicate(true)}

func _mark_project_clean() -> void:
	_saved_project_snapshot = document.get_snapshot()
	_saved_project_metadata = project_metadata.duplicate(true)
	_saved_project_editor_state = _serialize_editor_state()
	project_dirty = false
	# A successful Save/Open/New can change the path while remaining clean, so
	# always notify the shell rather than only notifying on a dirty flip.
	project_state_changed.emit(project_path, project_dirty)

func _update_project_dirty() -> void:
	if document == null:
		return
	var next_dirty: bool = document.get_snapshot() != _saved_project_snapshot or project_metadata != _saved_project_metadata or _serialize_editor_state() != _saved_project_editor_state
	if next_dirty == project_dirty:
		return
	project_dirty = next_dirty
	project_state_changed.emit(project_path, project_dirty)

func _serialize_editor_state() -> Dictionary:
	var states: Dictionary = {}
	for id in _graph_states:
		var state: Variant = _graph_states[id]
		var normalized := _serialize_graph_state(state)
		if not normalized.is_empty():
			states[str(id)] = normalized
	if graph != null and not graph.graph_id.is_empty():
		var current := _serialize_graph_state({"zoom": graph.zoom, "scroll": graph.scroll_offset})
		if not current.is_empty():
			states[graph.graph_id] = current
	return {"activeGraphId": graph.graph_id, "graphStates": states}

func _serialize_graph_state(state: Variant) -> Dictionary:
	if not state is Dictionary:
		return {}
	var zoom: Variant = state.get("zoom", 1.0)
	var scroll: Variant = state.get("scroll", Vector2.ZERO)
	if not _is_finite_number(zoom) or not scroll is Vector2 or not scroll.is_finite():
		return {}
	return {"zoom": float(zoom), "scroll": {"x": float(scroll.x), "y": float(scroll.y)}}

func _restore_editor_state(state: Variant) -> String:
	_graph_states.clear()
	var fallback: String = document.root_graph_id
	if not state is Dictionary:
		return fallback
	var raw_states: Variant = state.get("graphStates", {})
	if raw_states is Dictionary:
		for id in raw_states:
			if not id is String or document.get_graph(id) == null:
				continue
			var raw: Variant = raw_states[id]
			if not raw is Dictionary:
				continue
			var zoom: Variant = raw.get("zoom", 1.0)
			var scroll: Variant = raw.get("scroll", {})
			if not _is_finite_number(zoom) or not scroll is Dictionary:
				continue
			if not _is_finite_number(scroll.get("x", null)) or not _is_finite_number(scroll.get("y", null)):
				continue
			_graph_states[id] = {"zoom": clampf(float(zoom), 0.1, 2.0), "scroll": Vector2(float(scroll.x), float(scroll.y)), "selected": []}
	var active: Variant = state.get("activeGraphId", fallback)
	if active is String and document.get_graph(active) != null:
		return active
	return fallback

func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _project_error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "severity": "error", "graph_id": "", "node_id": "", "port_id": "", "link_id": ""}

func _project_compile_options() -> Dictionary:
	var options: Dictionary = PROJECT_CODEC.to_compile_options(project_metadata)
	return options if not options.is_empty() else DEFAULT_RUNTIME_PACKAGE_OPTIONS.duplicate(true)

## 编译当前文档并写入一个可由 Node 引擎读取的目录包。
##
## 默认目录使用 `user://runtime-package`，避免把构建产物写入编辑器资源树；
## 外部项目宿主可传入实际项目导出目录和包元数据。返回值统一使用
## `{ok, diagnostics, directory, manifest_path}`，因此菜单、测试和后续 CLI 桥接
## 不需要捕获 UI 专属异常。
const DEFAULT_RUNTIME_PACKAGE_DIRECTORY := "user://runtime-package"
const DEFAULT_RUNTIME_PACKAGE_OPTIONS := {"package_id": "untitled.story", "title": "Untitled Story"}

func export_runtime_package(destination: String = DEFAULT_RUNTIME_PACKAGE_DIRECTORY, options: Dictionary = {}) -> Dictionary:
	graph.finish_edits()
	var effective_options: Dictionary = options.duplicate(true) if not options.is_empty() else _project_compile_options()
	var compiled: Dictionary = COMPILER.new().compile(document, effective_options)
	if not compiled.ok:
		_show_diagnostics(compiled.diagnostics)
		return {"ok": false, "diagnostics": compiled.diagnostics, "directory": "", "manifest_path": ""}
	var result: Dictionary = PACKAGE_WRITER.new().write(compiled, destination)
	if result.ok:
		_status.text = "Exported Runtime Package: " + result.directory
		_status.tooltip_text = result.manifest_path
	else:
		_show_diagnostics(result.diagnostics)
	return result

func _export_default_package() -> void:
	export_runtime_package()

## 先写出包，再使用真实的 TypeScript PackageLoader 做校验。这里故意不把
## PackageLoader 行为复制到 GDScript；Node CLI 的 JSON 输出可供后续面板消费。
func validate_runtime_package(destination: String = DEFAULT_RUNTIME_PACKAGE_DIRECTORY, options: Dictionary = {}) -> Dictionary:
	var exported := export_runtime_package(destination, options)
	if not exported.ok:
		return exported
	var validated: Dictionary = ENGINE_CLI.new().validate(exported.directory)
	if validated.ok:
		_status.text = "Runtime Package validated by Node engine: " + exported.directory
		_status.tooltip_text = validated.output.strip_edges()
		return {"ok": true, "diagnostics": [], "directory": exported.directory, "manifest_path": exported.manifest_path, "engine": validated.result}
	_show_diagnostics(validated.diagnostics)
	return {"ok": false, "diagnostics": validated.diagnostics, "directory": exported.directory, "manifest_path": exported.manifest_path, "engine": validated.result}

## 最小跨层运行验证：让 Node StoryRunner 自动推进台词/等待并选择第一个可用选项。
## 正式的 Godot 交互预览仍需要 IPC 请求/表现适配器，不能由此 API 假装完成。
func run_runtime_package_auto(destination: String = DEFAULT_RUNTIME_PACKAGE_DIRECTORY, options: Dictionary = {}) -> Dictionary:
	var validated := validate_runtime_package(destination, options)
	if not validated.ok:
		return validated
	var ran: Dictionary = ENGINE_CLI.new().run_auto(validated.directory)
	if ran.ok:
		_status.text = "Runtime Package ran in Node engine: " + validated.directory
		_status.tooltip_text = ran.output.strip_edges()
		return {"ok": true, "diagnostics": [], "directory": validated.directory, "manifest_path": validated.manifest_path, "engine": ran.result}
	_show_diagnostics(ran.diagnostics)
	return {"ok": false, "diagnostics": ran.diagnostics, "directory": validated.directory, "manifest_path": validated.manifest_path, "engine": ran.result}

func _validate_default_package() -> void:
	validate_runtime_package()

func _run_default_package() -> void:
	run_runtime_package_auto()

func _open_picker() -> void:
	_open_picker_at(graph.size * 0.5)

func _open_picker_at(local_position: Vector2) -> void:
	graph.finish_edits()
	_add_position = (local_position + graph.scroll_offset) / graph.zoom
	_search.text = ""
	_populate_types()
	_picker.popup_centered(Vector2i(340, 360))
	_search.grab_focus()

func _populate_types() -> void:
	_types.clear()
	var current = document.get_graph(graph.graph_id)
	if current == null:
		return
	for definition in registry.list_definitions(current.kind):
		if definition.type_id in ["gel.project_start", "gel.graph_input"]:
			continue
		var caption: String = "%s / %s" % [definition.category, definition.display_name]
		if not _search.text.is_empty() and not (_search.text.to_lower() in (caption + definition.type_id).to_lower()):
			continue
		var index := _types.add_item(caption)
		_types.set_item_metadata(index, definition.type_id)
		_types.set_item_tooltip(index, definition.type_id)
	if _types.item_count > 0:
		_types.select(0)
	$NodePicker/Contents/Add.disabled = _types.item_count == 0

func _add_selected_type() -> void:
	var indices := _types.get_selected_items()
	if indices.is_empty():
		return
	var type_id: String = _types.get_item_metadata(indices[0])
	_picker.hide()
	add_node_type(type_id, _add_position)

func add_node_type(type_id: String, at: Vector2) -> Dictionary:
	var result: Dictionary = controller.execute({"op": "create_node", "type_id": type_id, "graph_id": graph.graph_id, "position": at})
	graph.request_refresh()
	return result

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or (focus != null and not is_ancestor_of(focus)):
		return
	if event.is_command_or_control_pressed() and event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo()
		else:
			_undo()
	elif event.is_command_or_control_pressed() and event.keycode == KEY_Y:
		_redo()
	elif event.keycode == KEY_DELETE:
		graph.delete_selection()
	else:
		return
	get_viewport().set_input_as_handled()
