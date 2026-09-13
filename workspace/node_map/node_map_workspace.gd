extends TabContainer

func _ready() -> void:
	set_tab_title(0, "Node Map")
	set_tab_title(1, "Static Preview")

func _on_tab_changed(_tab: int) -> void:
	if is_node_ready():
		$NodeMapEditor.graph.finish_edits()
