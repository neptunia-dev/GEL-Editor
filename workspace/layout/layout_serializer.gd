extends RefCounted
class_name EditorLayoutSerializer

## 编辑器布局状态的序列化边界。
##
## 序列化器故意不依赖 Godot 控件，也不依赖 SceneMap 领域模型。它以 Dictionary
## 作为中间格式，因此未来既可以接入 ConfigFile，也可以接入 JSON 文件或宿主应用
## 的用户偏好存储，而无需改变布局状态对象本身。

const CURRENT_SCHEMA_VERSION := 1
const STATE_SCRIPT := preload("res://workspace/layout/layout_state.gd")

func serialize(state) -> Dictionary:
    if state == null or not state.has_method("to_dict"):
        return {}
    return state.to_dict()

func deserialize(source: Variant, definition) -> Dictionary:
    if definition == null:
        return {"ok": false, "state": null, "errors": ["layout definition must not be null"]}
    if not source is Dictionary:
        return {"ok": false, "state": null, "errors": ["layout source must be a dictionary"]}
    var state = STATE_SCRIPT.from_dict(source, definition)
    var migration: Dictionary = _migrate_state(state, source)
    if not bool(migration["ok"]):
        return {"ok": false, "state": null, "errors": migration["errors"]}
    state = migration["state"]
    return {"ok": true, "state": state, "errors": []}

func validate(state, definition, dock_ids: Array = [], workspace_ids: Array = []) -> Array:
    if state == null or not state.has_method("validate_self"):
        return ["layout state must not be null"]
    if definition == null:
        return ["layout definition must not be null"]
    return state.validate_self(definition, dock_ids, workspace_ids)

func _migrate_state(state, source: Dictionary) -> Dictionary:
    var version := int(source.get("schemaVersion", 1))
    if version <= 0:
        return {"ok": false, "errors": ["unsupported layout schema version '%s'" % version]}
    if version > CURRENT_SCHEMA_VERSION:
        return {"ok": false, "errors": ["layout schema version '%s' is newer than supported version '%s'" % [version, CURRENT_SCHEMA_VERSION]]}
    # 当前版本 1 是第一种持久化格式。即使暂时没有旧版本迁移逻辑，也保留明确的
    # 迁移入口；将来字段发生不兼容变化时，可以集中在这里处理，而不用把兼容代码
    # 分散到 LayoutState 和 LayoutManager 的各个方法中。
    state.schema_version = CURRENT_SCHEMA_VERSION
    return {"ok": true, "state": state}

func encode_json(state) -> String:
    return "{}" if state == null or not state.has_method("to_dict") else JSON.stringify(state.to_dict(), "  ")

func decode_json(text: String, definition) -> Dictionary:
    var json := JSON.new()
    if json.parse(text) != OK:
        return {"ok": false, "state": null, "errors": ["layout JSON is invalid"]}
    return deserialize(json.data, definition)
