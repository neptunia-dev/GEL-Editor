# SceneNode 设计

> 状态：新 Node Map 设计阶段，尚未实现。
>
> `SceneNode` 是一个继承 `SubgraphNode` 的普通画布节点。它出现在项目根图中，代表一个
> Runtime Scene；双击后可以进入它所拥有的子图，编辑对话、条件、选择和动作节点。
>
> 本文只定义 `SceneNode` 的节点契约。文档级所有权、通用端口、连接和复合节点规则见
> [Node Map 重设计与文件架构](node-map-file-architecture.md)。

## 1. 设计目标

`SceneNode` 同时具有两个身份：

```text
RootGraph 中的普通节点
    -> 可以被移动、复制、连接和删除

SubgraphNode
    -> 通过 child_graph_id 指向一张 SceneGraph
    -> 可以展开进入内部流程图
```

它不是一个特殊的路由容器，也不拥有条件树、出口数组或目标 Scene。Scene 的输入和输出
端口由子图中的接口节点投影到父图。

```text
RootGraph

ProjectStart -> SceneNode: Prologue -> SceneNode: Chapter
                         │
                         ├── continue
                         └── retry

SceneGraph(Prologue)

GraphInput: enter -> Dialogue -> If
                              ├── true  -> GraphOutput: continue
                              └── false -> GraphOutput: retry
```

## 2. 继承关系

```text
NodeMapNode
└── SubgraphNode
    └── SceneNode
```

`NodeMapNode` 提供所有画布节点共有的实例身份、布局、输入值、复制、序列化和本地校验
契约。`SubgraphNode` 只增加子图引用：

```text
child_graph_id: String
```

`SceneNode` 不直接持有 `NodeGraph` 对象。`NodeMapDocument` 才是所有图的所有者。

## 3. 字段设计

### 3.1 公共节点字段

这些字段由 `NodeMapNode` 提供，`SceneNode` 不重复声明：

```text
node_id          文档内稳定唯一的节点实例 ID
node_type        固定为 gel.scene
node_version     SceneNode 数据版本
position         根图中的画布位置
size             根图中的显示尺寸
collapsed        是否折叠
locked           是否锁定布局
enabled          是否允许进入执行编译结果
title_override   可选的编辑器标题覆盖
input_values     数据输入的本地值；第一版 Scene 只有 flow 接口，固定为空
```

### 3.2 SceneNode 自身字段

```text
scene_id         Runtime Scene 的稳定 ID
display_name     编辑器和运行时显示名称
child_graph_id   SceneGraph 的稳定 ID
```

`scene_id` 与 `node_id` 必须分离：

- `node_id` 识别编辑器中的节点实例。
- `scene_id` 识别 Runtime 中的场景。
- 修改 `scene_id` 不改变节点位置、父图连接或 `node_id`。
- `scene_id` 在整个文档中必须唯一。

`display_name` 只用于显示和诊断，不参与连接身份。父图端口的显示名称来自子图接口的
`display_name`，接口身份使用稳定 `interface_id`。

### 3.3 不属于 SceneNode 的字段

以下数据不再放进 `SceneNode`：

```text
独立的出口列表或条件树
目标 Scene 或父图连接
SceneGraph 对象本身
手写 main.lua 路径
运行时变量、角色状态和执行栈
Godot GraphNode 控件
```

Scene 的运行脚本是子图编译结果，由导出器按照 Runtime Package 规则生成。节点模型不
读取文件，也不保存编译后的 Lua 文本。

## 4. Scene 子图接口

### 4.1 输入接口

第一版每个 SceneGraph 必须有且只有一个入口：

```text
GraphInputNode
├── interface_id = enter
├── display_name = Enter
└── out: flow output -> SceneGraph 内部第一个节点
```

从父图看，`SceneNode` 暴露一个 `enter` 输入端口。根图的 `ProjectStartNode` 或其他
SceneNode 可以连接到它。

`enter` 是保留接口 ID，不是从显示名称推导的文本。它投影为父图 flow 输入，允许多条
来自不同前驱的连接；内部 `out` 端口最多连接一个后继，不能混用外部和内部端口 ID。

### 4.2 输出接口

SceneGraph 可以有多个命名出口：

```text
GraphOutputNode(interface_id=interface-7f2c, display_name=Continue)
GraphOutputNode(interface_id=interface-a93d, display_name=Retry)
```

