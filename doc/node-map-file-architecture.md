# Node Map 重设计与文件架构

> 状态：模型、工作区、`gel.node-map` 快照、`.gelproj` 工程文件和最小 Runtime
> Package 编译链均已实现。本文保留部分未来设计（例如变量节点、完整资源模型）作为
> 规范草案；当前行为以源码和可执行测试为准。工程文件的已实现契约见
> [Node Map 工程文件](node-map-project-file.md)。
>
> `workspace/node_map/` 现在包含模型驱动的正式编辑器；静态预览仍作为独立 Tab 保留。
> 编辑器工程与 Runtime Package 是不同层，不能互相替代。

## 1. 设计目标

新的 Node Map 需要同时满足以下要求：

- 节点类型可以持续扩展，不为每一种业务节点创建一套独立的图协议。
- 节点有稳定的实例 ID、类型 ID、端口和编辑器布局数据。
- 输入值可以来自节点控件，也可以来自另一节点的连接。
- 控制流和数据流使用同一种连接模型，但必须区分类型。
- `Scene` 在项目总图中表现为普通节点，进入后编辑自己的子图。
- 子图边界通过普通的输入/输出接口节点表达，不在父节点中复制一份出口列表。
- 编辑器模型不依赖 Godot `GraphNode` 控件，不读写工程文件，也不直接执行 Lua。
- 删除、复制、改名和端口变更不会留下悬空连接。
- 文件格式使用稳定的类型 ID 和版本字段，不依赖 GDScript 类名。

## 2. 总体结构

```text
NodeMapDocument
├── RootGraph
│   ├── ProjectStartNode
│   └── SceneNode
│       └── SceneGraph
│           ├── GraphInputNode
│           ├── DialogueNode
│           ├── IfNode
│           ├── ChoiceNode
│           └── GraphOutputNode
│
└── NodeRegistry
```

上图表示导航关系，不表示对象嵌套所有权。`RootGraph` 和 `SceneGraph` 是
`NodeGraph.kind` 的语义名称，不是两个额外的容器类；所有图都平铺保存在文档的
`graphs` 集合中。注册表由宿主注入，属于配置依赖，不写入文档文件。

模型继承关系：

```text
NodeMapNode
├── ProjectStartNode
├── GraphInputNode
├── GraphOutputNode
├── DialogueNode
├── IfNode
├── ChoiceNode
├── EndStoryNode
├── SetVariableNode
├── GetVariableNode
└── SubgraphNode
    └── SceneNode
```

这些对象是领域模型，不是 Godot 场景树中的节点。视图层另行定义：

```text
NodeMapNode      -> 纯 RefCounted 模型
NodeMapNodeView  -> Godot GraphNode/Control 视图
NodeGraphView    -> GraphEdit 和视图生命周期
```

`NodeMapNodeView` 不应该成为 `NodeMapNode` 的父类，也不应被领域模型反向引用。

## 3. 核心对象和所有权

### 3.1 `NodeMapDocument`

`NodeMapDocument` 是整个编辑器文档的聚合根，拥有所有图和注册表引用：

```text
NodeMapDocument
├── root_graph_id
├── graphs[graph_id] -> NodeGraph
└── registry -> NodeRegistry
```

它负责：

- 创建、删除和复制 `NodeGraph`。
- 创建、删除和复制节点。
- 创建、删除和更新 `NodeLink`。
- 检查整个文档中的 ID、子图所有权和接口引用。
- 解析复合节点的对外端口。
- 在删除节点、子图或接口时原子清理相关连接。
- 为撤销/重做提供一个完整的文档变更边界。
- 将有效文档交给编译器或序列化器。

它不负责：

- 创建 Godot `GraphEdit`。
- 保存选中、悬停和当前视口等临时 UI 状态。
- 直接访问操作系统文件。
- 直接拼接 Lua 源码。

### 3.2 `NodeGraph`

`NodeGraph` 是一个局部图容器，只拥有同一图范围内的节点和连接：

```text
NodeGraph
├── graph_id
├── kind
├── owner_node_id
├── nodes[node_id] -> NodeMapNode
└── links[link_id] -> NodeLink
```

`kind` 第一版只有两种值：

```text
root   项目级场景拓扑图
scene  某个 SceneNode 的内部流程图
```

`root` 图的 `owner_node_id` 为空；`scene` 图的 `owner_node_id` 必须指向一个
`SubgraphNode`。一个子图只能有一个拥有者，一个 `SubgraphNode` 只能拥有一个子图。

两个方向必须互相匹配：节点的 `child_graph_id` 指向该图，图的 `owner_node_id` 指回
该节点。第一版拥有者只能是根图中的 SceneNode，子图 kind 必须为 scene；根图不能
被任何节点作为子图引用。

`NodeGraph` 负责局部集合和结构检查，但跨图操作仍必须通过 `NodeMapDocument`。

