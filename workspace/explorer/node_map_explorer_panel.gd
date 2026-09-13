@tool
extends "res://workspace/explorer/explorer_panel.gd"
class_name EditorNodeMapExplorerPanel

const ADAPTER := preload("res://workspace/explorer/node_map_explorer_adapter.gd")

var _adapter

func set_document(document) -> void:
	if _adapter == null:
		_adapter = ADAPTER.new(document)
		set_model(_adapter.get_model())
	else:
		_adapter.set_document(document)

func get_adapter():
	return _adapter

func _on_refresh_pressed() -> void:
	refresh_requested.emit()
	if _adapter != null:
		_adapter.refresh()
