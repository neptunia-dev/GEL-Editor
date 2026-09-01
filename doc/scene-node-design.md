# Scene Node 设计草稿

> 状态：已确认、已落地初版
>
> 当前范围：只实现单个 Scene Node 数据模型，不包含 Godot UI，不实现完整 Graph。
>
> 当前实现位于 `node_map/`：`CastMember`、`ExitPort` 和 `SceneNode` 均为不依赖 UI 的 `RefCounted` 类。
>
> v2：`SceneNode` 已增加可选 `ConditionTree` 装饰数据；当前契约见
> [条件树设计](condition-tree-design.md)。下文“初版不包含条件”的描述仅作历史设计记录。
>
> 本目录作为独立 Node Map 代码模块发布，宿主编辑器负责 View、工程读写和测试。

## 1. 目标

编辑器中的一个 `SceneNode` 表示一个剧情 Scene。

```text
一个 SceneNode
    -> 一个 Runtime Package Scene
    -> 一个 main.lua 入口
```

Node 负责描述当前 Scene 自身的信息，不负责管理其他 Scene 或 Scene 之间的连线。

## 2. 当前不包含的内容

以下内容暂时不属于单个 `SceneNode`：

- 整个剧情图。
- 其他 Node。
- Scene 之间的路由连线。
- 入口 Scene 的全局配置。
- Lua 脚本的执行状态。
- 角色的运行时状态。
- 变量运行时值。
- Godot 的 `GraphNode` 控件。
- 任何 Godot UI 或 View。
- PackageLoader 和 Runtime Package 的导出流程。

## 3. Python 类比

以下代码是 Python 结构类比；实际实现使用 GDScript。

```python
from dataclasses import dataclass, field


@dataclass
class CastMember:
    """当前 Scene 中允许使用的角色。"""

    character_id: str
    role: str | None = None
    display_name: str | None = None


@dataclass
class ExitPort:
    """当前 Scene 的一个出口。"""

    port_id: str
    name: str


@dataclass
class SceneNode:
    """编辑器中的一个剧情 Scene Node。"""

    # 编辑器内部身份
    node_id: str

    # 导出到 Runtime Package 的稳定 Scene ID
    scene_id: str

    # Scene 的显示标题
    title: str

    # Scene 对应的 Lua 主入口
    main_script: str

    # 当前 Scene 的角色列表
    cast: list[CastMember] = field(default_factory=list)

    # 当前 Scene 的出口列表
    exits: list[ExitPort] = field(default_factory=list)

    # 编辑器画布坐标
    position: tuple[float, float] = (0, 0)
```

## 4. 字段设计

### 4.1 `node_id`

```python
node_id: str
```

编辑器内部 ID，建议使用 UUID。

用途：

- 在编辑器内部唯一识别 Node。
- 保存 Node 的位置。
- 供未来的连线引用。
- 支持撤销和重做。
- 修改 `scene_id` 后保持 Node 的编辑器身份不变。

示例：

```text
node-550e8400-e29b-41d4-a716-446655440000
```

### 4.2 `scene_id`

```python
scene_id: str
```

Runtime Package 中 Scene 的稳定 ID。

示例：

```text
prologue
chapter-one
ending.true
```

约束：

```text
^[a-z][a-z0-9_.-]*$
```

用途：

- Runtime Package 的 `scenes[].id`。
- 路由表中的 Scene 引用。
- 存档中的 Scene 引用。
- 引擎日志和诊断信息。

修改 `scene_id` 时：

```text
node_id 保持不变
scene_id 改变
```

### 4.3 `title`

```python
title: str
```

Scene 的显示标题，例如：

```text
序章
第一次相遇
真结局
```

它不参与：

- 路由查找。
- 存档引用。
- Lua 文件定位。

待确认：

- 标题是否允许为空？
- 标题为空时是否自动显示 `scene_id`？
- 标题是否需要长度限制？

### 4.4 `main_script`

```python
main_script: str
```

Scene 的 Lua 主入口路径。

示例：

```text
scenes/prologue/main.lua
```

约束：

- 必须是包内相对路径。
- 必须位于 `scenes/` 目录下。
- 文件名必须是 `main.lua`。
- 一个 Scene 只有一个主入口。

新建 Node 时可以根据 `scene_id` 生成默认路径：

```text
scenes/<scene_id>/main.lua
```

