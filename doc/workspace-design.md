# GEL Editor 工作区框架设计

> 状态：布局管理逻辑已完成，EditorShell 占位 UI 已开始，具体业务 UI 尚未接入。
>
> 本文是在阅读 Godot 4.6 编辑器源码之后整理的 GEL 工作区设计。当前 `editor/`
> 已保留 Node Map 领域模型，并实现不依赖 Godot Control 的布局拓扑、Dock/Workspace
> 描述、状态转换和序列化逻辑；在工作区框架通过纯 UI 验收之前，不接入
> `SceneMap`、`GraphEdit` 或具体编辑功能。

## 1. 设计目标

GEL 需要的是一个可以长期承载编辑器功能的工作区，而不是在一个 `HBoxContainer` 中
继续堆叠按钮和面板。

工作区框架应当首先解决：

- 中央工作区始终是视觉和空间上的主体；
- 左、右 Dock 有明确的槽位、Tab 和可调整分隔线；
- 底部面板属于中央区域，可以折叠和恢复高度；
- Dock 内容与 Dock 位置相互独立；
- 中央工作区与侧边 Dock 使用不同的生命周期；
- 布局状态与项目/业务数据分开保存；
- 后续加入 Map、Script、Preview 等功能时，不需要重写根布局；
- 面板之间通过统一上下文通信，而不是互相持有引用。

### 1.1 当前阶段明确不做

以下内容不属于第一阶段的工作区框架：

- Scene 创建、删除、连线和 Inspector 业务；
- SceneMap 的加载和保存；
- Lua 文件写回；
- 完整的插件系统；
- 任意 Dock 拖到独立窗口；
- 任意 Dock 跨槽拖放；
- 运行时预览。

第一阶段即使放置占位面板，也必须明确标记为占位，不能用未完成的业务功能掩盖布局
问题。

## 2. 参考的 Godot 4.6 源码

本设计参考 Godot 4.6 分支的以下文件：

| Godot 文件 | 研究内容 |
|---|---|
| `editor/editor_node.cpp` | 编辑器根布局、中央区域、顶部栏和 Dock 初始化 |
| `editor/editor_node.h` | 根布局持有的 Split、主屏幕和布局状态对象 |
| `editor/docks/dock_constants.h` | Dock 槽位和布局类型 |
| `editor/docks/editor_dock.h/.cpp` | Dock 的元数据和生命周期 |
| `editor/docks/editor_dock_manager.h/.cpp` | Dock 注册、移动、开关、Tab、布局保存/恢复 |
| `editor/editor_main_screen.h/.cpp` | 中央主编辑器页面切换 |
| `editor/gui/editor_bottom_panel.h/.cpp` | 底部面板折叠、Tab、高度和布局状态 |
| `editor/gui/editor_title_bar.h/.cpp` | 顶部菜单、主工作区按钮和全局工具 |
| `editor/plugins/editor_plugin.h/.cpp` | 主编辑器、Dock 和底部面板的接入边界 |
| `scene/gui/split_container.cpp` | 分隔线、折叠、偏移和拖拽行为 |

上游源码地址：

- <https://github.com/godotengine/godot/blob/4.6/editor/editor_node.cpp>
- <https://github.com/godotengine/godot/blob/4.6/editor/docks/editor_dock.h>
- <https://github.com/godotengine/godot/blob/4.6/editor/docks/editor_dock_manager.cpp>
- <https://github.com/godotengine/godot/blob/4.6/editor/editor_main_screen.cpp>
- <https://github.com/godotengine/godot/blob/4.6/editor/gui/editor_bottom_panel.cpp>
- <https://github.com/godotengine/godot/blob/4.6/scene/gui/split_container.cpp>

## 3. Godot 的真实布局模型

### 3.1 根布局不是简单的三列

Godot 的根层级可以抽象为：

```text
EditorNode
└── gui_base
    └── main_vbox
        ├── EditorTitleBar
        └── DockHSplitMain
            ├── Left Dock Region
            ├── Center Region
            └── Right Dock Region
```

`DockHSplitMain` 不是普通的两子节点 `HSplitContainer`，而是一个允许多个 Dock
区域参与布局的横向分割结构。左右两边还各自包含纵向分割：

