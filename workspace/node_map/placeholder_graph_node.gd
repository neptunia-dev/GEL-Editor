@tool
extends GraphNode

## 只负责视觉样式，不是领域模型 NodeMapNode 的公共父类。
@export var accent: Color = Color("76bcb0"):
	set(value):
		accent = value
		if is_node_ready():
			_update_styles()

func _ready() -> void:
	_update_styles()

func _update_styles() -> void:
	var title_style := get_theme_stylebox("titlebar").duplicate() as StyleBoxFlat
	title_style.border_color = accent
	add_theme_stylebox_override("titlebar", title_style)
	var selected_title := title_style.duplicate() as StyleBoxFlat
	selected_title.bg_color = Color("3b3d40")
	add_theme_stylebox_override("titlebar_selected", selected_title)
	var selected_panel := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	selected_panel.border_color = accent
	selected_panel.shadow_color = Color(accent, 0.22)
	selected_panel.shadow_size = 4
	add_theme_stylebox_override("panel_selected", selected_panel)
	add_theme_color_override("title_color", Color("e9fbf6"))
	add_theme_font_size_override("title_font_size", 14)
	for child in get_children():
		if child is Label:
			child.add_theme_color_override("font_color", Color("cfe9e4"))
			child.add_theme_font_size_override("font_size", 12)
		if child is HBoxContainer:
			for item in child.get_children():
				if item is Label:
					item.add_theme_color_override("font_color", Color("b7d8d3"))
