extends RefCounted
class_name NodeMapModule

## Node Map 领域模块的统一入口。
##
## 这个脚本本身不保存运行时状态，也不创建 SceneMap 实例；它只是提供一个稳定的
## 模块边界，方便宿主项目一次性 preload 本模块，并通过模块入口访问核心类型。
##
## 当前核心类型由 Godot 的 class_name 注册：
## - CastMember：Scene 内的角色绑定；
## - ExitPort：Scene 的本地出口；
## - SceneNode：单个 Scene 的编辑器模型；
## - RouteEdge：两个 SceneNode 之间的路由引用；
## - SceneMap：Node 和 RouteEdge 的聚合根。
##
## GDScript 不能像 Python 一样在脚本文件中导出类型别名，因此具体对象仍通过
## 各自的 class_name 使用。这个入口类的主要作用是标识模块边界和承载模块版本。

## 当前 Node Map 数据模型版本。
##
## 这是编辑器模块内部的数据结构版本，不等同于 Runtime Package formatVersion，也
## 不等同于游戏存档版本。字段结构发生不兼容变化时应递增这个值。
const MODULE_VERSION := 1

## 返回模块版本，供宿主或调试工具读取。
static func version() -> int:
	return MODULE_VERSION
