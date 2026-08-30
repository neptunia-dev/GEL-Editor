# Node Map 文件架构设计

> 状态：v2 已落地。RouteEdge 已支持 `scene_exit` 与 `condition_branch` 两种互斥源端点；
> 条件树、原子删除和隐藏 Runtime exit 的当前契约见
> [condition/README.md](condition/README.md)。下文保留的初版设计说明只适用于普通 ExitPort。
>
> 当前范围：实现 `RouteEdge` 和 `SceneMap` 的领域模型、受控数据访问和跨 Node 校验。
>
> 已有范围：单个 `SceneNode`、`CastMember` 和 `ExitPort` 已经落地。
>
> 当前不包含：Godot UI、View、完整工程文件读写和 Lua 执行。

## 1. 设计目标

单个 `SceneNode` 只描述一个 Scene 自身的数据。`SceneMap` 层负责把多个
`SceneNode` 组织成一张剧情图，并保存 Scene 之间的路由关系。

```text
CastMember / ExitPort
          |
          v
      SceneNode
          |
          +----------------+
          |                |
          v                v
      RouteEdge       SceneMap
```

Map 层需要解决的问题：

- 管理多个 SceneNode。
- 管理 SceneNode 之间的 RouteEdge。
- 通过稳定 ID 找到节点和出口。
- 保证节点、Scene ID 和连线 ID 的唯一性。
- 保证连线引用有效的 Node 和 ExitPort。
- 保存入口 Node 的编辑器身份。
- 删除 Node 时清理相关连线。
- 进行跨 Node 的图结构校验。
- 为后续编辑器序列化和 Runtime Package 导出提供数据入口。

## 2. 推荐目录结构

### 2.1 当前阶段

当前 Map 层已经实现 `map/scene_map.gd` 和 `map/route_edge.gd`；其他未来文件仍按需创建。
当前模块作为独立代码子模块发布，测试由宿主工程或独立验证工程维护。

```text
editor/
├─ README.md
└─ node_map/
   ├─ node_map.gd
   ├─ cast_member.gd
   ├─ exit_port.gd
   ├─ scene_node.gd
   ├─ scene-node-design.md
   ├─ map-file-architecture.md
   └─ map/
      ├─ scene_map.gd       # 已实现
      └─ route_edge.gd       # 已实现
```

选择 `node_map/map/` 的原因：

- `node_map/` 是整个 Node Map 功能模块的根目录。
- 根目录下的三个文件描述单个 Node 的组成部分。
- `map/` 子目录专门放“多个 Node 组成图”的对象。
- 不把 `SceneMap` 误命名为通用的 `map.gd`，避免和 Godot 或其他地图概念混淆。

### 2.2 Map 功能增加后的目标结构

当 Map 的序列化和校验需求出现后，再逐步扩展为：

```text
editor/
├─ project.godot
├─ node_map/
│  ├─ cast_member.gd
│  ├─ exit_port.gd
│  ├─ scene_node.gd
│  ├─ scene-node-design.md
│  ├─ map-file-architecture.md
│  │
│  ├─ map/
│  │  ├─ scene_map.gd
│  │  └─ route_edge.gd
│  │
│  ├─ validation/            # 需要丰富诊断信息时再增加
│  │  ├─ map_diagnostic.gd
│  │  └─ node_map_validator.gd
│  │
│  ├─ serialization/         # 需要独立工程读写时再增加
│  │  ├─ node_map_reader.gd
│  │  ├─ node_map_writer.gd
│  │  └─ runtime_scene_adapter.gd
│  │
│  └─ view/                  # 开始做 Godot 画布时再增加
│     ├─ scene_node_view.gd
│     └─ scene_map_view.gd
│
└─ tests/
   └─ node_map/
      ├─ scene_node_smoke.gd
      ├─ route_edge_smoke.gd
      ├─ scene_map_smoke.gd
      └─ fixtures/
```

这些后续目录不是现在的实现要求。目录只在对应职责真正出现时创建。

## 3. 文件职责

### 3.1 `cast_member.gd`

类名：`CastMember`

职责：

- 保存角色在当前 Scene 中的局部绑定。
- 保存 `character_id`、`role` 和 `display_name`。
- 检查自身字段格式。
- 转换为编辑器字典和 Runtime Scene.cast 字典。
- 返回自身的独立副本。

不负责：

- 管理项目中的全部角色。
- 验证角色 ID 是否存在于项目。
- 保存角色的运行时立绘和显示状态。
- 管理 Scene 之间的关系。

