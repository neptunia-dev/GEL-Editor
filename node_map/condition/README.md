# SceneNode 条件 Wrapper

## 所有权与结构

每个 `SceneNode` 最多拥有一个 `ConditionTree`。树用稳定 ID 保存 wrapper、branch 和
child wrapper 引用，不持有目标 `SceneNode`：

```text
SceneNode
└─ ConditionTree.root_wrapper_id
   └─ wrapper
      ├─ branch.child_wrapper_id -> wrapper
      └─ terminal branch -> RouteEdge -> target SceneNode
```

`ConditionTree.validate_self()` 检查唯一 ID、固定分支、缺失引用、环、共享子树、不可达
wrapper、switch 重复值和有限数值常量。wrapper/branch ID 限制为
`^[A-Za-z0-9_-]+$`，使隐藏 Runtime port 的拼接没有歧义。

## Wrapper

- `IfWrapper`：boolean 变量和 true/false 固定分支。
- `SwitchCaseWrapper`：标量变量、有序 case 和必需 default。case 的 `branch_id` 与
  `match_value`/label 分离，编辑值不会破坏路由。
- `NumericCompareWrapper`：number 变量或有限常量组成左右操作数，固定 `<`、`=`、`>`
  三个分支。

`LuaConditionCompiler` 接受只读变量目录。目录值既可以直接是 schema，也可以是带
`schema` 字段的 Runtime 变量定义：

```gdscript
var result := LuaConditionCompiler.new().compile(tree, {
    "flags.met_alice": {"type": "boolean"},
    "score": {"schema": {"type": "number", "min": 0}},
})
```

编译器使用 `ctx.state:get()` 读取变量，以 `if/elseif/else` 生成 Lua，并在每个叶子
返回 `ctx.flow:exit(hidden_port)`。字符串和标量字面量使用确定性转义。

## SceneMap 原子操作

以下删除操作会同步清理受影响的 `RouteEdge`：

- `SceneMap.remove_exit(node_id, port_id)`
- `SceneMap.remove_condition_branch(node_id, branch_id)`
- `SceneMap.remove_condition_wrapper(node_id, wrapper_id)`
- `SceneMap.clear_condition_tree(node_id)`

`SceneMap.update_node()` 不做隐式清理；若新 Node 会使已有源端点悬空，它会拒绝整个
更新。这样编辑器可以明确选择“保守更新”或“原子删除”。

`SceneMap.to_runtime_definition(variable_catalog)` 在导出时同时执行图结构和变量类型
校验，生成显式/隐藏 Scene exits 及对应 routes。编辑器 ID 不进入 Runtime 数据。