身份的作用域固定如下：

| 身份 | 唯一性范围 | 修改规则 |
| --- | --- | --- |
| `graph_id` / `node_id` / `link_id` | 各自在整个文档内唯一 | 插入文档后不可改名；复制时生成新值 |
| `node_type` | 注册表中的稳定类型键 | 类名、标题变化不改变类型 ID |
| `scene_id` | 整个文档 | 通过文档命令修改并检查唯一性 |
| `port_id` | 所属节点内，输入和输出共用命名空间 | 静态端口由定义固定；动态端口删除后不可复用旧 ID |
| `interface_id` | 所属子图内，输入和输出共用命名空间 | 与显示名称无关；父图端点还必须带拥有者 node_id |

第一版保留入口接口 ID `enter`，其余接口 ID 由 ID 分配器生成。不同 Scene 的入口
都叫 `enter` 不会冲突，因为连接端点是 `(node_id, port_id)`，不是孤立的端口字符串。

### 3.3 `NodeMapNode`

`NodeMapNode` 是所有画布节点的公共父类。它只拥有节点自己的数据，不拥有其他节点、
连接或 `NodeGraph` 对象。

所有节点公共字段：

```text
node_id          文档内稳定唯一的实例 ID
node_type        稳定类型 ID，例如 gel.dialogue
node_version     当前节点数据版本
position         画布位置
size             画布尺寸
collapsed        折叠状态
locked           是否锁定布局
enabled          是否允许进入执行编译结果
title_override   可选的实例标题覆盖值
input_values     数据输入的本地值；连线覆盖时仍保留
```

字段的实际命名统一使用 GDScript 的 `snake_case`；序列化时使用约定的 JSON 命名。
`node_type` 和当前 `node_version` 由注册定义提供，不允许用户任意修改。业务参数由子类
拥有并通过 `serialize_data()` 输出，不把全部业务字段堆进公共父类。

公共父类的职责：

```text
get_type_id()
get_local_port_specs()
validate_self()
duplicate_node()
serialize_data()
to_editor_dict()
```

其中：

- `get_type_id()` 返回稳定的注册类型 ID，不返回脚本类名。
- `get_local_port_specs()` 返回节点自身声明的端口。复合节点的外部端口由文档解析。
- `validate_self()` 检查本地字段和可在本地解析的输入值；子图派生端口由文档校验。
- `duplicate_node()` 创建脱离文档的副本草稿，深复制值数据并生成新节点 ID。
- `serialize_data()` 由子类返回自己的业务字段。
- `to_editor_dict()` 组合公共字段、业务字段和输入值。

公共父类不负责：

- 节点之间的连接。
- 其他节点的 ID。
- 子图对象的所有权。
- 运行时状态、Lua 执行上下文和 Godot 控件引用。

复制不是撤销快照。快照必须保留所有 ID；复合节点的副本草稿必须清空 `child_graph_id`，
由文档复制命令补齐新子图和唯一业务 ID 后才能插入。查询返回的节点副本也不能被直接
修改后当作已提交状态，已有节点的变更必须通过文档命令。

禁用不会删除连线，也不隐式旁路节点。第一版允许保存禁用状态，但可达控制流、被使用的
数据依赖或已启用 Scene 的接口引用到禁用节点时，导出必须报错。入口和边界节点保持启用。

所有已启用 Scene 都进入导出集合，即使从根入口不可达也只给出不可达警告；它们的子图
仍必须有效。禁用 Scene 及其子图整体不导出，但根入口或已启用 Scene 的出口连接到禁用
Scene 时必须报错，不能自动重定向或省略那条路由。

### 3.4 `SubgraphNode`

`SubgraphNode` 是可拥有子图的中间父类：

```text
NodeMapNode
└── SubgraphNode
    └── SceneNode
```

它只增加一个字段：

```text
child_graph_id
```

该字段是引用，不是对象所有权。实际子图由 `NodeMapDocument.graphs` 持有。这样复制、
删除、检测孤儿子图和序列化时，所有关系都经过文档聚合根处理。

第一版只实现 `SceneNode` 这一种复合节点，不在 `SceneGraph` 内再次放置 `SceneNode`。
以后增加宏节点、子流程节点或可复用流程节点时，可以复用 `SubgraphNode`。

### 3.5 `NodeLink`

`NodeLink` 是同一 `NodeGraph` 内两个端口之间的连接：

```text
NodeLink
├── link_id
├── source_node_id
├── source_port_id
├── target_node_id
└── target_port_id
```

连接只保存 ID，不持有节点对象。它必须满足：

- 源节点和目标节点属于同一个图。
- 源端点是输出端口。
- 目标端点是输入端口。
- 端口的 `kind` 和 `value_type` 兼容。
- 两端连接数都没有超过各自上限，且不存在完全重复的端点组合。
- `link_id` 在文档内稳定且唯一。