```text
Left Region                 Center Region                 Right Region
┌──────────────┐            ┌──────────────────┐          ┌──────────────┐
│ upper slot   │            │                  │          │ upper slot   │
├──────────────┤            │  central editor  │          ├──────────────┤
│ lower slot   │            │                  │          │ lower slot   │
└──────────────┘            ├──────────────────┤          └──────────────┘
                            │ bottom panel     │
                            └──────────────────┘
```

Godot 源码在 `editor/editor_node.cpp` 中创建了四个侧边纵向 Split：

```text
left_l_vsplit
left_r_vsplit
right_l_vsplit
right_r_vsplit
```

因此它实际上预留了左右两列、每列上下两个槽位，而不是把左右面板硬编码成一个
Panel。

### 3.2 Dock 是带身份的内容容器

Godot 用 `EditorDock` 包裹具体 Dock 内容。Dock 自身保存的不是业务数据，而是布局
所需的元数据：

```text
title
layout_key
icon
shortcut
default_slot
available_layouts
current_layout
is_open
enabled
previous_tab_index
```

最重要的原则是：

```text
Dock 内容：Scene
Dock 位置：Left Upper Slot
```

内容不应该知道自己固定在左侧；用户可以将它切换、关闭、恢复，未来还可以移动到
别的槽位或浮动。

### 3.3 一个槽位是一个 TabContainer

每个 Dock 槽位本质上承载一个 `TabContainer`：

```text
Left Upper Slot
└── TabContainer
    ├── Scene
    └── Import
```

因此多个 Dock 可以共享空间：

```text
┌──────────────────────────────┐
│ Scene │ Import               │
├──────────────────────────────┤
│ 当前活动 Dock 的内容          │
└──────────────────────────────┘
```

Godot 还为 Tab 提供了：

- 拖动重排；
- 当前 Tab；
- 右键菜单；
- 关闭和重新打开；
- 跨槽移动；
- 浮动窗口。

### 3.4 中央区域和底部面板是嵌套关系

Godot 的中央区域可以抽象为：

```text
CenterSplit（垂直，可折叠）
├── TopSplit
│   └── MainEditorArea
└── BottomPanel
```

底部面板默认折叠。它不是简单地把某个 Panel 的 `visible` 改成 `false`，而是由
SplitContainer 保留分隔线偏移和恢复逻辑：

```text
折叠：
┌─────────────────────────────┐
│                             │
│      Main Editor Area       │
│                             │
└─────────────────────────────┘

展开：
┌─────────────────────────────┐
│      Main Editor Area       │
├─────────────────────────────┤
│ Output │ Problems │ Debug  │
└─────────────────────────────┘
```

Godot 还会按底部 Dock 的稳定名称保存各自的高度，所以在 `Output` 和 `Debugger`
之间切换时可以恢复不同的分割位置。

### 3.5 中央主屏幕与 Dock 是两套系统

Godot 的 `EditorMainScreen` 负责中央页面：

```text
2D / 3D / Script / Game / Asset Library
```

它负责：

- 注册主编辑器页面；
- 切换当前页面；
- 调用旧页面的隐藏和新页面的显示；
- 通知插件主屏幕变化；
- 保存和恢复当前页面。

它不负责左右 Dock。这个职责分离很重要：

```text
EditorWorkspaceManager  → 中央工作区
EditorDockManager       → 侧边和底部 Dock
```

### 3.6 顶部栏是语义分区，不是按钮堆

Godot 的 `EditorTitleBar` 包含多个具有明确职责的区域：

```text
EditorTitleBar
├── Main Menu
├── Project Title
├── Main Workspace Buttons
├── Run Controls
├── Environment / Renderer
└── Window Controls
```

中央工作区按钮由主屏幕注册，而不是由具体业务面板直接插入顶部栏。

## 4. GEL 的目标布局

GEL 当前是独立的 Godot runtime 应用，而不是 `EditorPlugin`。因此我们借鉴 Godot
的布局抽象，但不直接依赖 Godot 编辑器内部类。