但生成之后，`main_script` 仍然是 Node 中明确保存的字段。

建议的改名行为：

```text
scene_id 改名
    -> main_script 默认不自动修改
```

原因：Scene ID 和脚本路径在 Runtime Package 设计中是两个独立字段。

待确认：

- 是否允许用户手动修改 `main_script`？
- 是否提供“同步 Scene ID 和脚本路径”的操作？
- 是否允许脚本路径暂时指向不存在的文件？

### 4.5 `cast`

```python
cast: list[CastMember]
```

表示当前 Scene 允许引用哪些角色。

示例：

```python
cast = [
    CastMember(
        character_id="alice",
        role="女主角",
        display_name="爱丽丝",
    ),
]
```

`CastMember` 的字段：

```python
character_id: str
role: str | None
display_name: str | None
```

Node 自身可以检查：

- `character_id` 不能为空。
- 同一个 Node 中不能重复出现相同的 `character_id`。
- `role` 可以为空。
- `display_name` 可以为空。

Node 不负责检查：

- `character_id` 是否存在于整个工程的角色注册表。
- 角色的立绘是否存在。
- 角色资源是否有效。

这些属于项目级或导出级校验。

### 4.6 `exits`

```python
exits: list[ExitPort]
```

表示当前 Scene 可以返回的本地出口。

示例：

```python
exits = [
    ExitPort(port_id="exit-001", name="continue"),
    ExitPort(port_id="exit-002", name="retry"),
]
```

`ExitPort` 的字段：

```python
port_id: str
name: str
```

`port_id` 是编辑器内部的稳定端口 ID，建议使用 UUID。

`name` 是运行时使用的本地出口名称。

### 为什么出口需要 `port_id`

如果只保存字符串：

```python
exits = ["continue", "retry"]
```

编辑器连线只能引用出口名称。

如果用户把出口改名：

```text
continue -> proceed
```

连线就需要额外处理。

使用稳定端口 ID 后：

```text
port_id: exit-001
name: continue
```

改名后：

```text
port_id: exit-001
name: proceed
```

编辑器仍然知道这是同一个出口。

导出 Runtime Package 时，才去掉 `port_id`：

```json
{
  "exits": ["proceed", "retry"]
}
```

出口数组的顺序表示显示顺序，因此暂时不需要单独的 `order` 字段。

Node 不保存出口的目标 Scene：

```python
# 不放在 SceneNode 中
source_scene_id
 target_scene_id
 route
 connection
```

出口定义属于 Node，目标关系属于未来的 Graph/Edge 对象。

待确认：

- 出口名称是否需要遵循特定格式？
- 是否允许出口名称包含空格或中文？
- 删除出口时，未来是否由 Graph 自动删除对应连线？
- 是否允许没有出口的 Scene？

### 4.7 `position`

```python
position: tuple[float, float]
```

Node 在编辑器画布中的坐标。

示例：

```python
position = (120, 80)
```

这个字段只属于编辑器工程，不进入 Runtime Package。

暂时不保存：

- Node 的选中状态。
- Node 的悬停状态。
- Node 的 Godot 控件引用。
- Node 的连线。
- Node 的撤销历史。

待确认：

- 是否需要保存 Node 尺寸？
- 是否需要保存折叠状态？
- 是否需要保存节点颜色？
- 是否需要保存注释？

## 5. SceneNode 的职责

单个 Node 可以负责：

- 保存自身的 Scene 数据。
- 修改 `scene_id`。
- 修改 `title`。
- 修改 `main_script`。
- 添加角色。
- 删除角色。
- 修改角色在当前 Scene 中的局部信息。
- 添加出口。
- 删除出口。
- 重命名出口。
- 调整出口顺序。
- 保存自身的画布位置。
- 检查自身字段是否合法。
- 转换为 Runtime Package 所需的 Scene 定义。

## 6. SceneNode 不负责的职责

以下职责留给更高层对象：

| 职责 | 未来所属对象 |
| --- | --- |
| 管理所有 Scene Node | `StoryGraph` 或 `Project` |
| 检查多个 Node 的 `scene_id` 是否重复 | `StoryGraph` 或 `Project` |
| 创建和删除连线 | `StoryGraph` 或 `RouteGraph` |
| 判断入口 Scene | `Project` 或 `StoryGraph` |
| 检查 Scene 是否可达 | `StoryGraph` |
| 检查角色 ID 是否存在 | `Project` |
| 生成完整 `manifest.json` | `Exporter` |
| 执行 Lua | Runtime Engine |
| 绘制 Godot 控件 | 宿主工程的 View 层 |

