# 联机 Resync：Archive 回灌一致性（M4）
# 场景：
# - server 执行若干命令
# - client 只回放部分命令（模拟 index/hash mismatch 前置状态）
# - client 通过 load_from_archive 回灌到 server 状态
# - 回灌后继续回放 1 条命令，确保一致性可继续维持
class_name OnlineResyncArchiveTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var server_engine := GameEngine.new()
	var init_s := server_engine.initialize(player_count, seed)
	if not init_s.ok:
		return Result.failure("server initialize 失败: %s" % init_s.error)

	var client_engine := GameEngine.new()
	var init_c := client_engine.initialize(player_count, seed)
	if not init_c.ok:
		return Result.failure("client initialize 失败: %s" % init_c.error)

	var setup := TestPhaseUtilsClass.complete_setup(server_engine)
	if not setup.ok:
		return Result.failure("server complete_setup 失败: %s" % setup.error)

	var history: Array[Command] = server_engine.get_command_history()
	if history.is_empty():
		return Result.failure("server 命令历史为空")

	var partial_count: int = maxi(1, int(floor(float(history.size()) / 2.0)))
	for i in range(partial_count):
		var cmd: Command = history[i]
		var parsed := Command.from_dict(cmd.to_dict())
		if not parsed.ok:
			return Result.failure("Command.from_dict 失败: %s" % parsed.error)
		var replay_cmd: Command = parsed.value
		var exec := client_engine.execute_command(replay_cmd, true)
		if not exec.ok:
			return Result.failure("client partial replay 失败: %s" % exec.error)

	var archive_r := server_engine.create_archive()
	if not archive_r.ok:
		return Result.failure("server create_archive 失败: %s" % archive_r.error)
	var archive: Dictionary = archive_r.value

	var load_r := client_engine.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("client load_from_archive 失败: %s" % load_r.error)

	var hash_s := str(server_engine.get_state().compute_hash())
	var hash_c := str(client_engine.get_state().compute_hash())
	if hash_s != hash_c:
		return Result.failure("resync 后 state_hash 不一致: server=%s client=%s" % [hash_s.substr(0, 12), hash_c.substr(0, 12)])

	# 回灌后继续执行一条命令，并验证回放仍一致（避免“只能加载但无法继续”）。
	var state := server_engine.get_state()
	var actor := int(state.get_current_player_id())
	var next_cmd: Command = null
	if str(state.phase) == DefsClass.PHASE_WORKING and not str(state.sub_phase).is_empty():
		next_cmd = Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor)
	else:
		next_cmd = Command.create(ActionIdsClass.END_TURN, actor)

	var exec_s := server_engine.execute_command(next_cmd)
	if not exec_s.ok:
		return Result.failure("server 后续命令失败: %s (%s)" % [exec_s.error, str(next_cmd.action_id)])
	var parsed2 := Command.from_dict(next_cmd.to_dict())
	if not parsed2.ok:
		return Result.failure("后续命令 Command.from_dict 失败: %s" % parsed2.error)
	var replay_cmd2: Command = parsed2.value
	var exec_c := client_engine.execute_command(replay_cmd2, true)
	if not exec_c.ok:
		return Result.failure("client 后续回放失败: %s (%s)" % [exec_c.error, str(replay_cmd2.action_id)])

	var hash_s2 := str(server_engine.get_state().compute_hash())
	var hash_c2 := str(client_engine.get_state().compute_hash())
	if hash_s2 != hash_c2:
		return Result.failure("resync 后继续回放 hash 不一致: server=%s client=%s" % [hash_s2.substr(0, 12), hash_c2.substr(0, 12)])

	return Result.success()
