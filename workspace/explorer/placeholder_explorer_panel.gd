@tool
extends "res://workspace/explorer/explorer_panel.gd"
class_name EditorPlaceholderExplorerPanel

const DATA_SCRIPT := preload("res://workspace/explorer/placeholder_explorer_data.gd")

## 仅用于展示通用 Explorer 的占位面板。
##
## 正式接入时可以把这个脚本替换成 SceneMap 或其他数据源适配器，而不改变
## EditorExplorerPanel、EditorExplorerTree 和 EditorExplorerModel 的接口。

func _ready() -> void:
    super._ready()
    set_model(DATA_SCRIPT.create_model())
