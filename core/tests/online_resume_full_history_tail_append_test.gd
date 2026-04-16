class_name OnlineResumeFullHistoryTailAppendTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumeFastRuntimeArchiveBuilderClass = preload("res://core/engine/game_engine/online_resume_fast_runtime_archive_builder.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")
	if EventBus == null:
		return Result.failure("EventBus autoload missing")

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_local_role := str(NetContext.local_role)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	var prev_event_history := EventBus.get_history()

	var build_r := _build_resume_bundle_with_live_tail()
	if not build_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"构造 live tail 测试数据失败: %s" % build_r.error
		)
	var info: Dictionary = Dictionary(build_r.value)
	var bundle: Dictionary = Dictionary(info.get("bundle", {})).duplicate(true)
	var runtime_first_cmd: Dictionary = Dictionary(info.get("runtime_first_cmd", {})).duplicate(true)
	var runtime_second_cmd: Dictionary = Dictionary(info.get("runtime_second_cmd", {})).duplicate(true)
	var expected_after_first_hash := str(info.get("expected_after_first_hash", "")).strip_edges()
	var expected_after_second_hash := str(info.get("expected_after_second_hash", "")).strip_edges()
	var full_history_size := int(info.get("full_history_size", -1))
	var runtime_history_size := int(info.get("runtime_history_size", -1))

	EventBus.clear_history_and_reset_sequence()
	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "FAST04",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("FAST04", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
	NetContext.mark_online_resume_in_game(true)

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)
	client.handle_rpc_game_started({
		"player_id_by_peer_id": {
			7: 0,
			8: 1,
		},
		"local_player_id": 0,
		"config": {
			"desired_player_count": 2,
			"seed": 12345,
			"allow_spectators": true,
			"enabled_modules_v2": [],
			"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
			"restaurant_logo_choices_by_player": [-1, -1],
		},
		"resume_fast_start_bundle": bundle,
	})

	var runtime_engine = Globals.current_game_engine
	if runtime_engine == null or runtime_engine.get_state() == null:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"GameStarted fast-start 后缺少 runtime_engine"
		)
	if int(runtime_engine.command_history.size()) != runtime_history_size:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"runtime_engine 历史长度错误: %d vs %d"
				% [int(runtime_engine.command_history.size()), runtime_history_size]
		)

	var session_before: Dictionary = client.get_online_resume_session_snapshot()
	if bool(session_before.get("full_replay_ready", false)):
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"deferred 构建前不应标记 full_replay_ready"
		)

	var apply_first_r: Result = _apply_runtime_command(runtime_engine, runtime_first_cmd)
	if not apply_first_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"runtime first command 执行失败: %s" % apply_first_r.error
		)
	if str(runtime_engine.get_state().compute_hash()) != expected_after_first_hash:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"runtime first command hash 错误: %s vs %s"
				% [str(runtime_engine.get_state().compute_hash()), expected_after_first_hash]
		)
	client.record_online_resume_runtime_command_applied(runtime_first_cmd, expected_after_first_hash)

	var session_pending: Dictionary = client.get_online_resume_session_snapshot()
	if int(session_pending.get("full_replay_live_tail_count", 0)) != 1:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"full_replay live tail 应先缓存 1 条命令，实际: %d"
				% int(session_pending.get("full_replay_live_tail_count", 0))
		)

	await tree.process_frame

	var full_replay_engine = client.get_online_resume_full_replay_engine()
	if full_replay_engine == null or full_replay_engine.get_state() == null:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"full_replay_engine deferred 构建失败"
		)
	if int(full_replay_engine.command_history.size()) != full_history_size + 1:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"full_replay_engine 未补放首条 live tail: %d vs %d"
				% [int(full_replay_engine.command_history.size()), full_history_size + 1]
		)
	if str(full_replay_engine.get_state().compute_hash()) != expected_after_first_hash:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"full_replay_engine 首次补放 hash 错误: %s vs %s"
				% [str(full_replay_engine.get_state().compute_hash()), expected_after_first_hash]
		)

	var apply_second_r: Result = _apply_runtime_command(runtime_engine, runtime_second_cmd)
	if not apply_second_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"runtime second command 执行失败: %s" % apply_second_r.error
		)
	client.record_online_resume_runtime_command_applied(runtime_second_cmd, expected_after_second_hash)

	if int(full_replay_engine.command_history.size()) != full_history_size + 2:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"full_replay_engine ready 后未继续追尾: %d vs %d"
				% [int(full_replay_engine.command_history.size()), full_history_size + 2]
		)
	if str(full_replay_engine.get_state().compute_hash()) != expected_after_second_hash:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
				"full_replay_engine 第二次追尾 hash 错误: %s vs %s"
					% [str(full_replay_engine.get_state().compute_hash()), expected_after_second_hash]
		)

	await tree.process_frame

	var session_final: Dictionary = client.get_online_resume_session_snapshot()
	if not bool(session_final.get("full_replay_ready", false)):
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"最终 snapshot 应标记 full_replay_ready"
		)
	if int(session_final.get("full_replay_live_tail_count", 0)) != 2:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"最终 full_replay_live_tail_count 错误: %d"
				% int(session_final.get("full_replay_live_tail_count", 0))
		)
	if not bool(session_final.get("full_replay_step_timeline_ready", false)):
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"最终 snapshot 应标记 full_replay_step_timeline_ready"
		)

	var cached_timeline_val = client.get_online_resume_full_replay_step_timeline()
	if not (cached_timeline_val is Dictionary):
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"cached full_replay_step_timeline 类型错误"
		)
	var cached_timeline: Dictionary = Dictionary(cached_timeline_val).duplicate(true)
	var cached_processed_count := StepTimelineHelpersClass.read_processed_command_count(cached_timeline)
	if cached_processed_count != full_history_size + 2:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"cached full_replay_step_timeline processed_command_count 错误: %d vs %d"
				% [cached_processed_count, full_history_size + 2]
		)

	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_engine,
		prev_is_game_active,
		prev_event_history
	)
	return Result.success({
		"full_history_size": full_history_size,
		"runtime_history_size": runtime_history_size,
		"tail_count": int(session_final.get("full_replay_live_tail_count", 0)),
		"cached_processed_count": cached_processed_count,
	})

