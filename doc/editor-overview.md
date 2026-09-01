# GEL Editor Node Map

这是 GEL 编辑器的 Node Map 领域模型和工作区布局核心模块。Node Map 部分包含 Scene
数据、条件 wrapper 树、稳定路由端点、Runtime Scene/route 转换，以及条件 Lua 的纯文本
编译与受控区块替换；工作区部分已经包含不依赖 Godot Control 的布局状态管理逻辑，以及可在 Godot 编辑器
中直接查看的 EditorShell 占位布局。当前仍不包含具体业务 UI，模块注册逻辑已完成，
LayoutRenderer 尚未开始。

## 目录

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
└─ modules/
   ├─ module_descriptor.gd
   └─ module_registry.gd
node_map/
├─ cast_member.gd
├─ exit_port.gd
├─ scene_node.gd
├─ condition/
│  ├─ condition_tree.gd
│  ├─ condition_branch.gd
│  ├─ condition_wrapper.gd
│  ├─ if_wrapper.gd
│  ├─ switch_case_wrapper.gd
│  ├─ numeric_compare_wrapper.gd
│  └─ numeric_operand.gd
├─ lua/
│  ├─ lua_condition_compiler.gd
│  └─ lua_condition_block_writer.gd
└─ map/
   ├─ route_edge.gd
   └─ scene_map.gd
```

`SceneNode.conditionTree` 是可选装饰数据。分支若指向 child wrapper 就留在条件树内；
叶子分支通过 `RouteEdge.SOURCE_CONDITION_BRANCH` 连接目标 Node，并导出为稳定隐藏出口：

```text
__gel.condition.<wrapper_id>.<branch_id>
```

普通出口仍可用原构造方式：

```gdscript
var edge := RouteEdge.new("edge-id", "source-node", "port-id", "target-node")
```

条件叶子使用显式工厂：

```gdscript
var edge := RouteEdge.from_condition_branch(
    "edge-id", "source-node", "wrapper-id", "branch-id", "target-node",
)
```

完整模型、校验和编译契约见 [条件树设计](condition-tree-design.md)。

## 模块边界

领域模型只负责数据和规则，不依赖 Godot 控件，也不访问操作系统文件。宿主编辑器未来
负责：

- 创建工作区和视图；
- 保存、加载编辑器工程文件；
- 将视图交互转换为领域模型操作；
- 调用 Runtime Package 导出器。

工作区布局设计记录在 [工作区设计](workspace-design.md)，模块接入方式记录在 [编辑器模块框架](editor-module-framework-design.md)，树形浏览显示框架记录在 [Explorer 显示框架](editor-explorer-display-framework-design.md)。当前已完成布局管理系统
的纯逻辑第一阶段：布局拓扑、Dock/Workspace 描述、状态转换、Bottom Panel 状态、Split
偏移、JSON 序列化和状态重置。EditorShell 占位场景已经把这些区域映射到 Godot 的
`SplitContainer`、`TabContainer` 和占位面板；工作区布局不应反向成为 `node_map/` 领域模块
的依赖。

## Lua 编译边界

`LuaConditionCompiler.compile(tree, variable_catalog)` 校验变量声明和类型，返回 Lua
区块及隐藏出口元数据。`LuaConditionBlockWriter` 只替换以下唯一标记内部的文本：

```lua
-- GEL:generated:conditions:start
-- GEL:generated:conditions:end
```

宿主 Project/Exporter 仍负责读取、写回、UTF-8 校验和 Lua 预编译。领域模型不访问
操作系统文件。

## 验证

领域模型回归：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . --script res://tests/run_tests.gd
```

布局管理逻辑回归：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . --script res://tests/layout_manager_tests.gd
```

当前结果：

```text
Node Map: 55 checks
Layout manager: 153 checks
```

`tests/emit_generated_lua.gd` 会把真实 compiler + writer 结果输出给引擎 Lua 解析器做
集成预编译检查。
