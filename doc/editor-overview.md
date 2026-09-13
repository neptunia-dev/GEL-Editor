# GEL Editor 概览

GEL Editor 是一个以工作区为宿主、以 Node Map 为核心创作工具的 Godot 4.6 编辑器。
当前工作区和通用显示基础设施已经实现，Node Map 正在从旧版 Scene 专用模型重设计为
类似 ComfyUI 的层级节点图模型。

旧版 Node Map 代码已经删除。新的 Node Map 文档规定下一步实现，目前尚无对应模型
代码；已有引擎 Runtime 并未因此删除。布局逻辑、模块注册和占位 Shell/Explorer 已实现，
业务模块接入和 LayoutRenderer 仍待实现。中央区域已有基于原生 GraphEdit/GraphNode
的 Node Map 显示占位，仅使用静态演示场景，不代表领域模型已经实现。

## 目录

当前有效的代码主要包括：

```text
workspace/
├─ layout/
│  ├─ layout_definition.gd
│  ├─ layout_state.gd
│  ├─ layout_manager.gd
│  ├─ layout_serializer.gd
│  ├─ dock_descriptor.gd
│  ├─ dock_slot_state.gd
│  └─ workspace_descriptor.gd
├─ modules/
│  ├─ module_descriptor.gd
│  └─ module_registry.gd
└─ explorer/
   ├─ explorer_entry.gd
   ├─ explorer_model.gd
   ├─ explorer_panel.gd
   ├─ explorer_tree.gd
   └─ placeholder_explorer_data.gd
```

Node Map 的目标目录和文件职责见 [Node Map 重设计与文件架构](node-map-file-architecture.md)。
当前 `node_map/` 不包含新的领域实现。

显示占位位于 `workspace/node_map/`，入口为 `placeholder_node_map.tscn`，已经嵌入
`workspace/editor_shell.tscn`。根图和三个 Scene 子图均可独立在 Godot 中查看、调整；
边界与运行方式见 [Node Map 显示占位](node-map-preview.md)。

## Node Map 方向

新的模型采用一份文档管理多张局部图：

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
└── NodeRegistry
```

上图表示导航关系；图对象由文档平铺持有，SceneNode 只保存子图 ID。RootGraph 和
SceneGraph 是同一种 NodeGraph 的不同 kind，注册表由宿主注入且不属于持久化数据。

所有可放置在画布中的业务节点都继承 `NodeMapNode`。`SceneNode` 继承
`SubgraphNode`，在根图中是普通节点，但通过 `child_graph_id` 指向可展开编辑的
Scene 子图。子图的输入和输出由 `GraphInputNode`、`GraphOutputNode` 定义并投影到
SceneNode 的公开端口。

节点之间的连接统一使用 `NodeLink`：

```text
NodeLink
├── source_node_id
├── source_port_id
├── target_node_id
└── target_port_id
```

条件、选择和变量操作都是 SceneGraph 中的普通节点。转场使用子图输出接口；剧情结束
使用 EndStoryNode，不把未连线的出口当作结局。旧条件树和专用路由模型不再使用。

完整的公共父类、端口协议、复合节点接口、所有权、校验、序列化和编译边界见：

- [Node Map 重设计与文件架构](node-map-file-architecture.md)
- [SceneNode 设计](scene-node-design.md)

## 模块边界

领域模型只负责数据和规则，不依赖 Godot 控件，也不访问操作系统文件。宿主编辑器未来
负责：

- 创建工作区和视图；
- 保存、加载编辑器工程文件；
- 将视图交互转换为领域模型命令；
- 调用 Runtime Package 导出器；
- 通过 Workspace 导航根图和 Scene 子图。

工作区布局不反向成为 `node_map/` 领域模块的依赖。工作区设计记录在
[工作区设计](workspace-design.md)，模块接入方式记录在 [编辑器模块框架](editor-module-framework-design.md)，
树形浏览显示框架记录在 [Explorer 显示框架](editor-explorer-display-framework-design.md)。

## 编译边界

新的 Node Map 不在节点模型中直接拼接 Lua。编译流程规划为：

```text
NodeMapDocument
    -> 图结构和节点数据校验
    -> RootGraph / SceneGraph IR
    -> Runtime Package manifest 和 Scene 脚本
```

serialization 负责 JSON 转换，compiler 负责图分析和 IR，宿主工程/导出层负责文件
读写、Runtime 适配和 Lua 预编译。模型不直接调用 `FileAccess`，也不保存编译后的 Lua
文本。编辑草稿可以缺少连线或流程终点，导出则必须通过更严格的完整性校验。

## 当前验证

旧版 Node Map 的回归测试和条件 Lua 生成辅助脚本已随旧模型删除。当前仍可运行的布局
和通用显示测试使用 Godot headless，例如在 `editor/` 目录下运行以下命令。
`godot` 表示本机 Godot 4.6 可执行文件，未加入 PATH 时使用实际路径：

```sh
godot --headless --path . --script res://tests/layout_manager_tests.gd
godot --headless --path . --script res://tests/explorer_model_tests.gd
godot --headless --path . --script res://tests/module_registry_tests.gd
godot --headless --path . --script res://tests/explorer_display_tests.gd
godot --headless --path . --script res://tests/node_map_preview_tests.gd
```

新的 Node Map 实现开始后，应在 `tests/node_map/` 下为公共父类、端口、连接、层级图和
Scene 复制删除行为建立纯模型测试。
