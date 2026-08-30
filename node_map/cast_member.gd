extends RefCounted
class_name CastMember

## Scene 内的角色绑定数据。
##
## 一个 CastMember 只表示“这个角色在当前 Scene 中如何被引用”。
## 它不拥有项目级角色定义，也不保存角色在游戏运行时的状态。
## 角色是否存在、角色的立绘资源是否有效，应由 Project 或导出校验层负责。

## 指向项目级角色注册表的稳定角色 ID。
var character_id: String

## 角色在当前 Scene 中承担的叙事身份，例如“女主角”或“学生”。
## 空字符串表示当前 Scene 没有额外指定身份。
var role: String

## 当前 Scene 对角色显示名称的覆盖值。
## 空字符串表示使用角色全局定义中的名称。
var display_name: String

## 创建一个 Scene 内的角色绑定。
##
## 构造函数只保存传入值，不在这里检查角色是否存在；这样可以先加载编辑器
## 工程中的草稿数据，再由 SceneNode.validate_self() 和项目级校验统一报告问题。
func _init(
		p_character_id: String = "",
		p_role: String = "",
		p_display_name: String = "",
) -> void:
	character_id = p_character_id
	role = p_role
	display_name = p_display_name

## 创建当前对象的独立副本。
##
## SceneNode 在接收 CastMember 时会复制对象，避免调用方继续修改原对象后，
## 意外改变 Node 内部的数据。
func duplicate_member() -> CastMember:
	return CastMember.new(character_id, role, display_name)

## 检查角色绑定自身可以检查的约束。
##
## 这里故意只检查字段格式，不检查 character_id 是否在整个工程中存在。
## path 用于生成能定位到具体字段的错误信息，例如 cast[0].character_id。
func validate_self(path: String = "cast") -> Array:
	var errors: Array = []

	# 角色 ID 是绑定成立的必要信息；首尾空格不在这里自动删除，避免静默改写引用。
	if character_id.is_empty():
		errors.append("%s.character_id must not be empty" % path)
	elif character_id != character_id.strip_edges():
		errors.append("%s.character_id must not have surrounding whitespace" % path)

	# 可选文本允许为空，但如果有值，就不应带有首尾空格。
	if role != role.strip_edges():
		errors.append("%s.role must not have surrounding whitespace" % path)
	if display_name != display_name.strip_edges():
		errors.append("%s.display_name must not have surrounding whitespace" % path)
	return errors

## 转换为编辑器工程中的字典格式。
##
## 编辑器字段使用 camelCase，以便后续直接写入 JSON；空的可选字段被省略，
## 从而区分“未设置”和一个实际存在的空文本值。
func to_editor_dict() -> Dictionary:
	var result: Dictionary = {
		"characterId": character_id,
	}
	if not role.is_empty():
		result["role"] = role
	if not display_name.is_empty():
		result["displayName"] = display_name
	return result

## 转换为 Runtime Package 中 Scene.cast 使用的字典。
##
## 当前运行时的 SceneCastMember 与编辑器中的角色绑定字段相同，因此复用同一
## 序列化结果。未来如果编辑器字段增加，应在这里明确过滤掉编辑器专属字段。
func to_runtime_definition() -> Dictionary:
	return to_editor_dict()