### 4.1 目标视觉结构

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ GEL │ Project │ Edit │ View │ Window │ Help                  [global tools] │
├────────────────────────────────────────────────────────────────────────────┤
│                 MAP WORKSPACE       SCRIPT       PREVIEW                    │
├───────────────┬────────────────────────────────────────┬───────────────────┤
│               │                                        │                   │
│ Left Upper    │                                        │ Right Upper       │
│               │                                        │                   │
├───────────────┤          Active Workspace              ├───────────────────┤
│ Left Lower    │                                        │ Right Lower       │
│               │                                        │                   │
│               ├────────────────────────────────────────┤                   │
│               │ Output │ Problems │ Diagnostics       │                   │
└───────────────┴────────────────────────────────────────┴───────────────────┘
```

### 4.2 目标节点层级

```text
EditorShell (Control)
└── RootVBox
    ├── EditorTopBar
    │   ├── MainMenu
    │   ├── ProductTitle
    │   ├── WorkspaceSwitcher
    │   └── GlobalCommandArea
    │
    └── MainDockSplit
        ├── LeftRegion
        │   └── LeftVerticalSplit
        │       ├── LeftUpperSlot
        │       │   └── DockTabs
        │       └── LeftLowerSlot
        │           └── DockTabs
        │
        ├── CenterRegion
        │   └── CenterVerticalSplit (collapsed by default)
        │       ├── WorkspaceHost
        │       │   ├── DocumentTabs (预留)
        │       │   └── ActiveWorkspace
        │       └── BottomPanel
        │           └── DockTabs
        │
        └── RightRegion
            └── RightVerticalSplit
                ├── RightUpperSlot
                │   └── DockTabs
                └── RightLowerSlot
                    └── DockTabs
```

第一版可以只显示一个 `Map` 工作区和少数占位 Dock，但节点层级从一开始就按照这个
结构建立。

### 4.3 第一版默认槽位

以 `1440×900` 视口为基准，建议默认值如下：

| 区域 | 默认内容 | 建议尺寸 | 默认状态 |
|---|---|---:|---|
| Left Upper | Scene / Navigator 占位 | 250 px | 打开 |
| Left Lower | Explorer 占位 | 250 px | 打开 |
| Center | Map 工作区占位 | 剩余空间 | 打开 |
| Right Upper | Inspector 占位 | 340 px | 打开 |
| Right Lower | History / Export 占位 | 340 px | 打开 |
| Bottom | Output / Problems 占位 | 200 px | 收起 |

这些是**默认布局**，不是内容和位置的永久绑定。用户调整的分割线位置属于布局
状态。

## 5. GEL 工作区框架的核心对象

### 5.1 `EditorShell`

职责：

- 持有根节点层级；
- 创建顶部栏、主 Dock 分割和状态栏；
- 连接 `EditorDockManager`、`EditorWorkspaceManager` 和 `EditorContext`；
- 提供布局重置、布局保存、布局加载和无干扰模式；
- 不理解 `SceneMap` 的业务规则。

不负责：

- 创建 Scene；
- 验证 RouteEdge；
- 修改领域模型；
- 直接渲染具体 Map 节点。

### 5.2 `EditorDock`

每一个 Dock 具有稳定的布局身份：

```text
id: String
 title: String
 icon: StringName（可选）
 default_slot: DockSlot
 allowed_layouts: flags
 closable: bool
 transient: bool
 content: Control
```

其中 `id` 是持久化关键，不能使用数组索引或显示标题代替。显示标题可以修改，
稳定 ID 不应修改。

建议的 Dock 生命周期：

```text
registered → open → focused
                  ↓
                closed
                  ↓
                reopened
```

### 5.3 `EditorDockManager`

职责：

```text
register_dock(dock)
remove_dock(id)
open_dock(id)
close_dock(id)
focus_dock(id)
move_dock(id, slot)       # 后续阶段
set_docks_visible(flag)
get_dock_slot(id)
save_layout(config)
load_layout(config)
reset_layout()
```

它负责管理：

- Dock 与槽位的关系；
- 每个槽位的 Tab 顺序；
- 当前 Tab；
- Dock 是否打开；
- SplitContainer 偏移；
- Dock 菜单和可见性。

它不负责 Dock 内部的业务逻辑。

### 5.4 `EditorWorkspace`

中央工作区页面使用独立接口：

```text
id: String
 title: String
 content: Control
 shortcut: String（可选）