第一版不再为场景出口、条件分支或其他业务语义创建不同的连接类。所有连接都使用
`NodeLink`。

## 4. 端口协议

### 4.1 `PortSpec`

`PortSpec` 是节点端口定义的值对象，不继承 `NodeMapNode`：

```text
PortSpec
├── port_id
├── display_name
├── direction       input / output
├── kind            flow / data
├── value_type      flow 时为空；data 时为 boolean / number / string / character / ...
├── required
├── max_connections
├── has_default_value
├── default_value
└── order
```

约束：

- `port_id` 在所属节点内稳定唯一。
- `display_name` 只用于显示，不参与连接身份。
- `flow` 端口只连接 `flow` 端口。
- `data` 端口只连接 `data` 端口；第一版要求值类型相同，不做隐式转换。
- `max_connections` 为正整数或 `-1`（不限）；不能使用含义不明的零值。
- `data` 输入最多一条连接，输出默认不限；第一版没有多值输入或隐式合并。
- `flow` 输入默认不限，表示来自不同前驱的可选进入，不表示并行汇合或等待所有输入。
- `flow` 输出最多一条连接，分支由多个命名输出表达，不按连接数组顺序隐式广播执行。
- `required` 表示导出时是否必须有连线或有效数据值，不阻止保存未完成的草稿。
- `order` 只用于渲染顺序，不作为 ID。

数据输入的解析优先级为：已连接的数据源、本地 `input_values[port_id]`、端口默认值。
必须区分没有默认值和显式 `null`，是否允许 `null` 由类型定义决定；flow 不允许本地值或
默认值。连接不会擦除本地值，断开后恢复该值。序列化的值只能由 JSON 基础类型组成，
不得包含 Godot Object、Callable 或资源实例。

端口定义可以来自三处：

```text
静态节点       -> NodeDefinition
动态节点       -> 节点实例数据 + NodeDefinition
复合节点外部端口 -> child graph 的 GraphInterface 投影
```

### 4.2 动态端口

`ChoiceNode`、`SwitchNode` 或未来的多出口节点可以动态增加端口。动态端口必须有独立
的稳定 ID：

```text
ChoiceItem
├── choice_id
├── label
└── order
```

`choice_id` 作为对应输出端口的 `port_id`。不能使用以下内容作为连接身份：

```text
选项文字
数组下标
当前显示顺序
```

改名和排序只改变显示数据；删除动态项时，`NodeMapDocument` 负责原子删除该端口占用的
所有 `NodeLink`。

### 4.3 复合节点的外部端口

复合节点的外部端口不是 `SceneNode` 中另存的一份出口数组。它由子图边界节点推导：

```text
GraphInputNode  -> SubgraphNode 的输入端口
GraphOutputNode -> SubgraphNode 的输出端口
```

`GraphInterface` 是文档根据子图计算出来的只读投影：

```text
GraphInterface
├── interface_id
├── display_name
├── direction       input / output, 从复合节点外部观察
├── kind
├── value_type
├── required
├── max_connections  外部端口的连接上限
├── has_default_value
├── default_value
├── order
├── boundary_node_id 子图内的声明节点
└── boundary_port_id 声明节点的对内端口
```

`interface_id` 是连接身份；`display_name` 可以修改。`SceneNode` 的父图端点使用
`interface_id` 作为 `port_id`。子图内部的 `NodeLink` 仍然连接到具体的
`GraphInputNode` 或 `GraphOutputNode`，不会跨图直接连接。

第一版 Scene 只暴露 flow 接口；类型结构保留 data 的扩展位置，但在明确 Runtime 参数
传递协议前不允许 Scene 的 data 边界。接口投影不序列化，其来源字段保存在边界节点的
业务数据中，渲染顺序仍不参与端点身份。

## 5. 图边界和 Scene 复合节点

### 5.1 根图

根图展示项目级场景拓扑：

```text
ProjectStartNode -> SceneNode -> SceneNode -> ...
```

第一版根图允许：

- 恰好一个 `ProjectStartNode`，不能被普通删除或复制命令移除或增殖。
- 多个 `SceneNode`。
- 以后增加项目级的非执行辅助节点。

根图不放置对话、条件和变量操作节点。这些节点属于 Scene 子图。

### 5.2 Scene 子图

每个 `SceneNode` 对应一个 `scene` 图：

```text
SceneGraph
├── 一个 GraphInputNode: enter
├── DialogueNode / IfNode / ChoiceNode / action nodes
└── GraphOutputNode（转场）或 EndStoryNode（剧情结束）
```

示例：

```text
RootGraph

ProjectStart -> Scene: Prologue -> Scene: Chapter
                         │
                         └── retry -> Scene: Prologue

SceneGraph(Prologue)

Entry: enter -> Dialogue -> If
                         ├── true  -> Output: continue
                         └── false -> Output: retry
```

