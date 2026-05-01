# Online client：GameStarted 的 config bootstrap 必须带上房间配置覆盖
class_name OnlineClientConfigBootstrapOverridesTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")

	var invalid_base_dir_r := _test_invalid_modules_base_dir_rejected()
	if not invalid_base_dir_r.ok:
		return invalid_base_dir_r
	var invalid_override_shape_r := _test_invalid_override_shape_rejected()
	if not invalid_override_shape_r.ok:
		return invalid_override_shape_r

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

	Globals.current_game_engine = null
	Globals.is_game_active = false

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "SGBOOT",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)
	client.handle_rpc_game_started({
		"player_id_by_peer_id": {
			7: 0,
			8: 1,
		},
		"config": {
			"desired_player_count": 2,
			"seed": 12345,
			"allow_spectators": true,
			"enabled_modules_v2": [],
			"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
			"restaurant_logo_choices_by_player": [-1, -1],
			"game_option_overrides": {
				"rules.salary_cost": 0,
				"rules.bankruptcy_max_breaks": 1,
				"bank.default_per_player": 75,
				"rules.bankruptcy_extra_reserve_per_player": 0,
				"setup.auto_select_reserve_cards": true,
			},
		},
	})

	var engine = Globals.current_game_engine
	if engine == null or engine.get_state() == null:
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
			"GameStarted 后应创建本地 engine"
		)

	var state: GameState = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_SETUP:
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
			"短游戏 bootstrap 阶段错误: %s" % str(state.phase)
		)
	if str(state.sub_phase) != "":
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
			"短游戏 bootstrap 应跳过储备卡选择，实际 sub_phase=%s" % str(state.sub_phase)
		)
	if int(state.bank.get("total", -1)) != 150:
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
			"短游戏 bootstrap 银行初始资金错误: %s" % str(state.bank.get("total", null))
		)

	for pid in range(state.players.size()):
		var player: Dictionary = Dictionary(state.players[pid])
		var cards_val = player.get("reserve_cards", null)
		if not (cards_val is Array):
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
				"players[%d].reserve_cards 类型错误" % pid
			)
		var cards: Array = cards_val
		var sel := int(player.get("reserve_card_selected", -1))
		if sel < 0 or sel >= cards.size():
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
				"短游戏 bootstrap 未自动选择储备卡(pid=%d): %d" % [pid, sel]
			)
		if bool(player.get("reserve_card_revealed", true)):
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
				"短游戏 bootstrap 不应揭示储备卡(pid=%d)" % pid
			)

	if int(NetContext.local_player_id) != 0:
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
			"local_player_id 错误: %d" % int(NetContext.local_player_id)
		)
	if str(mock_net._online_client_engine_room_code) != "SGBOOT":
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
			"房间标记错误: %s" % str(mock_net._online_client_engine_room_code)
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
			"game_started 信号应发出一次: %s" % str(mock_net.game_started_payloads)
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
	return Result.success()

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

static func _test_invalid_modules_base_dir_rejected() -> Result:
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	Globals.current_game_engine = null
	Globals.is_game_active = false

	var client = ClientLogicClass.new()
	var mock_net := _MockNet.new()
	client.setup(mock_net)
	var init_r: Result = client._initialize_online_client_engine_from_config({
		"desired_player_count": 2,
		"seed": 12345,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": "/tmp/not_res_modules",
		"restaurant_logo_choices_by_player": [-1, -1],
	}, "BADCFG", 0)
	var engine_after = Globals.current_game_engine

	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

	if init_r.ok:
		return Result.failure("Online client config 中非法 modules_v2_base_dir 不应回退默认目录后初始化成功")
	if str(init_r.error).find("modules_v2_base_dir") < 0:
		return Result.failure("错误信息应包含 modules_v2_base_dir，实际: %s" % init_r.error)
	if engine_after != null:
		return Result.failure("Online client config 初始化失败时不应写入 Globals.current_game_engine")

	return Result.success()

static func _test_invalid_override_shape_rejected() -> Result:
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	Globals.current_game_engine = null
	Globals.is_game_active = false

	var client = ClientLogicClass.new()
	var mock_net := _MockNet.new()
	client.setup(mock_net)
	var init_r: Result = client._initialize_online_client_engine_from_config({
		"desired_player_count": 2,
		"seed": 12345,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
		"restaurant_logo_choices_by_player": [-1, -1],
		"game_option_overrides": "bad",
	}, "BADOVR", 0)
	var engine_after = Globals.current_game_engine

	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active

	if init_r.ok:
		return Result.failure("非法 game_option_overrides 类型应被 online client bootstrap 拒绝")
	if str(init_r.error).find("game_option_overrides") < 0:
		return Result.failure("非法 game_option_overrides 错误信息不明确: %s" % init_r.error)
	if engine_after != null:
		return Result.failure("非法 game_option_overrides 不应创建 engine")
	return Result.success()

class _MockMultiplayer:
	extends RefCounted

	func get_unique_id() -> int:
		return 7

class _MockNet:
	extends RefCounted

	signal game_started(payload: Dictionary)
	signal resync_archive_received(archive: Dictionary)
	signal room_state_updated(room_state: Dictionary)

	var multiplayer := _MockMultiplayer.new()
	var _pending_resync_archive: Dictionary = {}
	var _online_client_engine_room_code: String = ""
	var game_started_payloads: Array[Dictionary] = []

	func _init() -> void:
		game_started.connect(_on_game_started)

	func _on_game_started(payload: Dictionary) -> void:
		game_started_payloads.append(Dictionary(payload).duplicate(true))
