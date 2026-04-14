# skip：Cleanup pending 阶段不应允许“确认结束”，且回放旧命令时应被忽略
class_name SkipCleanupPendingRegressionTest
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const SkipActionClass = preload("res://gameplay/actions/skip_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count < 2:
		player_count = 2

	var runtime_r := _test_runtime_and_force_skip_ignore(player_count, seed_val)
	if not runtime_r.ok:
		return runtime_r

	var archive_r := _test_archive_replay_skip_is_noop_before_choose_fridge_keep(player_count, seed_val)
	if not archive_r.ok:
		return archive_r

	return Result.success({"cases": 2})

static func _test_runtime_and_force_skip_ignore(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init_r := engine.initialize(player_count, seed_val)
	if not init_r.ok:
		return Result.failure("initialize 失败: %s" % init_r.error)

	var state: GameState = engine.get_state()
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 1
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [{"kind": "fridge_keep", "player_id": 1}],
	}

	var pending_before := str(state.round_state.get("pending_phase_actions", null))
	var skip_r := engine.execute_command(Command.create(ActionIdsClass.SKIP, 1, {}))
	if skip_r.ok:
		return Result.failure("Cleanup pending 时 skip 应失败")
	var err := str(skip_r.error)
	if err.find("待处理动作") < 0:
		return Result.failure("skip 错误信息应包含 待处理动作，实际: %s" % err)
	if int(state.get_current_player_id()) != 1:
		return Result.failure("skip 失败后当前玩家不应变化，实际: %d" % int(state.get_current_player_id()))
	if str(state.round_state.get("pending_phase_actions", null)) != pending_before:
		return Result.failure("skip 失败后不应改写 pending_phase_actions")

	var action = SkipActionClass.new(engine.phase_manager)
	var force_r := action.compute_new_state_force(state, Command.create(ActionIdsClass.SKIP, 1, {}))
	if not force_r.ok:
		return Result.failure("force replay skip 应成功忽略旧命令: %s" % force_r.error)
	var forced_state: GameState = force_r.value
	if forced_state == null:
		return Result.failure("force replay skip 后 state 为空")
	if int(forced_state.get_current_player_id()) != 1:
		return Result.failure("force replay skip 不应切走当前玩家，实际: %d" % int(forced_state.get_current_player_id()))
	if str(forced_state.round_state.get("pending_phase_actions", null)) != pending_before:
		return Result.failure("force replay skip 不应改写 pending_phase_actions")

	return Result.success({"error": err})

static func _test_archive_replay_skip_is_noop_before_choose_fridge_keep(player_count: int, seed_val: int) -> Result:
	var setup_engine := GameEngine.new()
	var init_r := setup_engine.initialize(player_count, seed_val)
	if not init_r.ok:
		return Result.failure("archive case initialize 失败: %s" % init_r.error)

	var setup_state: GameState = setup_engine.get_state()
	setup_state.phase = DefsClass.PHASE_CLEANUP
	setup_state.sub_phase = ""
	setup_state.round_number = 1
	setup_state.turn_order = [0, 1]
	setup_state.current_player_index = 0

	var claim_r := StateUpdaterClass.claim_milestone(setup_state, 1, "first_throw_away")
	if not claim_r.ok:
		return Result.failure("archive case 领取 first_throw_away 失败: %s" % claim_r.error)

	setup_state.players[1]["inventory"] = {
		"burger": 12,
		"pizza": 9,
		"soda": 20,
		"lemonade": 0,
		"beer": 10
	}

	var cleanup_r := CleanupSettlementClass.apply(setup_state)
	if not cleanup_r.ok:
		return Result.failure("archive case CleanupSettlement 失败: %s" % cleanup_r.error)
	if int(setup_state.get_current_player_id()) != 1:
		return Result.failure("archive case Cleanup pending 当前玩家应为 1，实际: %d" % int(setup_state.get_current_player_id()))

	var archive_initial_state: Dictionary = setup_state.to_dict()
	var archive_rng: Dictionary = setup_engine.random_manager.to_dict()
	var timestamp := DefsClass.compute_timestamp(setup_state)

	var skip_cmd := _build_command_dict(0, ActionIdsClass.SKIP, 1, {}, DefsClass.PHASE_CLEANUP, "", timestamp)
	var choose_cmd := _build_command_dict(1, "choose_fridge_keep", 1, {
		"keep": {
			"pizza": 3,
			"beer": 2
		}
	}, DefsClass.PHASE_CLEANUP, "", timestamp)
	var choose_only_cmd := _build_command_dict(0, "choose_fridge_keep", 1, {
		"keep": {
			"pizza": 3,
			"beer": 2
		}
	}, DefsClass.PHASE_CLEANUP, "", timestamp)

	var bad_archive := _build_archive(archive_initial_state, archive_rng, [skip_cmd, choose_cmd])
	var good_archive := _build_archive(archive_initial_state, archive_rng, [choose_only_cmd])

	var replay_engine := GameEngine.new()
	var replay_bad_r := replay_engine.load_from_archive(bad_archive)
	if not replay_bad_r.ok:
		return Result.failure("bad archive load 失败: %s" % replay_bad_r.error)
	var reference_engine := GameEngine.new()
	var replay_good_r := reference_engine.load_from_archive(good_archive)
	if not replay_good_r.ok:
		return Result.failure("good archive load 失败: %s" % replay_good_r.error)

	var bad_state: GameState = replay_engine.get_state()
	var good_state: GameState = reference_engine.get_state()
	if bad_state == null or good_state == null:
		return Result.failure("archive replay 后 state 为空")

	var bad_hash := str(bad_state.compute_hash())
	var good_hash := str(good_state.compute_hash())
	if bad_hash != good_hash:
		return Result.failure("旧 skip 回放后最终状态应与正常 choose_fridge_keep 一致: bad=%s good=%s" % [bad_hash, good_hash])

	var pending_val = bad_state.round_state.get("pending_phase_actions", null)
	if pending_val is Dictionary and Dictionary(pending_val).has(DefsClass.PHASE_CLEANUP):
		return Result.failure("archive replay choose_fridge_keep 后不应残留 pending_phase_actions[Cleanup]")

	var inv_val = bad_state.players[1].get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("archive replay 后玩家 1 inventory 类型错误")
	var inv: Dictionary = inv_val
	var kept_total := 0
	for pid in ["burger", "pizza", "soda", "lemonade", "beer"]:
		kept_total += int(inv.get(pid, 0))
	if kept_total != 5 or int(inv.get("pizza", 0)) != 3 or int(inv.get("beer", 0)) != 2:
		return Result.failure("archive replay choose_fridge_keep 结果错误: %s" % str(inv))

	return Result.success({
		"bad_hash": bad_hash,
		"good_hash": good_hash
	})

static func _build_archive(initial_state: Dictionary, rng_data: Dictionary, commands: Array[Dictionary]) -> Dictionary:
	return {
		"schema_version": GameState.SCHEMA_VERSION,
		"initial_state": Dictionary(initial_state).duplicate(true),
		"commands": Array(commands).duplicate(true),
		"current_index": commands.size() - 1,
		"rng": Dictionary(rng_data).duplicate(true),
		"checkpoints": [],
		"created_at": "skip_cleanup_pending_regression_test",
		"game_version": "test"
	}

static func _build_command_dict(
	index: int,
	action_id: String,
	actor: int,
	params: Dictionary,
	phase: String,
	sub_phase: String,
	timestamp: int
) -> Dictionary:
	return {
		"index": index,
		"action_id": action_id,
		"actor": actor,
		"params": Dictionary(params).duplicate(true),
		"phase": phase,
		"sub_phase": sub_phase,
		"timestamp": timestamp,
		"metadata": {}
	}
