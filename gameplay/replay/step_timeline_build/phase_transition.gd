# StepTimelineBuild：阶段切换事件归属（phase transition）
# - 拆分 PHASE_CHANGED 前后事件归属
# - 结算产生的 cash/milestone 事件按触发点归属（兼容 exit+enter 叠加）
# - Marketing enter effects 延后到离开 Marketing 后输出
# - CleanupDiscard: first_throw_away 里程碑按“清理库存动作完成后”显示
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")

static func append_phase_transition_events(
	engine: GameEngine,
	out_events: Array[Dictionary],
	command_index: int,
	old_step_index: int,
	new_step_index: int,
	old_state: GameState,
	new_state: GameState,
	transition_events: Array[Dictionary],
	cash_events_full: Array[Dictionary],
	milestone_events_full: Array[Dictionary],
	cash_cmd: Command,
	milestone_cmd: Command,
	pending_marketing_enter_effect_events: Array[Dictionary],
	pending_marketing_enter_anchor_command_index: int,
	pending_cleanup_throw_away_milestone_events: Array[Dictionary],
	seq_in: int
) -> Result:
	var seq := int(seq_in)
	var pending_anchor := int(pending_marketing_enter_anchor_command_index)

	var before_phase_events: Array[Dictionary] = []
	var after_phase_events: Array[Dictionary] = []
	var seen_phase_changed := false
	for ev_val in transition_events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t: String = str(ev.get("type", "")).strip_edges()
		if t == EventBus.EventType.PHASE_CHANGED:
			seen_phase_changed = true
		if seen_phase_changed:
			after_phase_events.append(ev)
		else:
			before_phase_events.append(ev)

	var old_phase_name := str(old_state.phase)
	var new_phase_name := str(new_state.phase)

	var phase_report_events: Array[Dictionary] = []
	if not before_phase_events.is_empty():
		var kept_before_phase_events: Array[Dictionary] = []
		for before_ev_val in before_phase_events:
			if not (before_ev_val is Dictionary):
				continue
			var before_ev: Dictionary = before_ev_val
			var before_type := str(before_ev.get("type", "")).strip_edges()
			if before_type.ends_with("_report"):
				phase_report_events.append(before_ev)
			else:
				kept_before_phase_events.append(before_ev)
		before_phase_events = kept_before_phase_events

	if not before_phase_events.is_empty():
		StepTimelineHelpersClass.append_events(out_events, before_phase_events, command_index, old_step_index, old_phase_name, seq)
		seq = _sync_seq(out_events, seq)

	# Marketing: 先输出汇总事件（如 DEMAND_GENERATED），再输出进入 Marketing 时产生的 cash/milestone。
	if old_phase_name == PhaseDefsClass.PHASE_MARKETING and pending_marketing_enter_effect_events != null and not pending_marketing_enter_effect_events.is_empty():
		StepTimelineHelpersClass.append_events(out_events, pending_marketing_enter_effect_events, command_index, old_step_index, PhaseDefsClass.PHASE_MARKETING, seq)
		seq = _sync_seq(out_events, seq)
		pending_marketing_enter_effect_events.clear()
		pending_anchor = -1

	# 结算/里程碑/现金变化：按结算触发点归属。
	# - 兼容 Payday->Marketing 的 exit+enter 叠加：拆分 exit/enter 的差异，避免 Marketing:enter 被误归到 Payday。
	var trace: Dictionary = engine.phase_manager.consume_timeline_last_advance_trace() if (engine != null and engine.phase_manager != null) else {}

	var old_exit_scheduled := false
	var new_enter_scheduled := false
	if engine != null and engine.phase_manager != null:
		var old_enum := PhaseDefsClass.get_phase_enum(old_phase_name.strip_edges())
		if old_enum != -1 and engine.phase_manager.is_settlement_scheduled(old_enum, SettlementRegistryClass.Point.EXIT):
			old_exit_scheduled = true
		var new_enum := PhaseDefsClass.get_phase_enum(new_phase_name.strip_edges())
		if new_enum != -1 and engine.phase_manager.is_settlement_scheduled(new_enum, SettlementRegistryClass.Point.ENTER):
			new_enter_scheduled = true

	var after_exit_settlements: GameState = null
	if old_exit_scheduled and new_enter_scheduled:
		var v = trace.get("after_exit_settlements", null)
		if v is GameState:
			after_exit_settlements = v

	var cash_events_old: Array[Dictionary] = []
	var milestone_events_old: Array[Dictionary] = []
	var cash_events_new: Array[Dictionary] = []
	var milestone_events_new: Array[Dictionary] = []

	if after_exit_settlements != null:
		cash_events_old = CommandRunnerClass.build_player_cash_changed_events(old_state, after_exit_settlements, cash_cmd)
		milestone_events_old = CommandRunnerClass.build_milestone_achieved_events(old_state, after_exit_settlements, milestone_cmd)
		cash_events_new = CommandRunnerClass.build_player_cash_changed_events(after_exit_settlements, new_state, cash_cmd)
		milestone_events_new = CommandRunnerClass.build_milestone_achieved_events(after_exit_settlements, new_state, milestone_cmd)
	else:
		var to_old_segment := StepTimelineHelpersClass.should_attribute_settlement_effects_to_old_phase(engine, old_phase_name, new_phase_name)
		if to_old_segment:
			cash_events_old = cash_events_full
			milestone_events_old = milestone_events_full
		else:
			cash_events_new = cash_events_full
			milestone_events_new = milestone_events_full

	milestone_events_old = StepTimelineHelpersClass.filter_out_first_throw_away_milestone_events(milestone_events_old, pending_cleanup_throw_away_milestone_events)
	milestone_events_new = StepTimelineHelpersClass.filter_out_first_throw_away_milestone_events(milestone_events_new, pending_cleanup_throw_away_milestone_events)

	if not cash_events_old.is_empty():
		StepTimelineHelpersClass.append_events(out_events, StepTimelineHelpersClass.override_events_phase_fields(cash_events_old, old_state), command_index, old_step_index, old_phase_name, seq)
		seq = _sync_seq(out_events, seq)
	if not milestone_events_old.is_empty():
		StepTimelineHelpersClass.append_events(out_events, StepTimelineHelpersClass.override_events_phase_fields(milestone_events_old, old_state), command_index, old_step_index, old_phase_name, seq)
		seq = _sync_seq(out_events, seq)

	if not phase_report_events.is_empty():
		# 报告事件（例如 PAYDAY_REPORT）语义仍归属旧阶段，但应挂到触发阶段推进的当前命令 step。
		# 这样实时日志增量 append 能在玩家点击“确认结束”后立刻显示报告，
		# 避免把新报告 backfill 到已渲染过的旧 step。
		StepTimelineHelpersClass.append_events(out_events, phase_report_events, command_index, new_step_index, old_phase_name, seq)
		seq = _sync_seq(out_events, seq)

	if not after_phase_events.is_empty():
		StepTimelineHelpersClass.append_events(out_events, after_phase_events, command_index, new_step_index, new_phase_name, seq)
		seq = _sync_seq(out_events, seq)

	if not cash_events_new.is_empty() or not milestone_events_new.is_empty():
		if new_phase_name == PhaseDefsClass.PHASE_MARKETING:
			pending_anchor = command_index
			if pending_marketing_enter_effect_events != null:
				if not cash_events_new.is_empty():
					pending_marketing_enter_effect_events.append_array(StepTimelineHelpersClass.override_events_phase_fields(cash_events_new, new_state))
				if not milestone_events_new.is_empty():
					pending_marketing_enter_effect_events.append_array(StepTimelineHelpersClass.override_events_phase_fields(milestone_events_new, new_state))
		else:
			if not cash_events_new.is_empty():
				StepTimelineHelpersClass.append_events(out_events, StepTimelineHelpersClass.override_events_phase_fields(cash_events_new, new_state), command_index, new_step_index, new_phase_name, seq)
				seq = _sync_seq(out_events, seq)
			if not milestone_events_new.is_empty():
				StepTimelineHelpersClass.append_events(out_events, StepTimelineHelpersClass.override_events_phase_fields(milestone_events_new, new_state), command_index, new_step_index, new_phase_name, seq)
				seq = _sync_seq(out_events, seq)

	# CleanupDiscard: 若进入 Cleanup 时无需 pending（无 choose_fridge_keep），则在该 step 末尾刷出 first_throw_away。
	var cleanup_pending_read := StepTimelineHelpersClass.read_has_pending_cleanup_actions(new_state)
	if not cleanup_pending_read.ok:
		return Result.failure("StepTimelineBuild: %s" % cleanup_pending_read.error)
	if new_phase_name == PhaseDefsClass.PHASE_CLEANUP and (not bool(cleanup_pending_read.value)) and pending_cleanup_throw_away_milestone_events != null and not pending_cleanup_throw_away_milestone_events.is_empty():
		StepTimelineHelpersClass.append_events(out_events, pending_cleanup_throw_away_milestone_events, command_index, new_step_index, PhaseDefsClass.PHASE_CLEANUP, seq)
		seq = _sync_seq(out_events, seq)
		pending_cleanup_throw_away_milestone_events.clear()

	return Result.success({
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
