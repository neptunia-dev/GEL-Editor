# GEL Explorer 显示框架设计

> 状态：通用条目模型、Tree 显示层、静态 Shell 挂载和占位数据源已实现；真实业务数据源尚未决定。
>
> 本文只定义一个可复用的树形浏览显示框架。它不决定最终展示 Scene、项目资源、
> 磁盘文件还是混合内容，也不实现真实文件系统。

## 1. 目标

GEL 当前需要先验证工作区中“树形浏览区域”的视觉、展开、筛选、选择和激活行为，
但还不应提前承诺数据来源。

当前 Shell 使用下面这组**演示数据**：

```text
Project
└── Scenes
    ├── prologue
    │   └── main.lua
    ├── chapter-one
    │   └── main.lua
    └── ending
        └── main.lua
```

这只是 Explorer 的展示样例，不表示：

- `Scenes` 必定是磁盘目录；
- `prologue` 必定是真实文件夹；
- `main.lua` 已经存在于操作系统；
- 当前 Explorer 已经绑定 `SceneMap`；
- GEL 将来一定把该区域接到某一种特定数据源。

## 2. 当前结构

```text
EditorShell
└── Left Lower Dock
    └── Explorer Placeholder Panel
        ├── Toolbar
        │   ├── Heading
        │   ├── Filter
        │   └── Refresh
        └── EditorExplorerTree
```

代码层：

```text
workspace/explorer/
├── explorer_entry.gd
├── explorer_model.gd
├── explorer_tree.gd
├── explorer_panel.gd
├── placeholder_explorer_data.gd
└── placeholder_explorer_panel.gd
```

职责：

```text
EditorExplorerEntry
    一个稳定显示条目

EditorExplorerModel
    条目树、原子替换、排序和查询

EditorExplorerTree
    将模型渲染为 Godot Tree，并维护展开、筛选和选择状态

EditorExplorerPanel
    组合标题、筛选框、刷新按钮和 Tree

Placeholder Explorer Data
    仅提供当前可视化演示数据
```

## 3. `EditorExplorerEntry`

一个条目包含：

```text
entry_id
 title
parent_id
is_container
icon_hint
search_terms
metadata
```

字段边界：

- `entry_id`：稳定显示层身份；
- `title`：显示文本；
- `parent_id`：稳定父条目身份；
- `is_container`：是否允许拥有子项；
- `icon_hint`：`generic`、`container` 或 `document` 等显示提示；
- `search_terms`：数据源显式允许用于筛选的文本；
- `metadata`：对 Explorer 完全不透明的扩展数据。

`metadata` 可以保存未来数据源的稳定引用，例如：

```text
node_id
asset_id
document_id
logical_path
```

但 Explorer 不读取、搜索或修改它。这样数据源的内部结构不会反向成为显示框架的协议。

## 4. 数据源替换点

目前：

```text
EditorPlaceholderExplorerData
    ↓
EditorExplorerModel
    ↓
EditorExplorerPanel
```

未来任选其一时，只替换数据源或适配器：

```text
SceneMap Adapter
    SceneNode -> ExplorerEntry

Project Asset Adapter
    Asset registry -> ExplorerEntry

Disk Browser Adapter
    Directory snapshot -> ExplorerEntry

Mixed Project Adapter
    多种领域对象 -> ExplorerEntry
```

Explorer 本身不应出现：

```text
SceneMap
SceneNode
DirAccess
FileAccess
DirectoryFileSystem
Runtime Package
Lua VM
```

## 5. 树一致性

`EditorExplorerModel.set_entries()` 使用候选树原子替换：

```text
外部条目数组
    ↓
完整校验
    ↓
检查根条目、父子关系、容器关系、重复 ID、环和不可达条目
    ↓
排序
    ↓
一次性替换内部 entries / children
    ↓
发出 changed(revision)
```

无效数据不能污染原模型：

```text
旧树有效
    ↓
新数据无效
    ↓
旧树保持不变
revision 不递增
last_error 保留原因
```

## 6. 搜索和显示状态

Explorer 搜索规则：

```text
title
+ search_terms
```

不会搜索：

```text
metadata
```

筛选命中子项时，所有祖先容器会保留并自动展开；筛选清空后恢复用户之前的展开状态。

显示层私有状态：

```text
filter_query
expanded entry IDs
selected entry ID
```

这些状态不写入领域对象，也不写入 LayoutState。是否持久化到用户配置由后续 Shell
状态层决定。

## 7. 事件边界

Explorer Panel 对外只发送稳定显示条目 ID：

```text
entry_selected(entry_id)
entry_activated(entry_id)
refresh_requested()
```

数据源适配器或 WorkspaceHost 再把 `entry_id` 解析成具体业务动作。这样 Tree 不会
直接持有 Node Map Canvas、Inspector、Script Workspace 或磁盘服务。

## 8. 当前实现范围

已经实现：

- 稳定条目 ID；
- 可替换模型；
- 容器/文档显示提示；
- 原子模型替换；
- 父子关系、环和不可达条目校验；
- 稳定排序；
- 显式搜索词；
- Tree 展开、筛选、选择恢复；
- 静态 `EditorShell` 中的可见 Explorer；
- 运行时替换数据源后 Tree 会原子刷新；
- 占位数据源；
- 纯模型测试和静态场景显示测试。

当前明确不做：

- 接入 `SceneMap`；
- 接入真实文件系统；
- 新建、移动、复制、重命名或删除任何文件；
- 对 `.lua`、`.rscn`、JSON 或资源进行解析；
- 决定最终项目浏览器的信息架构；
- 注册正式 Explorer Dock 模块 ID；
- 领域选择上下文或 Workspace 激活路由。

## 9. 验收标准

- [x] 打开 `editor_shell.tscn` 能直接看到 Explorer 静态节点；
- [x] 运行时 Tree 显示占位条目树；
- [x] Tree 可展开、筛选、选择和刷新；
- [x] 数据源不依赖 `SceneMap` 或操作系统文件；
- [x] metadata 不被显示层解释或搜索；
- [x] 无效候选树不会污染旧模型；
- [x] 空间布局测试不需要业务数据；
- [x] 运行时可以替换数据源而不重写 Tree；
- [ ] 确定正式项目浏览器的数据源；
- [ ] 决定 Scene、资产、角色和脚本的最终展示方式；
- [ ] 接入正式 ProjectSession 和 WorkspaceHost。