### 3.2 `exit_port.gd`

类名：`ExitPort`

职责：

- 保存一个本地出口的稳定 `port_id`。
- 保存出口的运行时名称 `name`。
- 支持出口名称修改。
- 检查自身字段格式。
- 转换为编辑器字典或运行时出口名称。

不负责：

- 保存目标 Scene。
- 创建或删除连线。
- 判断出口是否在当前 Node 中重名。
- 判断出口是否已经连接。

### 3.3 `scene_node.gd`

类名：`SceneNode`

职责：

- 表示一个编辑器 Scene Node。
- 保存 `node_id`、`scene_id`、标题、脚本路径和画布位置。
- 管理当前 Scene 的 CastMember 列表。
- 管理当前 Scene 的 ExitPort 列表。
- 执行单个 Node 的本地校验。
- 生成编辑器数据和 Runtime Scene 数据。

不负责：

- 管理其他 SceneNode。
- 保存出口目标。
- 设置整个图的入口。
- 检查其他 Node 的 Scene ID 是否重复。
- 判断图的可达性。
- 绘制 Godot 控件。

详细定义见：[scene-node-design.md](scene-node-design.md)。

### 3.4 `map/route_edge.gd`

类名：`RouteEdge`

一个 `RouteEdge` 表示一条编辑器路由连线。

建议字段：

```text
edge_id: String
source_node_id: String
source_port_id: String
target_node_id: String
```

字段含义：

- `edge_id`：编辑器内部的连线 ID，建议使用 UUID。
- `source_node_id`：起点 SceneNode 的 `node_id`。
- `source_port_id`：起点 SceneNode 中某个 ExitPort 的 `port_id`。
- `target_node_id`：终点 SceneNode 的 `node_id`。

当前不需要 `target_port_id`，因为一个 SceneNode 暂时只有一个默认输入端口。

`RouteEdge` 不应该直接持有 `SceneNode` 对象引用，而应该保存稳定 ID，原因是：

- 便于 JSON 序列化。
- 便于撤销和重做。
- 避免 Node 和 Edge 相互持有导致循环引用。
- Node 被重新组织时，引用关系仍然是明确的。

`RouteEdge` 不负责：

- 检查引用的 Node 是否存在。
- 检查 `source_port_id` 是否属于起点 Node。
- 决定同一个出口是否允许多条边。
- 解析运行时 Scene ID。

这些都是 `SceneMap` 的职责。

### 3.5 `map/scene_map.gd`

类名：`SceneMap`

`SceneMap` 是 Map 层的聚合根。所有 Node 和 Edge 的增删改关系，都应该经过
`SceneMap`，而不是让外部直接修改内部字典。

建议保存的数据：

```text
_nodes: Dictionary[node_id, SceneNode]
_edges: Dictionary[edge_id, RouteEdge]
_entry_node_id: String
```

入口使用 `node_id`，不直接保存 `scene_id`：

```text
entry_node_id -> SceneNode -> scene_id
```

这样用户修改 Scene ID 时，入口仍然指向同一个编辑器 Node。

`SceneMap` 负责：

- 添加和删除 Node。
- 按 `node_id` 查找 Node。
- 检查 `node_id` 是否重复。
- 检查 `scene_id` 是否与其他 Node 重复。
- 设置和清除入口 Node。
- 添加和删除 RouteEdge。
- 检查 `edge_id` 是否重复。
- 检查 Edge 的源 Node、源出口和目标 Node 是否存在。
- 保证同一个源出口最多有一条出边。
- 删除 Node 时清理所有相关 Edge。
- 转发或执行跨 Node 的图校验。
- 把编辑器 ID 解析为 Runtime Package 所需的 Scene ID 和出口名称。

`SceneMap` 不负责：

- 直接绘制 GraphEdit。
- 执行 Lua。
- 读取或复制资源文件。
- 验证 Lua 源码语法。
- 处理角色全局定义。
- 直接访问操作系统文件系统。

## 4. 依赖方向

依赖应该保持单向：

```text
CastMember       ExitPort
      \           /
       \         /
        -> SceneNode
              |
              v
          RouteEdge
              |
              v
           SceneMap
```

更准确地说：

```text
cast_member.gd       -> 无本模块依赖
exit_port.gd         -> 无本模块依赖
scene_node.gd        -> CastMember, ExitPort
route_edge.gd        -> 只保存 ID，不依赖 SceneNode 实例
scene_map.gd         -> SceneNode, RouteEdge
```

不允许的方向：

