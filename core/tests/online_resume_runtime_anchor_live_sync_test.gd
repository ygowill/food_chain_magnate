class_name OnlineResumeRuntimeAnchorLiveSyncTest
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

	var build_r := _build_resume_point_and_follow_up_history()
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
			"构造 runtime-anchor 测试数据失败: %s" % build_r.error
		)
	var info: Dictionary = Dictionary(build_r.value)
	var bundle: Dictionary = Dictionary(info.get("bundle", {})).duplicate(true)
	var selected_index := int(info.get("selected_index", -1))
	var next_cmd: Dictionary = Dictionary(info.get("next_cmd", {})).duplicate(true)
	var delta_payload: Dictionary = Dictionary(info.get("delta_payload", {})).duplicate(true)
	var runtime_history_size := int(info.get("runtime_history_size", -1))
	var full_history_size := int(info.get("full_history_size", -1))

	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "FAST03",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("FAST03", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
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

	if Globals.current_game_engine == null or Globals.current_game_engine.get_state() == null:
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
			"fast-start runtime_engine 构建失败"
		)

	client.handle_rpc_command_applied({
		"cmd": next_cmd,
		"state_hash": "",
	})
	if mock_net.command_applied_payloads.size() != 1:
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
			"应透传 command_applied 信号"
		)
	var translated_cmd: Dictionary = Dictionary(mock_net.command_applied_payloads[0].get("cmd", {})).duplicate(true)
	if int(translated_cmd.get("index", -999999)) != runtime_history_size:
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
			"command_applied 的 index 应映射到 runtime 本地坐标: %d vs %d"
				% [int(translated_cmd.get("index", -999999)), runtime_history_size]
		)

	client.handle_rpc_rewind_to_turn_start_meta({
		"request_id": "rew_fast_anchor",
		"room_code": "FAST03",
		"target_index": selected_index,
		"before_index": selected_index + 1,
		"history_size": selected_index + 1,
		"state_hash": "hash_rewind_anchor",
		"noop": true,
	})
	if mock_net.rewind_meta_payloads.size() != 1:
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
			"rewind meta 应透传一次"
		)
	var rewind_meta: Dictionary = Dictionary(mock_net.rewind_meta_payloads[0]).duplicate(true)
	if int(rewind_meta.get("target_index", -999999)) != runtime_history_size - 1:
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
			"rewind target_index 应映射到 runtime 本地坐标: %d vs %d"
				% [int(rewind_meta.get("target_index", -999999)), runtime_history_size - 1]
		)

	client.handle_rpc_resync_delta(delta_payload)
	if not mock_net.delta_failures.is_empty():
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
			"mapped delta 不应失败: %s" % str(mock_net.delta_failures)
		)
	if mock_net.delta_applied_payloads.size() != 1:
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
			"mapped delta 应成功应用一次"
		)
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
			"delta 后 runtime_engine 缺失"
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
			"delta 后 resume progress 应保持全局序列: %d vs %d"
				% [int(NetContext.get_online_resume_last_applied_sequence()), full_history_size]
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
		"selected_index": selected_index,
		"runtime_history_size": runtime_history_size,
		"full_history_size": full_history_size,
	})

