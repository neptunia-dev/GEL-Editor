# GEL Editor 文档索引

这里集中存放 GEL Editor 的设计、领域模型和工作区架构文档。

## 文档列表

- [编辑器概览](editor-overview.md)：模块边界、目录结构、验证方式和宿主集成说明。
- [工作区框架设计](workspace-design.md)：参考 Godot 4.6 源码整理的 Shell、Dock、Workspace、Bottom Panel 和布局状态设计。
- [编辑器模块框架](editor-module-framework-design.md)：轻量模块注册、槽位接入和未来工作区模块的扩展方式。
- [Explorer 显示框架](editor-explorer-display-framework-design.md)：可替换数据源的树形显示、筛选、选择和激活框架。
- [Node Map 文件架构](node-map-file-architecture.md)：SceneNode、RouteEdge、SceneMap 的职责、所有权和依赖方向。
- [SceneNode 设计](scene-node-design.md)：单个 SceneNode 的字段、接口和校验边界。
- [条件树设计](condition-tree-design.md)：If、Switch、Numeric Compare wrapper 及其分支和路由契约。

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

模块注册逻辑已经完成，具体协议见 [编辑器模块框架](editor-module-framework-design.md)。
EditorShell 占位场景已经将布局状态映射到 `SplitContainer`、`TabContainer` 和占位面板；
具体业务模块和 LayoutRenderer 仍待后续实现。具体阶段和验收标准见 [工作区框架设计](workspace-design.md)。
