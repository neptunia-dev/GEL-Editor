# GEL Node Map Handoff

更新时间：2026-08-31

## 当前状态

`gelEditor` 已经是可独立运行的 Godot runtime 应用，不是 EditorPlugin。

目前已完成：

- 内存中的 `SceneMap`、Scene、普通出口和稳定 RouteEdge。
- If、Switch、Numeric Compare 条件树及领域校验。
- 条件叶子隐藏 runtime exit 和 Runtime routes 生成。
- 纯字符串 `LuaConditionCompiler` 和 `LuaConditionBlockWriter`。
- GraphEdit 画布、Scene Node、Inspector、移动、选择、删除和连线。
- wrapper 展开/折叠、分支端口和嵌套 wrapper 展示。
- 节点右键新增 If/Switch/Numeric 根 wrapper。
- Switch Inspector 的 **+ Add Case**，以及 case 删除和编辑。
- 端口扩大命中区、鼠标 hover 高亮，以及从输出或输入两侧开始拖线。
- 内置 `--demo` 验收图。

当前自动化结果：

```text
PASS: 55 checks
PASS: 57 runtime UI checks
```

## 还没有完成

### 1. Lua 文件实际写回

目前只有 compiler 和 block writer，尚未接到编辑器宿主的文件读写流程。下一步需要：

1. 根据 `SceneNode.main_script` 定位并读取 `main.lua`。
2. 检查文件存在、UTF-8 和唯一的 generated markers。
3. 调用 `LuaConditionCompiler.compile()` 生成条件代码。
4. 调用 `LuaConditionBlockWriter` 只替换 markers 内部内容。
5. 使用临时文件加原子替换写回，避免写坏手写 Lua。
6. 写回前执行 Lua 语法预编译；失败时保留原文件并显示诊断。
7. 检查手写主体中与生成条件出口冲突的最终 `ctx.flow:exit()`。

文件系统访问应放在 Project/Export 宿主层，不要放进 `SceneNode` 或 `SceneMap`。

### 2. 工程保存和加载

- 还没有 SceneMap JSON/project 文件保存。
- 还没有从磁盘恢复节点位置、wrapper 展开状态和路由。
- 关闭应用后当前编辑内容会丢失。
- 需要设计格式版本和迁移策略。

### 3. Runtime Package 导出接线

领域层已有 `SceneMap.to_runtime_definition()`，但 UI 尚未提供 Export 操作，也没有把
Runtime Scene、隐藏 exits、routes 和生成后的 Lua 写入真实 package 目录。

### 4. 变量目录和 Project 校验

- Inspector 中变量 key 仍然是文本输入。
- 尚未接入 Package 的变量目录下拉选择。
- boolean/number/schema 校验只在 compiler/export 阶段可用，编辑时还没有即时提示。

### 5. 编辑器能力

- 没有 Undo/Redo。
- 没有清空或替换根 wrapper 的 UI；目前只支持为空 Scene 添加根 wrapper。
- 没有复制/粘贴 Scene 或 wrapper。
- 没有自动布局和工程级搜索。
- 没有运行时预览。

### 6. 仍需人工回归

端口 hotzone、高亮和双向拖线已有自动化覆盖，但最近一次真实窗口拖拽验证被中断。
继续开发前建议实际启动一次，重点确认：

- 从左右两侧圆点按住拖动时显示连线预览，不再出现框选矩形。
- 圆点 hover 变为黄色，移开后恢复原色。
- 输入端拖到输出端时仍生成“输出 Scene → 输入 Scene”的 RouteEdge。
- 节点右键菜单可以新增根 wrapper。
- Switch 的 **+ Add Case** 能立即增加新分支和输出端口。

## 关键文件

```text
app/node_map_application.gd    应用壳和 UI 信号接线
app/node_map_controller.gd     SceneMap 唯一写入口
app/node_map_canvas.gd         GraphEdit、连线和右键菜单
app/scene_node_view.gd         GraphNode、wrapper 和端口
app/node_inspector.gd          Scene/Wrapper/Branch/Edge Inspector
node_map/map/scene_map.gd      图校验和 Runtime 定义
node_map/lua/                  Lua compiler 与受控区块 writer
tests/run_tests.gd             领域模型测试
tests/runtime_ui_tests.gd      Standalone UI 测试
```

## 常用命令

运行示例：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/calcite/GEL/gelEditor -- --demo
```

运行测试：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/calcite/GEL/gelEditor \
  --script res://tests/run_tests.gd

/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/calcite/GEL/gelEditor \
  --script res://tests/runtime_ui_tests.gd
```