```

行为接口：

```text
activate()
deactivate()
can_deactivate()
save_state()
load_state(state)
```

第一版只注册：

```text
map
```

但接口应允许未来添加：

```text
script
preview
project
```

工作区切换只影响中央区域，不应隐式改变左右 Dock 的内容。

### 5.5 `EditorWorkspaceManager`

职责：

```text
register_workspace(workspace)
unregister_workspace(id)
activate_workspace(id)
get_active_workspace_id()
save_state()
load_state()
```

切换过程：

```text
请求 activate("script")
        ↓
当前 workspace.deactivate()
        ↓
新 workspace.activate()
        ↓
更新 WorkspaceSwitcher
        ↓
通知 EditorContext
```

### 5.6 `EditorBottomPanel`

底部面板不是普通的全局 Panel，而是 `CenterRegion` 的垂直分割子项：

```text
CenterVerticalSplit
├── WorkspaceHost
└── BottomPanel
```

必须支持：

- 默认收起；
- 点击 Tab 展开；
- 再次点击当前 Tab 收起；
- 保存每个底部 Tab 的高度；
- 切换底部 Tab 时恢复各自高度；
- 可选的锁定/展开控制；
- 不改变左右 Dock 的宽度和纵向布局。

### 5.7 `EditorLayoutState`

布局状态和业务模型完全分离。建议保存以下信息：

```text
schema_version
active_workspace
main_split_offsets
left_split_offsets
right_split_offsets
bottom_split_offset
bottom_panel_open
bottom_panel_active_tab
dock_slots
  - tab order
  - selected tab
  - open/closed state
window state（后续）
```

示意格式：

```json
{
  "schemaVersion": 1,
  "activeWorkspace": "map",
  "splits": {
    "main": [250, -340],
    "left": [0],
    "right": [0],
    "center": [0]
  },
  "docks": {
    "left_upper": {
      "tabs": ["scene"],
      "active": "scene"
    },
    "left_lower": {
      "tabs": ["project"],
      "active": "project"
    },
    "right_upper": {
      "tabs": ["inspector"],
      "active": "inspector"
    },
    "right_lower": {
      "tabs": ["history", "export"],
      "active": "history"
    },
    "bottom": {
      "tabs": ["output", "problems"],
      "active": null,
      "offsets": {
        "output": 220,
        "problems": 180
      }
    }
  }
}
```

实际格式可以使用 Godot `ConfigFile` 或 JSON，但必须满足：

- 带有 schema 版本；
- 使用稳定 ID 而不是索引；
- 遇到未知 Dock 时忽略，而不是使整个布局加载失败；
- 缺少字段时使用默认值；
- 布局配置损坏时可以回到默认布局；
- 保存采用延迟写入，避免拖动分隔线时每帧写盘。

### 5.8 `EditorContext`

工作区内的选择和当前对象不应由各个面板分别保存。建议使用一个轻量上下文：

```text
EditorContext
├── active_workspace
├── active_document
├── selection
├── focus_target
└── diagnostics
```

选择事件流：

```text
Scene Navigator / Workspace / Dock
              │
              ▼
      EditorContext.select(object)
              │
       ┌──────┼────────┐
       ▼      ▼        ▼
    Canvas Inspector StatusBar
```

面板之间禁止采用以下直接依赖：

```text
SceneDock → 直接调用 Inspector
Inspector → 直接调用 Canvas
Canvas    → 直接隐藏 SceneDock
```

## 6. Dock 槽位设计

### 6.1 第一版槽位模型

为了保留 Godot 的扩展能力，同时避免一开始复制全部复杂度，第一版使用五个逻辑
槽位：

```text
LEFT_UPPER
LEFT_LOWER
RIGHT_UPPER
RIGHT_LOWER
BOTTOM
```

每个槽位包含：

```text
DockSlot
├── stable_id
├── side
├── orientation
├── TabContainer
└── default visibility
```

### 6.2 后续扩展

如果未来需要 Godot 类似的内外双列布局，可以在不改变 Dock 内容接口的前提下扩展为：

```text
LEFT_UL / LEFT_BL / LEFT_UR / LEFT_BR
RIGHT_UL / RIGHT_BL / RIGHT_UR / RIGHT_BR
BOTTOM
```

这也是 Godot 4.6 使用八个侧边槽位的原因：Dock 的内容和可停靠位置已经分离，
增加槽位不会要求重写 Dock 本身。

### 6.3 关闭和隐藏

关闭 Dock 时不应销毁 Dock 内容：

```text
open Dock
   ↓ close
