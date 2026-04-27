# 联机结算：历史记录上报应使用对局状态中的餐厅 Logo，而不是座位档案里的旧值
class_name MatchFinalizeParticipantLogoPayloadTest
extends RefCounted

const ServerMatchFinalizePayloadBuilderClass = preload("res://autoload/net_client/server_match_finalize_payload_builder.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")


class _DummyRoom:
	extends RefCounted

	var _seat_profile_by_seat_index: Dictionary = {}
	var _user_id_by_seat_index: Dictionary = {}
	var game_engine = null


class _DummyState:
	extends RefCounted

	var players: Array = []


static func run() -> Result:
	var r := _test_prefers_state_logo_over_seat_profile()
	if not r.ok:
		return r
	r = _test_sparse_seat_indices_fall_back_to_player_order()
	if not r.ok:
		return r
	r = _test_participant_stats_payload_uses_rebuilt_events()
	if not r.ok:
		return r
	return Result.success()

static func _test_prefers_state_logo_over_seat_profile() -> Result:
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

	var payload: Dictionary = ServerMatchFinalizePayloadBuilderClass.build_participant_score_payload(room, state, 0)
	if int(payload.get("restaurant_logo_id", -1)) != 4:
		return Result.failure("结算上报应使用 state.players 中的餐厅 Logo，实际: %s" % str(payload))
	if str(payload.get("display_name", "")) != "Host":
		return Result.failure("结算上报应保留玩家显示名，实际: %s" % str(payload))
	return Result.success()

static func _test_sparse_seat_indices_fall_back_to_player_order() -> Result:
	var room := _DummyRoom.new()
	room._seat_profile_by_seat_index = {
		1: {"name": "Seat1", "restaurant_logo_id": 0},
		3: {"name": "Seat3", "restaurant_logo_id": 1},
	}
	room._user_id_by_seat_index = {
		1: "u1",
		3: "u3",
	}

	var state := _DummyState.new()
	state.players = [
		{
			"cash": 12,
			"forfeited": false,
			"employees": ["ceo"],
			"reserve_employees": ["trainer"],
			"busy_marketers": [],
			"restaurants": ["rest_a"],
			"milestones": ["first_have_20"],
			"inventory": {"burger": 1},
		},
		{
			"cash": 18,
			"forfeited": false,
			"employees": ["brand_manager"],
			"reserve_employees": [],
			"busy_marketers": ["marketing_trainee"],
			"restaurants": ["rest_b"],
			"milestones": ["first_billboard"],
			"inventory": {"lemonade": 2},
		},
	]

	var participants: Array = ServerMatchFinalizePayloadBuilderClass.build_finalize_participants(room, state, 0)
	if participants.size() != 2:
		return Result.failure("sparse seats fallback 应保留 2 名参与者，实际: %s" % str(participants))

	var score_1: Variant = JSON.parse_string(str(Dictionary(participants[0]).get("score_json", "")))
	var score_2: Variant = JSON.parse_string(str(Dictionary(participants[1]).get("score_json", "")))
	if not (score_1 is Dictionary) or not (score_2 is Dictionary):
		return Result.failure("score_json 解析失败: %s" % str(participants))
	if not Array(Dictionary(score_1).get("employees", [])).has("ceo"):
		return Result.failure("seat=1 应回退到 players[0]，实际: %s" % str(score_1))
	if not Array(Dictionary(score_2).get("milestones", [])).has("first_billboard"):
		return Result.failure("seat=3 应回退到 players[1]，实际: %s" % str(score_2))
	if str(Dictionary(participants[0]).get("result", "")) != "win":
		return Result.failure("seat=1 应映射为 winner_player_id=0 的获胜者，实际: %s" % str(participants[0]))
	if str(Dictionary(participants[1]).get("result", "")) != "lose":
		return Result.failure("seat=3 应映射为失败者，实际: %s" % str(participants[1]))
	return Result.success()

static func _test_participant_stats_payload_uses_rebuilt_events() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("stats payload 初始化失败: %s" % init.error)
	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("stats payload complete_setup 失败: %s" % setup_r.error)

	var room := _DummyRoom.new()
	room.game_engine = engine
	room._seat_profile_by_seat_index = {
		0: {"name": "P1", "restaurant_logo_id": 0},
		1: {"name": "P2", "restaurant_logo_id": 1},
	}
	room._user_id_by_seat_index = {
		0: "u1",
		1: "u2",
	}

	var state := engine.get_state()
	var payload_0: Dictionary = ServerMatchFinalizePayloadBuilderClass.build_participant_score_payload(room, state, 0)
	var payload_1: Dictionary = ServerMatchFinalizePayloadBuilderClass.build_participant_score_payload(room, state, 1)
	var stats_0 := Dictionary(payload_0.get("stats", {}))
	var stats_1 := Dictionary(payload_1.get("stats", {}))
	var metrics_0 := Dictionary(stats_0.get("metrics", {}))
	var metrics_1 := Dictionary(stats_1.get("metrics", {}))
	if int(metrics_0.get("restaurant_built", 0)) <= 0:
		return Result.failure("player0 stats 应统计 setup 放置餐厅，实际: %s" % str(stats_0))
	if int(metrics_1.get("restaurant_built", 0)) <= 0:
		return Result.failure("player1 stats 应统计 setup 放置餐厅，实际: %s" % str(stats_1))
	return Result.success()
