class_name OnlineResumeSingleFullEngineCacheTest
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")

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

	var build_r := _build_working_phase_resume_archive_transfer()
	if not build_r.ok:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "构造 working-phase 恢复存档失败: %s" % build_r.error)
	var build_info: Dictionary = Dictionary(build_r.value)
	var transfer: Dictionary = Dictionary(build_info.get("transfer", {})).duplicate(true)

	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "FULL02",
		"room_mode": "resume_archive",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("FULL02", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
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
		"resume_bootstrap_mode": "full_archive_snapshot",
	})
	var manifest: Dictionary = Dictionary(transfer.get("manifest", {})).duplicate(true)
	manifest["room_code"] = "FULL02"
	manifest["request_id"] = "req_full_cache"
	client.handle_rpc_resync_snapshot_manifest(manifest)
	for chunk_val in Array(transfer.get("chunks", [])):
		if chunk_val is Dictionary:
			client.handle_rpc_resync_snapshot_chunk(Dictionary(chunk_val).duplicate(true))

	var runtime_engine = Globals.current_game_engine
	if runtime_engine == null or runtime_engine.get_state() == null:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "bootstrap 后缺少 runtime engine")

	var snapshot_before: Dictionary = client.get_online_resume_session_snapshot()
	if int(snapshot_before.get("full_replay_live_tail_count", -1)) != 0:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "single full-engine 模式不应预存 live tail")

	var actor_id := int(runtime_engine.get_state().get_current_player_id())
	var cmd := Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor_id, {})
	cmd.timestamp = int(Time.get_unix_time_from_system())
	var apply_r: Result = runtime_engine.execute_command(cmd, true)
	if not apply_r.ok:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "应用 follow-up 命令失败: %s" % apply_r.error)
	var state_hash := str(runtime_engine.get_state().compute_hash()) if runtime_engine.get_state() != null else ""
	client.record_online_resume_runtime_command_applied(cmd.to_dict(), state_hash)

	var snapshot_after_record: Dictionary = client.get_online_resume_session_snapshot()
	if int(snapshot_after_record.get("full_replay_live_tail_count", -1)) != 0:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "single full-engine 模式下 record_online_resume_runtime_command_applied 不应再积累 live tail")

	var ensure_r := client.ensure_online_resume_full_history_timeline_current(true)
	if not ensure_r.ok:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "刷新单引擎 timeline cache 失败: %s" % ensure_r.error)

	var cached_timeline: Dictionary = client.get_online_resume_full_replay_step_timeline()
	if int(StepTimelineHelpersClass.read_processed_command_count(cached_timeline)) != int(runtime_engine.command_history.size()):
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "timeline cache 未追平到当前 full engine")
	if client.get_online_resume_full_replay_engine() != runtime_engine:
		return _restore_and_fail(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active, "刷新 cache 后 full engine 不应与 runtime engine 分离")

	_restore(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active)
	return Result.success({
		"history_size": int(runtime_engine.command_history.size()),
	})

static func _build_working_phase_resume_archive_transfer() -> Result:
	var engine := GameEngineClass.new()
	engine.checkpoint_interval = 1
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("初始化恢复历史失败: %s" % init_r.error)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("complete_setup 失败: %s" % setup_r.error)
	var restructuring_r: Result = TestPhaseUtilsClass.complete_restructuring(engine)
	if not restructuring_r.ok:
		return Result.failure("complete_restructuring 失败: %s" % restructuring_r.error)
	var oob_r: Result = TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("complete_order_of_business 失败: %s" % oob_r.error)
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("prepare_engine_for_online_resume 失败: %s" % prepare_r.error)
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive 失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var transfer_r := ResyncSnapshotTransferClass.build_snapshot_transfer(archive, "full_cache_transfer", 4096, 256)
	if not transfer_r.ok:
		return Result.failure("build_snapshot_transfer 失败: %s" % transfer_r.error)
	return Result.success({
		"transfer": Dictionary(transfer_r.value).duplicate(true),
	})

static func _restore(prev_mode: int, prev_local_player_id: int, prev_local_role: String, prev_server_url: String, prev_connect_token: String, prev_room_state: Dictionary, prev_room_list: Array, prev_player_profile: Dictionary, prev_resume_state: Dictionary, prev_engine, prev_is_game_active: bool) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.local_role = prev_local_role
	NetContext.server_url = prev_server_url
	NetContext.connect_token = prev_connect_token
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.room_list = prev_room_list.duplicate(true)
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

static func _restore_and_fail(prev_mode: int, prev_local_player_id: int, prev_local_role: String, prev_server_url: String, prev_connect_token: String, prev_room_state: Dictionary, prev_room_list: Array, prev_player_profile: Dictionary, prev_resume_state: Dictionary, prev_engine, prev_is_game_active: bool, message: String) -> Result:
	_restore(prev_mode, prev_local_player_id, prev_local_role, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state, prev_engine, prev_is_game_active)
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
	signal local_bootstrap_progress(payload: Dictionary)
	signal resume_fast_start_ready(payload: Dictionary)
	signal resume_full_history_ready(payload: Dictionary)
	signal resync_archive_received(archive: Dictionary)

	var multiplayer := _MockMultiplayer.new(7)
	var _pending_resync_archive: Dictionary = {}
	var _pending_resync_snapshot_manifest: Dictionary = {}
	var _pending_resync_snapshot_chunks: Dictionary = {}
	var _pending_resync_delta: Dictionary = {}
	var _online_client_engine_room_code: String = ""
