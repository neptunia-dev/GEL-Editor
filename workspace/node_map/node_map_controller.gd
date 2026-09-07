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
		var after: Dictionary = document.get_snapshot()
		if before != after:
			_undo.append({"before": before, "after": after})
			if _undo.size() > HISTORY_LIMIT:
				_undo.pop_front()
			_redo.clear()
			history_changed.emit()
	return result

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

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
