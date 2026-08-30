extends SceneTree

## Integration helper: emit a real compiler + block-writer result for the engine Lua parser.
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
