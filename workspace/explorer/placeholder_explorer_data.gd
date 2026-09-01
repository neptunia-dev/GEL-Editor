@tool
extends RefCounted
class_name EditorPlaceholderExplorerData

const MODEL_SCRIPT := preload("res://workspace/explorer/explorer_model.gd")
const ENTRY_SCRIPT := preload("res://workspace/explorer/explorer_entry.gd")

## 仅用于观察通用 Explorer 的占位数据源。
##
## 这些条目模拟未来的 Scene 投影，但当前不依赖 SceneMap，也不访问磁盘。metadata
## 仅保存未来适配器需要的稳定引用；可筛选文本必须显式放进 search_terms。

static func create_model():
    var model = MODEL_SCRIPT.new()
    var entries: Array = [
        ENTRY_SCRIPT.root("project", "Project", ["gel project"]),
        ENTRY_SCRIPT.container("scenes", "Scenes", "project", ["scene collection"]),
        ENTRY_SCRIPT.container(
            "scene:prologue", "prologue", "scenes",
            ["prologue"],
            {
                "source_kind": "scene",
                "node_id": "node-prologue",
                "scene_id": "prologue",
            },
        ),
        ENTRY_SCRIPT.document(
            "scene-script:prologue", "main.lua", "scene:prologue",
            ["scenes/prologue/main.lua", "prologue script"],
            {
                "source_kind": "scene_script",
                "node_id": "node-prologue",
                "logical_path": "scenes/prologue/main.lua",
            },
        ),
        ENTRY_SCRIPT.container(
            "scene:chapter-one", "chapter-one", "scenes",
            ["chapter-one"],
            {
                "source_kind": "scene",
                "node_id": "node-chapter-one",
                "scene_id": "chapter-one",
            },
        ),
        ENTRY_SCRIPT.document(
            "scene-script:chapter-one", "main.lua", "scene:chapter-one",
            ["scenes/chapter-one/main.lua", "chapter-one script"],
            {
                "source_kind": "scene_script",
                "node_id": "node-chapter-one",
                "logical_path": "scenes/chapter-one/main.lua",
            },
        ),
        ENTRY_SCRIPT.container(
            "scene:ending", "ending", "scenes",
            ["ending"],
            {
                "source_kind": "scene",
                "node_id": "node-ending",
                "scene_id": "ending",
            },
        ),
        ENTRY_SCRIPT.document(
            "scene-script:ending", "main.lua", "scene:ending",
            ["scenes/ending/main.lua", "ending script"],
            {
                "source_kind": "scene_script",
                "node_id": "node-ending",
                "logical_path": "scenes/ending/main.lua",
            },
        ),
    ]
    model.set_entries(entries, "project")
    return model
