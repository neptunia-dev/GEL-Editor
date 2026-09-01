# GEL Editor 模块框架设计

> 状态：轻量模块注册、静态 EditorShell 和 Explorer 显示框架已完成；正式业务模块数据源与 LayoutRenderer 尚未开始。

本文定义 GEL 工作区接入未来功能模块的最小协议。它服务于 Explorer 显示层、Node Map、
脚本编辑器、预览器等 GEL 内部模块，不试图复制 Godot 的完整插件生态。

## 1. 目标

增加一个工作区模块时，只需要构造一个 `EditorModuleDescriptor` 并交给
`EditorModuleRegistry`：

```gdscript
var sample_dock = EditorModuleDescriptor.dock(
    "gel.sample_dock",
    "Sample Dock",
    EditorLayoutDefinition.SLOT_LEFT_LOWER,
    sample_dock_scene,
)
module_registry.register_module(sample_dock)
```

模块只需要描述：

- 稳定身份和显示标题；
- 属于中央 Workspace 还是 Dock；
- Dock 的默认槽位和允许槽位；
- 内容将来由哪个场景或工厂创建。

模块不需要理解布局树，也不需要直接持有其他模块或 `EditorShell` 的节点引用。

## 2. 为什么不使用完整插件系统

Godot 的 `EditorPlugin` 面向完整的 Godot 编辑器生态，包含插件依赖、对象编辑、主屏幕、
Dock 浮动、插件窗口布局和编辑器全局服务。GEL 当前只是自己的 runtime 编辑器，需要的
是把内部功能挂进工作区。

因此 GEL 只借鉴三个布局原则：

1. 中央 Workspace 与侧边 Dock 分离；
2. 模块内容与模块位置分离；
3. 布局状态使用稳定 ID 保存。

当前不引入：

- `EditorExtensionHost`；
- 插件依赖图和插件生命周期；
- 独立的命令注册表；
- 独立的 Context 主题总线；
- Dock 浮动和任意跨槽拖放。

## 3. 结构和职责

```text
EditorShell
├── EditorLayoutManager       # 管理槽位、Tab、Split 和布局状态
├── EditorModuleRegistry      # 保存模块描述，并接入布局元数据
└── LayoutRenderer            # 后续把模块内容挂到 Godot 控件
```

职责边界：

```text
EditorLayoutManager
    只认识 Workspace/Dock 的布局描述和可变布局状态

EditorModuleRegistry
    只认识模块描述，并将 Workspace/Dock 元数据注册到 LayoutManager

LayoutRenderer
    后续按需创建 content_scene 或调用 content_factory

具体模块
    提供自己的内容和交互，不直接修改根布局
```

模块注册逻辑不创建 `Control`、不实例化 `PackedScene`，也不调用内容工厂。

## 4. `EditorModuleDescriptor`

### 4.1 字段

描述对象保存以下静态信息：

```text
module_id
title
kind
content_scene
content_factory
default_active
default_order
default_slot
allowed_slots
default_open
closable
transient
icon_name
```

字段含义：

- `module_id`：稳定模块 ID，用于注册表查询和布局状态；
- `title`：显示标题，可以修改，不作为身份；
- `kind`：`workspace` 或 `dock`；
- `content_scene`：可选的 `PackedScene`；
- `content_factory`：可选的延迟创建回调；
- `default_active`：Workspace 首次成为默认活动页的标记；
- `default_order`：同一槽位或 Workspace 列表中的默认排序；
- `default_slot`：Dock 首次注册时使用的槽位；
- `allowed_slots`：Dock 可以移动到的槽位；
- `default_open`：Dock 是否出现在默认布局中；
- `closable`：Dock 是否允许用户关闭；
- `transient` 和 `icon_name`：传递给现有 Dock 布局描述的元数据。

内容来源可以为空。这允许在 UI 还不存在时先注册和测试布局模块。提供内容时，
`content_scene` 和 `content_factory` 只能二选一。

### 4.2 工厂方法

为了避免调用方记忆 Workspace 和 Dock 的参数顺序，描述对象提供两个静态工厂：

```gdscript
EditorModuleDescriptor.workspace(
    module_id,
    title,
    content_scene,
    content_factory,
    default_active,
    default_order,
)
```

```gdscript
EditorModuleDescriptor.dock(
    module_id,
    title,
    default_slot,
    content_scene,
    content_factory,
    allowed_slots,
    default_open,
    closable,
    default_order,
    icon_name,
)
```

通用占位 Dock 通常只需要前三个参数；未显式提供 `allowed_slots` 时，默认只
允许留在自己的默认槽位。

### 4.3 模块 ID

模块 ID 使用以下格式：

```text
^[a-z][a-z0-9_.-]*$
```

推荐：

```text
gel.node_map
gel.sample_dock
gel.script
gel.preview
```

标题不是身份，数组索引和 `NodePath` 也不能作为模块 ID，因为布局文件需要在代码和
界面结构变化后继续识别同一个模块。

## 5. Workspace 和 Dock

### 5.1 Workspace

