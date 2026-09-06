extends RefCounted
class_name NodeMapHistory

var _undo_stack: Array = []
var _redo_stack: Array = []
var _current: SceneMap
var _saved: Dictionary
var _limit := 100

func reset(map: SceneMap) -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_current = map.duplicate_map()
	mark_saved(map)

func record(map: SceneMap) -> bool:
	if map.to_editor_dict() == _current.to_editor_dict():
		return false
	_undo_stack.append(_current)
	if _undo_stack.size() > _limit:
		_undo_stack.pop_front()
	_current = map.duplicate_map()
	_redo_stack.clear()
	return true

func undo() -> SceneMap:
	if _undo_stack.is_empty():
		return null
	_redo_stack.append(_current)
	_current = _undo_stack.pop_back()
	return _current.duplicate_map()

func redo() -> SceneMap:
	if _redo_stack.is_empty():
		return null
	_undo_stack.append(_current)
	_current = _redo_stack.pop_back()
	return _current.duplicate_map()

func mark_saved(map: SceneMap) -> void:
	_saved = map.to_editor_dict()

func is_dirty(map: SceneMap) -> bool:
	return map.to_editor_dict() != _saved
