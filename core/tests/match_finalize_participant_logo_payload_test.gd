# 联机结算：历史记录上报应使用对局状态中的餐厅 Logo，而不是座位档案里的旧值
class_name MatchFinalizeParticipantLogoPayloadTest
extends RefCounted

const ServerLogicClass = preload("res://autoload/net_client/server.gd")


class _DummyRoom:
	extends RefCounted

	var _seat_profile_by_seat_index: Dictionary = {}


class _DummyState:
	extends RefCounted

	var players: Array = []


static func run() -> Result:
	var server = ServerLogicClass.new()
	var room := _DummyRoom.new()
	room._seat_profile_by_seat_index = {
		0: {
			"name": "Host",
			"restaurant_logo_id": -1,
		},
	}

	var state := _DummyState.new()
	state.players = [{
		"restaurant_logo_id": 4,
		"cash": 12,
		"forfeited": false,
		"employees": [],
		"reserve_employees": [],
		"busy_marketers": [],
		"restaurants": [],
		"milestones": [],
		"inventory": {},
	}]

	var payload: Dictionary = server._build_participant_score_payload(room, state, 0)
	if int(payload.get("restaurant_logo_id", -1)) != 4:
		return Result.failure("结算上报应使用 state.players 中的餐厅 Logo，实际: %s" % str(payload))
	if str(payload.get("display_name", "")) != "Host":
		return Result.failure("结算上报应保留玩家显示名，实际: %s" % str(payload))
	return Result.success()
