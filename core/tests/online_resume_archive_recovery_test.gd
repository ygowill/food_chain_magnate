class_name OnlineResumeArchiveRecoveryTest
extends RefCounted

const ArchiveRecoveryClass = preload("res://core/engine/game_engine/archive_recovery.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"

static func run() -> Result:
	var marker_r := _run_prepare_persists_online_confirm_markers_case()
	if not marker_r.ok:
		return marker_r
	var repair_marker_r := _run_repair_missing_marketing_marker_case()
	if not repair_marker_r.ok:
		return repair_marker_r
	var replay_import_r := _run_replay_import_repairs_missing_marketing_marker_case()
	if not replay_import_r.ok:
		return replay_import_r
	var replay_import_tail_r := _run_replay_import_rejects_bad_tail_case()
	if not replay_import_tail_r.ok:
		return replay_import_tail_r
	var recover_r := _run_recover_bad_tail_command_case()
	if not recover_r.ok:
		return recover_r
	return _run_resume_room_accepts_recovered_archive_case()

static func _run_prepare_persists_online_confirm_markers_case() -> Result:
	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化 marker 测试失败: %s" % init_r.error)
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("prepare_engine_for_online_resume 失败: %s" % prepare_r.error)
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建 marker 测试存档失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value)
	var initial: Dictionary = Dictionary(archive.get("initial_state", {}))
	var rules: Dictionary = Dictionary(initial.get("rules", {})) if initial.get("rules", null) is Dictionary else {}
	if int(rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, 0)) != 1:
		return Result.failure("恢复存档 initial_state 缺少晚餐确认 marker")
	if int(rules.get(ONLINE_MARKETING_CONFIRM_KEY, 0)) != 1:
		return Result.failure("恢复存档 initial_state 缺少营销确认 marker")
	return Result.success()

static func _run_repair_missing_marketing_marker_case() -> Result:
	var archive_r := _build_missing_marketing_marker_archive()
	if not archive_r.ok:
		return archive_r
	var bad_archive: Dictionary = Dictionary(archive_r.value).duplicate(true)

	var direct_engine := GameEngineClass.new()
	var direct_load: Result = direct_engine.load_from_archive(bad_archive)
	if direct_load.ok:
		return Result.failure("缺少 marketing marker 的在线确认历史不应能直接完整加载")

	var recover_r: Result = ArchiveRecoveryClass.load_for_online_resume(bad_archive)
	if not recover_r.ok:
		return Result.failure("修补缺失 marketing marker 后仍加载失败: %s" % recover_r.error)
	var info: Dictionary = Dictionary(recover_r.value)
	if bool(info.get("truncated", true)):
		return Result.failure("缺失 marketing marker 应完整修补加载，不应截断: %s" % str(info))
	var repaired_markers: Array = Array(info.get("repaired_online_confirm_markers", []))
	if not repaired_markers.has(ONLINE_MARKETING_CONFIRM_KEY):
		return Result.failure("修补结果应记录 marketing marker: %s" % str(info))
	var recovered_archive: Dictionary = Dictionary(info.get("archive", {})).duplicate(true)
	var initial: Dictionary = Dictionary(recovered_archive.get("initial_state", {}))
	var rules: Dictionary = Dictionary(initial.get("rules", {})) if initial.get("rules", null) is Dictionary else {}
	if int(rules.get(ONLINE_MARKETING_CONFIRM_KEY, 0)) != 1:
		return Result.failure("修补后的存档 initial_state 仍缺少 marketing marker")
	var commands: Array = Array(recovered_archive.get("commands", [])) if recovered_archive.get("commands", null) is Array else []
	if commands.size() != 3:
		return Result.failure("修补加载应保留完整命令历史，实际命令数: %d" % commands.size())
	return Result.success()

static func _build_corrupted_tail_archive() -> Result:
	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化测试存档失败: %s" % init_r.error)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("构造测试存档失败: %s" % setup_r.error)
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建测试存档失败: %s" % archive_r.error)

	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var commands_val = archive.get("commands", null)
	if not (commands_val is Array):
		return Result.failure("测试存档缺少 commands")
	var commands: Array = Array(commands_val).duplicate(true)
	if commands.size() < 2:
		return Result.failure("测试存档命令数不足: %d" % commands.size())
	var bad_index := commands.size() - 1
	var bad_command: Dictionary = Dictionary(commands[bad_index]).duplicate(true)
	bad_command["action_id"] = "__missing_action_for_archive_recovery_test__"
	commands[bad_index] = bad_command
	archive["commands"] = commands
	archive["current_index"] = bad_index
	return Result.success({
		"archive": archive,
		"bad_index": bad_index,
		"original_command_count": commands.size(),
	})