`SceneNode` 的字段：

```text
scene_id        Runtime Scene 的稳定 ID
display_name    编辑器和运行时显示名称
child_graph_id  对应内部 SceneGraph 的 ID
```

`SceneNode` 不再保存：

- 独立出口数组。
- 条件树或 wrapper 树。
- 目标 Scene。
- 手写 `main.lua` 路径。
- 角色绑定的特殊列表。

Scene 的运行入口由其子图编译生成。Runtime Package 需要的 `main.lua` 路径由导出器
根据 `scene_id` 和包规范决定；如果未来支持用户脚本，应使用独立的脚本节点或资源引用，
不把脚本路径重新塞回公共节点父类。

导出器必须把所选路径显式写进 Runtime Scene 的 `mainScript`；引擎不会从 Scene ID
猜测脚本位置。SceneNode 的编辑器字段与 Runtime 清单字段不是一对一照搬。

### 5.3 子图入口和出口节点

`GraphInputNode` 和 `GraphOutputNode` 本身也继承 `NodeMapNode`。

`GraphInputNode`：

```text
interface_id = enter
display_name
order
out: flow output，最多一条内部连接
```

`GraphOutputNode`：

```text
interface_id
display_name
order
in: flow input，允许多个内部前驱
```

边界节点对内端口固定为 `out` 或 `in`，父图端口才使用 `interface_id`。两者不能混用。
第一版的方向、flow 类型和连接上限由节点定义提供，接口名称和顺序存于实例数据。

第一版约束：

- 每个 SceneGraph 必须有且只有一个 `enter` 输入接口。
- SceneGraph 可以没有输出接口，此时有效流程必须由 `EndStoryNode` 结束。
- 所有输入和输出接口的 `interface_id` 在该 SceneGraph 内唯一，输出不能占用 `enter`。
- 一个接口节点只有一个对内端口。
- 导出时每个可达流程节点都必须存在到 `GraphOutputNode` 或 `EndStoryNode` 的路径。
- 导出时每个公开输出必须有且只有一条父图路由；未连线不表示剧情结束。

创建 Scene 的文档命令同时创建入口、一个新输出接口和两者间的连线。尚未连接父图路由
的文档可以保存为草稿。将出口改成结局时，用 `EndStoryNode` 替代流程终点，并删除不再
需要的输出接口；这些编辑可以一次性提交。

未来支持多个入口或带数据参数的 Scene 时，只扩展接口节点和接口投影规则，不修改
`NodeLink` 格式。

## 6. 具体节点类型

第一版建议先实现以下节点：

| 类型 ID | 节点 | 所属图 | 端口语义 |
| --- | --- | --- | --- |
| `gel.project_start` | `ProjectStartNode` | root | 一个 flow 输出 |
| `gel.scene` | `SceneNode` | root | 由子图接口投影 |
| `gel.graph_input` | `GraphInputNode` | scene | 一个对内 flow 输出；投影为 Scene 输入 |
| `gel.graph_output` | `GraphOutputNode` | scene | 一个对内 flow 输入；投影为 Scene 输出 |
| `gel.dialogue` | `DialogueNode` | scene | flow 输入、文本/角色数据、flow 输出 |
| `gel.if` | `IfNode` | scene | flow 输入、boolean 输入、true/false 输出 |
| `gel.choice` | `ChoiceNode` | scene | flow 输入、多个稳定动态 flow 输出 |
| `gel.end_story` | `EndStoryNode` | scene | flow 输入；终止剧情，没有输出 |
| `gel.set_variable` | `SetVariableNode` | scene | flow 输入、变量和值数据、flow 输出 |
| `gel.get_variable` | `GetVariableNode` | scene | 变量配置、变量 data 输出 |

节点类型 ID 是文件格式和注册表协议的一部分。类名可以重命名，但类型 ID 不能在没有
迁移的情况下改变。

示例端口：

```text
IfNode
├── in: flow input
├── condition: data<boolean> input
├── true: flow output
└── false: flow output

DialogueNode
├── in: flow input
├── speaker: data<character> input
├── text: data<string> input
└── next: flow output
```

节点只声明自身的端口和参数，不知道目标节点，也不决定整个图的执行顺序。

`ChoiceNode` 每次只激活被选项对应的一个输出；导出时至少有一个有效选项，且每个选项
都有后继。`SetVariableNode` / `GetVariableNode` 通过业务参数保存变量键，数据端口类型
由项目变量声明解析，不能在连接时临时猜测。变量读操作在每次消费者激活时重新求值，
不能把可变状态读取当作整张图编译期间的常量缓存。

## 7. 注册表和节点创建

`NodeRegistry` 维护稳定类型 ID 到节点定义的映射：

