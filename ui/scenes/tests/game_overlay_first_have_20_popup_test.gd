class_name GameOverlayFirstHave20PopupTest
extends RefCounted

const _PATH := "res://ui/scenes/game/overlay/controller.gd"

static func run(seed_val: int = 12345) -> Result:
	var _unused := seed_val
	var read_r := _read_text(_PATH)
	if not read_r.ok:
		return read_r
	var text: String = str(read_r.value)
	if text.find("_maybe_show_milestone_reward_view") >= 0:
		return Result.failure("overlay 不应直接打开 first_have_20 储备卡总览: %s" % _PATH)
	if text.find("show_reserve_cards_overview") >= 0:
		return Result.failure("overlay 不应直接调用 show_reserve_cards_overview: %s" % _PATH)
	return Result.success({})

static func _read_text(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取文件: %s" % path)
	var text := file.get_as_text()
	file.close()
	return Result.success(text)
