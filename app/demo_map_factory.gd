extends RefCounted
class_name DemoMapFactory

## Manual acceptance fixture: explicit exit + nested if/switch/numeric + shared targets.
static func create() -> SceneMap:
    var numeric := NumericCompareWrapper.new(
        "wrapper-score", NumericOperand.variable("score.current"), NumericOperand.constant(10),
        "score-less", "score-equal", "score-greater",
    )
    var switch := SwitchCaseWrapper.new(
        "wrapper-mood", "mood.current", ["mood-happy"], "mood-default",
    )
    var root := IfWrapper.new("wrapper-met", "flags.met_alice", "met-true", "met-false")
    var tree := ConditionTree.new("wrapper-met", [root, switch, numeric], [
        ConditionBranch.new("met-true", "Alice was met", "wrapper-mood"),
        ConditionBranch.new("met-false", "Not met"),
        ConditionBranch.new("mood-happy", "Happy", "wrapper-score", true, "happy"),
        ConditionBranch.new("mood-default", "Other mood"),
        ConditionBranch.new("score-less", "Below ten"),
        ConditionBranch.new("score-equal", "Exactly ten"),
        ConditionBranch.new("score-greater", "Above ten"),
    ])

    var result := SceneMap.new()
    result.add_node(SceneNode.new(
        "node-start", "prologue", "Prologue", "",
        [], [ExitPort.new("exit-continue", "continue")], Vector2(100, 150), tree,
    ))
    result.add_node(SceneNode.new("node-hub", "chapter-hub", "Chapter Hub", "", [], [], Vector2(600, 80)))
    result.add_node(SceneNode.new("node-low", "ending-low", "Low Score", "", [], [], Vector2(600, 260)))
    result.add_node(SceneNode.new("node-equal", "ending-equal", "Equal Score", "", [], [], Vector2(600, 430)))
    result.add_node(SceneNode.new("node-high", "ending-high", "High Score", "", [], [], Vector2(950, 250)))
    result.add_node(SceneNode.new("node-other", "ending-other", "Other Mood", "", [], [], Vector2(950, 430)))
    result.set_entry_node("node-start")
    result.add_route(RouteEdge.new("edge-continue", "node-start", "exit-continue", "node-hub"))
    result.add_route(RouteEdge.from_condition_branch("edge-not-met", "node-start", "wrapper-met", "met-false", "node-hub"))
    result.add_route(RouteEdge.from_condition_branch("edge-other", "node-start", "wrapper-mood", "mood-default", "node-other"))
    result.add_route(RouteEdge.from_condition_branch("edge-low", "node-start", "wrapper-score", "score-less", "node-low"))
    result.add_route(RouteEdge.from_condition_branch("edge-equal", "node-start", "wrapper-score", "score-equal", "node-equal"))
    result.add_route(RouteEdge.from_condition_branch("edge-high", "node-start", "wrapper-score", "score-greater", "node-high"))
    return result
