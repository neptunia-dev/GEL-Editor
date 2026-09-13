extends RefCounted
class_name EngineCliBridge

## Godot 编辑器到 TypeScript 引擎开发 CLI 的窄桥接。
##
## 此类只负责启动已构建的 Node CLI 并返回结构化进程结果；它不解析
## Runtime Package，也不在 GDScript 中复刻 PackageLoader / StoryRunner 逻辑。
## 默认约定 editor 与 engine 是同级目录；集成宿主可以通过环境变量覆盖：
##
##   GEL_ENGINE_CLI       已构建的 dist/src/cli/index.js 的绝对路径
##   GEL_NODE_EXECUTABLE  Node 可执行文件路径（默认 `node`）

const ENGINE_CLI_ENV := "GEL_ENGINE_CLI"
const NODE_EXECUTABLE_ENV := "GEL_NODE_EXECUTABLE"

func validate(package_directory: String) -> Dictionary:
	return _invoke("validate", package_directory)

## 自动推进 dialogue/wait，并为 choice 选择第一个 enabled 选项。
## 这是可重复的引擎冒烟运行，不是 Godot 内嵌交互式预览。
func run_auto(package_directory: String) -> Dictionary:
	return _invoke("run", package_directory, ["--auto"])

func get_cli_path() -> String:
	var configured := OS.get_environment(ENGINE_CLI_ENV).strip_edges()
	if not configured.is_empty():
		return configured.simplify_path()
	var editor_root := ProjectSettings.globalize_path("res://").simplify_path()
	return editor_root.path_join("..").path_join("engine").path_join("dist").path_join("src").path_join("cli").path_join("index.js").simplify_path()

func get_node_executable() -> String:
	var configured := OS.get_environment(NODE_EXECUTABLE_ENV).strip_edges()
	return configured if not configured.is_empty() else "node"

func _invoke(command: String, package_directory: String, trailing_arguments: Array = []) -> Dictionary:
	var diagnostics: Array = []
	if package_directory.strip_edges().is_empty():
		diagnostics.append(_error("invalid_package_directory", "Runtime Package directory must not be empty."))
		return _failure(diagnostics)
	var cli_path := get_cli_path()
	if not FileAccess.file_exists(cli_path):
		diagnostics.append(_error("engine_cli_missing", "Node engine CLI was not found at '" + cli_path + "'. Run npm --prefix engine run build or set " + ENGINE_CLI_ENV + "."))
		return _failure(diagnostics)

	var arguments: Array = [cli_path, command, package_directory]
	arguments.append_array(trailing_arguments)
	var output: Array = []
	# OS.execute is synchronous in Godot 4.6. The Node-side Lua instruction
	# budget is the hard guard for authored Lua; this bridge deliberately keeps
	# process invocation simple until the editor is converted to an async host.
	# A future interactive preview should use a long-lived IPC worker rather than
	# polling process pipes from the UI thread.
	var exit_code := OS.execute(get_node_executable(), PackedStringArray(arguments), output, true)
	var text := _join_output(output)
	var parsed: Variant = _parse_last_json(text)
	if exit_code != 0:
		diagnostics.append(_error("engine_cli_failed", "Engine " + command + " failed with exit code " + str(exit_code) + (": " + text.strip_edges() if not text.strip_edges().is_empty() else ".")))
		return {
			"ok": false,
			"diagnostics": diagnostics,
			"exit_code": exit_code,
			"output": text,
			"result": parsed,
		}
	return {
		"ok": true,
		"diagnostics": [],
		"exit_code": exit_code,
		"output": text,
		"result": parsed,
	}

func _join_output(output: Array) -> String:
	var text := ""
	for item in output:
		if not text.is_empty():
			text += "\n"
		text += str(item)
	return text

func _parse_last_json(text: String) -> Variant:
	var lines := text.split("\n", false)
	for index in range(lines.size() - 1, -1, -1):
		var json := JSON.new()
		if json.parse(lines[index]) == OK:
			return json.data
	return null

func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "severity": "error", "graph_id": "", "node_id": "", "port_id": "", "link_id": ""}

func _failure(diagnostics: Array) -> Dictionary:
	return {"ok": false, "diagnostics": diagnostics, "exit_code": -1, "output": "", "result": null}
