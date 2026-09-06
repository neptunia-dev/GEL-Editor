# GEL Editor 文档索引

这里集中存放 GEL Editor 的设计、领域模型和工作区架构文档。

## 文档列表

- [编辑器概览](editor-overview.md)：模块边界、当前状态、Node Map 方向和宿主集成说明。
- [工作区框架设计](workspace-design.md)：参考 Godot 4.6 源码整理的 Shell、Dock、Workspace、Bottom Panel 和布局状态设计。
- [编辑器模块框架](editor-module-framework-design.md)：轻量模块注册、槽位接入和未来工作区模块的扩展方式。
- [Explorer 显示框架](editor-explorer-display-framework-design.md)：可替换数据源的树形显示、筛选、选择和激活框架。
- [Node Map 重设计与文件架构](node-map-file-architecture.md)：公共节点父类、层级 Graph、端口、连接、复合 Scene、序列化和编译边界。
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

旧版 Node Map 领域代码、条件树、专用路由对象及其旧测试已经删除。新的 Node Map
领域模型目前只完成架构设计，尚未开始实现；实现规范见 [Node Map 重设计与文件架构](node-map-file-architecture.md)。
中央 Workspace 已接入独立的静态显示占位，可以查看根图、三个 Scene 子图及临时连线效果，
但没有工程文件读写、编译或真实业务数据源。
