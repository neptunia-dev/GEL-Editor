extends RefCounted
class_name NodeMapDocument

const Serializer = preload("res://node_map/persistence/node_map_serializer.gd")

var scene_map: SceneMap = SceneMap.new()
var file_path := ""
var is_dirty := false
var last_error := ""

func new_document() -> void:
	scene_map = SceneMap.new()
	file_path = ""
	last_error = ""
	mark_clean()

func get_diagnostics() -> Array:
	return scene_map.get_diagnostics()

func mark_dirty() -> void:
	is_dirty = true

func mark_clean() -> void:
	is_dirty = false

func save() -> bool:
	if file_path.is_empty():
		last_error = "No file path; use save_as()"
		return false
	return save_as(file_path)

func save_as(path: String) -> bool:
	var result := Serializer.save_file(path, scene_map)
	if not bool(result["ok"]):
		last_error = str(result["error"])
		return false
	file_path = path
	mark_clean()
	last_error = ""
	return true

func load_file(path: String) -> bool:
	var result := Serializer.load_file(path)
	if not bool(result["ok"]):
		last_error = str(result["error"])
		return false
	scene_map = (result["scene_map"] as SceneMap).duplicate_map()
	file_path = path
	mark_clean()
	last_error = ""
	return true
