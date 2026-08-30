extends RefCounted
class_name SceneNode

## 编辑器中单个 Runtime Package Scene 的数据模型。
##
## 一个 SceneNode 对应一个 Scene 和一个 main.lua 入口。这个类只管理当前 Scene
## 自身的字段，不知道其他 Node、路由目标、入口 Scene 或整个工程的全局数据。
##
## 这里使用 RefCounted 而不是 Godot 的 Node：SceneNode 是纯数据对象，不是 UI 控件。
## 将来可以由一个单独的 SceneNodeView（继承 GraphNode）负责把它显示在画布上。
##
## 设计边界：
## - 编辑器字段：node_id、position，以及出口的 port_id。
## - 运行时字段：scene_id、title、main_script、cast 和出口名称。
## - 不属于本类：连线、目标 Scene、角色全局定义和 Lua 执行状态。

## 引擎 Scene ID 的格式约束。
##
## 该规则与 engine/src/scene/scene-id.ts 中的规则保持一致。Scene ID 会进入路由、
## 存档和日志，因此这里不接受大写字母、中文、空格或数字开头的 ID。
const SCENE_ID_PATTERN := "^[a-z][a-z0-9_.-]*$"

## 编辑器内部的 Node 身份，建议使用 UUID。
##
## node_id 和 scene_id 必须分开：用户修改 Scene ID 时，编辑器仍应把它视为原来的
## 同一个 Node，这依赖 node_id 保持稳定。
var node_id: String

## Runtime Package 中的稳定 Scene ID。
##
## 该 ID 会被写入 manifest.scenes[].id，并被 Graph 的路由和入口配置引用。单个
## SceneNode 只能检查自身格式是否合法，是否与其他 Node 重复要由更高层负责。
var scene_id: String

## Scene 的显示标题。
##
## 标题只用于编辑器和游戏显示，不参与路由、存档或 Lua 文件定位。空字符串表示
## 当前没有设置标题；运行时导出时会省略这个可选字段。
var title: String

## Scene 的 Lua 主入口路径。
##
## 这是包内逻辑路径，不是操作系统的绝对路径。合法值必须位于 scenes/ 目录内，
## 并且文件名严格为 main.lua。路径是否真实存在、源码是否能编译，属于导出加载器。
var main_script: String

## Node 在编辑器画布中的位置。
##
## position 只保存到编辑器工程，导出 Runtime Package 时必须排除。使用 Vector2 是
## 为了与 Godot 的画布坐标模型保持一致；序列化时会转换为 x/y 两个数字。
var position: Vector2

## 最近一次修改操作的失败原因。
##
## GDScript 当前的修改接口使用 bool 表示成功或失败，而不是抛出异常。调用方在
## 收到 false 后可以读取 last_error，把原因显示在 Inspector 或诊断面板中。
var last_error: String = ""

## 私有的角色绑定列表。
##
## 不直接暴露这个数组，避免外部通过 append、remove 或修改成员对象绕过 Node 的
## 唯一性检查。get_cast() 会返回每个成员的独立副本。
var _cast: Array = []

## 私有的出口列表。
##
## 数组顺序就是出口的显示顺序。出口目标不存储在这里，未来由 Graph/Edge 单独维护。
var _exits: Array = []

## 创建一个 SceneNode。
##
## p_main_script 为空时，会按照当前 scene_id 生成默认入口路径，方便新建 Scene。
## 但默认值仍会写入 main_script，之后修改 scene_id 不会隐式改写脚本路径。
##
## p_cast 和 p_exits 中的合法对象会被复制后保存；不合法对象暂时保留在内部，
## 由 validate_self() 统一报告，这样从工程文件加载草稿时可以一次显示全部问题。
func _init(
        p_node_id: String = "",
        p_scene_id: String = "",
        p_title: String = "",
        p_main_script: String = "",
        p_cast: Array = [],
        p_exits: Array = [],
        p_position: Vector2 = Vector2.ZERO,
) -> void:
    node_id = p_node_id
    scene_id = p_scene_id
    title = p_title
    position = p_position

    # 新建 Node 时提供一个符合 Runtime Package 目录规则的默认脚本路径。
    var requested_script := p_main_script
    if requested_script.is_empty() and not p_scene_id.is_empty():
        requested_script = "scenes/%s/main.lua" % p_scene_id

    # 构造阶段尽量保留输入值；如果路径不合法，先记录错误，之后由 validate_self()
    # 返回完整诊断，而不是在加载一个草稿时只抛出第一个异常。
    if not requested_script.is_empty():
        var script_result := _normalize_main_script(requested_script)
        if bool(script_result["ok"]):
            main_script = str(script_result["value"])
        else:
            main_script = requested_script
            last_error = str(script_result["message"])

    # 拷贝已知类型，保持 SceneNode 对内部数据的所有权；未知类型保留给校验阶段处理。
    for member in p_cast:
        if member is CastMember:
            _cast.append((member as CastMember).duplicate_member())
        else:
            _cast.append(member)

    for port in p_exits:
        if port is ExitPort:
            _exits.append((port as ExitPort).duplicate_port())
        else:
            _exits.append(port)