```text
NodeDefinition
├── type_id
├── version
├── display_name
├── category
├── allowed_graph_kinds
├── factory
├── static port schema
└── compiler key
```

注册表负责：

- 提供节点菜单和分类元数据。
- 根据 `node_type` 创建节点。
- 校验类型版本是否可加载。
- 提供静态端口定义。
- 将节点类型交给对应的编译器。

加载文件时不能根据 GDScript 类名、文件名或脚本路径猜测节点类型。未知类型应形成
诊断信息，并保留原始数据供编辑器显示或迁移处理，不能静默创建错误节点。

未知节点用继承 `NodeMapNode` 的占位模型保留原始 type/version/data 及相关连接，不伪造
端口或执行语义。含未知类型的文档可以无损保存，但禁止编译；未解析的连接不因加载失败
而被自动删掉。根容器损坏、重复 ID 或所有权错误则使整次加载失败，不覆盖当前文档。

## 8. 数据所有权和修改规则

推荐的所有权关系：

```text
NodeMapDocument
├── NodeGraph
│   ├── NodeMapNode
│   │   └── input_values / node data
│   └── NodeLink
└── NodeRegistry
```

修改规则：

- `NodeGraph` 不把内部字典直接暴露给调用方。
- `NodeMapDocument` 保存节点和连接的明确所有权。
- 查询接口返回副本、只读投影或受控句柄，不能绕过聚合根修改关系。
- 修改节点端口、动态项或子图接口时，由文档协调连接检查；已插入的实体 ID 不可修改。
- 单个节点只校验自己的字段；跨节点规则由图或文档校验。
- 所有对用户可见的复合修改都应能作为一个原子命令进入撤销栈。

例如删除一个 `GraphOutputNode`：

```text
删除请求
    -> 找到所属 SceneGraph
    -> 找到对应 interface_id
    -> 删除该接口的父图 NodeLink
    -> 删除 SceneGraph 内部 NodeLink
    -> 删除 GraphOutputNode
    -> 一次性提交文档变更
```

不能只删除节点而留下父图中的悬空端点。

端口改名和排序保持连接；删除端口时原子清理关联连接。修改类型、方向或连接上限时先
试算，若现有连接将失效，默认拒绝整个操作并返回受影响 link_id；只有显式包含断线的
复合命令才能清理后提交，不能默默丢失用户连线。

实现统一采用“复制受影响数据 -> 应用候选变更 -> 校验结构 -> 一次提交并通知”的流程。
失败返回带 `code`、`message`、`graph_id`、`node_id`、`port_id`、`link_id` 的诊断，
不改变原文档；成功返回包含受影响 ID 和前后快照的变更结果，供宿主撤销/重做使用。
撤销栈和界面通知订阅属于控制器，文档不反向依赖 Workspace。

## 9. 序列化格式

格式标识固定为 `gel.node-map`，新容器版本从 `1` 开始。它与 Runtime Package 的
`formatVersion`、模块 API 版本和各节点的 `version` 独立计数，不能根据同为数字 `1`
就判定格式兼容。未带新格式标识的文件不按新文档猜测解析。

最小可保存草稿如下。它有根图和入口，但尚未连接 Scene，因此不能导出：

```json
{
  "format": "gel.node-map",
  "formatVersion": 1,
  "rootGraphId": "graph-root",
  "graphs": [
    {
      "graphId": "graph-root",
      "kind": "root",
      "ownerNodeId": "",
      "nodes": [
        {
          "id": "node-start",
          "type": "gel.project_start",
          "version": 1,
          "position": {"x": 0, "y": 0},
          "size": {"x": 180, "y": 100},
          "ui": {"collapsed": false, "locked": false, "titleOverride": ""},
          "enabled": true,
          "inputs": {},
          "data": {}
        }
      ],
      "links": []
    }
  ]
}
```

以下是独立记录示例，不是可单独加载的完整文档。节点公共数据和业务数据分开：

```json
{
  "id": "node-dialogue-001",
  "type": "gel.dialogue",
  "version": 1,
  "position": {"x": 320, "y": 180},
  "size": {"x": 280, "y": 160},
  "ui": {
    "collapsed": false,
    "locked": false,
    "titleOverride": ""
  },
  "enabled": true,
  "inputs": {
    "speaker": "alice",
    "text": "Hello"
  },
  "data": {}
}
```

`SceneNode` 的数据示例：

```json
{
  "id": "scene-prologue",
  "type": "gel.scene",
  "version": 1,
  "position": {"x": 160, "y": 100},
  "size": {"x": 300, "y": 180},
  "ui": {
    "collapsed": false,
    "locked": false,
    "titleOverride": ""
  },
  "enabled": true,
  "inputs": {},
  "data": {
    "sceneId": "prologue",
    "displayName": "序章",
    "childGraphId": "graph-scene-prologue"
  }
}
```

连接独立保存：

