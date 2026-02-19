# 联机对局启动 + 命令回放一致性（M2）
class_name OnlineStartGameReplayTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const CommandClass = preload("res://core/types/command.gd")
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123456

	var rm = RoomManagerClass.new(rng)

	var host_peer_id := 10
	var host_profile := {"name": "Host", "color_index": 1, "restaurant_logo_id": 2}
	var config := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	var cr: Result = rm.create_room(host_peer_id, host_profile, "pw", config)
	if not cr.ok:
		return Result.failure("CreateRoom 失败: %s" % cr.error)

	var room_code := str(Dictionary(cr.value).get("room_code", ""))
	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		return Result.failure("CreateRoom 未返回 room")

	var jr: Result = rm.join_room(11, {"name": "P2", "color_index": 2, "restaurant_logo_id": 0}, room_code, "pw")
	if not jr.ok:
		return Result.failure("JoinRoom 失败: %s" % jr.error)

	if not room.has_method("set_player_logo_by_seat"):
		return Result.failure("room 缺少 set_player_logo_by_seat")
	var set_logo_r0: Result = room.set_player_logo_by_seat(0, 1)
	if not set_logo_r0.ok:
		return Result.failure("set_player_logo_by_seat(0,1) 失败: %s" % set_logo_r0.error)
	var set_logo_r1: Result = room.set_player_logo_by_seat(1, -1)
	if not set_logo_r1.ok:
		return Result.failure("set_player_logo_by_seat(1,-1) 失败: %s" % set_logo_r1.error)

	var sr: Result = room.start_game()
	if not sr.ok:
		return Result.failure("StartGame 失败: %s" % sr.error)

	if room.game_engine == null:
		return Result.failure("StartGame 后 room.game_engine 为空")
	var server_engine = room.game_engine

	var payload: Dictionary = Dictionary(sr.value)
	var mapping: Dictionary = Dictionary(payload.get("player_id_by_peer_id", {}))
	var cfg: Dictionary = Dictionary(payload.get("config", {}))
	var logo_choices_cfg: Array = Array(cfg.get("restaurant_logo_choices_by_player", []))
	if logo_choices_cfg.size() < 2:
		return Result.failure("StartGame 配置缺少 restaurant_logo_choices_by_player: %s" % str(logo_choices_cfg))
	if int(logo_choices_cfg[0]) != 1 or int(logo_choices_cfg[1]) != -1:
		return Result.failure("StartGame 未保留房主分配的 Logo: %s" % str(logo_choices_cfg))

	var player_count := int(cfg.get("desired_player_count", 0))
	var seed := int(cfg.get("seed", 0))
	var base_dir := str(cfg.get("modules_v2_base_dir", "")).strip_edges()
	var enabled_modules: Array[String] = []
	var mods_val = cfg.get("enabled_modules_v2", null)
	if mods_val is Array:
		for it in Array(mods_val):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			enabled_modules.append(s)

	var logo_choices: Array[int] = []
	var lc_val = cfg.get("restaurant_logo_choices_by_player", null)
	if lc_val is Array:
		for it2 in Array(lc_val):
			if it2 is int or it2 is float:
				logo_choices.append(int(it2))
	while logo_choices.size() < player_count:
		logo_choices.append(-1)

	var client_engine = GameEngineClass.new()
	var init_r: Result = client_engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
	if not init_r.ok:
		return Result.failure("Client GameEngine.initialize 失败: %s" % init_r.error)
	var client_state = client_engine.get_state()
	if client_state != null:
		if not (client_state.rules is Dictionary):
			client_state.rules = {}
		client_state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1

	for _i in range(player_count):
		var server_state = server_engine.get_state()
		if server_state == null:
			return Result.failure("server_state 为空")
		var current_player_id := int(server_state.get_current_player_id())

		var acting_peer_id := -1
		for k in mapping.keys():
			if int(mapping.get(k, -1)) == current_player_id:
				acting_peer_id = int(k)
				break
		if acting_peer_id < 0:
			return Result.failure("未找到 current_player_id=%d 对应的 peer_id" % current_player_id)

		var actor_id := int(mapping.get(acting_peer_id, -1))
		if actor_id != current_player_id:
			return Result.failure("peer->player 映射错误: peer=%d mapped=%d current=%d" % [acting_peer_id, actor_id, current_player_id])

		var cmd = CommandClass.create("select_reserve_card", actor_id, {"selected_index": 0})
		var ar: Result = server_engine.execute_command(cmd)
		if not ar.ok:
			return Result.failure("Server execute_command 失败: %s" % ar.error)

		var cmd_dict = cmd.to_dict()
		var parsed: Result = CommandClass.from_dict(cmd_dict)
		if not parsed.ok:
			return Result.failure("Command.from_dict 失败: %s" % parsed.error)
		var replay_cmd: Command = parsed.value

		var cr2: Result = client_engine.execute_command(replay_cmd, true)
		if not cr2.ok:
			return Result.failure("Client replay execute_command 失败: %s" % cr2.error)

		var server_hash := str(server_engine.get_state().compute_hash())
		var client_hash := str(client_engine.get_state().compute_hash())
		if server_hash != client_hash:
			return Result.failure("回放后 state_hash 不一致: server=%s client=%s" % [server_hash, client_hash])

	return Result.success()