## 修改 Scene 的稳定 ID。
##
## 这里只检查格式，不检查是否与其他 Node 重复；后者需要 StoryGraph 或 Project
## 维护全局索引。修改成功后 node_id 保持不变，确保编辑器身份稳定。
func rename_scene(new_scene_id: String) -> bool:
    if not _is_valid_scene_id(new_scene_id):
        return _fail("scene_id must match %s" % SCENE_ID_PATTERN)
    scene_id = new_scene_id
    _clear_error()
    return true

## 修改显示标题。
##
## 标题允许为空；这里去掉首尾空格，避免 Inspector 输入产生无意义的空白。
## 标题的显示回退策略由 View 决定，不由数据模型强行写入 scene_id。
func set_title(new_title: String) -> bool:
    title = new_title.strip_edges()
    _clear_error()
    return true

## 设置并规范化 Lua 主入口路径。
##
## 路径会统一为 `/` 分隔，并处理 `.`、`..` 等相对路径片段，但绝对路径、越出
## 包根的路径、Scene 根目录下的 main.lua 以及非 main.lua 文件都会被拒绝。
func set_main_script(path: String) -> bool:
    var result := _normalize_main_script(path)
    if not bool(result["ok"]):
        return _fail(str(result["message"]))
    main_script = str(result["value"])
    _clear_error()
    return true

## 设置编辑器画布坐标。
##
## 坐标没有 Runtime 语义，不需要额外校验；负坐标也是合法的画布位置。
func set_position(new_position: Vector2) -> void:
    position = new_position
    _clear_error()

## 向当前 Scene 添加一个角色绑定。
##
## Node 只负责检查参数对象和当前列表内的重复 character_id。角色 ID 是否存在于
## 项目级角色注册表，由更高层校验。传入对象会被复制，调用方后续修改原对象不会
## 影响 Node 内部状态。
func add_cast_member(member: CastMember) -> bool:
    if member == null:
        return _fail("cast member must not be null")

    var member_errors: Array = member.validate_self("cast")
    if not member_errors.is_empty():
        return _fail(str(member_errors[0]))

    for existing in _cast:
        if existing is CastMember and (existing as CastMember).character_id == member.character_id:
            return _fail("cast contains duplicate character_id '%s'" % member.character_id)

    _cast.append(member.duplicate_member())
    _clear_error()
    return true

## 替换当前 Scene 中已有角色绑定的信息。
##
## 查找使用旧的 character_id，替换后的绑定可以保留原位置，但不能与列表中的其他
## 角色产生重复 ID。整个操作在校验通过后才写入，避免得到半更新状态。
func update_cast_member(character_id: String, member: CastMember) -> bool:
    if member == null:
        return _fail("cast member must not be null")
    var member_errors: Array = member.validate_self("cast")
    if not member_errors.is_empty():
        return _fail(str(member_errors[0]))

    var target_index := _find_cast_index(character_id)
    if target_index < 0:
        return _fail("cast member '%s' does not exist" % character_id)

    for index in range(_cast.size()):
        if index == target_index:
            continue
        var existing = _cast[index]
        if existing is CastMember and (existing as CastMember).character_id == member.character_id:
            return _fail("cast contains duplicate character_id '%s'" % member.character_id)

    _cast[target_index] = member.duplicate_member()
    _clear_error()
    return true