```json
{
  "linkId": "link-001",
  "sourceNodeId": "scene-prologue",
  "sourcePortId": "interface-7f2c",
  "targetNodeId": "scene-chapter",
  "targetPortId": "enter"
}
```

不保存以下派生或临时数据：

- 完整端口对象列表。
- `GraphInterface` 的缓存副本。
- Godot 控件引用。
- 选中、悬停、焦点和当前画布视口。
- 编译后的 Lua 文本。
- Runtime 中的变量值和执行栈。

`node_map/serialization/` 负责 JSON 文本与模型数据间的转换；宿主工程层负责实际
`FileAccess`、原子写盘和错误提示。加载流程为：

```text
JSON.parse -> 容器格式校验 -> 节点版本迁移 -> 创建候选文档
    -> 文档结构和接口校验 -> 整体替换当前文档
```

节点迁移必须显式注册版本路径，基于原始字典生成新字典，失败不覆盖现有数据。未知容器
版本直接拒绝加载；未知节点类型或节点版本保留占位记录并阻止编译。旧 Node Map 格式
不提供自动迁移。序列化应按稳定 ID 排序图、节点和连接，显示顺序仍只由 `order` 决定。
JSON 往返保留所有 ID，不调用产生新身份的 `duplicate_node()`。

## 10. 校验分层

### 10.1 节点本地校验

`NodeMapNode.validate_self()` 检查：

- `node_id` 非空且符合 ID 规则。
- `node_type` 与注册类型一致。
- `node_version` 是可支持的正整数。
- 位置和尺寸是有限数值，尺寸为正值。
- 本地可解析的数据输入键、值类型和默认值有效；派生输入留给上下文校验。
- 子类字段的存储类型和格式合法；未填写的必需业务参数作为导出诊断，不阻止草稿保存。
- 动态端口 ID、显示顺序和默认值合法。

### 10.2 图级校验

`NodeGraph` 的局部集合校验不读取其他图。需要端口信息的
`validate_connections(resolved_ports)` 由文档提供已解析的端口快照，检查：

- 节点 ID 和连接 ID 在图内唯一。
- 所有节点类型允许出现在当前图类型中。
- 所有连接端点存在。
- 连接方向正确。
- 端口类型兼容。
- 输入和输出连接数没有超过上限；必需连接的缺失属于导出诊断。
- 同一图内不存在跨图引用。
- `GraphInputNode` 和 `GraphOutputNode` 的接口规则满足当前图类型。
- 数据依赖没有环；纯数据循环不能借用 flow 循环的执行语义。

flow 图允许循环，因为对话重试和游戏流程循环是合法语义。Scene 内导出时拒绝从可达
节点出发不存在任何出口或剧情终点路径的封闭循环；这只是路径检查，不声称能证明每次
实际执行必然结束。根图中无法到达剧情终点的路由循环作为警告，是否允许由导出策略决定。

### 10.3 文档级校验

`NodeMapDocument.validate_self()` 检查：

- 只有一个根图，且根图存在。
- 图 ID、节点 ID 和连接 ID 分别在文档内唯一。
- 每个子图有且只有一个拥有者。
- `child_graph_id` 指向存在的图。
- 没有孤儿图或子图所有权环。
- 根图入口节点存在且类型正确。
- Scene 的 `scene_id` 在文档内唯一。
- 复合节点的外部端口与子图接口一致。
- 父图中没有指向已删除接口的连接。
- 子图派生输入及变量类型解析所需的只读项目声明与现有连接兼容。

结构有效和可编译必须分开：缺少必需连线、未填写台词、未选择变量和没有执行终点等
未完成状态可以保存。重复身份、悬空的已知端点和错误子图所有权不能提交。未知节点的
未解析端口属于第 7 节的保留模式，不应误报为已经解析的合法连接。

### 10.4 项目和导出级校验

项目层或导出器负责：

- 角色、变量和资源 ID 是否存在。
- 资源路径和脚本资源是否存在。
- Runtime Package 的 manifest 是否完整。
- 编译后的 IR 是否可以生成合法 Lua。
- Runtime Package 的版本和目标引擎约束。
- 根入口恰好连接到一个 Scene，所有已启用 Scene 的子图均可编译。
- 每个公开出口有且只有一个目标 Scene，未连接出口不是隐式结局。
- 可达执行节点的必需输入和每个分支出口完整；未知类型和被引用的禁用节点阻止导出。

未参与执行的普通节点给出未使用警告，不产生执行 IR；未知类型仍按第 7 节阻止整个文档
编译。结构诊断和编译诊断使用同一定位格式，并包含 `severity`，便于画布定位。

Node Map 模型不直接读取资源目录，也不执行 Lua。

## 11. 编译边界

编译分为三个阶段：

```text
NodeMapDocument
    -> 图结构和节点数据校验
    -> RootGraph / SceneGraph IR
    -> Runtime Package manifest 和每个 Scene 的 main.lua
```

