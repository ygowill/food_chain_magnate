# 教学边界契约测试
# 防止导览步骤与 tour 运行逻辑重新混回主场景脚本。
class_name TutorialSceneBoundaryContractTest
extends RefCounted

const SCENE_BOUNDARIES := {
	"res://ui/scenes/game/game.gd": [
		"start_tour(",
		"TutorialControllerClass",
		"\"target_key\":",
	],
	"res://ui/scenes/setup/game_setup.gd": [
		"start_tour(",
		"TutorialControllerClass",
		"\"target_key\":",
	],
}

const SETTINGS_CONFIG_BOUNDARIES := {
	"res://autoload/globals.gd": [
		"tutorial_enabled",
		"tutorial_auto_popup",
		"setup_welcome_seen",
		"setup_tour_seen",
		"game_ui_tour_seen",
		"flow_hints_seen",
		"_erase_legacy_tutorial_settings",
	],
	"res://ui/dialogs/settings_dialog.gd": [
		"tutorial_enabled",
		"tutorial_auto_popup",
		"setup_welcome_seen",
		"setup_tour_seen",
		"game_ui_tour_seen",
		"flow_hints_seen",
		"_erase_legacy_tutorial_settings",
	],
}

static func run() -> Result:
	for path_val in SCENE_BOUNDARIES.keys():
		var path := str(path_val)
		var read_r := _read_text(path)
		if not read_r.ok:
			return read_r
		var text := str(read_r.value)
		var forbidden_tokens: Array = SCENE_BOUNDARIES[path]
		for token_val in forbidden_tokens:
			var token := str(token_val)
			if text.find(token) >= 0:
				return Result.failure("%s 不应直接包含 tutorial 细节: %s" % [path, token])
	for path_val in SETTINGS_CONFIG_BOUNDARIES.keys():
		var path := str(path_val)
		var read_r := _read_text(path)
		if not read_r.ok:
			return read_r
		var text := str(read_r.value)
		var forbidden_tokens: Array = SETTINGS_CONFIG_BOUNDARIES[path]
		for token_val in forbidden_tokens:
			var token := str(token_val)
			if text.find(token) >= 0:
				return Result.failure("%s 不应保留教学设置历史键: %s" % [path, token])
	return Result.success({
		"files": SCENE_BOUNDARIES.keys().size() + SETTINGS_CONFIG_BOUNDARIES.keys().size(),
	})

static func _read_text(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取文件: %s" % path)
	var text := file.get_as_text()
	file.close()
	return Result.success(text)