## 按角色 ID 删除当前 Scene 的角色绑定。
##
## 删除角色不会影响项目级 Character，只会移除这个角色在当前 Scene 的局部引用。
func remove_cast_member(character_id: String) -> bool:
    var target_index := _find_cast_index(character_id)
    if target_index < 0:
        return _fail("cast member '%s' does not exist" % character_id)
    _cast.remove_at(target_index)
    _clear_error()
    return true

## 返回当前 Scene 的角色绑定副本。
##
## 返回的是新的 Array，且其中每个 CastMember 也是副本。这样 Inspector 或其他调用方
## 可以安全地读取和临时修改返回值，不会绕过 SceneNode 的唯一性约束。
func get_cast() -> Array:
    var result: Array = []
    for member in _cast:
        if member is CastMember:
            result.append((member as CastMember).duplicate_member())
    return result

## 按角色 ID 获取一个角色绑定副本。
## 找不到时返回 null，而不是创建一个空的 CastMember，避免把“未找到”误认为有效数据。
func get_cast_member(character_id: String) -> CastMember:
    var target_index := _find_cast_index(character_id)
    if target_index < 0:
        return null
    var member = _cast[target_index]
    if member is CastMember:
        return (member as CastMember).duplicate_member()
    return null

## 添加一个出口到当前 Scene。
##
## SceneNode 在列表级别检查 port_id 和 name 都不能重复。出口加入后，其数组位置
## 就是它的显示顺序。传入的 ExitPort 会被复制，Node 取得内部所有权。
func add_exit(port: ExitPort) -> bool:
    if port == null:
        return _fail("exit port must not be null")

    var port_errors: Array = port.validate_self("exit")
    if not port_errors.is_empty():
        return _fail(str(port_errors[0]))

    for existing in _exits:
        if not existing is ExitPort:
            continue
        var existing_port := existing as ExitPort
        if existing_port.port_id == port.port_id:
            return _fail("exits contain duplicate port_id '%s'" % port.port_id)
        if existing_port.name == port.name:
            return _fail("exits contain duplicate name '%s'" % port.name)

    _exits.append(port.duplicate_port())
    _clear_error()
    return true

## 修改一个出口的名称，但不改变它的 port_id。
##
## 这保证未来的编辑器连线仍可引用同一个端口。由于出口名称是当前 Scene 的本地
## 标识，改名时必须检查是否与同一 Node 的其他出口重复。
func rename_exit(port_id: String, new_name: String) -> bool:
    var normalized_name := new_name.strip_edges()
    if normalized_name.is_empty():
        return _fail("exit name must not be empty")

    var target_index := _find_exit_index(port_id)
    if target_index < 0:
        return _fail("exit port '%s' does not exist" % port_id)

    for index in range(_exits.size()):
        if index == target_index:
            continue
        var existing = _exits[index]
        if existing is ExitPort and (existing as ExitPort).name == normalized_name:
            return _fail("exits contain duplicate name '%s'" % normalized_name)

    (_exits[target_index] as ExitPort).name = normalized_name
    _clear_error()
    return true

## 删除一个出口定义。
##
## SceneNode 不知道外部是否存在指向该出口的连线，因此这里只修改自身列表；未来
## Graph 在调用此方法时，需要负责处理失效的 RouteEdge。
func remove_exit(port_id: String) -> bool:
    var target_index := _find_exit_index(port_id)
    if target_index < 0:
        return _fail("exit port '%s' does not exist" % port_id)
    _exits.remove_at(target_index)
    _clear_error()
    return true

## 调整出口在当前 Scene 中的显示顺序。
##
## 这里移动的是 ExitPort 对象本身，因此 port_id 和 name 都保持不变。未来 Graph 如果
## 使用数组索引绘制端口，应在出口顺序变化后重新计算视图位置，但不需要修改连线 ID。
func move_exit(port_id: String, new_index: int) -> bool:
    if new_index < 0 or new_index >= _exits.size():
        return _fail("exit index %d is out of range" % new_index)

    var current_index := _find_exit_index(port_id)
    if current_index < 0:
        return _fail("exit port '%s' does not exist" % port_id)
    if current_index == new_index:
        _clear_error()
        return true

    var port = _exits.pop_at(current_index)
    _exits.insert(new_index, port)
    _clear_error()
    return true