每个出口节点至少有：

```text
interface_id    子图内稳定唯一的接口 ID，也是父图 port_id
display_name    显示名称
order           显示顺序，不参与连接身份
in              固定对内 flow 输入端口，允许多个前驱
```

修改 `display_name` 不会改变 `interface_id`，所以父图连接保持不变。输入和输出的
interface_id 共用子图命名空间，输出不能占用保留值 `enter`。

父图看到的 SceneNode 输出端口是 `GraphOutputNode` 的只读投影：

```text
SceneNode output port
    port_id     = GraphOutputNode.interface_id
    display_name = GraphOutputNode.display_name
    kind        = flow
    max_connections = 1
```

`SceneNode` 不缓存这份投影。`NodeMapDocument` 或独立的接口解析器在需要时从
`child_graph_id` 读取子图并计算当前接口。

第一版 Scene 不开放 data 接口或多个入口。每个对外输出在导出时必须恰好连接一个目标
Scene；未连线的出口是草稿错误，不表示故事结束。`EndStoryNode` 才表示剧情结束，它
没有输出端口，不投影为 Scene 的公开接口，因此结局 Scene 可以完全没有命名出口。

### 4.3 接口变更

修改、删除或复制接口时必须保持 ID 规则：

```text
修改 display_name
    -> 保留 interface_id
    -> 父图连接不变

删除 GraphOutputNode
    -> 删除父图中引用该 interface_id 的 NodeLink
    -> 删除子图内部相关 NodeLink
    -> 原子提交

复制 SceneNode
    -> 复制子图和接口节点
    -> 保留固定入口 enter，为输出接口生成新的 interface_id
    -> 不复制原 Scene 在父图中的 NodeLink
```

不能用出口显示名称、数组顺序或隐藏字符串拼接结果作为接口身份。

接口类型、方向或连接数变更先检查所有内部和父图连接；不兼容时默认拒绝整个操作。
只有明确包含断线的文档命令才能清理这些连接。第一版 Scene 的 flow 边界类型不可编辑。

## 5. SceneNode 端口

SceneNode 的端口按来源分为两类：

```text
输入端口
    SceneGraph 的 GraphInputNode 投影

输出端口
    SceneGraph 的 GraphOutputNode 投影
```

第一版的固定形态是：

```text
input:
    enter: flow

outputs:
    由子图中的 GraphOutputNode 动态决定
```

端口的 `port_id` 必须稳定；端口的显示文本可以编辑。父图的 `NodeLink` 仍然使用统一
格式：

```text
source_node_id
source_port_id
target_node_id
target_port_id
```

父图连接只能连接到 SceneNode 的公开端口，不能直接连接到 SceneGraph 的内部节点。

## 6. SceneNode 的本地校验

`SceneNode.validate_self()` 只检查自身字段：

- `node_id` 非空且格式合法。
- `node_type` 为 `gel.scene`。
- `node_version` 是受支持的正整数。
- `scene_id` 非空且符合 Runtime ID 规则。
- `display_name` 满足标题规则。
- `child_graph_id` 非空。
- `position` 和 `size` 为有限数值。
- 第一版只有 flow 接口，因此 `input_values` 必须为空。

以下结构检查属于 `NodeMapDocument` 或由文档提供端口快照的 `NodeGraph`：

- `scene_id` 是否和其他 SceneNode 重复。
- `child_graph_id` 是否存在。
- 子图是否由当前 SceneNode 唯一拥有。
- 子图入口是否唯一、接口 ID 是否冲突。
- 父图连接的端口是否仍然存在。
- 根图和子图之间是否存在非法跨图连接。

SceneGraph 的终点可达性、必需输入、公开出口路由完整性属于导出校验，不阻止保存
结构完整的编辑草稿。未来 Scene 支持 data 接口后，由文档解析子图再校验对应输入值，
SceneNode 不能为了本地校验而持有或自行查询子图。

## 7. SceneGraph 最低结构

第一版 SceneGraph 的结构约束：

```text
一个 GraphInputNode(interface_id = enter)
零个或多个 GraphOutputNode
零个或多个业务节点
```

允许的内部业务节点包括：

```text
DialogueNode
IfNode
ChoiceNode
EndStoryNode
SetVariableNode
GetVariableNode
```

