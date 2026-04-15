# Online client：增量恢复应用到当前 engine
class_name OnlineClientResyncDeltaApplyTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)

	var server_engine = GameEngineClass.new()
	var init_server_r: Result = server_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_server_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"server engine 初始化失败: %s" % init_server_r.error
		)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(server_engine)
	if not setup_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"server complete_setup 失败: %s" % setup_r.error
		)

	var history: Array[Command] = server_engine.get_command_history()
	if history.size() < 2:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"测试需要至少 2 条命令历史，实际: %d" % history.size()
		)

	var hash_probe = GameEngineClass.new()
	var init_probe_r: Result = hash_probe.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_probe_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"probe engine 初始化失败: %s" % init_probe_r.error
		)
	var hashes_by_sequence: Dictionary = {
		0: str(hash_probe.get_state().compute_hash()),
	}
	for cmd in history:
		var parsed_probe: Result = Command.from_dict(cmd.to_dict())
		if not parsed_probe.ok:
			return _restore_and_fail(
				prev_mode,
				prev_local_player_id,
				prev_server_url,
				prev_connect_token,
				prev_room_state,
				prev_room_list,
				prev_player_profile,
				prev_resume_state,
				prev_engine,
				prev_is_game_active,
				"probe 命令解析失败: %s" % parsed_probe.error
			)
		var probe_cmd: Command = parsed_probe.value
		var exec_probe_r: Result = hash_probe.execute_command(probe_cmd, true)
		if not exec_probe_r.ok:
			return _restore_and_fail(
				prev_mode,
				prev_local_player_id,
				prev_server_url,
				prev_connect_token,
				prev_room_state,
				prev_room_list,
				prev_player_profile,
				prev_resume_state,
				prev_engine,
				prev_is_game_active,
				"probe 命令执行失败: %s" % exec_probe_r.error
			)
		hashes_by_sequence[int(hash_probe.command_history.size())] = str(hash_probe.get_state().compute_hash())

	var client_engine = GameEngineClass.new()
	var init_client_r: Result = client_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_client_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"client engine 初始化失败: %s" % init_client_r.error
		)

	var partial_count := maxi(1, int(floor(float(history.size()) / 2.0)))
	for i in range(partial_count):
		var parsed_client: Result = Command.from_dict(history[i].to_dict())
		if not parsed_client.ok:
			return _restore_and_fail(
				prev_mode,
				prev_local_player_id,
				prev_server_url,
				prev_connect_token,
				prev_room_state,
				prev_room_list,
				prev_player_profile,
				prev_resume_state,
				prev_engine,
				prev_is_game_active,
				"client partial 命令解析失败: %s" % parsed_client.error
			)
		var client_cmd: Command = parsed_client.value
		var exec_client_r: Result = client_engine.execute_command(client_cmd, true)
		if not exec_client_r.ok:
			return _restore_and_fail(
				prev_mode,
				prev_local_player_id,
				prev_server_url,
				prev_connect_token,
				prev_room_state,
				prev_room_list,
				prev_player_profile,
				prev_resume_state,
				prev_engine,
				prev_is_game_active,
				"client partial 命令执行失败: %s" % exec_client_r.error
			)

	Globals.set_current_game_engine(client_engine)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "DELTA01",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("DELTA01", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_resume_progress(
		partial_count,
		str(hashes_by_sequence.get(partial_count, "")),
		"cp_delta_apply"
	)

	var entries: Array[Dictionary] = []
	for i2 in range(partial_count, history.size()):
		var cmd2: Command = history[i2]
		var sequence := int(cmd2.index) + 1
		entries.append({
			"sequence": sequence,
			"cmd": cmd2.to_dict(),
			"post_state_hash": str(hashes_by_sequence.get(sequence, "")),
		})

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)
	client.handle_rpc_resync_delta({
		"room_code": "DELTA01",
		"checkpoint_id": "cp_delta_apply",
		"from_sequence": partial_count,
		"to_sequence": history.size(),
		"final_sequence": history.size(),
		"final_hash": str(hashes_by_sequence.get(history.size(), "")),
		"entries": entries,
	})

	if not mock_net.delta_failures.is_empty():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"delta 恢复不应失败: %s" % str(mock_net.delta_failures)
		)
	if mock_net.delta_applied_payloads.size() != 1:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"delta 恢复成功事件次数错误: %s" % str(mock_net.delta_applied_payloads)
		)

	var server_hash := str(server_engine.get_state().compute_hash())
	var client_hash := str(client_engine.get_state().compute_hash())
	if server_hash != client_hash:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"delta 恢复后 hash 不一致: server=%s client=%s" % [server_hash, client_hash]
		)
	if client_engine.command_history.size() != history.size():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"delta 恢复后命令数不一致: %d vs %d" % [client_engine.command_history.size(), history.size()]
		)
	if NetContext.get_online_resume_last_applied_sequence() != history.size():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"delta 恢复后游标 sequence 未更新: %d" % NetContext.get_online_resume_last_applied_sequence()
		)
	if NetContext.get_online_resume_last_state_hash() != client_hash:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			"delta 恢复后游标 hash 未更新: %s" % NetContext.get_online_resume_last_state_hash()
		)

	_restore(
		prev_mode,
		prev_local_player_id,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_engine,
		prev_is_game_active
	)
	return Result.success()

static func _restore(
	prev_mode,
	prev_local_player_id: int,
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

class _MockNet:
	extends RefCounted

	signal resync_delta_applied(payload: Dictionary)
	signal resync_delta_failed(message: String)

	var _pending_resync_delta: Dictionary = {}
	var _resume_force_snapshot_once: bool = false
	var delta_applied_payloads: Array[Dictionary] = []
	var delta_failures: Array[String] = []

	func _init() -> void:
		resync_delta_applied.connect(func(payload: Dictionary) -> void:
			delta_applied_payloads.append(Dictionary(payload).duplicate(true))
		)
		resync_delta_failed.connect(func(message: String) -> void:
			delta_failures.append(str(message))
		)

	func request_resume_force_snapshot_once() -> void:
		_resume_force_snapshot_once = true