static func _build_missing_marketing_marker_archive() -> Result:
	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化缺失 marketing marker 测试存档失败: %s" % init_r.error)
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("准备在线确认 marker 失败: %s" % prepare_r.error)
	var state = engine.get_state()
	if state == null:
		return Result.failure("缺失 marketing marker 测试 state 为空")
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	state.round_number = 3
	state.turn_order.clear()
	state.turn_order.append(0)
	state.turn_order.append(1)
	state.current_player_index = 0
	state.marketing_instances.clear()
	state.marketing_instances.append({
		"board_number": 1,
		"type": "radio",
		"owner": 0,
		"employee_type": "brand_director",
		"product": "soda",
		"world_pos": Vector2i(2, 2),
		"remaining_duration": 2,
		"axis": "",
		"tile_index": -1,
		"created_round": int(state.round_number),
	})
	if not (state.map is Dictionary):
		return Result.failure("缺失 marketing marker 测试 map 类型错误")
	if not (state.map.get("marketing_placements", null) is Dictionary):
		state.map["marketing_placements"] = {}
	state.map["marketing_placements"]["1"] = {
		"board_number": 1,
		"type": "radio",
		"owner": 0,
		"product": "soda",
		"world_pos": Vector2i(2, 2),
		"remaining_duration": 2,
		"axis": "",
		"tile_index": -1,
	}
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("缺失 marketing marker 测试缺少 checkpoint0")
	var cp0: Dictionary = Dictionary(engine.checkpoints[0]).duplicate(true)
	cp0["state_dict"] = state.to_dict().duplicate(true)
	cp0["hash"] = state.compute_hash()
	cp0["rng_calls"] = int(engine.random_manager.get_call_count()) if engine.random_manager != null else 0
	engine.checkpoints[0] = cp0

	var advance_r: Result = engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not advance_r.ok:
		return Result.failure("推进到 Marketing 失败: %s" % advance_r.error)
	if str(engine.get_state().phase) != DefsClass.PHASE_MARKETING:
		return Result.failure("应停留在 Marketing 等待确认，实际: %s" % str(engine.get_state().phase))
	var confirm0_r: Result = engine.execute_command(Command.create("confirm_marketing", 0, {}))
	if not confirm0_r.ok:
		return Result.failure("confirm_marketing(0) 失败: %s" % confirm0_r.error)
	var confirm1_r: Result = engine.execute_command(Command.create("confirm_marketing", 1, {}))
	if not confirm1_r.ok:
		return Result.failure("confirm_marketing(1) 失败: %s" % confirm1_r.error)
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建缺失 marketing marker 测试存档失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var initial: Dictionary = Dictionary(archive.get("initial_state", {})).duplicate(true)
	var rules: Dictionary = Dictionary(initial.get("rules", {})).duplicate(true) if initial.get("rules", null) is Dictionary else {}
	rules.erase(ONLINE_MARKETING_CONFIRM_KEY)
	initial["rules"] = rules
	archive["initial_state"] = initial
	return Result.success(archive)

static func _run_replay_import_repairs_missing_marketing_marker_case() -> Result:
	var archive_r := _build_missing_marketing_marker_archive()
	if not archive_r.ok:
		return archive_r
	var bad_archive: Dictionary = Dictionary(archive_r.value).duplicate(true)

	var direct_engine := GameEngineClass.new()
	var direct_load: Result = direct_engine.load_from_archive(bad_archive)
	if direct_load.ok:
		return Result.failure("缺少 marketing marker 的回放存档不应能直接完整加载")

	var import_r: Result = ArchiveRecoveryClass.load_for_replay_import(bad_archive)
	if not import_r.ok:
		return Result.failure("回放导入修补缺失 marketing marker 后仍加载失败: %s" % import_r.error)
	var info: Dictionary = Dictionary(import_r.value)
	if bool(info.get("truncated", true)):
		return Result.failure("回放导入不应截断命令历史: %s" % str(info))
	var repaired_markers: Array = Array(info.get("repaired_online_confirm_markers", []))
	if not repaired_markers.has(ONLINE_MARKETING_CONFIRM_KEY):
		return Result.failure("回放导入应记录 marketing marker 修补: %s" % str(info))
	var engine = info.get("engine", null)
	if engine == null or not is_instance_valid(engine) or not engine.has_method("get_state"):
		return Result.failure("回放导入结果缺少 engine")
	var imported_commands_val = engine.get("command_history")
	if not (imported_commands_val is Array):
		return Result.failure("回放导入结果 command_history 类型错误")
	var imported_commands: Array = imported_commands_val
	if imported_commands.size() != 3:
		return Result.failure("回放导入应保留完整命令历史，实际命令数: %d" % imported_commands.size())

	var tmp_path := "user://replay_import_missing_marketing_marker.json"
	var save_r: Result = ArchiveClass.save_archive_to_file(bad_archive, tmp_path)
	if not save_r.ok:
		return Result.failure("写入回放导入测试存档失败: %s" % save_r.error)
	var file_import_r: Result = ArchiveRecoveryClass.load_file_for_replay_import(tmp_path)
	if not file_import_r.ok:
		return Result.failure("回放文件导入修补缺失 marketing marker 后仍加载失败: %s" % file_import_r.error)

	return Result.success()

