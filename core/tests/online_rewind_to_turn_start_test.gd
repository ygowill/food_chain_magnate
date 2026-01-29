# Online：回退到当前玩家回合开始（Server 侧）应通过 archive 广播保持一致性。
# 目标：
# - Server room 能 rewind 到 turn-start，并丢弃未来历史（线性时间线）
# - Client 通过 load_from_archive 回灌后 hash 一致，且能继续回放
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123456

	var rm = RoomManagerClass.new(rng)

	var host_peer_id := 10
	var config := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	var cr: Result = rm.create_room(host_peer_id, {"name": "Host", "color_index": 1}, "pw", config)
	if not cr.ok:
		return Result.failure("CreateRoom 失败: %s" % cr.error)

	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		return Result.failure("CreateRoom 未返回 room")

	var room_code := str(Dictionary(cr.value).get("room_code", ""))
	var jr: Result = rm.join_room(11, {"name": "P2", "color_index": 2}, room_code, "pw")
	if not jr.ok:
		return Result.failure("JoinRoom 失败: %s" % jr.error)

	var sr: Result = room.start_game()
	if not sr.ok:
		return Result.failure("StartGame 失败: %s" % sr.error)
	if room.game_engine == null:
		return Result.failure("StartGame 后 room.game_engine 为空")

	var engine = room.game_engine

	# 推进到 Working，确保 turn-start 语义稳定。
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("complete_setup 失败: %s" % setup_r.error)
	var oob_r: Result = TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("complete_order_of_business 失败: %s" % oob_r.error)

	var idx_r: Result = engine.find_current_player_turn_start_command_index()
	if not idx_r.ok:
		return Result.failure("find_current_player_turn_start_command_index 失败: %s" % idx_r.error)
	var turn_start_index := int(idx_r.value)
	var before_index := int(engine.current_command_index)

	# 让当前玩家执行一条命令，制造可回退的历史。
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")
	var actor := int(state.get_current_player_id())
	var step_r: Result = engine.execute_command(Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor))
	if not step_r.ok:
		return Result.failure("执行 skip_sub_phase 失败: %s" % step_r.error)
	if int(engine.current_command_index) <= before_index:
		return Result.failure("执行命令后 command_index 未前进")

	# room rewind（应丢弃未来历史并返回 archive）
	if not room.has_method("rewind_to_current_player_turn_start"):
		return Result.failure("room 缺少 rewind_to_current_player_turn_start")
	var rr: Result = room.rewind_to_current_player_turn_start()
	if not rr.ok:
		return Result.failure("room rewind 失败: %s" % rr.error)
	if not (rr.value is Dictionary):
		return Result.failure("room rewind 返回类型错误")

	var payload: Dictionary = Dictionary(rr.value)
	var archive_val = payload.get("archive", null)
	if not (archive_val is Dictionary):
		return Result.failure("room rewind 未返回 archive")
	var archive: Dictionary = Dictionary(archive_val)

	if int(engine.current_command_index) != turn_start_index:
		return Result.failure("rewind 后 current_command_index 不符合 turn_start: got=%d want=%d" % [int(engine.current_command_index), turn_start_index])
	if turn_start_index >= 0 and engine.command_history.size() != (turn_start_index + 1):
		return Result.failure("rewind 后 command_history.size 不符合预期: got=%d want=%d" % [engine.command_history.size(), turn_start_index + 1])

	# client 回灌一致性（hash 应一致）
	var client_engine := GameEngine.new()
	var init_c: Result = client_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not init_c.ok:
		return Result.failure("client initialize 失败: %s" % init_c.error)

	var load_r: Result = client_engine.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("client load_from_archive 失败: %s" % load_r.error)

	var hash_s := str(engine.get_state().compute_hash())
	var hash_c := str(client_engine.get_state().compute_hash())
	if hash_s != hash_c:
		return Result.failure("rewind resync 后 state_hash 不一致: server=%s client=%s" % [hash_s.substr(0, 12), hash_c.substr(0, 12)])

	# 回灌后继续执行 1 条命令，并验证 client 回放仍一致。
	var state2: GameState = engine.get_state()
	if state2 == null:
		return Result.failure("state2 为空")
	var actor2 := int(state2.get_current_player_id())
	var next_cmd := Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor2)
	var exec_s: Result = engine.execute_command(next_cmd)
	if not exec_s.ok:
		return Result.failure("server 后续命令失败: %s" % exec_s.error)
	var parsed := Command.from_dict(next_cmd.to_dict())
	if not parsed.ok:
		return Result.failure("后续命令 Command.from_dict 失败: %s" % parsed.error)
	var replay_cmd: Command = parsed.value
	var exec_c: Result = client_engine.execute_command(replay_cmd, true)
	if not exec_c.ok:
		return Result.failure("client 后续回放失败: %s" % exec_c.error)

	var hash_s2 := str(engine.get_state().compute_hash())
	var hash_c2 := str(client_engine.get_state().compute_hash())
	if hash_s2 != hash_c2:
		return Result.failure("rewind 后继续回放 hash 不一致: server=%s client=%s" % [hash_s2.substr(0, 12), hash_c2.substr(0, 12)])

	return Result.success()
