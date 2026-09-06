extends SceneTree

var checks := 0
var failures := 0
var shell: Control
var popup: PopupMenu
var panels: Array[Control] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func checked(id: int) -> bool:
	return popup.is_item_checked(popup.get_item_index(id))

func activate(id: int) -> void:
	var menu: MenuButton = shell.find_child("WindowsMenu", true, false)
	menu.show_popup()
	check(popup.visible, "Windows menu opens")
	popup.id_pressed.emit(id)
	popup.hide()

func settle() -> void:
	for frame in 4:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1440, 900)
	shell = load("res://workspace/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await settle()
	popup = shell.find_child("WindowsMenu", true, false).get_popup()
	var node_map: NodeMapEditor = shell.find_child("NodeMapEditor", true, false)
	for panel_name in ["LeftUpper", "LeftLower", "RightUpper", "RightLower", "InspectorScroll", "Diagnostics"]:
		panels.append(shell.find_child(panel_name, true, false))
	var left: Control = panels[0].get_parent()
	var right: Control = panels[2].get_parent()
	var center: Control = shell.find_child("CenterRegion", true, false)
	var bottom: TabContainer = shell.find_child("EditorBottomPanel", true, false)
	var docks_button: Button = shell.find_child("ToggleDocks", true, false)
	var bottom_button: Button = shell.find_child("ToggleBottomPanel", true, false)
	check(popup.item_count == 9, "Only seven real panel controls and Show All")
	check(not checked(6) and bottom.current_tab == -1, "Bottom starts collapsed")
	check(panels[4].is_ancestor_of(node_map.title_edit), "Inspector targets the runtime scroll wrapper")
	node_map.add_default_node()
	var selected_id: String = node_map._selected_view().model_node_id
	var original_width := center.size.x
	for id in panels.size():
		check(checked(id), "Panel initially checked: %d" % id)
		activate(id)
		await settle()
		check(not panels[id].is_visible_in_tree() and not checked(id), "Menu hides actual panel: %d" % id)
		check(node_map.graph_edit.is_visible_in_tree(), "Canvas stays accessible")
		activate(id)
		await settle()
		check(panels[id].is_visible_in_tree() and checked(id), "Menu restores panel: %d" % id)
	check(node_map._selected_view().model_node_id == selected_id, "Selection survives visibility changes")
	check(node_map.title_edit.text == "New Scene", "Inspector retains selected data")
	activate(0)
	activate(1)
	await settle()
	check(not left.visible and right.visible, "Hiding both left docks hides only the left region")
	check(center.size.x > original_width + 100, "Hidden left region releases canvas width")
	activate(2)
	activate(3)
	await settle()
	check(not right.visible and docks_button.text == "Show Docks", "All side docks hidden synchronizes button")
	check(center.size.x >= center.get_parent().size.x - 1, "No empty side columns remain")
	activate(2)
	check(right.visible and not left.visible and checked(2) and not checked(3), "Individual menu restores only requested dock")
	docks_button.pressed.emit()
	for id in 4:
		check(not checked(id), "Docks button hides all and unchecks: %d" % id)
	docks_button.pressed.emit()
	for id in 4:
		check(checked(id) and panels[id].is_visible_in_tree(), "Show Docks restores all: %d" % id)
	panels[0].hide()
	check(not checked(0), "Direct panel visibility change synchronizes menu")
	panels[0].show()
	check(checked(0), "Direct panel restoration synchronizes menu")
	activate(6)
	await settle()
	check(checked(6) and bottom.current_tab == 0 and bottom_button.text == "Collapse", "Menu expands bottom and synchronizes button")
	var expanded_height := bottom.size.y
	bottom.current_tab = 1
	bottom_button.pressed.emit()
	await settle()
	check(not checked(6) and bottom.current_tab == -1 and bottom.size.y < expanded_height, "Bottom button collapses content and frees height")
	activate(6)
	check(bottom.current_tab == 1 and checked(6), "Reopen remembers Problems tab")
	activate(6)
	bottom.current_tab = 2
	check(checked(6) and bottom.current_tab == 2 and bottom_button.text == "Collapse", "Selecting collapsed Debugger tab expands without switching to Output")
	bottom.current_tab = -1
	check(not checked(6) and bottom_button.text == "Expand", "Tab deselection synchronizes collapsed state")
	bottom_button.pressed.emit()
	check(checked(6) and bottom.current_tab == 2, "Bottom button restores remembered tab")
	for id in panels.size():
		activate(id)
	activate(6)
	await settle()
	check(node_map.graph_edit.is_visible_in_tree(), "All optional panels hidden leaves canvas visible")
	activate(7)
	await settle()
	for id in panels.size():
		check(checked(id) and panels[id].is_visible_in_tree(), "Show All restores panel: %d" % id)
	check(checked(6) and bottom.current_tab == 2, "Show All restores bottom")
	check(left.visible and right.visible, "Show All restores side regions")
	shell.queue_free()
	await settle()
	print("%s: %d editor shell Windows checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
