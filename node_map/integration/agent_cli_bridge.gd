extends RefCounted
class_name AgentCliBridge

## Godot 到 `gel-engine author` 的窄桥接。
##
## 短命令（init/validate）可用同步 execute；LLM 阶段必须 start_author +
## status.json 轮询，不能在 UI 线程 OS.execute。

const ENGINE_CLI := preload("res://node_map/integration/engine_cli_bridge.gd")

func init_directory(directory: String) -> Dictionary:
	return run_author("init", directory)

func validate_directory(directory: String) -> Dictionary:
	return run_author("validate", directory)

func run_author(stage: String, directory: String, extra: Array = []) -> Dictionary:
	var engine = ENGINE_CLI.new()
	if directory.strip_edges().is_empty():
		return engine._failure([engine._error("invalid_package_directory", "Authoring directory must not be empty.")])
	var cli_path := engine.get_cli_path()
	if not FileAccess.file_exists(cli_path):
		return engine._failure([engine._error("engine_cli_missing", "Node engine CLI was not found at '" + cli_path + "'.")])
	var arguments: Array = [cli_path, "author", stage, directory]
	arguments.append_array(extra)
	var output: Array = []
	var exit_code := OS.execute(engine.get_node_executable(), PackedStringArray(arguments), output, true)
	var text := engine._join_output(output)
	var parsed: Variant = engine._parse_last_json(text)
	if exit_code != 0:
		return {
			"ok": false,
			"diagnostics": [engine._error("engine_cli_failed", "Engine author " + stage + " failed with exit code " + str(exit_code) + (": " + text.strip_edges() if not text.strip_edges().is_empty() else "."))],
			"exit_code": exit_code,
			"output": text,
			"result": parsed,
		}
	return {"ok": true, "diagnostics": [], "exit_code": exit_code, "output": text, "result": parsed}

func start_author(stage: String, directory: String, extra: Array = []) -> Dictionary:
	var engine = ENGINE_CLI.new()
	if directory.strip_edges().is_empty():
		return {"ok": false, "pid": -1, "diagnostics": [engine._error("invalid_package_directory", "Authoring directory must not be empty.")]}
	var cli_path := engine.get_cli_path()
	if not FileAccess.file_exists(cli_path):
		return {"ok": false, "pid": -1, "diagnostics": [engine._error("engine_cli_missing", "Node engine CLI was not found at '" + cli_path + "'.")]}
	var arguments: PackedStringArray = PackedStringArray([cli_path, "author", stage, directory])
	for item in extra:
		arguments.append(str(item))
	var pid := OS.create_process(engine.get_node_executable(), arguments)
	if pid < 0:
		return {"ok": false, "pid": pid, "diagnostics": [engine._error("engine_cli_failed", "Could not start author process.")]}
	return {"ok": true, "pid": pid, "diagnostics": []}

func read_status(directory: String) -> Dictionary:
	var path := directory.path_join("status.json")
	if not FileAccess.file_exists(path):
		return {"state": "idle", "stage": "", "ok": true, "message": "", "diagnostics": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"state": "idle", "stage": "", "ok": false, "message": "Could not read status.json", "diagnostics": []}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"state": "idle", "stage": "", "ok": true, "message": "", "diagnostics": []}
	return json.data
