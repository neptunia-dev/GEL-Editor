extends SceneTree

# 显式预加载领域脚本，避免全新 .godot 缓存下依赖 class_name 扫描顺序。
const CastMember = preload("res://node_map/cast_member.gd")
const ExitPort = preload("res://node_map/exit_port.gd")
const ConditionBranch = preload("res://node_map/condition/condition_branch.gd")
const ConditionWrapper = preload("res://node_map/condition/condition_wrapper.gd")
const IfWrapper = preload("res://node_map/condition/if_wrapper.gd")
const NumericOperand = preload("res://node_map/condition/numeric_operand.gd")
const NumericCompareWrapper = preload("res://node_map/condition/numeric_compare_wrapper.gd")
const SwitchCaseWrapper = preload("res://node_map/condition/switch_case_wrapper.gd")
const ConditionTree = preload("res://node_map/condition/condition_tree.gd")
const RouteEdge = preload("res://node_map/map/route_edge.gd")
const SceneNode = preload("res://node_map/scene_node.gd")
const SceneMap = preload("res://node_map/map/scene_map.gd")
const LuaConditionCompiler = preload("res://node_map/lua/lua_condition_compiler.gd")
const LuaConditionBlockWriter = preload("res://node_map/lua/lua_condition_block_writer.gd")

var _failures: int = 0
var _checks: int = 0

func _init() -> void:
    _test_if_compile()
    _test_switch_compile_and_duplicates()
    _test_numeric_compile()
    _test_variable_diagnostics()
    _test_tree_shape_diagnostics()
    _test_runtime_routes_and_stable_ids()
    _test_atomic_branch_deletion()
    _test_atomic_wrapper_deletion()
    _test_unconnected_leaf_blocks_export()
    _test_lua_block_writer()
    _test_legacy_scene_behavior()
    if _failures == 0:
        print("PASS: %d checks" % _checks)
        quit(0)
    else:
        push_error("FAIL: %d of %d checks failed" % [_failures, _checks])
        quit(1)

func _test_if_compile() -> void:
    var tree = _make_if_tree("flags.met_alice")
    var result := LuaConditionCompiler.new().compile(tree, {
        "flags.met_alice": {"type": "boolean"},
    })
    _check(result["ok"], "if tree compiles")
    _check(str(result["code"]).contains('if ctx.state:get("flags.met_alice") then'), "if reads state")
    _check(str(result["code"]).contains('__gel.condition.if-root.true'), "if true hidden exit")
    _check(str(result["code"]).contains('__gel.condition.if-root.false'), "if false hidden exit")

func _test_switch_compile_and_duplicates() -> void:
    var branches := [
        ConditionBranch.new("case-a", "A", "", true, "a"),
        ConditionBranch.new("case-b", "B", "", true, "b\n\"quoted\""),
        ConditionBranch.new("default", "Other"),
    ]
    var wrapper := SwitchCaseWrapper.new("switch-root", "route.choice", ["case-a", "case-b"], "default")
    var tree := ConditionTree.new("switch-root", [wrapper], branches)
    var result := LuaConditionCompiler.new().compile(tree, {
        "route.choice": {"schema": {"type": "string"}},
    })
    _check(result["ok"], "switch compiles")
    _check(str(result["code"]).contains("elseif"), "switch uses elseif")
    _check(str(result["code"]).contains('"b\\n\\\"quoted\\\""'), "Lua strings are escaped")
    _check(str(result["code"]).contains("else"), "switch emits default")

    var duplicate_tree := ConditionTree.new(
        "switch-root",
        [SwitchCaseWrapper.new("switch-root", "route.choice", ["one", "two"], "default")],
        [
            ConditionBranch.new("one", "One", "", true, 1),
            ConditionBranch.new("two", "Two", "", true, 1.0),
            ConditionBranch.new("default", "Default"),
        ],
    )
    _check(_contains(duplicate_tree.validate_self(), "duplicate case value"), "duplicate switch values are rejected")