## 7. 建议的方法

以下方法只处理 Node 自己的数据。

```python
class SceneNode:
    ...

    def rename_scene(self, new_scene_id: str) -> bool:
        """修改当前 Scene 的稳定 ID；失败时通过 last_error 返回原因。"""
        pass

    def set_title(self, title: str) -> bool:
        """修改 Scene 显示标题。"""
        pass

    def set_main_script(self, path: str) -> bool:
        """修改 Lua 主入口路径；失败时通过 last_error 返回原因。"""
        pass

    def add_cast_member(self, member: CastMember) -> None:
        """添加一个场景角色绑定。"""
        pass

    def remove_cast_member(self, character_id: str) -> None:
        """删除一个场景角色绑定。"""
        pass

    def add_exit(self, port: ExitPort) -> None:
        """添加一个 Scene 出口。"""
        pass

    def rename_exit(self, port_id: str, new_name: str) -> None:
        """修改出口名称，但保持 port_id 不变。"""
        pass

    def remove_exit(self, port_id: str) -> None:
        """删除一个出口。"""
        pass

    def move_exit(self, port_id: str, new_index: int) -> None:
        """调整出口显示顺序。"""
        pass

    def validate_self(self) -> list[str]:
        """只检查当前 Node 的本地数据。"""
        pass

    def to_runtime_scene(self) -> dict:
        """转换为 Runtime Package 中的 Scene 定义。"""
        pass
```

## 8. 本地校验范围

`validate_self()` 建议检查：

- `node_id` 不为空。
- `scene_id` 符合 Scene ID 格式。
- `title` 符合标题规则。
- `main_script` 是合法的 Scene 主入口路径。
- `cast` 中没有重复的 `character_id`。
- `cast` 中的文本字段满足空值规则。
- `exits` 中没有重复的 `port_id`。
- `exits` 中没有重复的出口名称。
- 出口名称不为空。
- 出口顺序有效。

不在本地校验范围内：

- `scene_id` 是否和其他 Node 重复。
- 角色 ID 是否存在。
- Lua 文件是否实际存在。
- Lua 文件是否可以编译。
- 出口是否连接了目标 Scene。
- 出口是否遗漏路由。

## 9. 编辑器工程数据示例

```json
{
  "nodeId": "node-001",
  "sceneId": "prologue",
  "title": "序章",
  "mainScript": "scenes/prologue/main.lua",
  "cast": [
    {
      "characterId": "alice",
      "role": "女主角",
      "displayName": "爱丽丝"
    }
  ],
  "exits": [
    {
      "portId": "exit-001",
      "name": "continue"
    },
    {
      "portId": "exit-002",
      "name": "retry"
    }
  ],
  "position": {
    "x": 120,
    "y": 80
  }
}
```

## 10. Runtime Package 导出结果

同一个 Node 导出为 Runtime Package 中的 Scene：

```json
{
  "id": "prologue",
  "title": "序章",
  "mainScript": "scenes/prologue/main.lua",
  "cast": [
    {
      "characterId": "alice",
      "role": "女主角",
      "displayName": "爱丽丝"
    }
  ],
  "exits": [
    "continue",
    "retry"
  ]
}
```

导出时不包含以下编辑器字段：

```text
node_id
exits[].port_id
position
```

## 11. 当前待确认问题

请直接在本文件中修改或补充：

- [ ] `title` 是否允许为空？
- [ ] `title` 是否需要最大长度？
- [ ] `main_script` 是否允许手动修改？
- [ ] 修改 `scene_id` 时是否始终保持 `main_script` 不变？
- [ ] `CastMember` 是否还需要其他字段？
- [ ] 出口名称是否需要格式限制？
- [ ] 出口名称是否允许重复？当前设计是不允许。
- [ ] 出口删除后，连线由谁处理？
- [ ] 是否需要一个默认输入端口？
- [ ] 是否需要保存 Node 尺寸？
- [ ] 是否需要保存折叠状态、颜色和注释？
- [ ] `position` 是否使用 Godot 的 `Vector2` 概念？
- [ ] 是否需要给 Node 增加版本字段？
