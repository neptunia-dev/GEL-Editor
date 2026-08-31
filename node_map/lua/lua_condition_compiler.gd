extends RefCounted
class_name LuaConditionCompiler

var _tree: ConditionTree
var _variable_catalog: Dictionary
var _diagnostics: Array
var _exits: Array
var _temp_index: int

## 编译条件树。variable_catalog 的值可以是 schema，也可以是含 schema 字段的变量定义。
func compile(tree: ConditionTree, variable_catalog: Dictionary) -> Dictionary:
    _diagnostics = []
    _exits = []
    _temp_index = 0
    _variable_catalog = variable_catalog

    if tree == null:
        return {"ok": true, "code": "", "exits": [], "diagnostics": []}
    _tree = tree.duplicate_tree()
    _diagnostics.append_array(_tree.validate_self())
    if not _diagnostics.is_empty():
        return _failure_result()

    _validate_variable_references()
    if not _diagnostics.is_empty():
        return _failure_result()

    var lines: Array = []
    _compile_wrapper(_tree.root_wrapper_id, 0, lines)
    return {
        "ok": true,
        "code": "\n".join(lines),
        "exits": _exits.duplicate(true),
        "diagnostics": [],
    }

func _validate_variable_references() -> void:
    for wrapper in _tree.get_wrappers():
        if wrapper is IfWrapper:
            var if_wrapper := wrapper as IfWrapper
            var schema := _get_schema(if_wrapper.variable_key)
            if schema.is_empty():
                _diagnostics.append("variable '%s' is not declared" % if_wrapper.variable_key)
            elif str(schema.get("type", "")) != "boolean":
                _diagnostics.append("if variable '%s' must use a boolean schema" % if_wrapper.variable_key)
        elif wrapper is SwitchCaseWrapper:
            var switch_wrapper := wrapper as SwitchCaseWrapper
            var schema := _get_schema(switch_wrapper.variable_key)
            if schema.is_empty():
                _diagnostics.append("variable '%s' is not declared" % switch_wrapper.variable_key)
                continue
            var schema_type := str(schema.get("type", ""))
            if not ["null", "boolean", "number", "string"].has(schema_type):
                _diagnostics.append("switch variable '%s' must use a scalar schema" % switch_wrapper.variable_key)
                continue
            for branch_id in switch_wrapper.case_branch_ids:
                var branch := _tree.get_branch(str(branch_id))
                if branch != null:
                    _validate_value_against_schema(branch.match_value, schema, "switch '%s' case '%s'" % [wrapper.wrapper_id, branch_id])
        elif wrapper is NumericCompareWrapper:
            var numeric_wrapper := wrapper as NumericCompareWrapper
            _validate_numeric_operand(numeric_wrapper.left_operand, "numeric '%s' left operand" % wrapper.wrapper_id)
            _validate_numeric_operand(numeric_wrapper.right_operand, "numeric '%s' right operand" % wrapper.wrapper_id)

func _validate_numeric_operand(operand: NumericOperand, path: String) -> void:
    if operand == null:
        _diagnostics.append("%s is missing" % path)
        return
    if operand.kind == NumericOperand.KIND_CONSTANT:
        if not ConditionBranch.is_finite_number(operand.constant_value):
            _diagnostics.append("%s must be a finite number" % path)
        return
    if operand.kind != NumericOperand.KIND_VARIABLE:
        _diagnostics.append("%s has an unsupported kind" % path)
        return
    var schema := _get_schema(operand.variable_key)
    if schema.is_empty():
        _diagnostics.append("variable '%s' is not declared" % operand.variable_key)
    elif str(schema.get("type", "")) != "number":
        _diagnostics.append("numeric variable '%s' must use a number schema" % operand.variable_key)

func _validate_value_against_schema(value: Variant, schema: Dictionary, path: String) -> void:
    var schema_type := str(schema.get("type", ""))
    if schema_type == "null":
        if value != null:
            _diagnostics.append("%s must match null" % path)
        return
    if schema_type == "boolean":
        if typeof(value) != TYPE_BOOL:
            _diagnostics.append("%s must be a boolean" % path)
        return
    if schema_type == "number":
        if not ConditionBranch.is_finite_number(value):
            _diagnostics.append("%s must be a finite number" % path)
            return
        var number := float(value)
        if bool(schema.get("integer", false)) and number != floor(number):
            _diagnostics.append("%s must be an integer" % path)
        if schema.has("min") and number < float(schema["min"]):
            _diagnostics.append("%s is below the schema minimum" % path)
        if schema.has("max") and number > float(schema["max"]):
            _diagnostics.append("%s is above the schema maximum" % path)
        return
    if schema_type == "string":
        if typeof(value) != TYPE_STRING:
            _diagnostics.append("%s must be a string" % path)
            return
        var text := str(value)
        if schema.has("minLength") and text.length() < int(schema["minLength"]):
            _diagnostics.append("%s is shorter than the schema minimum" % path)
        if schema.has("maxLength") and text.length() > int(schema["maxLength"]):
            _diagnostics.append("%s is longer than the schema maximum" % path)
        if schema.has("enum") and schema["enum"] is Array and not (schema["enum"] as Array).has(text):
            _diagnostics.append("%s is not in the schema enum" % path)
        if schema.has("pattern"):
            var regex := RegEx.new()
            if regex.compile(str(schema["pattern"])) != OK or regex.search(text) == null:
                _diagnostics.append("%s does not match the schema pattern" % path)