## 返回当前 Scene 的出口副本列表。
##
## 列表顺序就是编辑器中的显示顺序，也是 to_runtime_scene() 生成 exits 字符串数组
## 的顺序。返回对象全部是副本，外部不能直接绕过 Node 的规则修改内部出口。
func get_exits() -> Array:
    var result: Array = []
    for port in _exits:
        if port is ExitPort:
            result.append((port as ExitPort).duplicate_port())
    return result

## 按稳定 port_id 获取一个出口副本。
## 找不到时返回 null；调用方若要修改出口，应使用 rename_exit() 或其他 Node 方法。
func get_exit(port_id: String) -> ExitPort:
    var target_index := _find_exit_index(port_id)
    if target_index < 0:
        return null
    var port = _exits[target_index]
    if port is ExitPort:
        return (port as ExitPort).duplicate_port()
    return null

## 检查当前 SceneNode 能独立判断的所有本地约束。
##
## 返回 Array 而不是遇到第一个错误就停止，便于编辑器一次在诊断面板中显示多个
## 字段问题。这里不检查跨 Node 的 scene_id 唯一性，也不检查外部文件和角色引用。
func validate_self() -> Array:
    var errors: Array = []

    # node_id 是编辑器身份，只要求非空且没有首尾空格；全局唯一由 Graph/Project 检查。
    if node_id.is_empty():
        errors.append("node_id must not be empty")
    elif node_id != node_id.strip_edges():
        errors.append("node_id must not have surrounding whitespace")

    if not _is_valid_scene_id(scene_id):
        errors.append("scene_id must match %s" % SCENE_ID_PATTERN)

    if title != title.strip_edges():
        errors.append("title must not have surrounding whitespace")

    if main_script.is_empty():
        errors.append("main_script must not be empty")
    else:
        var script_result := _normalize_main_script(main_script)
        if not bool(script_result["ok"]):
            errors.append(str(script_result["message"]))

    # Scene 内同一个角色只能绑定一次。character_id 是否真实存在，属于项目级检查。
    var character_ids: Dictionary = {}
    for index in range(_cast.size()):
        var member = _cast[index]
        var cast_path := "cast[%d]" % index
        if not member is CastMember:
            errors.append("%s must be a CastMember" % cast_path)
            continue
        var cast_member := member as CastMember
        errors.append_array(cast_member.validate_self(cast_path))
        if character_ids.has(cast_member.character_id):
            errors.append("cast contains duplicate character_id '%s'" % cast_member.character_id)
        else:
            character_ids[cast_member.character_id] = true

    # port_id 用于编辑器连线引用，name 用于运行时出口查找，两者都需要在本 Node 内唯一。
    var port_ids: Dictionary = {}
    var exit_names: Dictionary = {}
    for index in range(_exits.size()):
        var port = _exits[index]
        var exit_path := "exits[%d]" % index
        if not port is ExitPort:
            errors.append("%s must be an ExitPort" % exit_path)
            continue
        var exit_port := port as ExitPort
        errors.append_array(exit_port.validate_self(exit_path))
        if port_ids.has(exit_port.port_id):
            errors.append("exits contain duplicate port_id '%s'" % exit_port.port_id)
        else:
            port_ids[exit_port.port_id] = true
        if exit_names.has(exit_port.name):
            errors.append("exits contain duplicate name '%s'" % exit_port.name)
        else:
            exit_names[exit_port.name] = true

    return errors

## 转换为编辑器工程文件中的字典。
##
## 这个结果保留编辑器所需的信息：nodeId、出口的 portId 和画布 position。返回的
## 嵌套数组和字典都是新对象，可以直接交给 JSON.stringify()，不会暴露内部列表。
func to_editor_dict() -> Dictionary:
    var cast_data: Array = []
    for member in _cast:
        if member is CastMember:
            cast_data.append((member as CastMember).to_editor_dict())

    var exit_data: Array = []
    for port in _exits:
        if port is ExitPort:
            exit_data.append((port as ExitPort).to_editor_dict())

    return {
        "nodeId": node_id,
        "sceneId": scene_id,
        "title": title,
        "mainScript": main_script,
        "cast": cast_data,
        "exits": exit_data,
        "position": {
            "x": position.x,
            "y": position.y,
        },
    }

