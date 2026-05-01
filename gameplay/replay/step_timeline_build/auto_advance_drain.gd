# StepTimelineBuild：auto-advance 分段（phase step）
# - sub_phase 变化打包在当前 step（更新快照 + 追加事件）
# - phase 变化插入 phase step，并按 PhaseTransition 规则归属事件
extends RefCounted

const AutoAdvanceDrainStepsClass = preload("res://core/engine/game_engine/auto_advance_drain_steps.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const PhaseTransitionClass = preload("res://gameplay/replay/step_timeline_build/phase_transition.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")

static func drain(
	engine: GameEngine,
	cmd: Command,
	command_index: int,
	state_in: GameState,
	steps: Array[Dictionary],
	out_events: Array[Dictionary],
	current_step_index: int,
	seq_in: int,
	pending_marketing_enter_effect_events: Array[Dictionary],
	pending_marketing_enter_anchor_command_index: int,
	pending_cleanup_throw_away_milestone_events: Array[Dictionary],
	warnings: Array[String]
) -> Result:
	var seq := int(seq_in)
	var pending_anchor := int(pending_marketing_enter_anchor_command_index)
	var final_state: GameState = state_in

	var drain_r := AutoAdvanceDrainStepsClass.drain_steps(state_in, engine.phase_manager, engine.action_registry)
	if not drain_r.ok:
		return Result.failure("StepTimelineBuild: auto_advance 失败(命令 #%d): %s" % [command_index, drain_r.error]).with_warnings(warnings).with_warnings(drain_r.warnings)
	warnings.append_array(drain_r.warnings)
	if not (drain_r.value is Dictionary):
		return Result.failure("StepTimelineBuild: auto_advance drain 返回值类型错误（期望 Dictionary）").with_warnings(warnings)
	var drain_info: Dictionary = drain_r.value
	var final_state_val = drain_info.get("state", state_in)
	if not (final_state_val is GameState):
		return Result.failure("StepTimelineBuild: auto_advance drain 返回 state 类型错误（期望 GameState）").with_warnings(warnings)
	final_state = final_state_val
	var auto_steps_val = drain_info.get("steps", null)
	if not (auto_steps_val is Array):
		return Result.failure("StepTimelineBuild: auto_advance drain 返回 steps 类型错误（期望 Array）").with_warnings(warnings)

	for auto_step_val in Array(auto_steps_val):
		if not (auto_step_val is Dictionary):
			return Result.failure("StepTimelineBuild: auto_advance step 类型错误（期望 Dictionary）").with_warnings(warnings)
		var auto_step: Dictionary = auto_step_val
		var before_val = auto_step.get("before", null)
		var after_val = auto_step.get("after", null)
		if not (before_val is GameState):
			return Result.failure("StepTimelineBuild: auto_advance step.before 类型错误（期望 GameState）").with_warnings(warnings)
		if not (after_val is GameState):
			return Result.failure("StepTimelineBuild: auto_advance step.after 类型错误（期望 GameState）").with_warnings(warnings)
		var before: GameState = before_val
		state_in = after_val

		var phase_changed := (str(before.phase) != str(state_in.phase))

		# 构建阶段/子阶段变化事件（与 CommandRunner.drain_auto_advances 对齐）
		var phase_events := CommandRunnerClass.build_phase_change_events(before, state_in)
		var cash_events := CommandRunnerClass.build_player_cash_changed_events(before, state_in, Command.create_system("auto_advance"))
		var milestone_events := CommandRunnerClass.build_milestone_achieved_events(before, state_in, cmd)
		var milestone_filter_r := StepTimelineHelpersClass.filter_deferred_cleanup_milestone_events(milestone_events, pending_cleanup_throw_away_milestone_events)
		if not milestone_filter_r.ok:
			return milestone_filter_r.with_warnings(warnings)
		milestone_events = milestone_filter_r.value

		if phase_changed:
			# 冻结旧 step 的快照：停在“离开前阶段”的最后稳定状态
			steps[current_step_index] = StepTimelineHelpersClass.update_step_snapshot(steps[current_step_index], before)

			# 新建“阶段切换 step”：状态为进入新阶段后的 state（含 enter settlement/enter hooks）
			var phase_step_index := steps.size()
			steps.append(StepTimelineHelpersClass.build_step_dict("phase", command_index, state_in, {
				"from_phase": str(before.phase),
				"to_phase": str(state_in.phase),
			}))

			var update_r := PhaseTransitionClass.append_phase_transition_events(
				engine,
				out_events,
				command_index,
				current_step_index,
				phase_step_index,
				before,
				state_in,
				phase_events,
				cash_events,
				milestone_events,
				Command.create_system("auto_advance"),
				cmd,
				pending_marketing_enter_effect_events,
				pending_anchor,
				pending_cleanup_throw_away_milestone_events,
				seq
			)
			if not update_r.ok:
				return update_r
			if not (update_r.value is Dictionary):
				return Result.failure("StepTimelineBuild: phase transition 返回值类型错误（期望 Dictionary）")
			var update: Dictionary = update_r.value
			seq = int(update.get("seq", seq))
			pending_anchor = int(update.get("pending_marketing_enter_anchor_command_index", pending_anchor))

			current_step_index = phase_step_index
		else:
			# sub_phase 等变化：打包在当前 step，并更新快照到最新稳定状态
			steps[current_step_index] = StepTimelineHelpersClass.update_step_snapshot(steps[current_step_index], state_in)
			var append_phase_r := StepTimelineHelpersClass.append_events(out_events, phase_events, command_index, current_step_index, str(state_in.phase), seq)
			if not append_phase_r.ok:
				return append_phase_r.with_warnings(warnings)
			seq = int(append_phase_r.value)
			var append_cash_r := StepTimelineHelpersClass.append_events(out_events, cash_events, command_index, current_step_index, str(state_in.phase), seq)
			if not append_cash_r.ok:
				return append_cash_r.with_warnings(warnings)
			seq = int(append_cash_r.value)
			var append_milestone_r := StepTimelineHelpersClass.append_events(out_events, milestone_events, command_index, current_step_index, str(state_in.phase), seq)
			if not append_milestone_r.ok:
				return append_milestone_r.with_warnings(warnings)
			seq = int(append_milestone_r.value)

	return Result.success({
		"state": final_state,
		"current_step_index": current_step_index,
		"seq": seq,
		"pending_marketing_enter_anchor_command_index": pending_anchor,
	})

static func _sync_seq(out_events: Array[Dictionary], seq_fallback: int) -> int:
	if out_events == null or out_events.is_empty():
		return int(seq_fallback)
	var last = out_events.back()
	if last is Dictionary and Dictionary(last).has("sequence"):
		return int(Dictionary(last).get("sequence", seq_fallback))
	return int(seq_fallback)
