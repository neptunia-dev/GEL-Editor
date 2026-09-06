extends VBoxContainer
class_name NodeMapInspector

var editor: NodeMapEditor
var model: SceneNode

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _field(parent: Node, text: String, hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.placeholder_text = hint
	field.tooltip_text = hint
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func bind_node(node: SceneNode) -> void:
	model = node
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if node == null: return
	var position_row := HBoxContainer.new()
	add_child(position_row)
	var x := _field(position_row, str(node.position.x), "Position X")
	var y := _field(position_row, str(node.position.y), "Position Y")
	_button(position_row, "Set Position", func():
		if not x.text.is_valid_float() or not y.text.is_valid_float():
			editor._show_error("Position must be numeric")
			return
		editor._update_selected_node(func(n):
			var position := Vector2(float(x.text), float(y.text))
			if not position.is_finite(): return false
			n.set_position(position)
			return true))
	for member in node.get_cast() + [CastMember.new()]:
		var row := HBoxContainer.new()
		add_child(row)
		var id := _field(row, member.character_id, "Character ID")
		var role := _field(row, member.role, "Role")
		var display := _field(row, member.display_name, "Display Name")
		var old_id: String = member.character_id
		_button(row, "Add Cast" if old_id.is_empty() else "Update Cast", func():
			var candidate := CastMember.new(id.text, role.text, display.text)
			editor._update_selected_node(func(n): return n.add_cast_member(candidate) if old_id.is_empty() else n.update_cast_member(old_id, candidate)))
		if not old_id.is_empty():
			_button(row, "Delete Cast", func(): editor._update_selected_node(func(n): return n.remove_cast_member(old_id)))
	var tree := node.get_condition_tree()
	if tree == null:
		_add_buttons(self, "")
		return
	_button(self, "Clear Condition Tree", editor.remove_condition.bind("tree", ""))
	_wrapper_ui(tree, tree.root_wrapper_id, 0)

func _add_buttons(parent: Node, branch_id: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	for kind in ["If", "Switch", "Numeric"]:
		_button(row, "Add " + kind, add_wrapper.bind(kind, branch_id))

func add_wrapper(kind: String, parent_branch: String = "") -> void:
	var tree := model.get_condition_tree()
	if tree != null and tree.get_wrappers().size() >= 128:
		editor._show_error("At most 128 wrappers per Scene")
		return
	var id := editor._new_id("wrapper")
	var a := editor._new_id("a")
	var b := editor._new_id("b")
	var c := editor._new_id("c")
	var wrapper: ConditionWrapper
	var branches: Array
	match kind:
		"If":
			wrapper = IfWrapper.new(id, "flag", a, b)
			branches = [ConditionBranch.new(a, "true"), ConditionBranch.new(b, "false")]
		"Switch":
			wrapper = SwitchCaseWrapper.new(id, "choice", [], a)
			branches = [ConditionBranch.new(a, "default")]
		_:
			wrapper = NumericCompareWrapper.new(id, NumericOperand.variable("score"), NumericOperand.constant(0), a, b, c)
			branches = [ConditionBranch.new(a, "less"), ConditionBranch.new(b, "equal"), ConditionBranch.new(c, "greater")]
	if tree == null:
		tree = ConditionTree.new(id, [wrapper], branches)
	elif not tree.attach_child_wrapper(parent_branch, wrapper, branches):
		editor._show_error(tree.last_error)
		return
	editor.apply_tree(tree)

func _wrapper_ui(tree: ConditionTree, id: String, depth: int) -> void:
	var wrapper := tree.get_wrapper(id)
	var heading := Label.new()
	heading.text = "%s%s [%s]" % ["  ".repeat(depth), wrapper.to_editor_dict().type, id]
	add_child(heading)
	var row := HBoxContainer.new()
	add_child(row)
	if wrapper is IfWrapper or wrapper is SwitchCaseWrapper:
		var variable := _field(row, wrapper.variable_key, "Variable Key")
		_button(row, "Apply Variable", func():
			wrapper.variable_key = variable.text
			_update_wrapper(tree, wrapper))
	else:
		var left := _field(row, JSON.stringify(wrapper.left_operand.to_editor_dict()), "Left operand JSON: kind + variableKey/value")
		var right := _field(row, JSON.stringify(wrapper.right_operand.to_editor_dict()), "Right operand JSON: kind + variableKey/value")
		_button(row, "Apply Operands (< / = / >)", func():
			var left_json := JSON.new()
			var right_json := JSON.new()
			if left_json.parse(left.text) != OK or right_json.parse(right.text) != OK:
				editor._show_error("Invalid operand JSON")
				return
			var l = left_json.data
			var r = right_json.data
			for operand in [l, r]:
				var error := NodeMapSerializer._validate(operand, "operand")
				if not error.is_empty():
					editor._show_error(error)
					return
			wrapper.left_operand = NodeMapSerializer._operand(l)
			wrapper.right_operand = NodeMapSerializer._operand(r)
			_update_wrapper(tree, wrapper))
	if id != tree.root_wrapper_id:
		_button(row, "Delete Wrapper", editor.remove_condition.bind("wrapper", id))
	if wrapper is SwitchCaseWrapper:
		var case_row := HBoxContainer.new()
		add_child(case_row)
		var value := _field(case_row, "", "New case JSON scalar (e.g. 1, true, null, \"yes\")")
		_button(case_row, "Add Case", func():
			var json := JSON.new()
			if json.parse(value.text) != OK:
				editor._show_error("Invalid case JSON")
				return
			var branch := ConditionBranch.new(editor._new_id("case"), value.text, "", true, json.data)
			if not tree.add_switch_case(id, branch): editor._show_error(tree.last_error)
			else: editor.apply_tree(tree))
	for branch_id in wrapper.get_branch_ids():
		var branch := tree.get_branch(branch_id)
		var branch_row := HBoxContainer.new()
		add_child(branch_row)
		var label := _field(branch_row, branch.label, "Branch Label [%s]" % branch_id)
		var value: LineEdit
		if branch.has_match_value:
			value = _field(branch_row, JSON.stringify(branch.match_value), "Case JSON scalar")
		_button(branch_row, "Apply Branch", func():
			var match_value = branch.match_value
			if value != null:
				var json := JSON.new()
				if json.parse(value.text) != OK:
					editor._show_error("Invalid case JSON")
					return
				match_value = json.data
			if not tree.update_branch_value(branch_id, label.text, branch.has_match_value, match_value): editor._show_error(tree.last_error)
			else: editor.apply_tree(tree))
		if branch.has_match_value:
			_button(branch_row, "Delete Case", editor.remove_condition.bind("branch", branch_id))
		if branch.is_terminal():
			_add_buttons(self, branch_id)
		else:
			_wrapper_ui(tree, branch.child_wrapper_id, depth + 1)

func _update_wrapper(tree: ConditionTree, wrapper: ConditionWrapper) -> void:
	if not tree.update_wrapper(wrapper): editor._show_error(tree.last_error)
	else: editor.apply_tree(tree)
