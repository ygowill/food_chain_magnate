class_name OnlineResumeClientDualEngineBootstrapTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumeFastRuntimeArchiveBuilderClass = preload("res://core/engine/game_engine/online_resume_fast_runtime_archive_builder.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
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

	var bundle_r := _build_resume_fast_start_bundle()
	if not bundle_r.ok:
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
			"构造 fast-start bundle 失败: %s" % bundle_r.error
		)
	var bundle_info: Dictionary = Dictionary(bundle_r.value)
	var expected_hash := str(bundle_info.get("expected_hash", "")).strip_edges()
	var full_history_size := int(bundle_info.get("full_history_size", -1))
	var runtime_history_size := int(bundle_info.get("runtime_history_size", -1))
	var bundle: Dictionary = Dictionary(bundle_info.get("bundle", {})).duplicate(true)
	if bundle.is_empty():
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
			"bundle 为空"
		)

	EventBus.clear_history_and_reset_sequence()
	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "FAST02",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("FAST02", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
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
			"GameStarted fast-start 后应立即持有 runtime_engine"
		)
	if str(runtime_engine.get_state().compute_hash()) != expected_hash:
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
			"runtime_engine hash 错误: %s vs %s" % [str(runtime_engine.get_state().compute_hash()), expected_hash]
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
			"runtime_engine 历史长度错误: %d vs %d" % [int(runtime_engine.command_history.size()), runtime_history_size]
		)
	if int(NetContext.get_online_resume_last_applied_sequence()) != full_history_size:
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
			"resume progress 应映射到完整全局序列: %d vs %d"
				% [int(NetContext.get_online_resume_last_applied_sequence()), full_history_size]
		)

	var session_now: Dictionary = client.get_online_resume_session_snapshot()
	if not bool(session_now.get("runtime_ready", false)):
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
			"session snapshot 应标记 runtime_ready"
		)
	if int(session_now.get("runtime_command_count", -1)) >= full_history_size:
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
			"runtime_command_count 应小于完整历史长度"
		)
	if mock_net.fast_start_payloads.size() != 1:
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
			"应发出 resume_fast_start_ready 信号"
		)

	EventBus.emit_event("test_resume_fast_marker", {"room_code": "FAST02"})
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
			"deferred full_replay_engine 构建失败"
		)
	if full_replay_engine == runtime_engine:
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
			"full_replay_engine 不应与 runtime_engine 共用实例"
		)
	if str(full_replay_engine.get_state().compute_hash()) != expected_hash:
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
			"full_replay_engine hash 错误: %s vs %s"
				% [str(full_replay_engine.get_state().compute_hash()), expected_hash]
		)
	if int(full_replay_engine.command_history.size()) != full_history_size:
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
			"full_replay_engine 历史长度错误: %d vs %d"
				% [int(full_replay_engine.command_history.size()), full_history_size]
		)
	if full_replay_engine.get_event_sink() == null:
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
			"full_replay_engine 应绑定独立 event_sink"
		)

	var marker_kept := false
	for item_val in EventBus.get_history():
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val)
		if str(item.get("type", "")) == "test_resume_fast_marker":
			marker_kept = true
			break
	if not marker_kept:
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
			"full_replay_engine 背景加载不应清空全局 EventBus.history"
		)

	var session_ready: Dictionary = client.get_online_resume_session_snapshot()
	if not bool(session_ready.get("full_replay_ready", false)):
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
			"session snapshot 应标记 full_replay_ready"
		)
	if not bool(session_ready.get("full_replay_step_timeline_ready", false)):
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
			"session snapshot 应标记 full_replay_step_timeline_ready"
		)
	if mock_net.full_history_ready_payloads.is_empty():
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
			"应发出 resume_full_history_ready 信号"
		)
	var full_history_ready_payload: Dictionary = Dictionary(mock_net.full_history_ready_payloads.back()).duplicate(true)
	if not bool(full_history_ready_payload.get("full_replay_step_timeline_ready", false)):
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
			"resume_full_history_ready 负载应包含 full_replay_step_timeline_ready=true"
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
	})

static func _build_resume_fast_start_bundle() -> Result:
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
	var working_r: Result = TestPhaseUtilsClass.complete_working_phase(engine)
	if not working_r.ok:
		return Result.failure("complete_working_phase failed: %s" % working_r.error)
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("prepare_engine_for_online_resume failed: %s" % prepare_r.error)
	var full_archive_r: Result = engine.create_archive()
	if not full_archive_r.ok:
		return Result.failure("create_archive failed: %s" % full_archive_r.error)
	var full_archive: Dictionary = Dictionary(full_archive_r.value).duplicate(true)
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
	if runtime_archive.is_empty():
		return Result.failure("runtime_archive 为空")
	return Result.success({
		"bundle": {
			"runtime_archive": runtime_archive,
			"runtime_anchor": Dictionary(runtime_info.get("runtime_anchor", {})).duplicate(true),
			"full_archive_meta": {
				"full_command_count": int(engine.command_history.size()),
				"full_final_hash": str(engine.get_state().compute_hash()) if engine.get_state() != null else "",
				"schema_version": int(full_archive.get("schema_version", 0)),
				"byte_size": int(var_to_bytes(full_archive).size()),
				"source": "test_authority_engine",
			},
			"full_archive_payload": full_archive,
		},
		"expected_hash": str(engine.get_state().compute_hash()) if engine.get_state() != null else "",
		"full_history_size": int(engine.command_history.size()),
		"runtime_history_size": int(Array(runtime_archive.get("commands", [])).size()),
	})

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
	var game_started_payloads: Array[Dictionary] = []
	var fast_start_payloads: Array[Dictionary] = []
	var full_history_ready_payloads: Array[Dictionary] = []

	func _init() -> void:
		game_started.connect(func(payload: Dictionary) -> void:
			game_started_payloads.append(Dictionary(payload).duplicate(true))
		)
		resume_fast_start_ready.connect(func(payload: Dictionary) -> void:
			fast_start_payloads.append(Dictionary(payload).duplicate(true))
		)
		resume_full_history_ready.connect(func(payload: Dictionary) -> void:
			full_history_ready_payloads.append(Dictionary(payload).duplicate(true))
		)
