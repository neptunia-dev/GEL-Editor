# GEL Editor Node Map

这是 GEL 编辑器的纯 GDScript Node Map 领域模块。它包含 Scene 数据、条件 wrapper
树、稳定路由端点、Runtime Scene/route 转换，以及条件 Lua 的纯文本编译与受控区块
替换；不依赖 Godot UI，也不直接访问游戏包文件系统。

## 目录

```text
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

仓库包含最小 `project.godot`，用于解析独立模块并运行 headless 回归：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . --script res://tests/run_tests.gd
```

`tests/emit_generated_lua.gd` 会把真实 compiler + writer 结果输出给引擎 Lua 解析器做
集成预编译检查。
