# core 架构边界守卫测试（阶段 0）
# 目标：
# - core 非测试脚本不得直接引用 `res://ui/`
# - UI 元数据职责不得继续扩散到新的 core 文件
# - core 非测试脚本不得直接访问 autoload 全局对象
# - ProjectSettings 读取仅允许停留在当前 provider/version 桥接点
class_name CoreArchitectureBoundaryContractTest
extends RefCounted

const _CORE_ROOT := "res://core"
const _CORE_TESTS_PATH := "res://core/tests/"

const _UI_METADATA_ALLOWLIST := {
	"phase_action_ui_modals": {
		"res://core/modules/v2/ruleset/ui_extensions.gd": true,
	},
	"piece_ui_hints": {
		"res://core/modules/v2/ruleset/ui_extensions.gd": true,
		"res://core/rules/piece_ui_hints_registry.gd": true,
	},
	"effect_ui_texts": {
		"res://core/modules/v2/ruleset/ui_extensions.gd": true,
		"res://core/rules/effect_ui_text_registry.gd": true,
	},
	"milestone_effect_ui_texts": {
		"res://core/modules/v2/ruleset/ui_extensions.gd": true,
		"res://core/rules/effect_ui_text_registry.gd": true,
	},
	"map_overlay_providers": {
		"res://core/modules/v2/ruleset/ui_extensions.gd": true,
		"res://core/rules/map_overlay_provider_registry.gd": true,
	},
	"ui_hide_if_not_initiatable": {
		"res://core/actions/action_executor.gd": true,
	},
	"ui_piece_ids": {
		"res://core/actions/action_executor.gd": true,
	},
}

const _DIRECT_AUTOLOAD_PATTERNS := [
	"EventBus.",
	"Globals.",
	"GameLog.",
	"DebugFlags.",
	"get_node(\"/root/",
	"get_node_or_null(\"/root/",
	"get_node('/root/",
	"get_node_or_null('/root/",
]

const _PROJECT_SETTINGS_ALLOWLIST := {
	"res://core/engine/game_engine/action_setup.gd": true,
	"res://core/engine/game_engine/command_runner.gd": true,
	"res://core/engine/game_engine/archive.gd": true,
	"res://core/state/game_state_factory.gd": true,
}

static func run() -> Result:
	var r1 := _assert_no_direct_ui_refs()
	if not r1.ok:
		return r1

	var r2 := _assert_ui_metadata_confined()
	if not r2.ok:
		return r2

	var r3 := _assert_no_direct_autoload_globals()
	if not r3.ok:
		return r3

	var r4 := _assert_project_settings_usage_confined()
	if not r4.ok:
		return r4

	return Result.success({
		"checks": 4,
	})

static func _assert_no_direct_ui_refs() -> Result:
	var files: Array[String] = []
	var list_r := _list_gd_files_recursive(_CORE_ROOT, files)
	if not list_r.ok:
		return list_r

	for path in files:
		if _should_skip_file(path):
			continue
		var hit := _find_code_pattern(path, ["res://ui/"])
		if not hit.is_empty():
			return Result.failure("core 不应直接引用 UI 资源: %s:%d contains %s" % [path, int(hit.get("line", 1)), str(hit.get("pattern", ""))])

	return Result.success()

static func _assert_ui_metadata_confined() -> Result:
	var files: Array[String] = []
	var list_r := _list_gd_files_recursive(_CORE_ROOT, files)
	if not list_r.ok:
		return list_r

	for path in files:
		if _should_skip_file(path):
			continue
		for pattern in _UI_METADATA_ALLOWLIST.keys():
			var hit := _find_code_pattern(path, [pattern])
			if hit.is_empty():
				continue
			var allowed: Dictionary = _UI_METADATA_ALLOWLIST[pattern]
			if allowed.has(path):
				continue
			return Result.failure("UI 元数据职责不应扩散到新的 core 文件: %s:%d contains %s" % [path, int(hit.get("line", 1)), pattern])

	return Result.success()

static func _assert_no_direct_autoload_globals() -> Result:
	var files: Array[String] = []
	var list_r := _list_gd_files_recursive(_CORE_ROOT, files)
	if not list_r.ok:
		return list_r

	for path in files:
		if _should_skip_file(path):
			continue
		var hit := _find_code_pattern(path, _DIRECT_AUTOLOAD_PATTERNS)
		if not hit.is_empty():
			return Result.failure("core 不应直接访问 autoload 全局对象: %s:%d contains %s" % [path, int(hit.get("line", 1)), str(hit.get("pattern", ""))])

	return Result.success()

static func _assert_project_settings_usage_confined() -> Result:
	var files: Array[String] = []
	var list_r := _list_gd_files_recursive(_CORE_ROOT, files)
	if not list_r.ok:
		return list_r

	for path in files:
		if _should_skip_file(path):
			continue
		var hit := _find_code_pattern(path, ["ProjectSettings.get_setting", "ProjectSettings.has_setting"])
		if hit.is_empty():
			continue
		if _PROJECT_SETTINGS_ALLOWLIST.has(path):
			continue
		return Result.failure("新增 ProjectSettings 读取前需先收敛依赖边界: %s:%d contains %s" % [path, int(hit.get("line", 1)), str(hit.get("pattern", ""))])

	return Result.success()

static func _should_skip_file(path: String) -> bool:
	return path.begins_with(_CORE_TESTS_PATH)

static func _find_code_pattern(path: String, patterns: Array) -> Dictionary:
	var read_r := _read_text(path)
	if not read_r.ok:
		return {"error": read_r.error}

	var text: String = str(read_r.value)
	var lines := text.split("\n")
	for i in range(lines.size()):
		var code := _strip_inline_comment(str(lines[i]))
		if code.strip_edges().is_empty():
			continue
		for pattern_variant in patterns:
			var pattern := str(pattern_variant)
			if code.find(pattern) >= 0:
				return {
					"line": i + 1,
					"pattern": pattern,
				}
	return {}

static func _strip_inline_comment(line: String) -> String:
	var idx := line.find("#")
	if idx < 0:
		return line
	return line.substr(0, idx)

static func _list_gd_files_recursive(root_dir: String, out: Array[String]) -> Result:
	if root_dir.is_empty():
		return Result.failure("root_dir 不能为空")
	if out == null:
		return Result.failure("out 不能为空")

	var dir := DirAccess.open(root_dir)
	if dir == null:
		return Result.failure("无法打开目录: %s" % root_dir)

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path := root_dir.path_join(entry)
		if dir.current_is_dir():
			var sub := _list_gd_files_recursive(path, out)
			if not sub.ok:
				dir.list_dir_end()
				return sub
		else:
			if entry.ends_with(".gd"):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return Result.success()

static func _read_text(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取文件: %s" % path)
	var text := file.get_as_text()
	file.close()
	return Result.success(text)
