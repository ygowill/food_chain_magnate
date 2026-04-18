# GameOver 在线结束返回契约：应请求离房，并在收到空 room_state 后返回联机大厅
class_name GameOverOnlineReturnContractTest
extends RefCounted

const _PATH := "res://ui/scenes/game/panel/end_panels.gd"


static func run() -> Result:
	var read_r := _read_text(_PATH)
	if not read_r.ok:
		return read_r
	var text: String = str(read_r.value)

	if text.find("request_leave_room()") < 0:
		return Result.failure("联机结算返回逻辑应请求 leave_room: %s" % _PATH)
	if text.find("_on_online_game_over_leave_room_state_updated") < 0:
		return Result.failure("联机结算返回逻辑应等待空 room_state 再跳转大厅: %s" % _PATH)
	if text.find("goto_online_lobby()") < 0:
		return Result.failure("联机结算返回逻辑应跳回 online_lobby: %s" % _PATH)
	if text.find("返回房间列表") < 0:
		return Result.failure("联机结算返回按钮应显示“返回房间列表”: %s" % _PATH)

	return Result.success({})


static func _read_text(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取文件: %s" % path)
	var text := file.get_as_text()
	file.close()
	return Result.success(text)