closed registry（保留稳定 ID 和上次位置）
   ↓ reopen
原槽位 + 原 Tab 位置
```

第一版可以不实现独立浮动窗口，但应保留 `previous_slot` 和 `previous_tab_index`
这类状态字段。

## 7. 顶部栏设计

顶部栏分成三个语义区：

```text
┌──────────────┬────────────────────────┬──────────────────────┐
│ Main Menu    │ Workspace Switcher     │ Global Commands      │
└──────────────┴────────────────────────┴──────────────────────┘
```

### 7.1 Main Menu

放置工程级命令：

```text
GEL
Project
Edit
View
Window
Help
```

菜单项可以先是 disabled 或占位，但菜单的视觉层级和归属应先确定。

### 7.2 Workspace Switcher

只负责中央工作区：

```text
MAP | SCRIPT | PREVIEW
```

第一版只启用 `MAP`，其余页面若显示必须明确标为未实现，或者暂时不显示按钮。
不建议为了模仿 Godot 而放置一排没有行为的假模式。

### 7.3 Global Commands

放置与当前 Dock 无关的全局控制：

```text
布局菜单
显示/隐藏 Dock
无干扰模式
帮助
```

Map 业务按钮不应直接污染全局顶部栏；它们应属于 `MapWorkspace` 自己的工具栏。

## 8. 状态边界

### 8.1 工作区布局状态

保存到编辑器用户配置，例如：

```text
user://gel_editor_layout.cfg
```

内容包括：

- Dock 槽位和 Tab；
- 分割线偏移；
- 当前中央工作区；
- 底部面板状态；
- 窗口状态（后续）。

### 8.2 项目/业务数据

由未来的工程层保存，例如：

```text
project.gel.json
```

内容包括：

- SceneMap；
- SceneNode；
- RouteEdge；
- 条件树；
- Scene 节点在 Map 中的位置。

### 8.3 严禁混合

```text
SceneMap 不保存 Dock 宽度
SceneNode 不保存当前 Inspector Tab
RouteEdge 不保存底部面板状态
布局文件不保存 Runtime Package 业务字段
```

## 9. 推荐代码目录

工作区框架属于宿主 UI 层，不应放入 `node_map/`：

```text
editor/
├── workspace/
│   ├── editor_shell.tscn
│   ├── editor_shell.gd
│   ├── editor_dock.gd
│   ├── editor_dock_manager.gd
│   ├── editor_workspace.gd
│   ├── editor_workspace_manager.gd
│   ├── editor_bottom_panel.gd
│   ├── editor_layout_state.gd
│   └── editor_context.gd
│
├── theme/
│   └── gel_editor_theme.tres
│
├── node_map/
│   └── ...                 # 与 UI 无关的领域模型
│
└── tests/
    ├── run_tests.gd        # 领域模型测试
    └── workspace_ui_tests.gd # 后续的纯工作区测试