## 转换为 Runtime Package 的 Scene 定义。
##
## 导出前先执行本地校验；只要 Node 自身不合法，就返回空字典并记录首个错误。跨
## Node 引用、Lua 文件存在性和脚本语法仍需由更高层导出器与 PackageLoader 检查。
##
## 与编辑器字典相比，结果会移除 node_id、出口 port_id 和 position，只保留引擎需要的
## scene_id、title、main_script、cast 以及出口名称。
func to_runtime_scene() -> Dictionary:
    var errors := validate_self()
    if not errors.is_empty():
        _fail(str(errors[0]))
        return {}

    var cast_data: Array = []
    for member in _cast:
        cast_data.append((member as CastMember).to_runtime_definition())

    var exit_names: Array = []
    for port in _exits:
        exit_names.append((port as ExitPort).to_runtime_name())

    var result: Dictionary = {
        "id": scene_id,
        "mainScript": main_script,
        "cast": cast_data,
        "exits": exit_names,
    }
    if not title.is_empty():
        result["title"] = title
    _clear_error()
    return result

## 在私有角色列表中查找角色位置。
## 使用索引而不是直接保存引用，方便统一实现替换和删除操作。
func _find_cast_index(character_id: String) -> int:
    for index in range(_cast.size()):
        var member = _cast[index]
        if member is CastMember and (member as CastMember).character_id == character_id:
            return index
    return -1

## 在私有出口列表中查找稳定端口 ID 的位置。
func _find_exit_index(port_id: String) -> int:
    for index in range(_exits.size()):
        var port = _exits[index]
        if port is ExitPort and (port as ExitPort).port_id == port_id:
            return index
    return -1

## 用引擎约定的正则检查 Scene ID。
## 正则对象每次临时创建，避免把可变的 RegEx 实例作为 Node 状态保存。
func _is_valid_scene_id(value: String) -> bool:
    var regex := RegEx.new()
    if regex.compile(SCENE_ID_PATTERN) != OK:
        return false
    return regex.search(value) != null

## 规范化并检查 main.lua 的包内逻辑路径。
##
## 这里实现的是引擎 VirtualPath 的必要子集：统一分隔符，处理当前目录和父目录，
## 拒绝绝对路径、盘符路径、NUL、越出包根的路径，并要求最终文件位于某个 Scene
## 目录中且文件名为 main.lua。这个类不访问文件系统，因此不检查文件是否存在。
func _normalize_main_script(path: String) -> Dictionary:
    if path.is_empty():
        return {"ok": false, "message": "main_script must not be empty"}
    if path != path.strip_edges():
        return {"ok": false, "message": "main_script must not have surrounding whitespace"}

    # Runtime Package 使用 `/` 作为逻辑路径分隔符；Windows 输入的反斜杠在这里统一。
    var normalized := path.replace("\\", "/")
    if normalized.to_utf8_buffer().has(0):
        return {"ok": false, "message": "main_script must not contain a NUL character"}
    if normalized.begins_with("/") or (normalized.length() >= 2 and normalized[1] == ":"):
        return {"ok": false, "message": "main_script must be a relative package path"}

    # 逐段处理路径，避免直接使用操作系统路径 API 把包内路径解析成宿主路径。
    var segments := PackedStringArray()
    for segment in normalized.split("/"):
        if segment.is_empty() or segment == ".":
            continue
        if segment == "..":
            if segments.is_empty():
                return {"ok": false, "message": "main_script must not escape the package root"}
            segments.remove_at(segments.size() - 1)
            continue
        segments.append(segment)

    var canonical := "/".join(segments)
    if not canonical.begins_with("scenes/"):
        return {"ok": false, "message": "main_script must be stored under the scenes/ directory"}
    if canonical.get_file() != "main.lua":
        return {"ok": false, "message": "main_script must point to a main.lua file"}
    var parent := canonical.get_base_dir()
    if parent == "." or parent == "scenes":
        return {"ok": false, "message": "main_script must be stored inside a Scene directory"}

    return {"ok": true, "value": canonical}

## 记录一次修改失败，并以 false 作为统一的失败返回值。
func _fail(message: String) -> bool:
    last_error = message
    return false

## 成功完成修改后清空旧错误，避免调用方读取到过期诊断。
func _clear_error() -> void:
    last_error = ""