static func _build_resume_point_and_follow_up_history() -> Result:
	var server_engine := GameEngineClass.new()
	server_engine.checkpoint_interval = 1
	var init_r: Result = server_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_r.ok:
		return Result.failure("server initialize failed: %s" % init_r.error)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(server_engine)
	if not setup_r.ok:
		return Result.failure("complete_setup failed: %s" % setup_r.error)
	var restructuring_r: Result = TestPhaseUtilsClass.complete_restructuring(server_engine)
	if not restructuring_r.ok:
		return Result.failure("complete_restructuring failed: %s" % restructuring_r.error)
	var full_archive_r: Result = server_engine.create_archive()
	if not full_archive_r.ok:
		return Result.failure("create_archive failed: %s" % full_archive_r.error)
	var full_archive: Dictionary = Dictionary(full_archive_r.value).duplicate(true)
	var full_history_size := int(server_engine.command_history.size())
	if full_history_size < 4:
		return Result.failure("测试历史过短: %d" % full_history_size)
	var selected_index := maxi(1, int(floor(float(full_history_size) / 2.0)) - 1)

	var resume_engine := GameEngineClass.new()
	var load_r: Result = resume_engine.load_from_archive(full_archive)
	if not load_r.ok:
		return Result.failure("resume load failed: %s" % load_r.error)
	var rewind_r: Result = resume_engine.rewind_to_command(selected_index)
	if not rewind_r.ok:
		return Result.failure("resume rewind failed: %s" % rewind_r.error)
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(resume_engine)
	if not prepare_r.ok:
		return Result.failure("resume prepare failed: %s" % prepare_r.error)
	var resume_archive_r: Result = resume_engine.create_archive()
	if not resume_archive_r.ok:
		return Result.failure("resume create_archive failed: %s" % resume_archive_r.error)
	var resume_archive: Dictionary = Dictionary(resume_archive_r.value).duplicate(true)

	var runtime_r: Result = OnlineResumeFastRuntimeArchiveBuilderClass.build_from_engine(
		resume_engine,
		{
			"full_archive": resume_archive,
		}
	)
	if not runtime_r.ok:
		return Result.failure("runtime build failed: %s" % runtime_r.error)
	var runtime_info: Dictionary = Dictionary(runtime_r.value)
	var runtime_archive: Dictionary = Dictionary(runtime_info.get("runtime_archive", {})).duplicate(true)
	var runtime_history_size := int(Array(runtime_archive.get("commands", [])).size())
	if runtime_history_size <= 0:
		return Result.failure("runtime_history_size 非法: %d" % runtime_history_size)

	var hashes_by_sequence: Dictionary = {}
	var probe_engine := GameEngineClass.new()
	var probe_init_r: Result = probe_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not probe_init_r.ok:
		return Result.failure("probe initialize failed: %s" % probe_init_r.error)
	hashes_by_sequence[0] = str(probe_engine.get_state().compute_hash()) if probe_engine.get_state() != null else ""
	for i in range(0, selected_index + 1):
		var cmd_val = server_engine.command_history[i]
		var parsed_r: Result = Command.from_dict(cmd_val.to_dict())
		if not parsed_r.ok:
			return Result.failure("probe cmd parse failed: %s" % parsed_r.error)
		var cmd: Command = parsed_r.value
		var exec_r: Result = probe_engine.execute_command(cmd, true)
		if not exec_r.ok:
			return Result.failure("probe cmd exec failed: %s" % exec_r.error)
		hashes_by_sequence[int(probe_engine.command_history.size())] = str(probe_engine.get_state().compute_hash()) if probe_engine.get_state() != null else ""
	var probe_prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(probe_engine)
	if not probe_prepare_r.ok:
		return Result.failure("probe prepare failed: %s" % probe_prepare_r.error)
	hashes_by_sequence[selected_index + 1] = str(probe_engine.get_state().compute_hash()) if probe_engine.get_state() != null else ""
	for i in range(selected_index + 1, server_engine.command_history.size()):
		var next_cmd_val = server_engine.command_history[i]
		var next_parsed_r: Result = Command.from_dict(next_cmd_val.to_dict())
		if not next_parsed_r.ok:
			return Result.failure("probe follow-up cmd parse failed: %s" % next_parsed_r.error)
		var next_cmd: Command = next_parsed_r.value
		var next_exec_r: Result = probe_engine.execute_command(next_cmd, true)
		if not next_exec_r.ok:
			return Result.failure("probe follow-up cmd exec failed: %s" % next_exec_r.error)
		hashes_by_sequence[int(i) + 1] = str(probe_engine.get_state().compute_hash()) if probe_engine.get_state() != null else ""

	var entries: Array[Dictionary] = []
	for i in range(selected_index + 1, server_engine.command_history.size()):
		var cmd: Command = server_engine.command_history[i]
		var sequence := int(cmd.index) + 1
		entries.append({
			"sequence": sequence,
			"cmd": cmd.to_dict(),
			"post_state_hash": str(hashes_by_sequence.get(sequence, "")),
		})
	if entries.is_empty():
		return Result.failure("缺少 follow-up entries")

	return Result.success({
		"bundle": {
			"runtime_archive": runtime_archive,
			"runtime_anchor": Dictionary(runtime_info.get("runtime_anchor", {})).duplicate(true),
			"full_archive_meta": {
				"full_command_count": int(Array(resume_archive.get("commands", [])).size()),
				"full_final_hash": str(resume_engine.get_state().compute_hash()) if resume_engine.get_state() != null else "",
				"schema_version": int(resume_archive.get("schema_version", 0)),
				"byte_size": int(var_to_bytes(resume_archive).size()),
				"source": "test_resume_engine",
			},
			"full_archive_payload": resume_archive,
		},
		"selected_index": selected_index,
		"runtime_history_size": runtime_history_size,
		"full_history_size": full_history_size,
		"next_cmd": Dictionary(entries[0].get("cmd", {})).duplicate(true),
		"delta_payload": {
			"room_code": "FAST03",
			"checkpoint_id": "cp_runtime_anchor",
			"from_sequence": selected_index + 1,
			"to_sequence": full_history_size,
			"final_sequence": full_history_size,
			"final_hash": str(hashes_by_sequence.get(full_history_size, "")),
			"entries": entries,
		},
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
	if NetContext.has_method("save_online_resume_state_to_disk"):
		NetContext.save_online_resume_state_to_disk()
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

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

	func get_unique_id() -> int:
		return 7

class _MockNet:
	extends RefCounted

	signal game_started(payload: Dictionary)
	signal resume_fast_start_ready(payload: Dictionary)
	signal command_applied(cmd_dict: Dictionary, state_hash: String)
	signal rewind_to_turn_start_meta_received(payload: Dictionary)
	signal resync_delta_applied(payload: Dictionary)
	signal resync_delta_failed(message: String)

	var multiplayer := _MockMultiplayer.new()
	var _pending_resync_delta: Dictionary = {}
	var _pending_rewind_to_turn_start_meta: Dictionary = {}
	var _online_client_engine_room_code: String = ""
	var command_applied_payloads: Array[Dictionary] = []
	var rewind_meta_payloads: Array[Dictionary] = []
	var delta_applied_payloads: Array[Dictionary] = []
	var delta_failures: Array[String] = []

	func _init() -> void:
		command_applied.connect(func(cmd_dict: Dictionary, state_hash: String) -> void:
			command_applied_payloads.append({
				"cmd": Dictionary(cmd_dict).duplicate(true),
				"state_hash": str(state_hash),
			})
		)
		rewind_to_turn_start_meta_received.connect(func(payload: Dictionary) -> void:
			rewind_meta_payloads.append(Dictionary(payload).duplicate(true))
		)
		resync_delta_applied.connect(func(payload: Dictionary) -> void:
			delta_applied_payloads.append(Dictionary(payload).duplicate(true))
		)
		resync_delta_failed.connect(func(message: String) -> void:
			delta_failures.append(str(message))
		)
