extends "res://node_map/model/node_map_node.gd"

## 子图引用不是所有权；普通复制草稿必须由文档补齐新子图。
var child_graph_id: String = ""

func _reset_duplicate_identity() -> void:
	child_graph_id = ""
