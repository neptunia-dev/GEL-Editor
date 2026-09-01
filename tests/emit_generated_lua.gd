extends SceneTree

const ConditionBranch = preload("res://node_map/condition/condition_branch.gd")
const IfWrapper = preload("res://node_map/condition/if_wrapper.gd")
const SwitchCaseWrapper = preload("res://node_map/condition/switch_case_wrapper.gd")
const ConditionTree = preload("res://node_map/condition/condition_tree.gd")
const LuaConditionCompiler = preload("res://node_map/lua/lua_condition_compiler.gd")
const LuaConditionBlockWriter = preload("res://node_map/lua/lua_condition_block_writer.gd")

## 集成验证辅助脚本：调用真实的条件编译器和区块写入器，生成一份 Lua 文件，
## 供引擎侧的 Lua 解析器继续执行预编译检查。该脚本只负责验证生成链路，不承担
## 编辑器工程保存或运行时文件管理职责。
func _init() -> void:
    var arguments := OS.get_cmdline_user_args()
    if arguments.is_empty():
        push_error("output path argument is required")
        quit(1)
        return

    var tree := ConditionTree.new(
        "root-if",
        [
            IfWrapper.new("root-if", "flags.met_alice", "met", "not-met"),
            SwitchCaseWrapper.new("mood-switch", "mood", ["happy"], "other"),
        ],
        [
            ConditionBranch.new("met", "", "mood-switch"),
            ConditionBranch.new("not-met"),
            ConditionBranch.new("happy", "", "", true, "开心\n\"Alice\""),
            ConditionBranch.new("other"),
        ],
    )
    var compiled := LuaConditionCompiler.new().compile(tree, {
        "flags.met_alice": {"type": "boolean"},
        "mood": {"type": "string"},
    })
    if not compiled["ok"]:
        push_error("condition compilation failed: %s" % compiled["diagnostics"])
        quit(1)
        return

    var writer := LuaConditionBlockWriter.new()
    var written := writer.replace_block(writer.standard_template(), str(compiled["code"]))
    if not written["ok"]:
        push_error("condition block writing failed: %s" % written["diagnostics"])
        quit(1)
        return

    var file := FileAccess.open(str(arguments[0]), FileAccess.WRITE)
    if file == null:
        push_error("cannot open output file: %s" % FileAccess.get_open_error())
        quit(1)
        return
    file.store_string(str(written["text"]))
    file.close()
    print("WROTE: %s" % arguments[0])
    quit(0)