节点父类不直接拼接最终 Lua。`NodeRegistry` 提供类型到编译器的映射，统一编译器负责：

- 按图分析控制流和数据依赖。
- 处理 `SceneNode` 的子图调用和输出接口。
- 把 `IfNode`、`ChoiceNode` 等降级为运行时 IR。
- 最后由 Runtime 适配器生成 Lua 或其他运行格式。

第一版 IR 至少要能表示以下内容：

```text
ProjectIR: entry_scene_id, scenes, routes
SceneIR: scene_id, entry_block_id, blocks, exits
BlockIR: block_id, operations, terminator
terminator: jump / branch / choice / scene_exit / end_story
```

为每个可达执行节点建立基本块，使用显式跳转保存分支、合流和循环。不要递归展开 flow
直到结束，否则循环图无法编译。数据表达式按依赖顺序在消费者激活时求值；当前变量值
不属于编译常量。Lua 发射器可使用基本块状态机，不要求输入图可表示成嵌套的 if 树。

与现有 [Runtime Scene](../../engine/src/scene/README.md) 和
[Runtime Package](../../engine/src/package/README.md) 的对应关系：

| 编辑器数据 | 导出结果 |
| --- | --- |
| 根入口所连 Scene | `manifest.entryScene` |
| `SceneNode.scene_id` / `display_name` | Scene 的 `id` / `title` |
| 导出器选择的包内脚本路径 | 显式 `mainScript` |
| `GraphOutputNode.interface_id` | `Scene.exits` 元素，以及 Lua `ctx.flow:exit(...)` 的参数 |
| 父图出口连接 | `routes[source_scene_id][interface_id] = target_scene_id` |
| `EndStoryNode` | `ctx.flow:end_story()`，不声明命名出口和路由 |

接口 ID 在出口协议中作为稳定字符串保留，但边界节点、图和连接对象不进入 Runtime。
不能用可修改的 `display_name` 代替出口键。Scene 第一版不支持 data 参数或多个入口，
与当前 Runtime 的单入口路由契约一致。

Runtime 的 `cast` 仍是舞台操作白名单。第一批台词、条件、变量节点不要求舞台操作，
可以导出空 `cast`；以后加入舞台节点时，从可静态确定的角色资源引用生成白名单。
角色可能值无法静态确定时，应产生诊断或要求显式声明，不能悄悄取消 Runtime 的权限检查。

编译器接收只读文档快照和角色、变量、资源目录，返回 `success`、`diagnostics` 和成功时
的 IR。导出器再生成 manifest 与脚本文本集合；有错误时不产生可发布包、不覆盖已有文件。
字符串转义、标识符分配和 Lua 预编译由发射器及宿主完成，不直接拼接用户标题为 Lua 代码。

条件逻辑始终是 SceneGraph 中的普通节点，不会再次形成独立的特殊树模型。

## 12. 复制、删除和导航

### 12.1 复制

复制 `SceneNode` 时必须深复制其子图：

```text
复制 SceneNode
    -> 创建新的 SceneNode.node_id
    -> 由调用方提供或分配新的唯一 scene_id
    -> 创建新的 child_graph_id
    -> 深复制 SceneGraph 中的节点和连接
    -> 重映射所有新节点 ID 和连接 ID
    -> 保留固定入口 enter，为输出接口生成新 ID 并记录映射
    -> 不复制原 SceneNode 在父图中的连接
```

固定对内端口 `in` / `out` 和静态端口 ID 不改变。接口 ID 的新值只更新接口字段和使用
接口身份的引用，不能盲目替换任意业务字符串。新 Scene 位于不同子图，入口继续使用
`enter` 并不共享对象；真正需要隔离的是所有可变节点数据和子图所有权。

复制普通节点只复制节点数据和布局，不复制指向原节点的连接。在同一子图中复制输出
边界节点时必须分配新接口 ID；入口节点不能单独复制。批量复制选择集时，仅复制两个
端点都在选择集内的连接，通过 node_id 和必要的 port_id 映射重建，不带入边界外连接。
复制 Scene 时的子图深复制复用这套规则，所有映射在原子提交前完成。

### 12.2 删除

删除 `SceneNode` 时，文档必须同时删除：

- 父图中与该节点相连的所有 `NodeLink`。
- 该节点拥有的子图。
- 子图中的所有节点和连接。
- 指向被删除接口的任何派生连接。

根入口和仍被拥有的子图入口不能单独删除。删除最后一个 Scene 或输出接口可以留下
待连接、待补终点的草稿，编译诊断随之更新，但必须保留合法所有权且清理全部已知连接。
撤销恢复原 ID、子图和连接，不重新调用创建命令生成身份。

### 12.3 展开和返回

进入 Scene 子图是视图层的导航动作：