static func _build_resume_bundle_with_live_tail() -> Result:
	var engine := GameEngineClass.new()
	engine.checkpoint_interval = 1
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("initialize failed: %s" % init_r.error)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("complete_setup failed: %s" % setup_r.error)
	var restructuring_r: Result = TestPhaseUtilsClass.complete_restructuring(engine)
	if not restructuring_r.ok:
		return Result.failure("complete_restructuring failed: %s" % restructuring_r.error)
	var oob_r: Result = TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("complete_order_of_business failed: %s" % oob_r.error)
	if str(engine.get_state().phase) != "Working":
		return Result.failure("测试前置阶段应为 Working，实际: %s" % str(engine.get_state().phase))

	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("prepare_engine_for_online_resume failed: %s" % prepare_r.error)
	var full_archive_r: Result = engine.create_archive()
	if not full_archive_r.ok:
		return Result.failure("create_archive failed: %s" % full_archive_r.error)
	var full_archive: Dictionary = Dictionary(full_archive_r.value).duplicate(true)
	var full_history_size := int(engine.command_history.size())

	var runtime_r: Result = OnlineResumeFastRuntimeArchiveBuilderClass.build_from_engine(
		engine,
		{
			"full_archive": full_archive,
		}
	)
	if not runtime_r.ok:
		return Result.failure("build_from_engine failed: %s" % runtime_r.error)
	var runtime_info: Dictionary = Dictionary(runtime_r.value)
	var runtime_archive: Dictionary = Dictionary(runtime_info.get("runtime_archive", {})).duplicate(true)
	var runtime_anchor: Dictionary = Dictionary(runtime_info.get("runtime_anchor", {})).duplicate(true)
	if runtime_archive.is_empty():
		return Result.failure("runtime_archive 为空")
	var global_start := int(runtime_anchor.get("global_command_start_index", -1))
	if global_start < 0:
		return Result.failure("runtime_anchor.global_command_start_index 无效: %d" % global_start)

	var first_tail_r: Result = _execute_follow_up_live_command(engine)
	if not first_tail_r.ok:
		return first_tail_r
	var first_global_cmd: Dictionary = Dictionary(first_tail_r.value).duplicate(true)
	var expected_after_first_hash := str(engine.get_state().compute_hash()) if engine.get_state() != null else ""

	var second_tail_r: Result = _execute_follow_up_live_command(engine)
	if not second_tail_r.ok:
		return second_tail_r
	var second_global_cmd: Dictionary = Dictionary(second_tail_r.value).duplicate(true)
	var expected_after_second_hash := str(engine.get_state().compute_hash()) if engine.get_state() != null else ""

	return Result.success({
		"bundle": {
			"runtime_archive": runtime_archive,
			"runtime_anchor": runtime_anchor,
			"full_archive_meta": {
				"full_command_count": full_history_size,
				"full_final_hash": str(full_archive.get("final_hash", "")).strip_edges(),
				"schema_version": int(full_archive.get("schema_version", 0)),
				"byte_size": int(var_to_bytes(full_archive).size()),
				"source": "test_authority_engine",
			},
			"full_archive_payload": full_archive,
		},
		"runtime_first_cmd": _translate_global_cmd_to_runtime(first_global_cmd, global_start),
		"runtime_second_cmd": _translate_global_cmd_to_runtime(second_global_cmd, global_start),
		"expected_after_first_hash": expected_after_first_hash,
		"expected_after_second_hash": expected_after_second_hash,
		"full_history_size": full_history_size,
		"runtime_history_size": int(Array(runtime_archive.get("commands", [])).size()),
	})

