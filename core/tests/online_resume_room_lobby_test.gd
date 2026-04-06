class_name OnlineResumeRoomLobbyTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"

static func run() -> Result:
	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化测试存档失败: %s" % init_r.error)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("构造恢复测试历史失败: %s" % setup_r.error)
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建测试存档失败: %s" % archive_r.error)
	var base_archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var commands_val = base_archive.get("commands", null)
	if not (commands_val is Array) or Array(commands_val).size() < 2:
		return Result.failure("恢复测试需要至少 2 条命令历史")
	var selected_index := maxi(0, int(floor(float(Array(commands_val).size()) / 2.0)) - 1)
	var preview_engine = GameEngineClass.new()
	var preview_load_r: Result = preview_engine.load_from_archive(base_archive)
	if not preview_load_r.ok:
		return Result.failure("预览测试存档失败: %s" % preview_load_r.error)
	var rewind_r: Result = preview_engine.rewind_to_command(selected_index)
	if not rewind_r.ok:
		return Result.failure("预览切换恢复点失败: %s" % rewind_r.error)
	var preview_state = preview_engine.get_state()
	if preview_state == null:
		return Result.failure("预览恢复点状态为空")
	if not (preview_state.rules is Dictionary):
		preview_state.rules = {}
	preview_state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
	var archive: Dictionary = base_archive.duplicate(true)
	archive["current_index"] = selected_index
	var expected_hash := str(preview_state.compute_hash())
	if expected_hash.is_empty():
		return Result.failure("测试存档缺少 final_hash")
	archive["final_hash"] = expected_hash
	var phase_text := str(preview_state.phase)
	var sub_phase_text := str(preview_state.sub_phase).strip_edges()
	if not sub_phase_text.is_empty():
		phase_text += " / %s" % sub_phase_text

	var rm = RoomManagerClass.new()
	var room_code := "RSM001"
	var config := {
		"room_mode": "resume_archive",
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
		"resume_summary": {
			"source_name": "resume_test.json",
			"player_count": 2,
			"round_number": int(preview_state.round_number),
			"phase": phase_text,
			"current_index": selected_index,
		},
	}
	var host_profile := {
		"name": "HostResume",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_resume_host",
	}
	var player_profile := {
		"name": "PlayerResume",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_resume_player",
	}

	var create_r: Result = rm.create_resume_room_with_code(10, host_profile, room_code, config, archive)
	if not create_r.ok:
		return Result.failure("create_resume_room_with_code 失败: %s" % create_r.error)
	var join_r: Result = rm.join_room_as_waiting_member(11, player_profile, room_code, "player")
	if not join_r.ok:
		return Result.failure("join_room_as_waiting_member 失败: %s" % join_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("resume room missing")
	if not room.has_method("is_resume_archive_room") or not room.is_resume_archive_room():
		return Result.failure("resume room 未标记为 resume_archive")
	if room.get_player_count() != 0:
		return Result.failure("初始恢复房不应已有已分座玩家: %d" % room.get_player_count())
	if not room.has_method("get_waiting_member_count") or int(room.get_waiting_member_count()) != 2:
		return Result.failure("待分配成员数错误: %s" % str(room.get_waiting_member_count() if room.has_method("get_waiting_member_count") else -1))

	var assign_host_r: Result = rm.assign_waiting_member_to_seat(room_code, "u_resume_host", 0)
	if not assign_host_r.ok:
		return Result.failure("assign_waiting_member_to_seat(host) 失败: %s" % assign_host_r.error)
	var assign_player_r: Result = rm.assign_waiting_member_to_seat(room_code, "u_resume_player", 1)
	if not assign_player_r.ok:
		return Result.failure("assign_waiting_member_to_seat(player) 失败: %s" % assign_player_r.error)

	if room.get_player_count() != 2:
		return Result.failure("分座后 player_count 错误: %d" % room.get_player_count())
	if room.get_connected_player_count() != 2:
		return Result.failure("分座后 connected_player_count 错误: %d" % room.get_connected_player_count())
	if int(room.get_waiting_member_count()) != 0:
		return Result.failure("分座完成后不应仍有待分配成员: %d" % int(room.get_waiting_member_count()))

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("resume room start_game 失败: %s" % start_r.error)
	if room.game_engine == null or room.game_engine.get_state() == null:
		return Result.failure("恢复房开局后缺少 game_engine/state")
	var actual_hash := str(room.game_engine.get_state().compute_hash())
	if actual_hash != expected_hash:
		return Result.failure("恢复房开局 hash 不一致: %s vs %s" % [expected_hash, actual_hash])
	var expected_history_size := selected_index + 1
	if int(room.game_engine.command_history.size()) != expected_history_size:
		return Result.failure(
			"恢复房开局后不应保留未来历史: %d vs %d"
				% [int(room.game_engine.command_history.size()), expected_history_size]
		)
	if int(room.game_engine.current_command_index) != selected_index:
		return Result.failure("恢复房开局 current_command_index 错误: %d vs %d" % [int(room.game_engine.current_command_index), selected_index])
	if int(room.game_engine.current_command_index) != int(room.game_engine.command_history.size()) - 1:
		return Result.failure(
			"恢复房开局后 current_command_index 应位于最新位置: %d vs %d"
				% [int(room.game_engine.current_command_index), int(room.game_engine.command_history.size()) - 1]
		)

	return Result.success({
		"room_code": room_code,
		"hash": actual_hash.substr(0, 8),
	})