它们全部继承 `NodeMapNode`，通过 `NodeLink` 连接。`IfNode` 本身就是一个普通节点：

```text
IfNode
├── in: flow input
├── condition: data<boolean> input
├── true: flow output
└── false: flow output
```

创建命令会同时创建入口、默认输出接口及其内部连线。用户可以把输出替换为
`EndStoryNode`，表示不再进入下一个 Scene。编辑过程允许临时断线和缺少终点；导出时
每个可达流程节点必须存在到出口或剧情终点的路径，每条分支也必须完整。

SceneGraph 可以包含 flow 循环，导出时拒绝可达且没有任何终点路径的封闭循环；数据
依赖不允许循环。多个 flow 前驱进入同一输入表示多条可选执行路径，不是并行汇合。

## 8. SceneNode 的操作契约

以下是接口签名示意，不是可直接运行的 GDScript。`SceneNode` 的本地 API 用于构建
脱离文档的候选数据；已经插入文档的实例不能绕过聚合根修改：

```gdscript
func set_scene_id(new_scene_id: String) -> bool
func set_display_name(new_display_name: String) -> bool
func validate_self() -> Array
func duplicate_node() -> NodeMapNode
func serialize_data() -> Dictionary
```

涉及父图、子图或连接的操作必须由 `NodeMapDocument` 提供：

```gdscript
func create_scene_node(scene_id: String) -> Dictionary
func update_scene(node_id: String, changes: Dictionary) -> Dictionary
func duplicate_scene_node(node_id: String, new_scene_id: String) -> Dictionary
func delete_scene_node(node_id: String) -> Dictionary
func get_child_graph_id(scene_node_id: String) -> String
func connect_nodes(graph_id: String, link: NodeLink) -> Dictionary
```

变更结果统一包含 `success`、`diagnostics`，成功时附新建 ID 和前后快照。创建 Scene
总是插入根图；`update_scene` 只允许名称、业务 ID、布局等受控字段，不允许直接替换
child_graph_id。子图引用只能由文档生命周期操作设置并同时维护 `owner_node_id`。

`duplicate_node()` 只返回脱离文档且 child_graph_id 为空的副本草稿，不完成 Scene
深复制。`duplicate_scene_node()` 才能创建拥有独立子图的有效 Scene。查询子图 ID
没有导航副作用，实际打开画布由 Workspace 处理，不能返回可被绕过文档修改的图句柄。

## 9. 复制和删除

### 9.1 复制 SceneNode

复制应作为一个文档级原子操作：

```text
原 SceneNode
    -> 新 node_id
    -> 新 scene_id，或由调用方提供唯一 scene_id
    -> 新 child_graph_id
    -> 深复制 SceneGraph 内所有节点
    -> 深复制 SceneGraph 内所有 NodeLink
    -> 重映射子图节点 ID 和连接 ID
    -> 保留 enter 和固定对内端口，为输出接口生成新 ID
    -> 保留业务数据和画布布局
    -> 不复制父图中的连接
```

复制后的 Scene 不能继续引用原 Scene 的子图或内部节点对象。接口 ID 只要求子图内唯一，
保留固定入口 enter 不会共享状态；普通输出分配新 ID，防止后续批量复制误用旧身份。
复制只更新已声明的 ID 引用，不替换台词或任意业务字符串中的同名文本。

### 9.2 删除 SceneNode

删除应由 `NodeMapDocument` 协调：

```text
删除父图中的 SceneNode
    -> 删除父图相关 NodeLink
    -> 删除 child_graph_id 对应 SceneGraph
    -> 删除子图内部所有节点和连接
    -> 保留根入口并检查其他子图的所有权
    -> 一次性提交
```

删除失败时，文档及其连接必须保持原状。

允许删除最后一个 Scene，根图只保留 ProjectStartNode，成为不可导出的空白草稿。
删除入口连线或出口后产生的流程缺口由导出诊断提示，不能为了保持连通而阻止正常编辑。
撤销删除应恢复原 ID 和连接，不能用创建新 Scene 的命令代替恢复。

## 10. 编辑器数据示例

