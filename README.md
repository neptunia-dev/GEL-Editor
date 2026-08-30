# GEL Editor Node Map

这是 GEL 编辑器的 Node Map 领域模型子模块。

当前模块只包含可复用的数据模型，不包含 Godot UI、GraphEdit、编辑器窗口、工程文件读写或测试文件。

## 目录结构

```text
editor/
├─ README.md
└─ node_map/
   ├─ node_map.gd
   ├─ cast_member.gd
   ├─ exit_port.gd
   ├─ scene_node.gd
   ├─ map/
   │  ├─ route_edge.gd
   │  └─ scene_map.gd
   ├─ scene-node-design.md
   └─ map-file-architecture.md
```

## 核心类型

```text
CastMember  Scene 内的角色绑定
ExitPort    Scene 的本地出口
SceneNode   单个 Scene 的编辑器数据模型
RouteEdge   Scene 之间的路由引用
SceneMap    Node 和 RouteEdge 的聚合根
```

## 模块入口

`node_map/node_map.gd` 是模块边界标识，并提供模块版本：

```gdscript
const NODE_MAP_MODULE = preload("res://node_map/node_map.gd")

print(NODE_MAP_MODULE.version())
```

具体类型通过各自脚本中的 `class_name` 使用：

```gdscript
var node := SceneNode.new()
var map := SceneMap.new()
```

## 当前职责

- 保存单个 Scene Node 的编辑器数据。
- 保存 Scene 内的角色绑定和出口。
- 保存 Scene 之间的 Edge ID 引用。
- 管理多个 Node 和 Edge。
- 检查本地和跨 Node 的图结构约束。
- 转换为编辑器字典和 Runtime Scene/route 数据。

## 明确不包含

- `GraphNode`、`GraphEdit` 和其他 Godot UI。
- Scene Map 可视化界面。
- 工程文件读写。
- Runtime Package 文件导出。
- Lua 执行。
- 测试文件。
- 宿主项目的角色注册表和资源管理。

## 集成方式

该模块可以被宿主 Godot 项目作为目录引入，也可以作为 Git submodule 放到宿主项目的 `editor/node_map` 路径下。

模块内部的领域类不依赖宿主项目场景，不访问操作系统文件，也不依赖 UI。宿主负责：

- 创建和管理 Godot 项目。
- 保存和加载工程 JSON。
- 创建 `SceneNodeView` 或其他 UI。
- 连接 View 与 `SceneMap`。
- 调用 Runtime Package 导出器。

## 版本说明

`MODULE_VERSION` 是 Node Map 编辑器数据模型的版本，不等同于 GEL Runtime Package 的 `formatVersion`，也不等同于存档版本。