```text
SceneNode -> SceneMap
ExitPort  -> SceneMap
RouteEdge -> Godot GraphEdit 控件
SceneMap  -> SceneNodeView
```

领域模型不应反向依赖 UI。UI 应该读取模型并把用户操作转交给模型。

## 5. 数据所有权

推荐的所有权关系：

```text
SceneMap
├─ 拥有 SceneNode 集合
│  ├─ SceneNode
│  │  ├─ 拥有 CastMember 集合
│  │  └─ 拥有 ExitPort 集合
│  └─ ...
└─ 拥有 RouteEdge 集合
```

具体规则：

- `SceneNode` 加入 Map 时，Map 应保存 Node 的明确所有权副本，或明确规定 Node
  不再由外部修改；两种策略需要在实现前选定一种。
- `SceneNode.get_cast()` 和 `SceneNode.get_exits()` 继续返回副本。
- `SceneMap.get_node()` 不应让调用方绕过 Map 修改全局关系。
- Edge 只保存 ID，不持有 Node 的可变对象引用。
- 外部不能直接取得 `_nodes` 或 `_edges` 字典。

建议第一版继续沿用当前 Node 的副本策略：

```text
传入 Map 的 Node -> Map 保存副本
Map 返回 Node      -> 返回副本或只读访问接口
```

这样数据边界清晰，但会增加更新 Node 的接口需求。实现 `SceneMap` 时需要在“副本模型”和
“受控可变对象模型”之间明确选择，不要混用。

## 6. SceneMap 的编辑器数据

编辑器工程中的 Map 只保存编辑器所需的数据：

```json
{
  "entryNodeId": "node-001",
  "nodes": [
    {
      "nodeId": "node-001",
      "sceneId": "prologue",
      "title": "序章",
      "mainScript": "scenes/prologue/main.lua",
      "cast": [],
      "exits": [],
      "position": {
        "x": 120,
        "y": 80
      }
    }
  ],
  "edges": [
    {
      "edgeId": "edge-001",
      "sourceNodeId": "node-001",
      "sourcePortId": "exit-001",
      "targetNodeId": "node-002"
    }
  ]
}
```

这里保留：

- `nodeId`。
- 出口的 `portId`。
- 画布坐标。
- Edge 的 `edgeId`。
- `entryNodeId`。

## 7. Runtime Package 的转换边界

Runtime Package 不直接使用编辑器 Node 和 Edge 的 ID。

转换关系：

```text
entryNodeId
    -> SceneNode.scene_id
    -> manifest.entryScene
```

```text
RouteEdge.sourceNodeId
    -> 源 SceneNode.scene_id

RouteEdge.sourcePortId
    -> 源 SceneNode 的 ExitPort.name

RouteEdge.targetNodeId
    -> 目标 SceneNode.scene_id
```

最终形成：

```json
{
  "entryScene": "prologue",
  "routes": {
    "prologue": {
      "continue": "chapter-one"
    }
  }
}
```

转换过程中必须拒绝：

- 找不到源 Node。
- 找不到源 ExitPort。
- 找不到目标 Node。
- 同一个源出口有多个目标。
- 两个 Node 导出出相同的 `scene_id`。

## 8. 校验职责分层

### 8.1 单个 Node 层

由 `SceneNode.validate_self()` 负责：

- Node 自身字段格式。
- Scene ID 格式。
- main.lua 路径格式。
- CastMember 字段和重复角色。
- ExitPort 字段、重复端口和重复名称。

### 8.2 Map 层

由 `SceneMap.validate_self()` 或 Map 内部校验逻辑负责：

- `node_id` 全局唯一。
- `scene_id` 全局唯一。
- `edge_id` 全局唯一。
- Edge 源 Node 存在。
- Edge 源 ExitPort 存在。
- Edge 目标 Node 存在。
- 一个出口最多一条出边。
- 声明的出口是否没有连接。
- 入口 Node 是否存在。
- 不可达 Node。

### 8.3 项目层

未来由 Project 或 Exporter 负责：

- CastMember 的角色 ID 是否存在。
- main.lua 文件是否存在。
- Lua 源码是否可以编译。
- 资源路径和资源引用是否有效。
- 完整 manifest 是否符合 Runtime Package v1。

不要让 `SceneNode` 或 `SceneMap` 直接承担项目级文件系统校验。

## 9. View 层边界

当前模块不包含 View。Godot 画布应由宿主编辑器另行实现，例如：

```text
宿主编辑器/
└─ view/
   ├─ scene_node_view.gd
   └─ scene_map_view.gd
```