Workspace 占据中央区域，一次显示一个：

```text
Map | Script | Preview
```

它只需要 `module_id`、`title`、内容来源、默认活动标记和默认顺序，不声明 Dock 槽位。
注册后会转换为 `EditorWorkspaceDescriptor`。

### 5.2 Dock

Dock 挂载到现有布局系统的逻辑槽位：

```text
left.upper
left.lower
right.upper
right.lower
bottom
```

通用占位 Dock 的注册可以保持很小：

```gdscript
var sample_dock = EditorModuleDescriptor.dock(
    "gel.sample_dock",
    "Sample Dock",
    EditorLayoutDefinition.SLOT_LEFT_LOWER,
    sample_dock_scene,
    Callable(),
    [EditorLayoutDefinition.SLOT_LEFT_LOWER,
     EditorLayoutDefinition.SLOT_LEFT_UPPER],
)
module_registry.register_module(sample_dock)
```

注册后会转换为 `EditorDockDescriptor`。`EditorLayoutManager` 不需要知道内容来自哪个
场景，也不需要知道内容是否已经创建。

## 6. `EditorModuleRegistry`

注册表维护模块描述和布局描述之间的映射，公开接口为：

```text
register_module(descriptor) -> bool
unregister_module(module_id) -> bool
has_module(module_id) -> bool
get_module(module_id)
get_module_ids()
get_module_count()
get_workspace_modules()
get_dock_modules()
get_layout_manager()
```

注册时检查：

- 模块描述接口存在；
- `module_id` 合法且唯一；
- 标题非空；
- 模块类型合法；
- Workspace 没有 Dock 槽位；
- Dock 的默认槽位存在且在允许列表内；
- Dock 的所有允许槽位都存在且没有重复；
- 内容场景和内容工厂不能同时提供。

注册流程如下：

```text
register_module(descriptor)
    ↓
校验模块描述
    ↓
转换为 WorkspaceDescriptor 或 DockDescriptor
    ↓
调用 EditorLayoutManager 注册布局元数据
    ↓
布局注册成功后保存模块描述
```

布局注册失败时，模块不会写入注册表。现有 `EditorLayoutManager` 的注册接口本身也会
在校验失败时保持原状态，因此不会留下半个模块。

模块注销时先移除对应布局描述，再移除注册表中的模块描述。布局注销失败时，模块描述
仍然保留，调用方可以看到 `last_error` 并决定如何处理。

## 7. 内容创建和 UI 边界

模块注册阶段只保存 `PackedScene` 或 `Callable`：

```text
register_module()
    不创建内容

LayoutRenderer 第一次需要显示
    content_scene.instantiate()
    或 content_factory.call()
```

这样纯逻辑测试不需要窗口或场景树，未显示的模块也不会提前消耗 UI 资源。

内容缓存、关闭后重新挂载、工厂异常占位等行为属于未来 `LayoutRenderer` 的职责，不属于
模块注册表。`EditorModuleRegistry` 不捕获或解释模块 UI 内部的业务错误。

## 8. 状态边界

布局和模块描述是两种不同数据：

```text
EditorModuleRegistry
    当前进程注册了哪些模块，以及每个模块的静态描述

EditorLayoutState
    模块所在槽位、Tab 顺序、Split 偏移、Dock 是否打开

Module Private State
    当前目录、过滤文本、工具选项等模块自己的状态（后续）
```

Node Map 领域数据继续独立保存：

```text
SceneMap / SceneNode / RouteEdge / ConditionTree
```

这些数据不能混入模块描述或布局状态。

## 9. 推荐目录结构

```text
editor/
├── workspace/
│   ├── layout/
│   │   └── ...
│   └── modules/
│       ├── module_descriptor.gd
│       └── module_registry.gd
│
├── doc/
│   └── editor-module-framework-design.md
│
└── tests/
    ├── layout_manager_tests.gd
    └── module_registry_tests.gd
```

具体模块的 UI 内容放在自己的目录，不放进布局核心：

```text
editor/modules/<feature>/
├── feature_module.gd        # 需要行为时再增加
├── feature_dock.tscn
└── feature_dock.gd
```

## 10. 当前实现和后续顺序

当前已经实现：

- `EditorModuleDescriptor`；
- Workspace/Dock 两种模块类型；
- 稳定模块 ID 和描述校验；
- 默认槽位、允许槽位和布局元数据映射；
- 模块注册、查询、按类型列出和注销；
- 注册失败时不污染模块注册表或布局状态；
- 内容场景和工厂的延迟保存，不创建 UI；
- 不依赖窗口或 `SceneMap` 的模块测试。

下一步顺序：

```text
模块注册逻辑
        ↓
EditorShell 静态布局
        ↓
LayoutRenderer
        ↓
占位模块挂载
        ↓
正式业务模块
        ↓
Node Map 模块
```

当前明确不做：

- `EditorExtensionHost` 和复杂扩展生命周期；
- 依赖图、命令注册表和 Context 主题总线；
- Dock 浮动、跨槽拖放和热重载；
- Node Map 业务 UI。