```text
用户双击 SceneNode
    -> Workspace 读取 child_graph_id
    -> Canvas 显示对应 NodeGraph
    -> Breadcrumb 显示 Root / Scene
```

导航栈、当前图、缩放和选中状态不写进 `NodeMapNode`，也不改变模型所有权。

## 13. 视图和编辑器集成

宿主 UI 负责：

- 把 `NodeMapNode` 映射成 Godot `GraphNode`。
- 根据 `PortSpec` 创建端口控件。
- 把拖动、连接、删除和参数编辑转换成 `NodeMapDocument` 命令。
- 监听文档变更并刷新图视图。
- 提供 Scene 展开、返回和面包屑导航。

Godot GraphEdit 回调中的整数端口索引只属于视图。每次构建视图时维护输入/输出索引到
稳定 port_id 的映射，连接请求先转换为模型端点；节点端口重排后重建映射和可视连线，
不能把 Godot slot 下标写入 NodeLink。视图只缓存绘制状态，文档仍是业务数据的唯一来源。

视图不能：

- 直接修改 `NodeGraph` 的私有字典。
- 自己决定端口是否兼容。
- 自己保存第二份节点数据。
- 在 UI 中执行 Runtime 或生成最终 Lua。

## 14. 推荐目录

代码实现时按职责创建文件：

```text
editor/
├── node_map/
│   ├── node_map.gd                 # 模块入口和公共类型导出
│   ├── model/
│   │   ├── node_map_node.gd        # 公共父类
│   │   ├── subgraph_node.gd        # 子图节点父类
│   │   ├── port_spec.gd            # 端口定义
│   │   ├── graph_interface.gd      # 子图接口投影
│   │   ├── node_link.gd            # 通用连接
│   │   ├── node_graph.gd           # 局部图容器
│   │   └── node_map_document.gd    # 文档聚合根
│   ├── nodes/
│   │   ├── project_start_node.gd
│   │   ├── graph_input_node.gd
│   │   ├── graph_output_node.gd
│   │   ├── scene_node.gd
│   │   ├── dialogue_node.gd
│   │   ├── if_node.gd
│   │   ├── choice_node.gd
│   │   ├── end_story_node.gd
│   │   ├── set_variable_node.gd
│   │   └── get_variable_node.gd
│   ├── registry/
│   │   ├── node_definition.gd
│   │   └── node_registry.gd
│   ├── serialization/
│   │   ├── node_map_reader.gd
│   │   └── node_map_writer.gd
│   └── compiler/
│       ├── node_map_compiler.gd
│       └── runtime_ir.gd
└── tests/
    └── node_map/
```

只有在职责真正需要时才创建对应文件。视图实现放在宿主 UI 层，不放进纯模型目录。

## 15. 实现顺序

```text
1. NodeMapNode + PortSpec
2. NodeLink + NodeGraph
3. NodeMapDocument 的所有权和原子变更
4. NodeRegistry + ProjectStartNode
5. GraphInputNode / GraphOutputNode + GraphInterface
6. SceneNode + SceneGraph 深复制和删除
7. DialogueNode / IfNode / ChoiceNode / EndStoryNode / 变量节点
8. 文档序列化和版本迁移
9. Node Map Canvas 视图
10. Runtime IR 和 Lua 导出
```

每一步都先补充纯模型测试，再接入 Godot 视图。第一阶段不恢复旧版条件树或专用路由
对象，也不为旧 JSON 提供隐式兼容。

最低测试矩阵：

- 公共字段、注册类型、本地参数、静态与动态端口校验。
- 方向、值类型、连接数、重复连接、非法跨图连接和数据环拒绝。
- flow 合流、分支、带终点路径的循环及禁用节点诊断。
- 固定入口、接口 ID 作用域、改名和排序保持父图连接。
- 动态端口删除清理，类型变更拒绝后的原状态保持。
- 普通节点和 Scene 深复制、批量复制的 ID 重映射及无共享可变数据。
- Scene 删除、子图所有权、失败事务不改变原文档及撤销恢复。
- JSON 往返身份不变、默认值与 null 区分、未知节点保留及版本拒绝。
- 草稿保存与导出校验分离，EndStory 编译、完整路由和 Runtime Package 加载。

## 16. 当前结论

新的核心关系固定为：

```text
NodeMapDocument
    owns NodeGraph
        owns NodeMapNode and NodeLink

SceneNode extends SubgraphNode
    references child NodeGraph by child_graph_id

GraphInputNode / GraphOutputNode
    define the child graph interface

NodeMapNode
    is the only common parent for all canvas nodes
```

`Scene` 是普通节点，但它的端口来自子图接口；进入 Scene 只是打开同一文档中的另一个
`NodeGraph`。这套边界能够保持 ComfyUI 式节点协议，同时保留 Runtime Scene 的编译边界。
