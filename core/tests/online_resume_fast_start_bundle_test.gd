class_name OnlineResumeFastStartBundleTest
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumeFastRuntimeArchiveBuilderClass = preload("res://core/engine/game_engine/online_resume_fast_runtime_archive_builder.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run() -> Result:
	var build_r := _build_long_resume_archive()
	if not build_r.ok:
		return build_r
	var build_info: Dictionary = Dictionary(build_r.value)
	var engine: GameEngine = build_info.get("engine", null)
	if engine == null:
		return Result.failure("测试 engine 为空")

	var full_archive: Dictionary = Dictionary(build_info.get("archive", {})).duplicate(true)
	var expected_hash := str(build_info.get("expected_hash", "")).strip_edges()
	var full_history_size := int(build_info.get("full_history_size", -1))

	var builder_r: Result = OnlineResumeFastRuntimeArchiveBuilderClass.build_from_engine(
		engine,
		{
			"full_archive": full_archive,
		}
	)
	if not builder_r.ok:
		return Result.failure("build_from_engine 失败: %s" % builder_r.error)
	var builder_info: Dictionary = Dictionary(builder_r.value)
	var runtime_archive: Dictionary = Dictionary(builder_info.get("runtime_archive", {})).duplicate(true)
	var runtime_anchor: Dictionary = Dictionary(builder_info.get("runtime_anchor", {})).duplicate(true)
	if runtime_archive.is_empty():
		return Result.failure("runtime_archive 为空")
	if runtime_anchor.is_empty():
		return Result.failure("runtime_anchor 为空")

	var full_commands: Array = Array(full_archive.get("commands", []))
	var runtime_commands: Array = Array(runtime_archive.get("commands", []))
	if runtime_commands.size() >= full_commands.size():
		return Result.failure(
			"runtime_archive 未缩短: runtime=%d full=%d"
				% [runtime_commands.size(), full_commands.size()]
		)

	var global_start := int(runtime_anchor.get("global_command_start_index", -1))
	var global_end := int(runtime_anchor.get("global_command_end_index", -1))
	if global_start <= 0:
		return Result.failure("runtime_anchor.global_command_start_index 应大于 0，实际: %d" % global_start)
	if global_end != int(engine.current_command_index):
		return Result.failure(
			"runtime_anchor.global_command_end_index 错误: %d vs %d"
				% [global_end, int(engine.current_command_index)]
		)
	if int(runtime_archive.get("current_index", -999999)) != global_end - global_start:
		return Result.failure(
			"runtime_archive.current_index 未按短链重基线: %d vs %d"
				% [int(runtime_archive.get("current_index", -999999)), global_end - global_start]
		)

	var runtime_checkpoints: Array = Array(runtime_archive.get("checkpoints", []))
	if runtime_checkpoints.is_empty():
		return Result.failure("runtime_archive.checkpoints 为空")
	if int(Dictionary(runtime_checkpoints[0]).get("index", -1)) != 0:
		return Result.failure(
			"runtime_archive.checkpoints[0].index 应为 0，实际: %d"
				% int(Dictionary(runtime_checkpoints[0]).get("index", -1))
		)

	var runtime_engine := GameEngineClass.new()
	var runtime_load_r: Result = runtime_engine.load_from_archive(runtime_archive)
	if not runtime_load_r.ok:
		return Result.failure("runtime_archive 读档失败: %s" % runtime_load_r.error)
	var runtime_prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(runtime_engine)
	if not runtime_prepare_r.ok:
		return Result.failure("runtime_archive prepare_engine_for_online_resume 失败: %s" % runtime_prepare_r.error)
	var runtime_hash := str(runtime_engine.get_state().compute_hash()) if runtime_engine.get_state() != null else ""
	if runtime_hash != expected_hash:
		return Result.failure("runtime_archive 读档 hash 不一致: %s vs %s" % [runtime_hash, expected_hash])

	var room_bundle_r := _assert_room_bundle_and_start(full_archive, expected_hash, full_history_size, runtime_commands.size())
	if not room_bundle_r.ok:
		return room_bundle_r

	return Result.success({
		"full_history_size": full_history_size,
		"runtime_history_size": runtime_commands.size(),
		"runtime_anchor_start": global_start,
	})

static func _build_long_resume_archive() -> Result:
	var engine := GameEngineClass.new()
	engine.checkpoint_interval = 1
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化恢复测试历史失败: %s" % init_r.error)

	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("complete_setup 失败: %s" % setup_r.error)
	var restructuring_r: Result = TestPhaseUtilsClass.complete_restructuring(engine)
	if not restructuring_r.ok:
		return Result.failure("complete_restructuring 失败: %s" % restructuring_r.error)
	var oob_r: Result = TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("complete_order_of_business 失败: %s" % oob_r.error)
	var working_r: Result = TestPhaseUtilsClass.complete_working_phase(engine)
	if not working_r.ok:
		return Result.failure("complete_working_phase 失败: %s" % working_r.error)

	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("prepare_engine_for_online_resume 失败: %s" % prepare_r.error)

	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive 失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var full_history_size := int(engine.command_history.size())
	if full_history_size < 4:
		return Result.failure("测试历史过短，无法验证 fast runtime: %d" % full_history_size)

	return Result.success({
		"engine": engine,
		"archive": archive,
		"expected_hash": str(engine.get_state().compute_hash()) if engine.get_state() != null else "",
		"full_history_size": full_history_size,
	})

static func _assert_room_bundle_and_start(
	archive: Dictionary,
	expected_hash: String,
	full_history_size: int,
	expected_runtime_history_size: int
) -> Result:
	var rm = RoomManagerClass.new()
	var room_code := "RSB001"
	var host_profile := {
		"name": "HostBundle",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_bundle_host",
	}
	var player_profile := {
		"name": "PlayerBundle",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_bundle_player",
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
		Dictionary(archive).duplicate(true)
	)
	if not create_r.ok:
		return Result.failure("create_resume_room_with_code 失败: %s" % create_r.error)

	var join_r: Result = rm.join_room_as_waiting_member(11, player_profile, room_code, "player")
	if not join_r.ok:
		return Result.failure("join_room_as_waiting_member 失败: %s" % join_r.error)
	var assign_host_r: Result = rm.assign_waiting_member_to_seat(room_code, "u_bundle_host", 0)
	if not assign_host_r.ok:
		return Result.failure("assign_waiting_member_to_seat(host) 失败: %s" % assign_host_r.error)
	var assign_player_r: Result = rm.assign_waiting_member_to_seat(room_code, "u_bundle_player", 1)
	if not assign_player_r.ok:
		return Result.failure("assign_waiting_member_to_seat(player) 失败: %s" % assign_player_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("resume room missing")

	var bundle_r: Result = room.build_resume_fast_start_bundle()
	if not bundle_r.ok:
		return Result.failure("build_resume_fast_start_bundle 失败: %s" % bundle_r.error)
	var bundle: Dictionary = Dictionary(bundle_r.value) if bundle_r.value is Dictionary else {}
	var runtime_archive: Dictionary = Dictionary(bundle.get("runtime_archive", {})).duplicate(true)
	var full_archive_meta: Dictionary = Dictionary(bundle.get("full_archive_meta", {})).duplicate(true)
	if runtime_archive.is_empty():
		return Result.failure("room bundle 缺少 runtime_archive")
	if int(Array(runtime_archive.get("commands", [])).size()) != expected_runtime_history_size:
		return Result.failure(
			"room bundle runtime_history_size 错误: %d vs %d"
				% [int(Array(runtime_archive.get("commands", [])).size()), expected_runtime_history_size]
		)
	if int(full_archive_meta.get("full_command_count", -1)) != full_history_size:
		return Result.failure(
			"room bundle full_command_count 错误: %d vs %d"
				% [int(full_archive_meta.get("full_command_count", -1)), full_history_size]
		)
	if str(full_archive_meta.get("full_final_hash", "")).strip_edges() != expected_hash:
		return Result.failure(
			"room bundle full_final_hash 错误: %s vs %s"
				% [str(full_archive_meta.get("full_final_hash", "")), expected_hash]
		)
	if int(full_archive_meta.get("byte_size", 0)) <= 0:
		return Result.failure("room bundle full_archive_meta.byte_size 应大于 0")
	if bundle.has("full_archive_payload"):
		return Result.failure("默认 fast-start bundle 不应直接内联 full_archive_payload")

	var bundle_with_payload_r: Result = room.build_resume_fast_start_bundle(true)
	if not bundle_with_payload_r.ok:
		return Result.failure("build_resume_fast_start_bundle(include_full_archive_payload=true) 失败: %s" % bundle_with_payload_r.error)
	var bundle_with_payload: Dictionary = Dictionary(bundle_with_payload_r.value) if bundle_with_payload_r.value is Dictionary else {}
	var full_archive_payload: Dictionary = Dictionary(bundle_with_payload.get("full_archive_payload", {})).duplicate(true)
	if full_archive_payload.is_empty():
		return Result.failure("include_full_archive_payload=true 时缺少 full_archive_payload")
	if Array(full_archive_payload.get("commands", [])).size() != full_history_size:
		return Result.failure(
			"full_archive_payload history_size 错误: %d vs %d"
				% [int(Array(full_archive_payload.get("commands", [])).size()), full_history_size]
		)

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("resume room start_game 失败: %s" % start_r.error)
	if room.game_engine == null or room.game_engine.get_state() == null:
		return Result.failure("resume room start_game 后缺少 game_engine/state")
	var live_hash := str(room.game_engine.get_state().compute_hash())
	if live_hash != expected_hash:
		return Result.failure("start_game 后权威 hash 错误: %s vs %s" % [live_hash, expected_hash])
	if int(room.game_engine.command_history.size()) != full_history_size:
		return Result.failure(
			"start_game 不应切换到短链历史: %d vs %d"
				% [int(room.game_engine.command_history.size()), full_history_size]
		)

	return Result.success()
