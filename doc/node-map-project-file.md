# Node Map 工程文件

状态：已实现，当前格式版本为 `1`。

`.gelproj` 是编辑器创作文件。它保存完整的 Node Map 快照、项目级 Runtime
Package 配置和可恢复的画布状态；它不是 Runtime Package，也不能交给 Node
引擎直接加载或运行。

## 三层边界

```text
.gelproj                         编辑器工程文件
  -> nodeMap                     gel.node-map 文档快照
  -> NodeMapCompiler
Runtime Package directory        manifest.json + scenes/<scene-id>/main.lua
  -> PackageLoader / StoryRunner
Engine session                   GameState、角色和表现层状态
```

编辑器工程可以保存尚未能导出的草稿。Runtime Package 只由编译器生成，绝不把
节点位置、折叠状态、选中状态或撤销历史带入 `manifest.json`。

## 文件格式

磁盘文件使用规范 camelCase 字段：

```json
{
  "format": "gel.editor-project",
  "formatVersion": 1,
  "projectId": "my_story",
  "metadata": {
    "title": "My Story",
    "author": "",
    "language": ""
  },
  "package": {
    "packageId": "my.story",
    "packageVersion": "0.1.0",
    "saveSchemaVersion": 1,
    "engineMinVersion": "0.1.0"
  },
  "entryScene": "",
  "nodeMap": {
    "format": "gel.node-map",
    "formatVersion": 1,
    "rootGraphId": "graph-...",
    "graphs": []
  },
  "editorState": {
    "activeGraphId": "graph-...",
    "graphStates": {}
  }
}
```

`editorState` 是可选字段。目前保存活动图及每张图的缩放、滚动位置；选中状态、
悬停状态、控件中尚未提交的文本和撤销/重做历史不写入文件。

内部 API 为与现有编译器调用兼容，接受 snake_case 和 camelCase 配置别名。若同一
字段的多个别名给出不同值，保存和加载会以 `conflicting_project_field` 失败；写出时
始终回到上述 canonical camelCase 形式。

## 兼容性和校验

- 工程容器版本与嵌入 Node Map 快照版本独立计数。
- 当前只支持 `gel.editor-project` v1 包含 `gel.node-map` v1；未知版本不会猜测
  迁移，也不会覆盖当前文档。
- `NodeMapProjectCodec` 校验容器、项目 ID、包 ID、语义版本、存档 schema、metadata、
  JSON 值、字段白名单和别名冲突。
- `NodeMapDocument.restore_snapshot()` 仍是节点、图、连接、注册表和结构校验的唯一
  深度恢复边界。
- 加载先在 detached `NodeMapDocument` 中恢复；仅成功后，编辑器才将快照原地恢复到
  当前 document。因此错误文件不会替换视图绑定的文档实例，也不会污染当前创作内容。

## 磁盘边界

`NodeMapProjectFile` 负责文件系统操作，`NodeMapProjectCodec` 不访问磁盘。

- 保存先写唯一 temporary 文件，必要时将旧文件移到 backup，再发布新的最终文件。
- 发布失败会尝试恢复原文件；若恢复也失败，会返回 `project_recovery_failed` 并保留
  backup 和 temporary 路径供人工恢复。
- 读写会拒绝目标文件或任意父目录中的 symbolic link/junction；这减少路径重定向，
  但不能消除并发文件系统修改造成的 TOCTOU 风险。
- 读写都限制为 32 MiB，避免成功保存一个随后无法安全加载的工程。
- 成功保存不清空 Undo/Redo；脏状态比较 Node Map 快照、项目配置和持久化的
  活动图/缩放/滚动状态。仅改变选中或悬停状态不会把工程标为修改。

## 编辑器工作流

`EditorShell` 的 Project 菜单提供 New、Open、Save、Save As 和 Project Settings。
Project Settings 会编辑上述项目及 Runtime Package 配置。未保存工程在 New、Open 或
Quit 前需要在 Save、Discard 和 Cancel 之间作出选择；对无路径工程，Save As 成功后才继续
原本的操作。无工程启动时仍保留示例文档，兼容演示和测试。

默认导出会把持久化的 package 配置转换为 `NodeMapCompiler` 选项。实际 entry scene
仍由 Project Start 的根图连接决定；设置中的 `entryScene` 只作为一致性约束，二者不
匹配时编译失败。