static func _run_replay_import_rejects_bad_tail_case() -> Result:
	var bad_r := _build_corrupted_tail_archive()
	if not bad_r.ok:
		return bad_r
	var bad_info: Dictionary = Dictionary(bad_r.value)
	var archive: Dictionary = Dictionary(bad_info.get("archive", {})).duplicate(true)

	var import_r: Result = ArchiveRecoveryClass.load_for_replay_import(archive)
	if import_r.ok:
		return Result.failure("回放导入不应截断损坏尾部命令并返回成功")
	if str(import_r.error).is_empty():
		return Result.failure("回放导入坏尾部失败时应返回错误信息")
	return Result.success()

static func _run_recover_bad_tail_command_case() -> Result:
	var bad_r := _build_corrupted_tail_archive()
	if not bad_r.ok:
		return bad_r
	var bad_info: Dictionary = Dictionary(bad_r.value)
	var archive: Dictionary = Dictionary(bad_info.get("archive", {})).duplicate(true)
	var bad_index := int(bad_info.get("bad_index", -1))
	var original_count := int(bad_info.get("original_command_count", -1))

	var full_engine := GameEngineClass.new()
	var full_load: Result = full_engine.load_from_archive(archive)
	if full_load.ok:
		return Result.failure("损坏尾部命令的存档不应能完整加载")

	var recover_r: Result = ArchiveRecoveryClass.load_for_online_resume(archive)
	if not recover_r.ok:
		return Result.failure("恢复坏尾部存档失败: %s" % recover_r.error)
	var info: Dictionary = Dictionary(recover_r.value)
	if not bool(info.get("truncated", false)):
		return Result.failure("恢复结果应标记 truncated: %s" % str(info))
	if int(info.get("failed_command_index", -1)) != bad_index:
		return Result.failure("失败命令索引错误: got=%d want=%d" % [int(info.get("failed_command_index", -1)), bad_index])
	if int(info.get("recovered_command_count", -1)) != original_count - 1:
		return Result.failure("恢复命令数错误: got=%d want=%d" % [int(info.get("recovered_command_count", -1)), original_count - 1])

	var recovered_archive: Dictionary = Dictionary(info.get("archive", {})).duplicate(true)
	var recovered_commands: Array = Array(recovered_archive.get("commands", [])) if recovered_archive.get("commands", null) is Array else []
	if recovered_commands.size() != original_count - 1:
		return Result.failure("恢复存档命令数错误: got=%d want=%d" % [recovered_commands.size(), original_count - 1])
	if int(recovered_archive.get("current_index", -999)) != bad_index - 1:
		return Result.failure("恢复 current_index 错误: got=%d want=%d" % [int(recovered_archive.get("current_index", -999)), bad_index - 1])

	var verify_engine := GameEngineClass.new()
	var verify_load: Result = verify_engine.load_from_archive(recovered_archive)
	if not verify_load.ok:
		return Result.failure("恢复后的存档仍无法加载: %s" % verify_load.error)
	return Result.success()

static func _run_resume_room_accepts_recovered_archive_case() -> Result:
	var bad_r := _build_corrupted_tail_archive()
	if not bad_r.ok:
		return bad_r
	var bad_info: Dictionary = Dictionary(bad_r.value)
	var archive: Dictionary = Dictionary(bad_info.get("archive", {})).duplicate(true)
	var bad_index := int(bad_info.get("bad_index", -1))
	var rm = RoomManagerClass.new()
	var room_code := "RSR001"
	var host_profile := {
		"name": "HostRecovery",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_recovery_host",
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
		archive
	)
	if not create_r.ok:
		return Result.failure("恢复房间应接受可截断存档: %s" % create_r.error)
	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("恢复房间缺失")
	var recovered_archive: Dictionary = room.get_resume_lobby_archive()
	var recovered_commands: Array = Array(recovered_archive.get("commands", [])) if recovered_archive.get("commands", null) is Array else []
	if recovered_commands.size() != bad_index:
		return Result.failure("恢复房间存档命令数错误: got=%d want=%d" % [recovered_commands.size(), bad_index])
	if int(recovered_archive.get("current_index", -999)) != bad_index - 1:
		return Result.failure("恢复房间 current_index 错误: got=%d want=%d" % [int(recovered_archive.get("current_index", -999)), bad_index - 1])
	return Result.success()
