# StepTimelineBuild：阶段边界“动作归属”回归测试（0.1.4）
# - Restructuring：最后一位玩家“确认重组”应仍归属 Restructuring，随后才进入 OrderOfBusiness
# - OrderOfBusiness：最后一位玩家“选择顺序”应仍归属 OrderOfBusiness，随后才进入 Working
class_name StepTimelinePhaseBoundaryOrderTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0

	# 构造一个“回合 2 的 Restructuring”，避免触发 round1 的 auto finalize 特判。
	state.round_number = 2
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""

	if not (state.round_state is Dictionary):
		state.round_state = {}

	var submitted := {0: false, 1: false}
	state.round_state["restructuring"] = {
		"submitted": submitted,
		"finalized": false,
	}
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_RESTRUCTURING: [0, 1]
	}

	# StepTimelineBuild 从 checkpoints[0].state_dict 开始回放：需要同步“初始状态”。
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	# 玩家 1 / 玩家 2 依次确认重组，之后应由 AutoAdvance 推进到 OrderOfBusiness。
	var r0 := engine.execute_command(Command.create("submit_restructuring", 0))
	if not r0.ok:
		return Result.failure("submit_restructuring p0 failed: %s" % r0.error)
	var r1 := engine.execute_command(Command.create("submit_restructuring", 1))
	if not r1.ok:
		return Result.failure("submit_restructuring p1 failed: %s" % r1.error)

	var state_after := engine.get_state()
	if state_after.phase != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("expected phase OrderOfBusiness after restructuring, got: %s" % str(state_after.phase))

	# 选择顺序（两人局：位置 0/1 必可用），之后应由 AutoAdvance 推进到 Working。
	var pid0 := state_after.get_current_player_id()
	var pick0 := engine.execute_command(Command.create("choose_turn_order", pid0, {"position": 0}))
	if not pick0.ok:
		return Result.failure("choose_turn_order #1 failed: %s" % pick0.error)
	state_after = engine.get_state()
	var pid1 := state_after.get_current_player_id()
	var pick1 := engine.execute_command(Command.create("choose_turn_order", pid1, {"position": 1}))
	if not pick1.ok:
		return Result.failure("choose_turn_order #2 failed: %s" % pick1.error)

	# Build timeline and assert attribution boundaries.
	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full failed: %s" % build_r.error)

	var data_val = build_r.value
	if not (data_val is Dictionary):
		return Result.failure("build_full.value type error (expected Dictionary)")
	var data: Dictionary = data_val
	var steps_val = data.get("steps", null)
	if not (steps_val is Array):
		return Result.failure("steps type error (expected Array)")
	var steps: Array = steps_val

	# command_index -> step_index（command kind）
	var command_steps := {}
	for i in range(steps.size()):
		var s_val = steps[i]
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if str(s.get("kind", "")).strip_edges() != "command":
			continue
		command_steps[int(s.get("anchor_command_index", -1))] = i

	if not (command_steps.has(1) and command_steps.has(3)):
		return Result.failure("expected command steps for command_index=1 and 3 (got=%s)" % str(command_steps.keys()))

	var step_submit_last: Dictionary = steps[int(command_steps[1])]
	var submit_phase := str(step_submit_last.get("phase", "")).strip_edges()
	if submit_phase != DefsClass.PHASE_RESTRUCTURING:
		return Result.failure("expected last submit_restructuring in Restructuring, got: %s" % submit_phase)

	var step_choose_last: Dictionary = steps[int(command_steps[3])]
	var choose_phase := str(step_choose_last.get("phase", "")).strip_edges()
	if choose_phase != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("expected last choose_turn_order in OrderOfBusiness, got: %s" % choose_phase)

	# 需要存在对应的 phase step，并且出现在该 command step 之后。
	var phase_step_oob := -1
	var phase_step_working := -1
	for i2 in range(steps.size()):
		var s2_val = steps[i2]
		if not (s2_val is Dictionary):
			continue
		var s2: Dictionary = s2_val
		if str(s2.get("kind", "")).strip_edges() != "phase":
			continue
		var anchor := int(s2.get("anchor_command_index", -1))
		var ph := str(s2.get("phase", "")).strip_edges()
		if anchor == 1 and ph == DefsClass.PHASE_ORDER_OF_BUSINESS:
			phase_step_oob = i2
		if anchor == 3 and ph == DefsClass.PHASE_WORKING:
			phase_step_working = i2

	if phase_step_oob < 0:
		return Result.failure("expected a phase step to OrderOfBusiness anchored at command_index=1")
	if phase_step_oob <= int(command_steps[1]):
		return Result.failure("expected OrderOfBusiness phase step after command_index=1 step (phase_step=%d cmd_step=%d)" % [phase_step_oob, int(command_steps[1])])

	if phase_step_working < 0:
		return Result.failure("expected a phase step to Working anchored at command_index=3")
	if phase_step_working <= int(command_steps[3]):
		return Result.failure("expected Working phase step after command_index=3 step (phase_step=%d cmd_step=%d)" % [phase_step_working, int(command_steps[3])])

	return Result.success({
		"steps": steps.size(),
		"commands": engine.command_history.size(),
		"phase_step_oob": phase_step_oob,
		"phase_step_working": phase_step_working,
	})
