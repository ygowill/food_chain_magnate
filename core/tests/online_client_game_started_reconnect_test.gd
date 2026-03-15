# Online client：重连路径下 GameStarted 复用现有 engine
class_name OnlineClientGameStartedReconnectTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

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

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_r.ok:
		return Result.failure("初始化测试 engine 失败: %s" % init_r.error)
	Globals.set_current_game_engine(engine)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "ROOM02",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("ROOM02", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_reconnecting(true)

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)

	client.handle_rpc_game_started({
		"player_id_by_peer_id": {
			7: 1,
		},
		"config": {
			"desired_player_count": 2,
			"seed": 12345,
			"allow_spectators": true,
			"enabled_modules_v2": [],
			"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
			"restaurant_logo_choices_by_player": [-1, -1],
		},
	})

	if Globals.current_game_engine != engine:
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
			"重连路径下不应替换现有 engine"
		)
	if int(NetContext.local_player_id) != 1:
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
			"local_player_id 恢复错误: %d" % int(NetContext.local_player_id)
		)
	if mock_net.game_started_payloads.size() != 1:
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
			"重连路径应继续发出 game_started: %s" % str(mock_net.game_started_payloads)
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

class _MockMultiplayer:
	extends RefCounted

	func get_unique_id() -> int:
		return 7

class _MockNet:
	extends RefCounted

	signal game_started(payload: Dictionary)

	var multiplayer := _MockMultiplayer.new()
	var game_started_payloads: Array[Dictionary] = []

	func _init() -> void:
		game_started.connect(_on_game_started)

	func _on_game_started(payload: Dictionary) -> void:
		game_started_payloads.append(Dictionary(payload).duplicate(true))
