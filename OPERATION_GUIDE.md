# GEL Node Map 简明操作指南

## 1. 启动

在终端运行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/calcite/GEL/gelEditor
```

应用会打开一张空白 Node Map。第一次体验 wrapper 和连线时，可以加载内置示例：

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/calcite/GEL/gelEditor -- --demo
```

也可以在应用工具栏点击 **Load Demo**。

> 当前数据只保存在内存中。关闭应用后修改会丢失。

## 2. 画布操作

- 鼠标滚轮：缩放画布。
- 按住鼠标右键拖动：平移画布。
- 在空白区域拖动：框选多个 Scene。
- 拖动 Scene 标题栏：移动节点；多选后可以一起移动。
- **Frame Selection**：将当前选中的 Scene 移到视野中央。
- **Reset View**：恢复默认缩放和画布位置。

## 3. 创建和编辑 Scene

点击工具栏 **Add Scene**，或在画布空白处点击右键并选择 **Add Scene**。

- `Scene ID` 必填，只能使用小写字母开头，以及小写字母、数字、`_`、`.`、`-`。
- `Title` 可选；留空时节点标题会显示 Scene ID。
- 空 Map 中创建的第一个 Scene 会自动成为入口。

点击 Scene 后，在右侧 Inspector 中可以编辑：

- Title 和 Scene ID
- Lua main 路径
- 是否为入口 Scene
- 普通出口

普通出口每行使用以下格式：

```text
port_id = 显示名称
```

例如：

```text
continue = Continue
cancel = Cancel
```

修改完成后点击 **Apply Scene**。如果输入不合法，原数据不会改变，错误会显示在
Inspector 和顶部状态栏中。

## 4. 创建和删除连线

Scene 左侧圆点是统一输入端口，右侧圆点是输出端口：

- 绿色：普通 Scene 出口。
- 紫色：条件树的叶子分支。
- 拥有子 wrapper 的条件分支不会显示输出端口。

从一个右侧输出端口拖到目标 Scene 的左侧输入端口即可创建路由。同一个输出端口
最多只能连接一个目标；一个 Scene 输入端口可以接受多条连线。

鼠标经过连线时会高亮并显示“源出口 → 目标 Scene”提示。点击连线后可以：

- 按 `Delete` 删除；或
- 在右侧 Edge Inspector 中点击 **Delete Connection**。

## 5. Wrapper 操作

带条件树的 Scene 会在卡片内部显示 wrapper。点击根 wrapper 左侧箭头可展开或折叠；
折叠只改变显示，不会改变路由和稳定 ID。

没有条件树的 Scene 可以通过节点右键菜单创建根 wrapper：

- **Add If Wrapper**
- **Add Switch Wrapper**
- **Add Numeric Compare Wrapper**

一个 Scene 只能有一个根 wrapper，因此已有条件树时这些选项会被禁用。

展开后：

- 点击 wrapper 标题，在 Inspector 中编辑变量、switch cases 或 numeric operands。
- Switch Wrapper 可以点击 **+ Add Case** 追加新 case；新分支会获得稳定 ID，随后可在
  cases 文本框中修改匹配值和显示标签。
- 点击条件分支，在 Inspector 中编辑分支标签和 case 值。
- 叶子分支可以通过 **Add child wrapper** 添加 `If`、`Switch` 或
  `Numeric compare` 子 wrapper。
- 有子 wrapper 的分支可以使用 **Remove Child Subtree** 删除子树。

输入格式：

- Switch case：`branch_id = JSON值 | 显示标签`
- Switch default：`branch_id = default | 显示标签`
- Numeric 变量：`var:score.current`
- Numeric 常量：例如 `10`、`3.5`

## 6. 删除 Scene

选中一个或多个 Scene 后按 `Delete`，或点击工具栏 **Delete**。确认后，Scene 及其
关联路由会一起从内存中的 SceneMap 删除。

## 7. 当前限制

- 不保存或加载项目文件。
- 不提供 Undo/Redo。
- 不写入 Scene Lua 文件。
- 不执行 Runtime Package 导出或运行时预览。
- 关闭应用会丢失当前编辑内容。
