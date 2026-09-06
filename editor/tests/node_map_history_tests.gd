extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _init() -> void:
	var history := NodeMapHistory.new()
	var map := SceneMap.new()
	history.reset(map)
	check(history.undo() == null and history.redo() == null, "Empty history")
	check(not history.record(map), "No-op does not record")
	map.add_node(SceneNode.new("a", "a"))
	check(history.record(map) and history.is_dirty(map), "Add snapshot dirty")
	history.mark_saved(map)
	check(not history.is_dirty(map), "Save point clean")
	map.add_node(SceneNode.new("b", "b"))
	history.record(map)
	var restored := history.undo()
	check(restored.has_node("a") and not restored.has_node("b"), "Undo isolated snapshot")
	check(not history.is_dirty(restored), "Undo to saved content clean")
	restored.remove_node("a")
	check(history.redo().get_node_count() == 2, "Returned snapshots cannot mutate history")
	check(history.undo().get_node_count() == 1, "Saved snapshot remains independent")
	map = history.undo()
	check(map.get_node_count() == 0 and history.is_dirty(map), "Undo before save dirty")
	history.mark_saved(map)
	check(not history.is_dirty(map), "Save after undo")
	map.add_node(SceneNode.new("c", "c"))
	history.record(map)
	check(history.redo() == null, "New branch clears redo")
	history._limit = 3
	for index in 10:
		map.add_node(SceneNode.new("n%d" % index, "n%d" % index))
		history.record(map)
	check(history._undo_stack.size() == 3, "History limit bounded")
	for index in 3: check(history.undo() != null, "Retained snapshot available")
	check(history.undo() == null, "Old snapshots evicted")
	history.reset(map)
	check(history._undo_stack.is_empty() and history._redo_stack.is_empty() and not history.is_dirty(map), "Load/reset clears history and dirty")
	print("Node Map history: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