以下记录属于同一示例的片段，不是完整文档。容器格式和加载规则见
[Node Map 序列化格式](node-map-file-architecture.md#9-序列化格式)。

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

对应子图接口节点：

```json
{
  "id": "output-prologue-retry",
  "type": "gel.graph_output",
  "version": 1,
  "position": {"x": 720, "y": 260},
  "size": {"x": 220, "y": 100},
  "ui": {
    "collapsed": false,
    "locked": false,
    "titleOverride": ""
  },
  "enabled": true,
  "inputs": {},
  "data": {
    "interfaceId": "interface-a93d",
    "displayName": "重试",
    "order": 0
  }
}
```

对应根图连接：

```json
{
  "linkId": "link-scene-retry",
  "sourceNodeId": "scene-prologue",
  "sourcePortId": "interface-a93d",
  "targetNodeId": "scene-prologue",
  "targetPortId": "enter"
}
```

这里的 `interface-a93d` 是接口 ID，不是显示名称；父图连接表示重新进入当前 Scene。
若显示名称从“重试”改为“再试一次”，连接不需要改动。

## 11. Runtime 转换边界

SceneNode 不直接生成 Runtime 数据。编译流程由文档和导出器完成：

```text
SceneNode.scene_id
    -> Runtime Scene ID

SceneGraph
    -> Scene 的运行时控制流和数据流 IR

GraphOutputNode.interface_id
    -> Scene.exits 和 ctx.flow:exit(interface_id)

EndStoryNode
    -> ctx.flow:end_story()，不声明命名出口

RootGraph NodeLink
    -> Runtime Scene 之间的路由
```

导出器生成对应 Runtime Scene、显式 `mainScript` 和脚本内容。接口 ID 会作为稳定
出口键进入 Runtime；编辑器的 `node_id`、`graph_id`、`link_id` 和布局仅用于源映射，
不作为运行协议必需字段。每个已声明出口必须有恰好一个目标路由，结局 Scene 可以
导出 `exits: []` 并由 `EndStoryNode` 结束。

`cast` 仍遵守 Runtime 的舞台操作白名单规则，由编译器从静态舞台角色引用收集；第一版
没有舞台节点时可以为空。详细 IR、路由和角色规则见
[Node Map 编译边界](node-map-file-architecture.md#11-编译边界)。

## 12. 与 UI 的边界

SceneNode 是纯 `RefCounted` 模型，不继承 Godot `GraphNode`。视图层可以：

- 显示 Scene 的 `display_name` 和 `scene_id`。
- 根据解析后的 `GraphInterface` 绘制输入/输出端口。
- 把拖动位置写入文档命令。
- 响应双击并请求 Workspace 打开 `child_graph_id`。
- 显示子图入口和出口的连接状态。

视图层不能：

- 自己维护一份 SceneGraph。
- 自己决定接口是否存在。
- 直接修改 `NodeMapDocument` 的内部字典。
- 把当前进入的子图和导航栈写入 SceneNode；画布节点自身的 collapsed 仍是持久布局字段。
- 直接执行 Lua 或修改 Runtime 状态。

## 13. 测试重点

`SceneNode` 的纯模型测试应覆盖：

- 公共字段和 `gel.scene` 类型 ID。
- `scene_id`、`display_name`、`child_graph_id` 的本地校验。
- 节点复制时不共享可变数据。
- SceneNode 序列化不包含 NodeLink 和 Godot UI 引用。
- 子图接口投影生成稳定的父图端口。
- 修改接口显示名称不会破坏父图连接。
- 删除输出接口会原子清理父图连接。
- 复制 Scene 会重映射子图节点、连接和输出接口 ID，保留 enter 及固定对内端口。
- 删除 Scene 会删除完整子图且不会留下孤儿图。
- 非法跨图连接被拒绝。
- 未完成的图可保存但不能导出，未连接出口不被隐式编译为结局。
- EndStoryNode 生成剧情终点，无输出的结局 Scene 可以导出。
- 失败变更不污染原文档，撤销恢复完整子图和原身份。

## 14. 当前结论

```text
SceneNode
    extends SubgraphNode
    appears as a normal node in RootGraph
    owns no NodeGraph object
    exposes the interface of its child SceneGraph
```

`SceneNode` 的最小稳定契约只有 `scene_id`、`display_name` 和 `child_graph_id`，其余
通用能力来自 `NodeMapNode`，其父图连接由 `NodeMapDocument` 管理，其内部流程由
`NodeGraph` 管理，编译结果由导出层生成。
