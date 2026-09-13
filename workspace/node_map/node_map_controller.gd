extends RefCounted

## 历史记录属于宿主；文档只提供原子变更和保留身份的快照。
signal history_changed
signal diagnostics_changed(diagnostics: Array)

const HISTORY_LIMIT := 100
var document
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

func _init(p_document) -> void:
	document = p_document

func execute(command: Dictionary) -> Dictionary:
	var before: Dictionary = document.get_snapshot()
	var result: Dictionary = document.execute(command)
	diagnostics_changed.emit(result.get("diagnostics", []))
	if result.get("ok", false):
		_record_history(before, document.get_snapshot(), command.duplicate(true))
	return result

## 一批命令共用一个撤销快照。失败时恢复批次开始前的文档。
func execute_batch(commands: Array) -> Dictionary:
	var before: Dictionary = document.get_snapshot()
	var applied: Array = []
	for command in commands:
		if not command is Dictionary:
			document.restore_snapshot(before)
			var invalid := [{"code": "invalid_command", "message": "Batch command must be a dictionary.", "severity": "error", "graph_id": "", "node_id": "", "port_id": "", "link_id": ""}]
			diagnostics_changed.emit(invalid)
			return {"ok": false, "diagnostics": invalid}
		var result: Dictionary = document.execute(command)
		if not result.get("ok", false):
			document.restore_snapshot(before)
			diagnostics_changed.emit(result.get("diagnostics", []))
			return result
		applied.append(result)
	_record_history(before, document.get_snapshot(), {"op": "batch"})
	diagnostics_changed.emit([])
	return {"ok": true, "diagnostics": [], "results": applied}

func _record_history(before: Dictionary, after: Dictionary, command: Dictionary) -> void:
	if before == after:
		return
	_undo.append({"before": before, "after": after, "command": command})
	if _undo.size() > HISTORY_LIMIT:
		_undo.pop_front()
	_redo.clear()
	history_changed.emit()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func get_history() -> Array:
	var result: Array = []
	for entry in _undo:
		result.append(_history_item(entry, true))
	var future := _redo.duplicate()
	future.reverse()
	for entry in future:
		result.append(_history_item(entry, false))
	return result

func get_history_cursor() -> int:
	return _undo.size()

func jump_to_history(index: int) -> bool:
	var target := clampi(index, 0, _undo.size() + _redo.size())
	while _undo.size() > target:
		if not undo():
			return false
	while _undo.size() < target:
		if not redo():
			return false
	return true

func undo() -> bool:
	return _restore(_undo, _redo, "before")

func redo() -> bool:
	return _restore(_redo, _undo, "after")

func clear_history() -> void:
	_undo.clear()
	_redo.clear()
	history_changed.emit()

func _restore(source: Array[Dictionary], target: Array[Dictionary], key: String) -> bool:
	if source.is_empty():
		return false
	var entry: Dictionary = source.back()
	var result: Dictionary = document.restore_snapshot(entry[key])
	diagnostics_changed.emit(result.get("diagnostics", []))
	if not result.get("ok", false):
		return false
	source.pop_back()
	target.append(entry)
	history_changed.emit()
	return true

func _history_item(entry: Dictionary, applied: bool) -> Dictionary:
	var command: Dictionary = entry.get("command", {})
	return {
		"operation": str(command.get("op", "edit")),
		"applied": applied,
	}