View 可以读取本模块的 `SceneNode` 和 `SceneMap`，但不能反向成为本模块的依赖。

宿主 View 的职责可以包括：

- 显示 Scene 标题、角色摘要和出口端口。
- 把拖动位置写回 `SceneNode.position`。
- 把端口连接请求交给 `SceneMap`。
- 根据 `SceneMap` 绘制 RouteEdge。
- 同步画布缩放、选择状态和视口状态。

View 不应该：

- 在本模块内保存另一份 Scene 数据。
- 自己决定是否允许连线。
- 自己生成 Runtime routes。
- 直接修改 `SceneMap` 的私有字典。

视图状态和临时交互状态不应写进 Runtime Package。

## 10. 序列化层的预留位置

当前 `SceneNode` 已经有 `to_editor_dict()` 和 `to_runtime_scene()`，先保留即可。

当 Map 工程读写真正开始时，再新增：

```text
node_map/serialization/
├─ node_map_reader.gd
├─ node_map_writer.gd
└─ runtime_scene_adapter.gd
```

职责建议：

- `node_map_reader.gd`：从编辑器 JSON 创建 SceneMap、SceneNode 和 RouteEdge。
- `node_map_writer.gd`：将 SceneMap 写为编辑器工程 JSON。
- `runtime_scene_adapter.gd`：把经过校验的 SceneMap 转换为 Runtime Package 的 scenes、entryScene
  和 routes。

不要让 `SceneMap` 直接读写文件，也不要让 Godot View 直接拼 JSON。

## 11. 测试边界

模块现在包含最小 `project.godot` 和 `tests/run_tests.gd`，用于独立执行领域模型的
headless 回归。宿主工程仍应通过 preload 引用本模块，并补充 UI/文件导出集成测试：

```text
宿主工程/
└─ tests/
   └─ node_map/
      ├─ scene_node_smoke.gd
      ├─ route_edge_smoke.gd
      ├─ scene_map_smoke.gd
      └─ fixtures/
```

建议测试顺序：

1. `scene_node_smoke.gd`：覆盖单个 Node。
2. `route_edge_smoke.gd`：覆盖 Edge 字段和本地规则。
3. `scene_map_smoke.gd`：覆盖 Node/Edge 的增删和跨对象校验。
4. `serialization_smoke.gd`：等宿主工程实现读写层后再增加。

这样可以保持本模块只包含可复用代码和设计文档，避免把测试运行方式绑定到某个宿主项目。

## 12. 当前推荐的实现顺序

```text
第一步：route_edge.gd
    已完成：定义一条只保存 ID 的连线对象。

第二步：scene_map.gd
    已完成：管理 Node、Edge 和 entry_node_id。

第三步：SceneMap 的本地 smoke test
    已完成：验证增删节点、增删连线、重命名和级联删除。

第四步：Map 跨对象校验
    验证悬空引用、重复 Scene ID、未连接出口和不可达 Node。

第五步：编辑器 Map JSON
    再设计 reader/writer，不提前混入 Godot View。

第六步：宿主 Godot View
    由宿主工程使用 GraphEdit/GraphNode 显示已经稳定的 SceneMap。
```

## 13. 当前不建议的结构

暂时不要采用：

```text
node_map/
├─ controller/
├─ manager/
├─ service/
├─ repository/
└─ component/
```

原因：当前领域对象很少，这些目录会把简单关系拆得过细，并且容易让 UI、文件读写和
运行时逻辑混进同一个“Manager”。先按领域对象和清晰的边界拆分即可。

也暂时不要：

- 把 `RouteEdge` 写进 `SceneNode`。
- 把所有 Node 的列表放进 `SceneNode`。
- 让宿主 View 成为数据真相来源。
- 用 `scene_id` 直接代替编辑器 `node_id`。
- 用数组索引代替出口 `port_id`。
- 在 Map 层复制一套 Lua 执行器。
- 把 Godot UI 反向加入这个纯模型模块。

## 14. 当前结论

下一步最小的文件架构是：

```text
node_map/
├─ cast_member.gd
├─ exit_port.gd
├─ scene_node.gd
└─ map/
   ├─ route_edge.gd
   └─ scene_map.gd
```

其中：

```text
SceneNode = 一个 Scene 自身
RouteEdge  = 一条 Scene 之间的连接
SceneMap   = 所有 Node、Edge 和入口配置的聚合根
```

Map 层的两个核心文件已经实现。本模块不创建 View、serialization 或 validation 目录；这些能力由宿主工程按需添加。
