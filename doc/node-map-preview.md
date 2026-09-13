# Node Map 显示占位

> 状态：已接入静态 EditorShell。仅用于观察显示效果和预览交互，尚未实现 Node Map 领域模型。

## 运行

在 Godot 4.6 中打开 `editor/project.godot` 后运行主场景，或在 `editor/` 下执行：

```sh
godot --path .
```

主场景仍是 `workspace/editor_shell.tscn`。也可以单独打开
`workspace/node_map/placeholder_node_map.tscn` 查看占位画布，稳定布局和演示节点全部
保存在 `.tscn` 中，方便直接在 Godot 编辑器里调整。

## 已有内容

- 根图：Project Start、Prologue、Chapter One、Ending，包含命名出口与 retry 回路。
- Prologue：入口、对话、变量 boolean 数据连线、If、continue/retry 输出接口。
- Chapter One：入口、Choice、两条对话分支和共同出口。
- Ending：入口、对话、End Story；结束节点不暴露出口。
- 拖动节点、框选、画布平移、缩放、网格吸附和小地图使用 Godot 原生 GraphEdit。
- 点击 Scene 的 Open Scene 或双击标题进入子图，返回按钮回到根图。
- 每张图保留本次运行中的位置、缩放、平移与临时连接；重置仅恢复当前图的演示状态。
- Frame All 重新适配当前图；状态栏显示节点数、连线数与当前选择。
- 回连曲线从节点下方绕行；Frame All 同时计算节点与连线范围，小地图沿用相同线形。

## 边界

这些脚本属于 `workspace/node_map/` 视图占位，不属于根目录 `node_map/` 领域模型。
`placeholder_graph_node.gd` 只统一视觉样式，不是设计中的 `NodeMapNode` 公共模型父类。
占位代码不会创建 NodeMapDocument，也不会读取或保存工程、执行 Lua、导出 Runtime
Package、接入 Inspector、Explorer 业务选择或 LayoutRenderer。

演示连接保存在 Godot 场景的 `GraphEdit.connections` 属性中，端口整数索引只用于这些
静态视图，不是新的 NodeLink 或文件协议。连接交互只检查端点存在、类型匹配、重复和
局部连接数限制；没有数据环检测、可达性分析或导出有效性保证。缺失连线只是预览状态，
不能据此判断真实流程可以导出。

节点参数和端口是静态展示，本轮没有新增、复制、删除业务节点或动态接口编辑。根图
Scene 端口与子图边界是成对制作的演示内容，不是实际 GraphInterface 投影。预览操作
只保留在内存，关闭程序后丢弃；不会生成 Node Map JSON，也不兼容旧文件格式。

正式实现时，按 [Node Map 重设计与文件架构](node-map-file-architecture.md) 引入纯模型
和适配器，以稳定的 node_id/port_id 替代演示端点，不能将 GraphEdit 当作领域数据来源。

## 验证

```sh
godot --headless --path . --script res://tests/node_map_preview_tests.gd
godot --path . --script res://tests/node_map_preview_tests.gd -- --screenshots
```

第一条检查场景结构、端口类型、进入/返回、视图状态保留、临时连线、重置和布局边界。
同时通过实际鼠标事件检查拖动、按钮点击和标题双击，检查节点内文字边界、示例连线
避开节点本体，以及平移后的连线形状。绕行只服务于占位显示，不是任意图的自动避障布线。
第二条使用真实渲染器，额外检查画面和画布区域的像素内容，并把不同窗口尺寸的截图写入 Git 忽略的
`.godot/node-map-preview/`。它们是显示测试，不替代未来 `tests/node_map/` 的模型测试。

工具按钮使用 Godot 内置图标和随项目分发的 Lucide 图标，第三方授权见
`workspace/node_map/icons/LICENSE.txt`。
