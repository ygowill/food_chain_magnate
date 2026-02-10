class_name GamePanelModalsControllerKindContractTest
extends RefCounted

const _PATH := "res://ui/scenes/game/game_panel_modals_controller.gd"

static func run() -> Result:
	var read_r := _read_text(_PATH)
	if not read_r.ok:
		return read_r
	var text: String = str(read_r.value)

	if text.find("kind == \"kimchi\"") >= 0:
		return Result.failure("controller 不应硬编码 kind==kimchi: %s" % _PATH)
	if text.find("\"fridge_keep\"") >= 0:
		return Result.failure("controller 不应硬编码 fridge_keep kind 字符串: %s" % _PATH)

	return Result.success({})

static func _read_text(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取文件: %s" % path)
	var text := file.get_as_text()
	file.close()
	return Result.success(text)