func _compile_wrapper(wrapper_id: String, indent: int, lines: Array) -> void:
    var wrapper := _tree.get_wrapper(wrapper_id)
    if wrapper is IfWrapper:
        var if_wrapper := wrapper as IfWrapper
        lines.append("%sif ctx.state:get(%s) then" % [_indent(indent), _lua_string(if_wrapper.variable_key)])
        _compile_branch(wrapper_id, if_wrapper.true_branch_id, indent + 1, lines)
        lines.append("%selse" % _indent(indent))
        _compile_branch(wrapper_id, if_wrapper.false_branch_id, indent + 1, lines)
        lines.append("%send" % _indent(indent))
    elif wrapper is SwitchCaseWrapper:
        var switch_wrapper := wrapper as SwitchCaseWrapper
        var value_name := _next_temp("value")
        lines.append("%slocal %s = ctx.state:get(%s)" % [_indent(indent), value_name, _lua_string(switch_wrapper.variable_key)])
        for index in range(switch_wrapper.case_branch_ids.size()):
            var branch_id := str(switch_wrapper.case_branch_ids[index])
            var branch := _tree.get_branch(branch_id)
            var keyword := "if" if index == 0 else "elseif"
            lines.append("%s%s %s == %s then" % [_indent(indent), keyword, value_name, _lua_literal(branch.match_value)])
            _compile_branch(wrapper_id, branch_id, indent + 1, lines)
        if switch_wrapper.case_branch_ids.is_empty():
            _compile_branch(wrapper_id, switch_wrapper.default_branch_id, indent, lines)
        else:
            lines.append("%selse" % _indent(indent))
            _compile_branch(wrapper_id, switch_wrapper.default_branch_id, indent + 1, lines)
            lines.append("%send" % _indent(indent))
    elif wrapper is NumericCompareWrapper:
        var numeric_wrapper := wrapper as NumericCompareWrapper
        var left_name := _next_temp("left")
        var right_name := _next_temp("right")
        lines.append("%slocal %s = %s" % [_indent(indent), left_name, _compile_operand(numeric_wrapper.left_operand)])
        lines.append("%slocal %s = %s" % [_indent(indent), right_name, _compile_operand(numeric_wrapper.right_operand)])
        lines.append("%sif %s < %s then" % [_indent(indent), left_name, right_name])
        _compile_branch(wrapper_id, numeric_wrapper.less_branch_id, indent + 1, lines)
        lines.append("%selseif %s > %s then" % [_indent(indent), left_name, right_name])
        _compile_branch(wrapper_id, numeric_wrapper.greater_branch_id, indent + 1, lines)
        lines.append("%selse" % _indent(indent))
        _compile_branch(wrapper_id, numeric_wrapper.equal_branch_id, indent + 1, lines)
        lines.append("%send" % _indent(indent))

func _compile_branch(wrapper_id: String, branch_id: String, indent: int, lines: Array) -> void:
    var branch := _tree.get_branch(branch_id)
    if branch != null and not branch.child_wrapper_id.is_empty():
        _compile_wrapper(branch.child_wrapper_id, indent, lines)
        return
    var port := _tree.runtime_port(wrapper_id, branch_id)
    lines.append("%sreturn ctx.flow:exit(%s)" % [_indent(indent), _lua_string(port)])
    _exits.append({"wrapperId": wrapper_id, "branchId": branch_id, "port": port})

func _compile_operand(operand: NumericOperand) -> String:
    if operand.kind == NumericOperand.KIND_VARIABLE:
        return "ctx.state:get(%s)" % _lua_string(operand.variable_key)
    return _lua_number(operand.constant_value)

func _get_schema(variable_key: String) -> Dictionary:
    if not _variable_catalog.has(variable_key) or not (_variable_catalog[variable_key] is Dictionary):
        return {}
    var entry := _variable_catalog[variable_key] as Dictionary
    if entry.has("schema") and entry["schema"] is Dictionary:
        return (entry["schema"] as Dictionary).duplicate(true)
    return entry.duplicate(true)

func _lua_literal(value: Variant) -> String:
    if value == null:
        return "nil"
    match typeof(value):
        TYPE_BOOL:
            return "true" if value else "false"
        TYPE_INT, TYPE_FLOAT:
            return _lua_number(value)
        TYPE_STRING:
            return _lua_string(str(value))
    return "nil"

func _lua_number(value: Variant) -> String:
    if typeof(value) == TYPE_INT:
        return str(value)
    var number := float(value)
    if number == 0.0:
        return "0"
    return String.num(number, 17)

func _lua_string(value: String) -> String:
    var result := "\""
    for index in range(value.length()):
        var codepoint := value.unicode_at(index)
        match codepoint:
            34:
                result += "\\\""
            92:
                result += "\\\\"
            10:
                result += "\\n"
            13:
                result += "\\r"
            9:
                result += "\\t"
            _:
                if codepoint < 32 or codepoint == 127:
                    result += "\\%03d" % codepoint
                else:
                    result += String.chr(codepoint)
    return result + "\""

func _next_temp(kind: String) -> String:
    _temp_index += 1
    return "_gel_%s_%d" % [kind, _temp_index]

func _indent(level: int) -> String:
    return "  ".repeat(level)

func _failure_result() -> Dictionary:
    return {"ok": false, "code": "", "exits": [], "diagnostics": _diagnostics.duplicate()}
