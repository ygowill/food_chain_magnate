# StepTimelineBuild：Cleanup 丢弃事件与里程碑顺序回归测试（0.1.5）
# - 进入 Cleanup 的自动丢弃必须产生 FOOD_DISCARDED，并且 first_throw_away 必须出现在所有清理库存之后
# - choose_fridge_keep 必须产生 FOOD_DISCARDED（清理库存: 丢弃...），且离开 Cleanup 时不得重复输出
class_name StepTimelineCleanupDiscardOrderTest
extends RefCounted

const StepTimelineBuildClass = preload("res://core/engine/game_engine/step_timeline_build.gd")
const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(seed_val: int = 12345) -> Result:
	var auto_r := _case_auto_discard(seed_val)
	if not auto_r.ok:
		return auto_r

	var keep_r := _case_choose_fridge_keep(seed_val)
	if not keep_r.ok:
		return keep_r

	return Result.success({
		"auto_discard": auto_r.value,
		"choose_fridge_keep": keep_r.value,
	})

static func _case_auto_discard(seed_val: int) -> Result:
	# Case A：无冰箱进入 Cleanup 自动丢弃
	# - 必须先出现 FOOD_DISCARDED，再出现 first_throw_away
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_number = 1
	state.phase = "Marketing"
	state.sub_phase = ""

	state.players[0]["inventory"] = {"burger": 2, "soda": 1}
	state.players[1]["inventory"] = {"pizza": 1}

	# StepTimelineBuild 从 checkpoints[0].state_dict 开始回放：需要同步“初始状态”。
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	var adv := engine.execute_command(Command.create_system("advance_phase"))
	if not adv.ok:
		return Result.failure("advance_phase failed: %s" % adv.error)

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full failed: %s" % build_r.error)
	if not (build_r.value is Dictionary):
		return Result.failure("build_full.value type error (expected Dictionary)")
	var data: Dictionary = build_r.value
	var events_val = data.get("events", null)
	if not (events_val is Array):
		return Result.failure("events type error (expected Array)")
	var events: Array = events_val

	var discard_idxs: Array[int] = []
	var milestone_idxs: Array[int] = []
	for idx in range(events.size()):
		var ev_val = events[idx]
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t := str(ev.get("type", "")).strip_edges()
		if t == EventBus.EventType.FOOD_DISCARDED and str(ev.get("phase_segment", "")).strip_edges() == "Cleanup":
			discard_idxs.append(idx)
		if t == EventBus.EventType.MILESTONE_ACHIEVED:
			var d_val = ev.get("data", null)
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			if str(d.get("milestone_id", "")).strip_edges() == "first_throw_away":
				milestone_idxs.append(idx)

	if discard_idxs.is_empty():
		return Result.failure("expected FOOD_DISCARDED events in Cleanup segment")
	if milestone_idxs.is_empty():
		return Result.failure("expected MILESTONE_ACHIEVED first_throw_away")

	var last_discard: int = int(discard_idxs.max())
	for midx in milestone_idxs:
		if int(midx) <= last_discard:
			return Result.failure("expected first_throw_away after all FOOD_DISCARDED (last_discard_idx=%d got_milestone_idx=%d)" % [last_discard, int(midx)])

	return Result.success({
		"discard_count": discard_idxs.size(),
		"milestone_count": milestone_idxs.size(),
		"last_discard_idx": last_discard,
		"first_milestone_idx": int(milestone_idxs.min()),
	})

static func _case_choose_fridge_keep(seed_val: int) -> Result:
	# Case B：已有 first_throw_away（冰箱容量）时，两人都需要 choose_fridge_keep
	# - 每次 choose_fridge_keep 都必须产生 FOOD_DISCARDED
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_number = 2
	state.phase = "Cleanup"
	state.sub_phase = ""

	# 手动给予冰箱（first_throw_away 的 gain_fridge=10），并制造超出容量的库存。
	for pid in [0, 1]:
		var claim := StateUpdaterClass.claim_milestone(state, pid, "first_throw_away")
		if not claim.ok:
			return Result.failure("claim first_throw_away failed: %s" % claim.error)

	state.players[0]["inventory"] = {"burger": 8, "soda": 8}
	state.players[1]["inventory"] = {"pizza": 9, "beer": 5}

	var cleanup_apply := CleanupSettlementClass.apply(state)
	if not cleanup_apply.ok:
		return Result.failure("CleanupSettlement.apply failed: %s" % cleanup_apply.error)

	# StepTimelineBuild 从 checkpoints[0].state_dict 开始回放：需要同步“初始状态”。
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	# 两位玩家依次选择保留（均会产生丢弃）。
	var r0 := engine.execute_command(Command.create("choose_fridge_keep", 0, {"keep": {"burger": 5, "soda": 5}}))
	if not r0.ok:
		return Result.failure("choose_fridge_keep p0 failed: %s" % r0.error)
	var r1 := engine.execute_command(Command.create("choose_fridge_keep", 1, {"keep": {"pizza": 5, "beer": 5}}))
	if not r1.ok:
		return Result.failure("choose_fridge_keep p1 failed: %s" % r1.error)

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full failed: %s" % build_r.error)
	if not (build_r.value is Dictionary):
		return Result.failure("build_full.value type error (expected Dictionary)")
	var data: Dictionary = build_r.value
	var events_val = data.get("events", null)
	if not (events_val is Array):
		return Result.failure("events type error (expected Array)")
	var events: Array = events_val

	var discard_idxs: Array[int] = []
	var discard_cmds := {}
	for idx in range(events.size()):
		var ev_val = events[idx]
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		if str(ev.get("type", "")).strip_edges() != EventBus.EventType.FOOD_DISCARDED:
			continue
		discard_idxs.append(idx)
		discard_cmds[int(ev.get("command_index", -1))] = true

	if discard_idxs.size() != 2:
		return Result.failure("expected 2 FOOD_DISCARDED events from choose_fridge_keep (got=%d)" % discard_idxs.size())
	if not (discard_cmds.has(0) and discard_cmds.has(1) and discard_cmds.size() == 2):
		return Result.failure("expected FOOD_DISCARDED command_index to be {0,1} (got=%s)" % str(discard_cmds.keys()))

	return Result.success({
		"discard_count": discard_idxs.size(),
	})