func _test_numeric_compile() -> void:
    var wrapper := NumericCompareWrapper.new(
        "compare-root",
        NumericOperand.variable("score.current"),
        NumericOperand.constant(10),
        "less", "equal", "greater",
    )
    var tree := ConditionTree.new("compare-root", [wrapper], [
        ConditionBranch.new("less", "Less"),
        ConditionBranch.new("equal", "Equal"),
        ConditionBranch.new("greater", "Greater"),
    ])
    var result := LuaConditionCompiler.new().compile(tree, {"score.current": {"type": "number"}})
    _check(result["ok"], "numeric compare compiles")
    _check(str(result["code"]).contains(" < "), "numeric less branch")
    _check(str(result["code"]).contains(" > "), "numeric greater branch")
    _check(str(result["code"]).contains('__gel.condition.compare-root.equal'), "numeric equal branch")

func _test_variable_diagnostics() -> void:
    var compiler := LuaConditionCompiler.new()
    _check(_contains(_make_if_tree("Invalid Key").validate_self(), "variable_key must match"), "invalid variable key diagnosed")
    var missing := compiler.compile(_make_if_tree("flags.missing"), {})
    _check(not missing["ok"] and _contains(missing["diagnostics"], "not declared"), "missing variable diagnosed")
    var mismatch := compiler.compile(_make_if_tree("flags.number"), {"flags.number": {"type": "number"}})
    _check(not mismatch["ok"] and _contains(mismatch["diagnostics"], "boolean schema"), "if type mismatch diagnosed")

    var invalid_numeric := ConditionTree.new(
        "bad-number",
        [NumericCompareWrapper.new(
            "bad-number", NumericOperand.constant(INF), NumericOperand.constant(1),
            "less", "equal", "greater",
        )],
        [ConditionBranch.new("less"), ConditionBranch.new("equal"), ConditionBranch.new("greater")],
    )
    _check(_contains(invalid_numeric.validate_self(), "finite number"), "non-finite numeric constant diagnosed")

func _test_tree_shape_diagnostics() -> void:
    var duplicate_ids := ConditionTree.new(
        "same",
        [IfWrapper.new("same", "flag", "yes", "no"), IfWrapper.new("same", "flag", "yes", "no")],
        [ConditionBranch.new("yes"), ConditionBranch.new("yes"), ConditionBranch.new("no")],
    )
    _check(_contains(duplicate_ids.validate_self(), "duplicate wrapper_id"), "duplicate wrapper ID diagnosed")
    _check(_contains(duplicate_ids.validate_self(), "duplicate branch_id"), "duplicate branch ID diagnosed")

    var missing := ConditionTree.new(
        "root", [IfWrapper.new("root", "flag", "yes", "missing")],
        [ConditionBranch.new("yes")],
    )
    _check(_contains(missing.validate_self(), "missing branch"), "missing fixed branch diagnosed")

    var cycle := ConditionTree.new(
        "one",
        [
            IfWrapper.new("one", "flag.one", "one-yes", "one-no"),
            IfWrapper.new("two", "flag.two", "two-yes", "two-no"),
        ],
        [
            ConditionBranch.new("one-yes", "", "two"), ConditionBranch.new("one-no"),
            ConditionBranch.new("two-yes", "", "one"), ConditionBranch.new("two-no"),
        ],
    )
    _check(_contains(cycle.validate_self(), "cycle"), "wrapper cycle diagnosed")

    var shared := ConditionTree.new(
        "one",
        [
            IfWrapper.new("one", "flag.one", "one-yes", "one-no"),
            IfWrapper.new("two", "flag.two", "two-yes", "two-no"),
        ],
        [
            ConditionBranch.new("one-yes", "", "two"), ConditionBranch.new("one-no", "", "two"),
            ConditionBranch.new("two-yes"), ConditionBranch.new("two-no"),
        ],
    )
    _check(_contains(shared.validate_self(), "shared by multiple branches"), "shared subtree diagnosed")