```

布局层级尽量使用 `.tscn` 表达，脚本只负责：

- 注册和管理 Dock；
- 注册和切换 Workspace；
- 转发上下文事件；
- 保存和恢复布局状态；
- 处理可见性和快捷键。

不要把所有控件都重新塞回一个超长的 `_build_interface()`。

## 10. 实施阶段

### 阶段 0：设计冻结（已完成）

完成：

- 记录 Godot 源码研究结论；
- 确认 Dock、Workspace、BottomPanel 和 LayoutState 的边界；
- 不创建业务 UI；
- 不依赖 SceneMap。

### 阶段 1：布局管理逻辑（已完成）

已经实现：

- `EditorLayoutDefinition`：槽位、Split 拓扑和默认偏移；
- `EditorDockDescriptor` / `EditorWorkspaceDescriptor`：稳定注册元数据；
- `EditorDockSlotState` / `EditorLayoutState`：Tab、活动项、关闭项和恢复位置；
- `EditorLayoutManager`：注册、切换、移动、关闭、恢复、事务和默认布局；
- `EditorLayoutSerializer`：JSON 中间格式、版本检查和迁移入口；
- `tests/layout_manager_tests.gd`：布局管理逻辑回归。

该阶段不创建任何 Godot Control，也不依赖 Node Map 领域对象。

### 阶段 2：静态工作区骨架（下一步）

只实现布局和占位内容：

- `EditorShell`；
- 顶部栏；
- 左右上下槽位；
- 中央工作区容器；
- 折叠的底部面板；
- 状态栏；
- 统一主题和边界线。

验收重点是窗口中的空间关系，而不是业务按钮。

### 阶段 3：Dock UI 映射

实现：

- Dock 注册；
- Tab 切换；
- Dock 打开/关闭；
- 分隔线拖动；
- Reset Layout；
- 延迟保存和恢复布局。

此阶段仍然使用占位 Dock，不接 Node Map。

### 阶段 4：Workspace UI 映射

实现：

- Workspace 注册；
- 中央页面切换；
- 当前 Workspace 保存/恢复；
- Workspace 私有工具栏区域；
- 工作区切换不会破坏 Dock 状态。

### 阶段 5：上下文总线

实现：

- 统一选择对象；
- 当前文档；
- 当前焦点；
- 诊断消息；
- Dock、Workspace 和状态栏的订阅关系。

### 阶段 6：接入 Node Map

最后才把现有领域模型和具体视图接入：

```text
MapWorkspace
├── MapToolbar
└── NodeMapCanvas

InspectorDock
└── NodeMapInspector
```

Map 视图通过 `EditorContext` 和领域控制器工作，不改变工作区内核。

## 11. 工作区框架验收标准

在接入任何 Scene 功能之前，工作区框架必须满足：

### 布局

- [ ] 启动后显示完整的编辑器层级，而不是单一画布；
- [ ] 中央区域在所有默认尺寸下保持最大可用空间；
- [ ] 左右 Dock 有清晰的上下层级和边界；
- [ ] 底部面板位于中央区域内部，不影响左右 Dock 的结构；
- [ ] 分隔线可以拖动，且不会把中央区域压到不可用；
- [ ] 最小窗口尺寸下不会出现负尺寸或控件重叠。

### Dock

- [ ] Dock 内容和 Dock 槽位分离；
- [ ] 一个槽位可以承载多个 Tab；
- [ ] Dock 可以打开、关闭和重新聚焦；
- [ ] 关闭后再次打开可以回到原槽位；
- [ ] 未实现的 Dock 显示明确的空状态。

### Workspace

- [ ] 中央工作区可以注册和切换；
- [ ] 当前工作区有稳定 ID；
- [ ] 工作区切换不会重置 Dock 宽度和 Tab；
- [ ] 只有一个中央工作区处于活动状态。

### Bottom Panel

- [ ] 默认收起；
- [ ] 点击底部 Tab 可以展开；
- [ ] 再次操作可以收起；
- [ ] 不同底部 Tab 可以保存不同高度；
- [ ] 展开/收起不会重建整个根布局。

### 布局状态

- [ ] Reset Layout 可以恢复默认布局；
- [ ] 保存和加载使用稳定 ID；
- [ ] 配置缺失字段时使用默认值；
- [ ] 配置损坏时可以安全回退；
- [ ] 拖动分隔线不会每帧写盘；
- [ ] 布局状态没有进入 `SceneMap`。

### 依赖边界

- [ ] 工作区框架不 preload Node Map 领域对象；
- [ ] Dock 不直接修改领域模型；
- [ ] 面板不互相持有业务引用；
- [ ] 纯工作区测试可以在没有任何 Scene 的情况下运行。

## 12. 最终原则

1. **先建立空间系统，再加入功能。**
2. **Dock 内容和 Dock 位置分离。**
3. **中央 Workspace 和侧边 Dock 分离。**
4. **Bottom Panel 是中央区域的子布局。**
5. **所有面板通过 `EditorContext` 协作。**
6. **布局状态和项目数据分开持久化。**
7. **使用稳定 ID，不使用显示文字或数组索引作为布局身份。**
8. **第一版只实现必要的 Dock 能力，浮动和任意拖放后置。**
9. **用 `.tscn` 表达稳定的布局层级，用脚本管理行为。**
10. **在工作区验收通过之前，不继续扩展 Node Map 业务 UI。**
