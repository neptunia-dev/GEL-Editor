# GEL Editor 文档索引

这里集中存放 GEL Editor 的设计、领域模型和工作区架构文档。

## 文档列表

- [编辑器概览](editor-overview.md)：模块边界、当前状态、Node Map 方向和宿主集成说明。
- [工作区框架设计](workspace-design.md)：参考 Godot 4.6 源码整理的 Shell、Dock、Workspace、Bottom Panel 和布局状态设计。
- [编辑器模块框架](editor-module-framework-design.md)：轻量模块注册、槽位接入和未来工作区模块的扩展方式。
- [Explorer 显示框架](editor-explorer-display-framework-design.md)：可替换数据源的树形显示、筛选、选择和激活框架。
- [Node Map 重设计与文件架构](node-map-file-architecture.md)：公共节点父类、层级 Graph、端口、连接、复合 Scene、序列化和编译边界。
- [Node Map 工程文件](node-map-project-file.md)：已实现的 `.gelproj` v1 容器、保存/加载、项目配置与 Runtime Package 的边界。
- [SceneNode 设计](scene-node-design.md)：作为复合节点的 SceneNode 字段、子图接口、复制、删除和校验契约。
- [Node Map 显示占位](node-map-preview.md)：当前 GraphEdit 演示场景、预览交互、运行方式与限制。

## 当前实现阶段

当前仓库已经完成布局管理系统的纯逻辑层，包括：

- 布局拓扑定义；
- Dock 和 Workspace 描述；
- Slot Tab 状态；
- Dock 打开、关闭、移动和恢复；
- 中央 Workspace 切换；
- Bottom Panel 状态；
- Split 偏移；
- JSON 序列化、版本检查和默认布局重置。

模块注册逻辑和 Explorer 占位显示框架也已经完成，具体协议见对应设计文档。
EditorShell 占位场景已经将布局状态映射到 `SplitContainer`、`TabContainer` 和占位面板；
具体业务模块和 LayoutRenderer 仍待后续实现。

Node Map 领域模型、编辑器画布、JSON 工程文件、Runtime Package 编译/导出及 Node CLI
校验/自动运行已实现并有 headless 回归覆盖。`.gelproj` 保存编辑器工程，Runtime Package
目录由编译器单独生成，二者不能互换；具体工程文件契约见 [Node Map 工程文件](node-map-project-file.md)。

无工程启动时仍显示示例文档。角色、资源、变量和 Godot 内交互式预览仍待后续工作。
