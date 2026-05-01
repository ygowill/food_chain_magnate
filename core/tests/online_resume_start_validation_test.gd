class_name OnlineResumeStartValidationTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

static func run() -> Result:
	var reject_r := _test_reject_game_over_resume_point()
	if not reject_r.ok:
		return reject_r

	var repair_r := _test_repair_dinnertime_resume_point()
	if not repair_r.ok:
		return repair_r

	return Result.success({
		"cases": [
			"reject_game_over_resume_point",
			"repair_dinnertime_resume_point",
		],
	})

static func _test_reject_game_over_resume_point() -> Result:
	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("构造 GameOver 恢复点失败: %s" % init_r.error)
	var state = engine.get_state()
	if state == null:
		return Result.failure("GameOver 测试 state 为空")
	state.phase = DefsClass.PHASE_GAME_OVER
	state.sub_phase = ""

	var archive_r := _build_snapshot_archive_from_engine(engine)
	if not archive_r.ok:
		return Result.failure("构造 GameOver 快照失败: %s" % archive_r.error)

	var rm = RoomManagerClass.new()
	var room_code := "RSG001"
	var host_profile := {
		"name": "HostReject",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_reject_host",
	}
	var create_r: Result = rm.create_resume_room_with_code(
		10,
		host_profile,
		room_code,
		{
			"room_mode": "resume_archive",
			"desired_player_count": 2,
			"seed_mode": "fixed",
			"seed": 12345,
			"allow_spectators": true,
			"enabled_modules_v2": [],
			"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
		},
		Dictionary(archive_r.value).duplicate(true)
	)
	if not create_r.ok:
		return Result.failure("create_resume_room_with_code(GameOver) 失败: %s" % create_r.error)
	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("GameOver 测试缺少 room")

	var build_r: Result = room.build_effective_resume_start_archive()
	if build_r.ok:
		return Result.failure("GameOver 恢复点应被拒绝，但 build_effective_resume_start_archive 成功了")
	if str(build_r.error).find("游戏结束阶段") == -1:
		return Result.failure("GameOver 恢复点报错不明确: %s" % build_r.error)
	return Result.success()

static func _test_repair_dinnertime_resume_point() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER
	var result := _run_dinnertime_resume_point_test_impl()
	_reset_net_context()
	return result

