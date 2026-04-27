class_name OnlineResumeFullSnapshotBootstrapTest
extends RefCounted

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

	var build_r := _build_resume_archive_transfer()
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
			"构造恢复房完整快照失败: %s" % build_r.error
		)
	var build_info: Dictionary = Dictionary(build_r.value)
	var archive: Dictionary = Dictionary(build_info.get("archive", {})).duplicate(true)
	var transfer: Dictionary = Dictionary(build_info.get("transfer", {})).duplicate(true)
	var expected_hash := str(build_info.get("expected_hash", "")).strip_edges()
	var full_history_size := int(build_info.get("history_size", -1))

	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "FULL01",
		"room_mode": "resume_archive",
		"status": "Starting",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("FULL01", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
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

	if Globals.current_game_engine != null:
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
			"完整快照模式下不应在收到 snapshot 前先创建 engine"
		)
	if not mock_net.game_started_payloads.is_empty():
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
			"完整快照模式下 game_started 应延迟到 archive 应用完成后再发出"
		)
	if mock_net.progress_payloads.is_empty():
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
			"应先发出等待完整快照的本地 bootstrap 进度"
		)

	var manifest: Dictionary = Dictionary(transfer.get("manifest", {})).duplicate(true)
	manifest["room_code"] = "FULL01"
	manifest["request_id"] = "req_full_bootstrap"
	client.handle_rpc_resync_snapshot_manifest(manifest)
	for chunk_val in Array(transfer.get("chunks", [])):
		if not (chunk_val is Dictionary):
			continue
		client.handle_rpc_resync_snapshot_chunk(Dictionary(chunk_val).duplicate(true))

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
			"完整快照 bootstrap 后应持有 full engine"
		)
	if int(runtime_engine.command_history.size()) != full_history_size:
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
			"runtime_engine 历史长度错误: %d vs %d" % [int(runtime_engine.command_history.size()), full_history_size]
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
			"runtime_engine hash 错误: %s vs %s" % [str(runtime_engine.get_state().compute_hash()), expected_hash]
		)
	if mock_net.game_started_payloads.size() != 1:
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
			"应在 archive 应用完成后发出一次 game_started"
		)
	if mock_net.fast_start_payloads.size() != 0:
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
			"single full-engine 方案下不应再发出 resume_fast_start_ready"
		)
	if mock_net.full_history_ready_payloads.size() != 1:
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
			"完整快照 bootstrap 后应发出一次 resume_full_history_ready"
		)
	if mock_net.resync_archives.size() != 1:
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
			"完整快照 bootstrap 后应只发出一次 resync_archive_received"
		)
	var has_replay_progress := false
	for payload_val in mock_net.progress_payloads:
		if not (payload_val is Dictionary):
			continue
		var progress: Dictionary = Dictionary(payload_val)
		if str(progress.get("stage_key", "")) == "archive_replay" and str(progress.get("detail", "")).contains("正在回放历史"):
			has_replay_progress = true
			break
	if not has_replay_progress:
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
			"本地 bootstrap 进度中应包含历史回放阶段"
		)

	var full_engine = client.get_online_resume_full_replay_engine()
	if full_engine != runtime_engine:
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
			"single full-engine 模式下 full engine 应与 runtime engine 共用实例"
		)

	var session_snapshot: Dictionary = client.get_online_resume_session_snapshot()
	if not bool(session_snapshot.get("single_full_engine_mode", false)):
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
			"session snapshot 应标记 single_full_engine_mode"
		)
	if not bool(session_snapshot.get("full_replay_step_timeline_ready", false)):
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
			"single full-engine bootstrap 后应直接预构建 step timeline cache"
		)
	if not bool(session_snapshot.get("full_replay_step_timeline_entries_ready", false)):
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
			"single full-engine bootstrap 后应直接预构建日志 entries cache"
		)
	if int(session_snapshot.get("runtime_command_count", -1)) != full_history_size:
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
			"runtime_command_count 应等于完整历史长度"
		)
	if int(session_snapshot.get("full_replay_command_count", -1)) != full_history_size:
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
			"full_replay_command_count 应等于完整历史长度"
		)

	var cached_timeline: Dictionary = client.get_online_resume_full_replay_step_timeline()
	if int(StepTimelineHelpersClass.read_processed_command_count(cached_timeline)) != full_history_size:
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
			"cached timeline 已处理命令数错误"
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
		prev_is_game_active
	)
	return Result.success({
		"history_size": full_history_size,
		"progress_events": mock_net.progress_payloads.size(),
	})

static func _build_resume_archive_transfer() -> Result:
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
	var transfer_r := ResyncSnapshotTransferClass.build_snapshot_transfer(archive, "full_bootstrap_transfer", 4096, 256)
	if not transfer_r.ok:
		return Result.failure("build_snapshot_transfer 失败: %s" % transfer_r.error)
	return Result.success({
		"archive": archive,
		"transfer": Dictionary(transfer_r.value).duplicate(true),
		"expected_hash": str(engine.get_state().compute_hash()) if engine.get_state() != null else "",
		"history_size": int(engine.command_history.size()),
	})

static func _restore(
	prev_mode: int,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool
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
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

static func _restore_and_fail(
	prev_mode: int,
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
		prev_is_game_active
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
	var game_started_payloads: Array[Dictionary] = []
	var progress_payloads: Array[Dictionary] = []
	var fast_start_payloads: Array[Dictionary] = []
	var full_history_ready_payloads: Array[Dictionary] = []
	var resync_archives: Array[Dictionary] = []

	func _init() -> void:
		game_started.connect(func(payload: Dictionary) -> void:
			game_started_payloads.append(Dictionary(payload).duplicate(true))
		)
		local_bootstrap_progress.connect(func(payload: Dictionary) -> void:
			progress_payloads.append(Dictionary(payload).duplicate(true))
		)
		resume_fast_start_ready.connect(func(payload: Dictionary) -> void:
			fast_start_payloads.append(Dictionary(payload).duplicate(true))
		)
		resume_full_history_ready.connect(func(payload: Dictionary) -> void:
			full_history_ready_payloads.append(Dictionary(payload).duplicate(true))
		)
		resync_archive_received.connect(func(archive: Dictionary) -> void:
			resync_archives.append(Dictionary(archive).duplicate(true))
		)