func _test_runtime_routes_and_stable_ids() -> void:
    var tree := ConditionTree.new(
        "switch-root",
        [SwitchCaseWrapper.new("switch-root", "route.choice", ["case-a"], "default")],
        [ConditionBranch.new("case-a", "Old", "", true, "a"), ConditionBranch.new("default")],
    )
    var source := SceneNode.new("source", "source", "", "", [], [], Vector2.ZERO, tree)
    var target_a := SceneNode.new("target-a", "target-a")
    var target_default := SceneNode.new("target-default", "target-default")
    var map := SceneMap.new()
    _check(map.add_node(source) and map.add_node(target_a) and map.add_node(target_default), "map accepts condition nodes")
    _check(map.set_entry_node("source"), "condition map entry set")
    _check(map.add_route(RouteEdge.from_condition_branch("edge-a", "source", "switch-root", "case-a", "target-a")), "case route added")
    _check(map.add_route(RouteEdge.from_condition_branch("edge-default", "source", "switch-root", "default", "target-default")), "default route added")

    var updated := map.get_node("source")
    var updated_tree := updated.get_condition_tree()
    _check(updated_tree.update_switch_case("case-a", "renamed", "New label"), "switch case value updated")
    _check(updated.set_condition_tree(updated_tree) and map.update_node(updated), "node update keeps stable branch endpoint")
    _check(map.get_route("edge-a") != null, "route survives switch case edit")

    var runtime := map.to_runtime_definition({"route.choice": {"type": "string"}})
    _check(not runtime.is_empty(), "condition map exports")
    var source_scene: Dictionary = runtime["scenes"][runtime["scenes"].find_custom(func(scene): return scene["id"] == "source")]
    _check((source_scene["exits"] as Array).has("__gel.condition.switch-root.case-a"), "runtime scene contains generated exit")
    _check(runtime["routes"]["source"]["__gel.condition.switch-root.case-a"] == "target-a", "generated route resolves target scene")
    var editor_edge := map.get_route("edge-a").to_editor_dict()
    _check(editor_edge["sourceKind"] == "condition_branch" and not editor_edge.has("sourcePortId"), "condition endpoint editor format is exclusive")
    var dangling_update := map.get_node("source")
    dangling_update.clear_condition_tree()
    _check(not map.update_node(dangling_update), "update_node rejects dangling condition edges")

    var mixed_endpoint := RouteEdge.new(
        "mixed", "source", "legacy-port", "target-a",
        RouteEdge.SOURCE_CONDITION_BRANCH, "switch-root", "case-a",
    )
    _check(_contains(mixed_endpoint.validate_self(), "must not use source_port_id"), "route endpoint fields cannot be mixed")

    var conflicting_node := SceneNode.new(
        "conflict", "conflict", "", "",
        [], [ExitPort.new("explicit", "__gel.condition.switch-root.case-a")], Vector2.ZERO, tree,
    )
    _check(_contains(conflicting_node.validate_self(), "conflicts with a generated"), "explicit and generated exit collision diagnosed")

func _test_atomic_branch_deletion() -> void:
    var tree := ConditionTree.new(
        "switch-root",
        [SwitchCaseWrapper.new("switch-root", "choice", ["case-a"], "default")],
        [ConditionBranch.new("case-a", "A", "", true, "a"), ConditionBranch.new("default")],
    )
    var map := SceneMap.new()
    map.add_node(SceneNode.new("source", "source", "", "", [], [], Vector2.ZERO, tree))
    map.add_node(SceneNode.new("a", "a"))
    map.add_node(SceneNode.new("fallback", "fallback"))
    map.set_entry_node("source")
    map.add_route(RouteEdge.from_condition_branch("edge-a", "source", "switch-root", "case-a", "a"))
    map.add_route(RouteEdge.from_condition_branch("edge-default", "source", "switch-root", "default", "fallback"))
    _check(map.remove_condition_branch("source", "case-a"), "switch case removed atomically")
    _check(map.get_route("edge-a") == null and map.get_route("edge-default") != null, "deleted branch edge cleaned")

func _test_atomic_wrapper_deletion() -> void:
    var tree := ConditionTree.new(
        "root-if",
        [
            IfWrapper.new("root-if", "flag", "root-true", "root-false"),
            SwitchCaseWrapper.new("child-switch", "choice", ["child-a"], "child-default"),
        ],
        [
            ConditionBranch.new("root-true", "", "child-switch"), ConditionBranch.new("root-false"),
            ConditionBranch.new("child-a", "", "", true, "a"), ConditionBranch.new("child-default"),
        ],
    )
    var map := SceneMap.new()
    map.add_node(SceneNode.new("source", "source", "", "", [], [], Vector2.ZERO, tree))
    map.add_node(SceneNode.new("a", "a"))
    map.add_node(SceneNode.new("fallback", "fallback"))
    map.add_node(SceneNode.new("false", "false"))
    map.set_entry_node("source")
    map.add_route(RouteEdge.from_condition_branch("child-a-edge", "source", "child-switch", "child-a", "a"))
    map.add_route(RouteEdge.from_condition_branch("child-default-edge", "source", "child-switch", "child-default", "fallback"))
    map.add_route(RouteEdge.from_condition_branch("false-edge", "source", "root-if", "root-false", "false"))
    _check(map.remove_condition_wrapper("source", "child-switch"), "nested wrapper removed atomically")
    _check(map.get_route("child-a-edge") == null and map.get_route("child-default-edge") == null, "deleted wrapper subtree edges cleaned")
    _check(map.get_route("false-edge") != null, "unrelated condition edge preserved")

