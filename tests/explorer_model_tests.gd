extends SceneTree

const ENTRY_SCRIPT := preload("res://workspace/explorer/explorer_entry.gd")
const MODEL_SCRIPT := preload("res://workspace/explorer/explorer_model.gd")
const DATA_SCRIPT := preload("res://workspace/explorer/placeholder_explorer_data.gd")

var _checks: int = 0
var _failures: int = 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_placeholder_tree()
    _test_explicit_search_terms()
    _test_generic_container_entries()
    _test_atomic_replacement()
    _test_structure_validation()

    if _failures == 0:
        print("PASS: %d explorer model checks" % _checks)
        quit(0)
    else:
        push_error("FAIL: %d of %d explorer model checks failed" % [_failures, _checks])
        quit(1)

func _test_placeholder_tree() -> void:
    var model = DATA_SCRIPT.create_model()
    _check(model.get_root_id() == "project", "placeholder model has a project root")
    _check(model.get_entry_count() == 8, "placeholder model contains container and document entries")
    var project_children: Array = model.get_children("project")
    _check(project_children.size() == 1 and project_children[0].entry_id == "scenes", "project contains Scenes group")
    var scene_children: Array = model.get_children("scenes")
    _check(_entry_ids(scene_children) == ["scene:chapter-one", "scene:ending", "scene:prologue"], "container entries are sorted deterministically")
    _check(_entry_ids(model.get_children("scene:prologue")) == ["scene-script:prologue"], "container contains document entry")

    var copy = model.get_entry("scene:prologue")
    copy.metadata["scene_id"] = "changed"
    _check(model.get_entry("scene:prologue").metadata["scene_id"] == "prologue", "entry queries return metadata copies")

func _test_explicit_search_terms() -> void:
    var model = DATA_SCRIPT.create_model()
    _check(_entry_ids(model.find("chapter")) == ["scene:chapter-one", "scene-script:chapter-one"], "search uses explicit title and search terms")
    _check(_entry_ids(model.find("main.lua")) == ["scene-script:chapter-one", "scene-script:ending", "scene-script:prologue"], "search finds document titles")
    _check(_entry_ids(model.find("scenes/ending")) == ["scene-script:ending"], "search finds explicit logical path term")
    _check(model.find("node-ending").is_empty(), "opaque metadata is not searched")
    _check(model.matches_entry("scene-script:ending", "ending script"), "matches_entry exposes explicit search contract")
    _check(not model.matches_entry("missing", "ending"), "missing entries do not match")

func _test_generic_container_entries() -> void:
    var model = MODEL_SCRIPT.new()
    var entries: Array = [
        ENTRY_SCRIPT.root("root", "Workspace"),
        ENTRY_SCRIPT.container("group", "Characters", "root", ["cast"]),
        ENTRY_SCRIPT.document("actor", "Alice", "group", ["heroine"], {"domain_id": "character-alice"}, "actor"),
    ]
    _check(model.set_entries(entries, "root"), "generic non-file entry kinds can form a tree")
    _check(_entry_ids(model.get_children("root")) == ["group"], "generic container remains visible")
    _check(_entry_ids(model.find("heroine")) == ["actor"], "explicit search terms work for non-scene data")

func _test_atomic_replacement() -> void:
    var model = DATA_SCRIPT.create_model()
    var before_revision: int = model.get_revision()
    var before_ids := _entry_ids(model.get_children("scenes"))
    var invalid_entries: Array = [
        ENTRY_SCRIPT.root("new-root", "New Project"),
        ENTRY_SCRIPT.document("new-child", "Child", "missing-parent"),
    ]
    _check(not model.set_entries(invalid_entries, "new-root"), "invalid replacement is rejected")
    _check(model.get_revision() == before_revision, "invalid replacement does not increment revision")
    _check(_entry_ids(model.get_children("scenes")) == before_ids, "invalid replacement preserves previous tree")

    var replacement: Array = [
        ENTRY_SCRIPT.root("root", "Project"),
        ENTRY_SCRIPT.container("folders", "Scenes", "root"),
        ENTRY_SCRIPT.container("entry:new", "new", "folders"),
    ]
    _check(model.set_entries(replacement, "root"), "valid replacement succeeds")
    _check(model.get_revision() == before_revision + 1, "valid replacement increments revision once")
    _check(model.get_entry("entry:new") != null, "replacement becomes visible atomically")

func _test_structure_validation() -> void:
    var model = MODEL_SCRIPT.new()
    _check(not model.set_entries([], ""), "empty tree is rejected")
    _check(not model.set_entries(["not an entry"], ""), "primitive inputs fail without a runtime crash")
    _check(not model.set_entries([
        ENTRY_SCRIPT.root("root", "Project"),
        ENTRY_SCRIPT.container("root", "Duplicate", "root"),
    ], "root"), "duplicate entry IDs are rejected")
    _check(not model.set_entries([
        ENTRY_SCRIPT.root("root", "Project"),
        ENTRY_SCRIPT.document("child", "Child", "root"),
        ENTRY_SCRIPT.document("grandchild", "Grandchild", "child"),
    ], "root"), "non-container entries cannot contain children")
    _check(not model.set_entries([
        ENTRY_SCRIPT.root("root", "Project"),
        ENTRY_SCRIPT.container("a", "A", "b"),
        ENTRY_SCRIPT.container("b", "B", "a"),
    ], "root"), "unreachable cycles are rejected")
    _check(not model.set_entries([
        ENTRY_SCRIPT.container("root", "Project", "parent"),
    ], "root"), "root entry cannot have a parent")

func _entry_ids(entries: Array) -> Array:
    var result: Array = []
    for entry in entries:
        result.append(entry.entry_id)
    return result

func _check(condition: bool, message: String) -> void:
    _checks += 1
    if condition:
        return
    _failures += 1
    push_error("CHECK FAILED: %s" % message)
