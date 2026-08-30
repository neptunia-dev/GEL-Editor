# GEL Editor Node Map

这是 GEL 的独立 Godot runtime Node Map 编辑器。运行项目会直接打开 GEL Editor
窗口；它不使用 `EditorPlugin`、`@tool`、Godot Inspector 或 editor dock。

应用当前维护内存中的 `SceneMap`，支持创建、编辑、移动和删除 Scene，稳定端口连线、
条件 wrapper 展开/折叠、连线 hover/选择，以及右侧 Inspector。当前版本不保存工程、
不写 Lua 文件，也不提供 Undo/Redo。

首次使用请参阅 [简明操作指南](OPERATION_GUIDE.md)。

## 目录

```text
app/
├─ node_map_application.gd/.tscn
├─ node_map_controller.gd
├─ node_map_canvas.gd
├─ scene_node_view.gd
├─ node_inspector.gd
└─ demo_map_factory.gd
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

完整模型、校验和编译契约见 [condition/README.md](node_map/condition/README.md)。

## 启动独立应用

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

应用默认从空 Map 启动。要载入包含普通出口、嵌套 if/switch/numeric wrapper 和
多条入边的内存验收图，可以运行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --demo
```

工具栏和画布右键菜单都能创建 Scene。第一个 Scene 自动成为入口；所有 UI 修改都
先交给 `NodeMapController`，由领域模型接受后再刷新画布。

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

Standalone UI 回归：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . --script res://tests/runtime_ui_tests.gd
```

`tests/emit_generated_lua.gd` 会把真实 compiler + writer 结果输出给引擎 Lua 解析器做
集成预编译检查。
