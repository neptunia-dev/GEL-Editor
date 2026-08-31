extends RefCounted
class_name LuaConditionBlockWriter

const START_MARKER := "-- GEL:generated:conditions:start"
const END_MARKER := "-- GEL:generated:conditions:end"

## 只替换两个唯一标记之间的内容；区块外的文本逐行原样保留。
func replace_block(source: String, generated_code: String) -> Dictionary:
    var lines := source.split("\n", true)
    var start_indices: Array = []
    var end_indices: Array = []
    for index in range(lines.size()):
        var comparable := str(lines[index]).trim_suffix("\r").strip_edges()
        if comparable == START_MARKER:
            start_indices.append(index)
        elif comparable == END_MARKER:
            end_indices.append(index)

    if start_indices.size() != 1 or end_indices.size() != 1:
        return _failure("main.lua must contain exactly one condition start marker and one end marker")
    var start_index := int(start_indices[0])
    var end_index := int(end_indices[0])
    if start_index >= end_index:
        return _failure("condition block markers are in the wrong order")

    if not generated_code.is_empty():
        var handwritten_parts: Array = []
        for index in range(start_index):
            handwritten_parts.append(lines[index])
        for index in range(end_index + 1, lines.size()):
            handwritten_parts.append(lines[index])
        if _contains_flow_exit("\n".join(handwritten_parts)):
            return _failure("handwritten main.lua must not call ctx.flow:exit when a condition block is generated")

    var start_line := str(lines[start_index]).trim_suffix("\r")
    var marker_column := start_line.find(START_MARKER)
    if marker_column < 0 or not start_line.substr(0, marker_column).strip_edges().is_empty():
        return _failure("condition block start marker must be on its own line")
    var indentation := start_line.substr(0, marker_column)
    var carriage := "\r" if source.contains("\r\n") else ""

    var output: Array = []
    for index in range(start_index + 1):
        output.append(lines[index])
    if not generated_code.is_empty():
        for generated_line in generated_code.split("\n", true):
            output.append("%s%s%s" % [indentation, generated_line, carriage])
    for index in range(end_index, lines.size()):
        output.append(lines[index])

    return {"ok": true, "text": "\n".join(output), "diagnostics": []}

func standard_template() -> String:
    return "return function(ctx)\n  -- Scene handwritten content\n\n  %s\n  %s\nend\n" % [START_MARKER, END_MARKER]

func _failure(message: String) -> Dictionary:
    return {"ok": false, "text": "", "diagnostics": [message]}

func _contains_flow_exit(source: String) -> bool:
    var regex := RegEx.new()
    if regex.compile("ctx[ \\t\\r\\n]*\\.[ \\t\\r\\n]*flow[ \\t\\r\\n]*:[ \\t\\r\\n]*exit[ \\t\\r\\n]*\\(") != OK:
        return false
    return regex.search(_lua_code_only(source)) != null

## 用空格遮蔽 Lua 字符串和注释，避免示例文本被误判为真实 flow:exit 调用。
func _lua_code_only(source: String) -> String:
    var result := ""
    var index := 0
    while index < source.length():
        if source.substr(index, 2) == "--":
            var comment_level := _long_bracket_level(source, index + 2)
            if comment_level >= 0:
                var comment_end := _find_long_bracket_end(source, index + 2, comment_level)
                var stop := source.length() if comment_end < 0 else comment_end
                result += " ".repeat(stop - index)
                index = stop
            else:
                while index < source.length() and source[index] != "\n":
                    result += " "
                    index += 1
            continue

        var quote := source[index]
        if quote == "\"" or quote == "'":
            result += " "
            index += 1
            while index < source.length():
                if source[index] == "\\":
                    result += " "
                    index += 1
                    if index < source.length():
                        result += " "
                        index += 1
                    continue
                var current := source[index]
                result += " "
                index += 1
                if current == quote:
                    break
            continue

        var string_level := _long_bracket_level(source, index)
        if string_level >= 0:
            var string_end := _find_long_bracket_end(source, index, string_level)
            var stop := source.length() if string_end < 0 else string_end
            result += " ".repeat(stop - index)
            index = stop
            continue

        result += source[index]
        index += 1
    return result

func _long_bracket_level(source: String, offset: int) -> int:
    if offset >= source.length() or source[offset] != "[":
        return -1
    var index := offset + 1
    while index < source.length() and source[index] == "=":
        index += 1
    if index < source.length() and source[index] == "[":
        return index - offset - 1
    return -1

func _find_long_bracket_end(source: String, offset: int, level: int) -> int:
    var closing := "]%s]" % "=".repeat(level)
    var content_start := offset + level + 2
    var found := source.find(closing, content_start)
    return -1 if found < 0 else found + closing.length()