static func _execute_follow_up_live_command(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("engine/state 为空")
	var before_size := int(engine.command_history.size())
	var state := engine.get_state()
	var player_id := int(state.get_current_player_id())
	var cmd := Command.create(ActionIdsClass.SKIP_SUB_PHASE, player_id, {})
	var exec_r: Result = engine.execute_command(cmd)
	if not exec_r.ok:
		return Result.failure("%s(%d) failed: %s" % [str(cmd.action_id), player_id, exec_r.error])
	if int(engine.command_history.size()) != before_size + 1:
		return Result.failure(
			"%s(%d) 后 history size 错误: %d vs %d"
				% [str(cmd.action_id), player_id, int(engine.command_history.size()), before_size + 1]
		)
	var history: Array[Command] = engine.get_command_history()
	return Result.success(history[before_size].to_dict())

static func _translate_global_cmd_to_runtime(cmd_dict: Dictionary, global_start: int) -> Dictionary:
	var translated: Dictionary = Dictionary(cmd_dict).duplicate(true)
	if translated.get("index", null) is int or translated.get("index", null) is float:
		translated["index"] = int(translated.get("index", -1)) - int(global_start)
	return translated

static func _apply_runtime_command(engine: GameEngine, cmd_dict: Dictionary) -> Result:
	if engine == null:
		return Result.failure("runtime engine 为空")
	var parsed: Result = Command.from_dict(Dictionary(cmd_dict).duplicate(true))
	if not parsed.ok:
		return Result.failure("命令解析失败: %s" % parsed.error)
	return engine.execute_command(parsed.value, true)

static func _restore(
	prev_mode,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool,
	prev_event_history: Array
) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.local_role = prev_local_role
	NetContext.server_url = prev_server_url
	NetContext.connect_token = prev_connect_token
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.room_list = prev_room_list.duplicate(true)
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	if NetContext.has_method("save_online_resume_state_to_disk"):
		NetContext.save_online_resume_state_to_disk()
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active
	EventBus.clear_history_and_reset_sequence()
	for item_val in prev_event_history:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val)
		if not EventBus.has_method("record_event"):
			continue
		EventBus.record_event(str(item.get("type", "")), Dictionary(item.get("data", {})).duplicate(true))

static func _restore_and_fail(
	prev_mode,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool,
	prev_event_history: Array,
	message: String
) -> Result:
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_engine,
		prev_is_game_active,
		prev_event_history
	)
	return Result.failure(message)

class _MockMultiplayer:
	extends RefCounted

	var _unique_id: int = 7

	func _init(unique_id: int = 7) -> void:
		_unique_id = int(unique_id)

	func get_unique_id() -> int:
		return _unique_id

class _MockNet:
	extends RefCounted

	signal game_started(payload: Dictionary)
	signal resume_fast_start_ready(payload: Dictionary)
	signal resume_full_history_ready(payload: Dictionary)

	var multiplayer := _MockMultiplayer.new(7)
	var _pending_resync_delta: Dictionary = {}
	var _online_client_engine_room_code: String = ""