func _test_unconnected_leaf_blocks_export() -> void:
    var map := SceneMap.new()
    map.add_node(SceneNode.new("source", "source", "", "", [], [], Vector2.ZERO, _make_if_tree("flag")))
    map.set_entry_node("source")
    _check(map.to_runtime_definition({"flag": {"type": "boolean"}}).is_empty(), "unconnected condition leaf blocks export")
    _check(map.last_error.contains("没有连接目标"), "unconnected leaf diagnostic is retained")

func _test_lua_block_writer() -> void:
    var writer := LuaConditionBlockWriter.new()
    var source := "return function(ctx)\n  ctx.dialogue:narrate(\"handwritten\")\n  -- GEL:generated:conditions:start\n  old_generated()\n  -- GEL:generated:conditions:end\nend\n"
    var first := writer.replace_block(source, "if true then\n  return ctx.flow:exit(\"next\")\nend")
    _check(first["ok"], "controlled block replaced")
    _check(str(first["text"]).contains("handwritten") and not str(first["text"]).contains("old_generated"), "writer preserves only outside block")
    var second := writer.replace_block(first["text"], "if true then\n  return ctx.flow:exit(\"next\")\nend")
    _check(second["text"] == first["text"], "controlled block update is idempotent")
    var empty := writer.replace_block(first["text"], "")
    _check(empty["ok"] and str(empty["text"]).contains(LuaConditionBlockWriter.START_MARKER), "empty tree keeps markers")
    _check(not writer.replace_block("return function(ctx) end", "x")["ok"], "missing markers diagnosed")
    _check(not writer.replace_block("-- GEL:generated:conditions:end\n-- GEL:generated:conditions:start", "x")["ok"], "wrong marker order diagnosed")
    _check(writer.standard_template().contains(LuaConditionBlockWriter.START_MARKER), "new scene template contains markers")
    var conflicting := "return function(ctx)\n  return ctx.flow:exit(\"manual\")\n  -- GEL:generated:conditions:start\n  -- GEL:generated:conditions:end\nend\n"
    _check(not writer.replace_block(conflicting, "return ctx.flow:exit(\"generated\")")["ok"], "manual final flow exit conflict diagnosed")
    var commented := "return function(ctx)\n  -- ctx.flow:exit(\"example\")\n  local text = [[ctx.flow:exit(\"not code\")]]\n  -- GEL:generated:conditions:start\n  -- GEL:generated:conditions:end\nend\n"
    _check(writer.replace_block(commented, "return ctx.flow:exit(\"generated\")")["ok"], "flow exit examples in comments and strings are ignored")

func _test_legacy_scene_behavior() -> void:
    var source := SceneNode.new("legacy", "legacy", "", "", [], [ExitPort.new("continue-id", "continue")])
    var target := SceneNode.new("end", "ending")
    var map := SceneMap.new()
    map.add_node(source)
    map.add_node(target)
    map.set_entry_node("legacy")
    _check(map.add_route(RouteEdge.new("legacy-edge", "legacy", "continue-id", "end")), "legacy RouteEdge constructor works")
    var runtime := map.to_runtime_definition()
    _check(not runtime.is_empty() and runtime["routes"]["legacy"]["continue"] == "ending", "legacy scene export unchanged")
    _check(not map.to_editor_dict()["nodes"][0].has("conditionTree"), "conditionTree stays optional")

func _make_if_tree(variable_key: String):
    return ConditionTree.new(
        "if-root",
        [IfWrapper.new("if-root", variable_key, "true", "false")],
        [ConditionBranch.new("true", "True"), ConditionBranch.new("false", "False")],
    )

func _contains(values: Array, needle: String) -> bool:
    for value in values:
        if str(value).contains(needle):
            return true
    return false

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if condition:
        return
    _failures += 1
    push_error("CHECK FAILED: %s" % message)