static func _run_dinnertime_resume_point_test_impl() -> Result:
	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化 Dinnertime 恢复测试失败: %s" % init_r.error)
	var init_state = engine.get_state()
	if init_state == null:
		return Result.failure("Dinnertime 测试初始化 state 为空")
	var prepare_marker_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_marker_r.ok:
		return Result.failure("Dinnertime 测试写入 online resume marker 失败: %s" % prepare_marker_r.error)
	if not (init_state.rules is Dictionary) or int(init_state.rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, 0)) != 1:
		return Result.failure("Dinnertime 测试缺少 online dinnertime confirm marker")
	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("构造 Dinnertime 恢复测试历史失败(setup): %s" % setup_r.error)
	var restruct_r := TestPhaseUtilsClass.complete_restructuring(engine)
	if not restruct_r.ok:
		return Result.failure("构造 Dinnertime 恢复测试历史失败(restructuring): %s" % restruct_r.error)
	var oob_r := TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("构造 Dinnertime 恢复测试历史失败(order_of_business): %s" % oob_r.error)
	var working_r := TestPhaseUtilsClass.complete_working_phase(engine)
	if not working_r.ok:
		return Result.failure("构造 Dinnertime 恢复测试历史失败(working): %s" % working_r.error)

	var live_state = engine.get_state()
	if live_state == null:
		return Result.failure("Dinnertime 测试 state 为空")
	if str(live_state.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("Dinnertime 测试应停留在晚餐阶段，实际: %s" % str(live_state.phase))

	var pending_phase_actions: Dictionary = {}
	if live_state.round_state is Dictionary and Dictionary(live_state.round_state).get("pending_phase_actions", null) is Dictionary:
		pending_phase_actions = Dictionary(Dictionary(live_state.round_state).get("pending_phase_actions", {})).duplicate(true)
	pending_phase_actions.erase(DefsClass.PHASE_DINNERTIME)
	live_state.round_state["pending_phase_actions"] = pending_phase_actions
	if live_state.round_state is Dictionary and Dictionary(live_state.round_state).has("online_dinnertime_confirmed_players"):
		live_state.round_state.erase("online_dinnertime_confirmed_players")

	var archive_r := _build_snapshot_archive_from_engine(engine)
	if not archive_r.ok:
		return Result.failure("构造 Dinnertime 快照失败: %s" % archive_r.error)

	var rm = RoomManagerClass.new()
	var room_code := "RSD001"
	var config := {
		"room_mode": "resume_archive",
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var host_profile := {
		"name": "HostRepair",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_repair_host",
	}
	var player_profile := {
		"name": "PlayerRepair",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_repair_player",
	}
	var create_r: Result = rm.create_resume_room_with_code(
		10,
		host_profile,
		room_code,
		config,
		Dictionary(archive_r.value).duplicate(true)
	)
	if not create_r.ok:
		return Result.failure("create_resume_room_with_code(Dinnertime) 失败: %s" % create_r.error)
	var join_r: Result = rm.join_room_as_waiting_member(11, player_profile, room_code, "player")
	if not join_r.ok:
		return Result.failure("join_room_as_waiting_member(Dinnertime) 失败: %s" % join_r.error)
	var assign_host_r: Result = rm.assign_waiting_member_to_seat(room_code, "u_repair_host", 0)
	if not assign_host_r.ok:
		return Result.failure("assign_waiting_member_to_seat(host) 失败: %s" % assign_host_r.error)
	var assign_player_r: Result = rm.assign_waiting_member_to_seat(room_code, "u_repair_player", 1)
	if not assign_player_r.ok:
		return Result.failure("assign_waiting_member_to_seat(player) 失败: %s" % assign_player_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("Dinnertime 测试缺少 room")

	var effective_r: Result = room.build_effective_resume_start_archive()
	if not effective_r.ok:
		return Result.failure("build_effective_resume_start_archive(Dinnertime) 失败: %s" % effective_r.error)
	var effective_info: Dictionary = Dictionary(effective_r.value) if effective_r.value is Dictionary else {}
	var effective_archive: Dictionary = Dictionary(effective_info.get("archive", {})).duplicate(true)
	if effective_archive.is_empty():
		return Result.failure("Dinnertime 有效恢复档为空")

	var probe_engine := GameEngineClass.new()
	var probe_load_r: Result = probe_engine.load_from_archive(effective_archive)
	if not probe_load_r.ok:
		return Result.failure("probe_engine.load_from_archive 失败: %s" % probe_load_r.error)
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(probe_engine)
	if not prepare_r.ok:
		return Result.failure("prepare_engine_for_online_resume(probe) 失败: %s" % prepare_r.error)
	var probe_assert_r := _assert_dinnertime_confirm_pending(probe_engine.get_state(), 2, "probe")
	if not probe_assert_r.ok:
		return probe_assert_r

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("resume room start_game(Dinnertime) 失败: %s" % start_r.error)
	if room.game_engine == null or room.game_engine.get_state() == null:
		return Result.failure("resume room start_game(Dinnertime) 后缺少 game_engine/state")
	return _assert_dinnertime_confirm_pending(room.game_engine.get_state(), 2, "room.start_game")

static func _build_snapshot_archive_from_engine(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("snapshot engine/state 为空")
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return archive_r
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var state = engine.get_state()
	var state_hash := str(state.compute_hash())
	archive["initial_state"] = state.to_dict().duplicate(true)
	archive["commands"] = []
	archive["current_index"] = -1
	archive["final_hash"] = state_hash
	archive["rng"] = engine.random_manager.to_dict() if engine.random_manager != null else {"initial_seed": int(state.seed), "call_count": 0}
	archive["checkpoints"] = [{
		"index": 0,
		"hash": state_hash,
		"rng_calls": int(engine.random_manager.get_call_count()) if engine.random_manager != null else 0,
	}]
	return Result.success(archive)

static func _assert_dinnertime_confirm_pending(state: GameState, player_count: int, label: String) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % label)
	if str(state.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("%s: 应停留在 Dinnertime，实际: %s" % [label, str(state.phase)])
	if not (state.round_state is Dictionary):
		return Result.failure("%s: round_state 类型错误（期望 Dictionary）" % label)
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("%s: pending_phase_actions 缺失或类型错误（期望 Dictionary）" % label)
	var list_val = Dictionary(ppa_val).get(DefsClass.PHASE_DINNERTIME, null)
	if not (list_val is Array):
		return Result.failure("%s: pending_phase_actions[Dinnertime] 缺失或类型错误（期望 Array）" % label)
	var list: Array = Array(list_val)
	if list.size() != player_count:
		return Result.failure("%s: Dinnertime pending 数量错误（期望 %d，实际 %d）" % [label, player_count, list.size()])
	var seen := {}
	for item_val in list:
		if not (item_val is Dictionary):
			return Result.failure("%s: Dinnertime pending 项类型错误（期望 Dictionary）" % label)
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			return Result.failure("%s: Dinnertime pending.kind 错误: %s" % [label, str(item.get("kind", null))])
		var player_id := int(item.get("player_id", -1))
		if player_id < 0 or player_id >= player_count:
			return Result.failure("%s: Dinnertime pending.player_id 越界: %d" % [label, player_id])
		seen[player_id] = true
	for player_id2 in range(player_count):
		if not seen.has(player_id2):
			return Result.failure("%s: Dinnertime pending 缺少 player_id=%d" % [label, player_id2])
	return Result.success()

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
