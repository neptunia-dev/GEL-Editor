extends SceneTree

const SHELL_SCENE := preload("res://workspace/editor_shell.tscn")
const ENTRY_SCRIPT := preload("res://workspace/explorer/explorer_entry.gd")
const MODEL_SCRIPT := preload("res://workspace/explorer/explorer_model.gd")

var _checks: int = 0
var _failures: int = 0
var _shell: Control
var _panel
var _tree

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _shell = SHELL_SCENE.instantiate()
    get_root().add_child(_shell)
    await process_frame
    await process_frame

    _panel = _shell.get_node("EditorRoot/DockHSplitMain/DockVSplitLeft/LeftLower/Explorer")
    _tree = _panel.get_node("ExplorerTree")

    _test_static_scene_structure()
    _test_placeholder_tree()
    _test_filter_and_selection()
    await _test_model_replacement()

    _shell.queue_free()
    if _failures == 0:
        print("PASS: %d explorer display checks" % _checks)
        quit(0)
    else:
        push_error("FAIL: %d of %d explorer display checks failed" % [_failures, _checks])
        quit(1)

func _test_static_scene_structure() -> void:
    _check(_panel != null, "static Explorer panel exists in EditorShell")
    _check(_tree != null, "static ExplorerTree exists in Explorer panel")
    _check(_panel.has_method("set_model"), "panel exposes replaceable model interface")
    _check(_tree.has_method("set_filter_query"), "tree exposes filter interface")
    _check(_tree.has_method("get_selected_entry_id"), "tree exposes stable selection interface")

func _test_placeholder_tree() -> void:
    var model = _panel.get_model()
    _check(model != null, "placeholder adapter provides a model")
    _check(model.get_root_id() == "project", "placeholder model has stable project root")
    var root = _tree.get_root()
    _check(root != null and root.get_text(0) == "Project", "Tree renders project root")

    var scenes = _child_named(root, "Scenes")
    _check(scenes != null, "Tree renders Scenes group")
    var prologue = _child_named(scenes, "prologue")
    _check(prologue != null, "Tree renders virtual scene folder")
    _check(_child_named(prologue, "main.lua") != null, "Tree renders scene main.lua entry")

func _test_filter_and_selection() -> void:
    _tree.set_filter_query("scenes/ending")
    var filtered_root = _tree.get_root()
    var filtered_scenes = _child_named(filtered_root, "Scenes")
    _check(filtered_scenes != null, "path filter keeps ancestor containers")
    _check(_child_named(filtered_scenes, "ending") != null, "path filter finds matching demonstration entry parent")
    _check(_child_named(filtered_scenes, "prologue") == null, "path filter hides unrelated demonstration entries")

    _tree.set_filter_query("")
    _check(_tree.select_entry("scene-script:prologue"), "Tree can select stable document entry")
    _check(_tree.get_selected_entry_id() == "scene-script:prologue", "Tree exposes selected stable entry ID")
    _panel.get_node("ExplorerToolbar/Refresh").emit_signal("pressed")
    _check(_tree.get_selected_entry_id() == "scene-script:prologue", "refresh preserves existing selection")

func _test_model_replacement() -> void:
    var old_model = _panel.get_model()
    var replacement = MODEL_SCRIPT.new()
    _check(replacement.set_entries([
        ENTRY_SCRIPT.root("replacement", "Replacement"),
        ENTRY_SCRIPT.document("replacement-doc", "Readme", "replacement", ["replacement document"]),
    ], "replacement"), "replacement model validates")
    _panel.set_model(replacement)
    await process_frame

    var root = _tree.get_root()
    _check(root != null and root.get_text(0) == "Replacement", "Tree rerenders when panel model changes")
    _check(_child_named(root, "Readme") != null, "replacement model supplies new entries")

    old_model.set_entries([
        ENTRY_SCRIPT.root("old", "Old Model"),
    ], "old")
    await process_frame
    root = _tree.get_root()
    _check(root != null and root.get_text(0) == "Replacement", "old model changes do not affect replacement tree")

func _child_named(item, title: String):
    if item == null:
        return null
    var child = item.get_first_child()
    while child != null:
        if child.get_text(0) == title:
            return child
        child = child.get_next()
    return null

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if condition:
        return
    _failures += 1
    push_error("CHECK FAILED: %s" % message)
