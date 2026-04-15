class_name OnlineResumeFullArchiveExportTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_local_role := str(NetContext.local_role)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)

	var setup_r := _build_started_resume_room()
	if not setup_r.ok:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("构造恢复房导出测试数据失败: %s" % setup_r.error)
	var setup: Dictionary = Dictionary(setup_r.value)
	var room_manager = setup.get("room_manager", null)
	var room = setup.get("room", null)
	var runtime_history_size := int(setup.get("runtime_history_size", -1))
	if room_manager == null or room == null:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("room_manager/room 缺失")

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_SERVER
	var mock_server_net := _MockServerNet.new(room_manager, 11)
	var server = ServerLogicClass.new()
	server.setup(mock_server_net)
	server.handle_rpc_request_full_archive_export({
		"request_id": "exp_full_01",
	})

	if mock_server_net.sent.size() != 1:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("服务端应返回一次 full_archive_export_ready，实际: %d" % mock_server_net.sent.size())
	var sent: Dictionary = Dictionary(mock_server_net.sent[0]).duplicate(true)
	if str(sent.get("method", "")) != "rpc_full_archive_export_ready":
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("导出 RPC 方法错误: %s" % str(sent.get("method", "")))
	var payload: Dictionary = Dictionary(sent.get("payload", {})).duplicate(true)
	var archive: Dictionary = Dictionary(payload.get("archive", {})).duplicate(true)
	var authority_history_size := int(room.game_engine.command_history.size())
	var authority_hash := str(room.game_engine.get_state().compute_hash()) if room.game_engine != null and room.game_engine.get_state() != null else ""
	if archive.is_empty():
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("full archive payload 为空")
	if int(Array(archive.get("commands", [])).size()) != authority_history_size:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure(
			"导出的 archive 应等于服务端完整权威历史: %d vs %d"
				% [int(Array(archive.get("commands", [])).size()), authority_history_size]
		)
	if authority_history_size <= runtime_history_size:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure(
			"测试前置错误：权威历史应长于 runtime 短链: authority=%d runtime=%d"
				% [authority_history_size, runtime_history_size]
		)
	if str(payload.get("final_hash", "")).strip_edges() != authority_hash:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure(
			"导出 final_hash 错误: %s vs %s"
				% [str(payload.get("final_hash", "")), authority_hash]
		)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": str(room.room_code).strip_edges().to_upper(),
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	var mock_client_net := _MockClientNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_client_net)
	client.handle_rpc_full_archive_export_ready(payload)

	if mock_client_net.full_archive_ready_payloads.size() != 1:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("客户端应发出一次 full_archive_export_ready 信号")
	var ready_payload: Dictionary = Dictionary(mock_client_net.full_archive_ready_payloads[0]).duplicate(true)
	if str(ready_payload.get("request_id", "")) != "exp_full_01":
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("客户端 request_id 错误: %s" % str(ready_payload.get("request_id", "")))
	if int(Array(Dictionary(ready_payload.get("archive", {})).get("commands", [])).size()) != authority_history_size:
		_restore(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state
		)
		return Result.failure("客户端收到的 archive 不是完整权威历史")

	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state
	)
	return Result.success({
		"authority_history_size": authority_history_size,
		"runtime_history_size": runtime_history_size,
	})

static func _build_started_resume_room() -> Result:
	var archive_r := _build_long_resume_archive()
	if not archive_r.ok:
		return archive_r
	var archive_info: Dictionary = Dictionary(archive_r.value)
	var archive: Dictionary = Dictionary(archive_info.get("archive", {})).duplicate(true)
	var engine: GameEngine = archive_info.get("engine", null)
	if engine == null:
		return Result.failure("authority engine 为空")

	var room_manager = RoomManagerClass.new()
	var room_code := "RSEXP1"
	var host_profile := {
		"name": "HostExport",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_export_host",
	}
	var player_profile := {
		"name": "PlayerExport",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_export_player",
	}
	var create_r: Result = room_manager.create_resume_room_with_code(
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
		return Result.failure("create_resume_room_with_code failed: %s" % create_r.error)
	var join_r: Result = room_manager.join_room_as_waiting_member(11, player_profile, room_code, "player")
	if not join_r.ok:
		return Result.failure("join_room_as_waiting_member failed: %s" % join_r.error)
	var assign_host_r: Result = room_manager.assign_waiting_member_to_seat(room_code, "u_export_host", 0)
	if not assign_host_r.ok:
		return Result.failure("assign host seat failed: %s" % assign_host_r.error)
	var assign_player_r: Result = room_manager.assign_waiting_member_to_seat(room_code, "u_export_player", 1)
	if not assign_player_r.ok:
		return Result.failure("assign player seat failed: %s" % assign_player_r.error)

	var room = room_manager.rooms.get(room_code, null)
	if room == null:
		return Result.failure("resume room missing")

	var bundle_r: Result = room.build_resume_fast_start_bundle()
	if not bundle_r.ok:
		return Result.failure("build_resume_fast_start_bundle failed: %s" % bundle_r.error)
	var bundle: Dictionary = Dictionary(bundle_r.value) if bundle_r.value is Dictionary else {}
	var runtime_history_size := int(Array(Dictionary(bundle.get("runtime_archive", {})).get("commands", [])).size())

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("room.start_game failed: %s" % start_r.error)
	if room.game_engine == null or room.game_engine.get_state() == null:
		return Result.failure("room.game_engine/state 缺失")
	return Result.success({
		"room_manager": room_manager,
		"room": room,
		"runtime_history_size": runtime_history_size,
		"full_history_size": int(engine.command_history.size()),
	})

static func _build_long_resume_archive() -> Result:
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
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive failed: %s" % archive_r.error)
	return Result.success({
		"engine": engine,
		"archive": Dictionary(archive_r.value).duplicate(true),
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
	prev_resume_state: Dictionary
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

class _MockMultiplayer:
	extends RefCounted

	var remote_sender_id: int = 0

	func _init(peer_id: int) -> void:
		remote_sender_id = int(peer_id)

	func get_remote_sender_id() -> int:
		return remote_sender_id

class _MockServerNet:
	extends RefCounted

	var multiplayer
	var _room_manager = null
	var sent: Array[Dictionary] = []

	func _init(room_manager, peer_id: int) -> void:
		_room_manager = room_manager
		multiplayer = _MockMultiplayer.new(peer_id)

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": Dictionary(payload).duplicate(true),
		})

class _MockClientNet:
	extends RefCounted

	signal full_archive_export_ready(payload: Dictionary)

	var full_archive_ready_payloads: Array[Dictionary] = []

	func _init() -> void:
		full_archive_export_ready.connect(func(payload: Dictionary) -> void:
			full_archive_ready_payloads.append(Dictionary(payload).duplicate(true))
		)
