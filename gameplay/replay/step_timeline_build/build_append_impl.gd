# 语义步进时间线增量构建（尾部 append）
# 目标：在已有稳定 timeline 基础上，仅回放新增命令，避免每次 live refresh 都全量重放历史。
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const ReplayStepRunnerClass = preload("res://core/engine/game_engine/replay_step_runner.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const PhaseTransitionClass = preload("res://gameplay/replay/step_timeline_build/phase_transition.gd")
const AutoAdvanceDrainClass = preload("res://gameplay/replay/step_timeline_build/auto_advance_drain.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func build_append_impl(engine: GameEngine, existing_timeline: Dictionary) -> Result:
	if engine == null:
		return Result.failure("StepTimelineBuild: engine 为空")
	if existing_timeline == null or not (existing_timeline is Dictionary) or existing_timeline.is_empty():
		return Result.failure("StepTimelineBuild: existing_timeline 为空")

	var timeline: Dictionary = existing_timeline.duplicate(false)
	var meta := StepTimelineHelpersClass.read_build_meta(timeline)
	if meta.is_empty():
		return Result.failure("StepTimelineBuild: existing_timeline 缺少 _build_meta，不能增量 append")
	if not meta.has("processed_command_count") or not (meta.get("processed_command_count", null) is int):
		return Result.failure("StepTimelineBuild: existing_timeline._build_meta.processed_command_count 缺失或类型错误")
	if not meta.has("last_event_sequence") or not (meta.get("last_event_sequence", null) is int):
		return Result.failure("StepTimelineBuild: existing_timeline._build_meta.last_event_sequence 缺失或类型错误")
	var steps: Array[Dictionary] = []
	var steps_val = existing_timeline.get("steps", null)
	if not (steps_val is Array):
		return Result.failure("StepTimelineBuild: existing_timeline.steps 缺失或类型错误（期望 Array）")
	var steps_src: Array = steps_val
	for i in range(steps_src.size()):
		var step_val = steps_src[i]
		if not (step_val is Dictionary):
			return Result.failure("StepTimelineBuild: existing_timeline.steps[%d] 类型错误（期望 Dictionary）" % i)
		steps.append(Dictionary(step_val).duplicate(true))
	var events_out: Array[Dictionary] = []
	var events_val = existing_timeline.get("events", null)
	if not (events_val is Array):
		return Result.failure("StepTimelineBuild: existing_timeline.events 缺失或类型错误（期望 Array）")
	var events_src: Array = events_val
	for i in range(events_src.size()):
		var event_val = events_src[i]
		if not (event_val is Dictionary):
			return Result.failure("StepTimelineBuild: existing_timeline.events[%d] 类型错误（期望 Dictionary）" % i)
		events_out.append(Dictionary(event_val).duplicate(true))
	var processed_command_count := int(meta.get("processed_command_count", 0))
	if processed_command_count < 0:
		return Result.failure("StepTimelineBuild: existing_timeline._build_meta.processed_command_count 不能为负数")
	var total_command_count := int(engine.command_history.size())
	if processed_command_count > total_command_count:
		return Result.failure(
			"StepTimelineBuild: existing_timeline 已处理命令数超出当前历史长度: %d > %d"
				% [processed_command_count, total_command_count]
		)

	var old_step_count := int(steps.size())
	var old_event_count := int(events_out.size())
	var last_event_sequence := int(meta.get("last_event_sequence", 0))
	if last_event_sequence < 0:
		return Result.failure("StepTimelineBuild: existing_timeline._build_meta.last_event_sequence 不能为负数")

	if processed_command_count == total_command_count:
		timeline = StepTimelineHelpersClass.attach_build_meta_owned(timeline, total_command_count, last_event_sequence)
		return Result.success({
			"timeline": timeline,
			"head_step_index": int(steps.size()) - 1,
			"append_applied": false,
			"appended_steps": [],
			"appended_events": [],
		})

	var restore_r := _restore_tail_state(timeline, processed_command_count)
	if not restore_r.ok:
		return restore_r
	if not (restore_r.value is GameState):
		return Result.failure("StepTimelineBuild: 增量构建恢复尾部 state 类型错误")
	var replay_state: GameState = restore_r.value

	var warnings: Array[String] = []
	var pending_marketing_enter_effect_events: Array[Dictionary] = []
	var pending_marketing_enter_anchor_command_index := -1
	var pending_cleanup_throw_away_milestone_events: Array[Dictionary] = []
	var seq := int(last_event_sequence)

	for i in range(processed_command_count, total_command_count):
		var cmd: Command = engine.command_history[i]
		var step_result := ReplayStepRunnerClass.apply_replay_command(replay_state, cmd, engine.action_registry, i, "StepTimelineBuild")
		if not step_result.ok:
			return step_result.with_warnings(warnings)
		warnings.append_array(step_result.warnings)
		var step_info: Dictionary = Dictionary(step_result.value)
		var executor = step_info.get("executor", null)
		if executor == null:
			return Result.failure("StepTimelineBuild: 回放命令 #%d executor 为空" % i).with_warnings(warnings)

		var old_state := replay_state
		var state_in: GameState = step_info.get("state", null)
		if state_in == null:
			return Result.failure("StepTimelineBuild: 回放命令 #%d 失败: state 为空" % i).with_warnings(warnings)

		var prev_step_index := steps.size() - 1

		var merge_into_prev_step := false
		if str(cmd.action_id).strip_edges() == ActionIdsClass.SKIP_SUB_PHASE and str(old_state.phase) == DefsClass.PHASE_WORKING:
			var order_names := engine.phase_manager.get_working_sub_phase_order_names()
			if not order_names.is_empty():
				var last_sub_phase: String = str(order_names[order_names.size() - 1])
				if str(old_state.sub_phase) != last_sub_phase and prev_step_index >= 0:
					merge_into_prev_step = true

		var command_step_index := -1
		if merge_into_prev_step:
			command_step_index = prev_step_index
			steps[command_step_index] = _update_step_snapshot(steps[command_step_index], state_in)
		else:
			command_step_index = steps.size()
			steps.append(_build_step_dict("command", i, state_in, {
				"action_id": str(cmd.action_id),
				"actor": int(cmd.actor),
				"action_display_name": str(executor.display_name),
			}))

		var command_events: Array = executor.generate_events(old_state, state_in, cmd)
		var cash_events_cmd: Array = CommandRunnerClass.build_player_cash_changed_events(old_state, state_in, cmd)
		var milestone_events_cmd: Array = CommandRunnerClass.build_milestone_achieved_events(old_state, state_in, cmd)
		var milestone_filter_r := _filter_deferred_cleanup_milestone_events(
			milestone_events_cmd,
			pending_cleanup_throw_away_milestone_events
		)
		if not milestone_filter_r.ok:
			return milestone_filter_r.with_warnings(warnings)
		milestone_events_cmd = milestone_filter_r.value

		var phase_changed_in_command := (str(old_state.phase) != str(state_in.phase))
		if phase_changed_in_command and prev_step_index >= -1:
			var update_r := PhaseTransitionClass.append_phase_transition_events(
				engine,
				events_out,
				i,
				prev_step_index,
				command_step_index,
				old_state,
				state_in,
				command_events,
				cash_events_cmd,
				milestone_events_cmd,
				cmd,
				cmd,
				pending_marketing_enter_effect_events,
				pending_marketing_enter_anchor_command_index,
				pending_cleanup_throw_away_milestone_events,
				seq
			)
			if not update_r.ok:
				return update_r.with_warnings(warnings)
			if not (update_r.value is Dictionary):
				return Result.failure("StepTimelineBuild: phase transition 返回值类型错误（期望 Dictionary）").with_warnings(warnings)
			var update: Dictionary = update_r.value
			seq = int(update.get("seq", seq))
			pending_marketing_enter_anchor_command_index = int(
				update.get(
					"pending_marketing_enter_anchor_command_index",
					pending_marketing_enter_anchor_command_index
				)
			)
		else:
			var append_command_r := _append_events(events_out, command_events, i, command_step_index, str(state_in.phase), seq)
			if not append_command_r.ok:
				return append_command_r.with_warnings(warnings)
			seq = int(append_command_r.value)
			if not cash_events_cmd.is_empty():
				var append_cash_r := _append_events(events_out, cash_events_cmd, i, command_step_index, str(state_in.phase), seq)
				if not append_cash_r.ok:
					return append_cash_r.with_warnings(warnings)
				seq = int(append_cash_r.value)
			if not milestone_events_cmd.is_empty():
				var append_milestone_r := _append_events(events_out, milestone_events_cmd, i, command_step_index, str(state_in.phase), seq)
				if not append_milestone_r.ok:
					return append_milestone_r.with_warnings(warnings)
				seq = int(append_milestone_r.value)

			var cleanup_pending_read := _read_has_pending_cleanup_actions(state_in)
			if not cleanup_pending_read.ok:
				return Result.failure("StepTimelineBuild: %s" % cleanup_pending_read.error).with_warnings(warnings)
			if (not bool(cleanup_pending_read.value)) \
				and not pending_cleanup_throw_away_milestone_events.is_empty():
				var append_cleanup_r := _append_events(
					events_out,
					pending_cleanup_throw_away_milestone_events,
					i,
					command_step_index,
					str(state_in.phase),
					seq
				)
				if not append_cleanup_r.ok:
					return append_cleanup_r.with_warnings(warnings)
				seq = int(append_cleanup_r.value)
				pending_cleanup_throw_away_milestone_events.clear()

		var current_step_index := command_step_index
		var drain := AutoAdvanceDrainClass.drain(
			engine,
			cmd,
			i,
			state_in,
			steps,
			events_out,
			current_step_index,
			seq,
			pending_marketing_enter_effect_events,
			pending_marketing_enter_anchor_command_index,
			pending_cleanup_throw_away_milestone_events,
			warnings
		)
		if not drain.ok:
			return drain
		if not (drain.value is Dictionary):
			return Result.failure("StepTimelineBuild: auto_advance drain 返回值类型错误（期望 Dictionary）").with_warnings(warnings)
		var drain_dict: Dictionary = drain.value
		var state_out_val = drain_dict.get("state", null)
		if not (state_out_val is GameState):
			return Result.failure("StepTimelineBuild: auto_advance drain 返回 state 类型错误（期望 GameState）").with_warnings(warnings)
		state_in = state_out_val
		current_step_index = int(drain_dict.get("current_step_index", current_step_index))
		seq = int(drain_dict.get("seq", seq))
		pending_marketing_enter_anchor_command_index = int(
			drain_dict.get(
				"pending_marketing_enter_anchor_command_index",
				pending_marketing_enter_anchor_command_index
			)
		)

		seq += 1
		events_out.append({
			"type": EventBus.EventType.COMMAND_EXECUTED,
			"data": {
				"command_index": i,
				"action_id": str(cmd.action_id),
				"actor": int(cmd.actor),
				"step_index": current_step_index,
				"command_step_index": command_step_index,
			},
			"sequence": seq,
			"timestamp": seq,
			"command_index": i,
			"step_index": current_step_index,
			"phase_segment": str(state_in.phase),
		})

		replay_state = state_in

	if not pending_marketing_enter_effect_events.is_empty():
		var flush_step_index := steps.size() - 1
		if flush_step_index >= 0:
			var flush_ci := pending_marketing_enter_anchor_command_index
			if flush_ci < 0:
				flush_ci = total_command_count - 1
			var append_marketing_flush_r := _append_events(
				events_out,
				pending_marketing_enter_effect_events,
				flush_ci,
				flush_step_index,
				DefsClass.PHASE_MARKETING,
				seq
			)
			if not append_marketing_flush_r.ok:
				return append_marketing_flush_r.with_warnings(warnings)
			seq = int(append_marketing_flush_r.value)
		pending_marketing_enter_effect_events = []
		pending_marketing_enter_anchor_command_index = -1

	if not pending_cleanup_throw_away_milestone_events.is_empty():
		var flush_step_index2 := steps.size() - 1
		if flush_step_index2 >= 0:
			var append_cleanup_flush_r := _append_events(
				events_out,
				pending_cleanup_throw_away_milestone_events,
				total_command_count - 1,
				flush_step_index2,
				DefsClass.PHASE_CLEANUP,
				seq
			)
			if not append_cleanup_flush_r.ok:
				return append_cleanup_flush_r.with_warnings(warnings)
			seq = int(append_cleanup_flush_r.value)
		pending_cleanup_throw_away_milestone_events = []

	timeline["steps"] = steps
	timeline["events"] = events_out
	timeline = StepTimelineHelpersClass.attach_build_meta_owned(timeline, total_command_count, seq)

	return Result.success({
		"timeline": timeline,
		"head_step_index": int(steps.size()) - 1,
		"append_applied": true,
		"appended_steps": _slice_dict_items(steps, old_step_count),
		"appended_events": _slice_dict_items(events_out, old_event_count),
	}).with_warnings(warnings)

static func _restore_tail_state(timeline: Dictionary, processed_command_count: int) -> Result:
	var state_dict: Dictionary = {}
	var steps_val = timeline.get("steps", null)
	if processed_command_count > 0:
		if not (steps_val is Array):
			return Result.failure("StepTimelineBuild: existing_timeline.steps 类型错误（期望 Array）")
		var steps: Array = steps_val
		if steps.is_empty():
			return Result.failure("StepTimelineBuild: 已处理命令>0 但 existing_timeline.steps 为空")
		var last_step_val = steps[steps.size() - 1]
		if not (last_step_val is Dictionary):
			return Result.failure("StepTimelineBuild: existing_timeline 最后一个 step 类型错误（期望 Dictionary）")
		state_dict = Dictionary(Dictionary(last_step_val).get("state_dict", {})).duplicate(true)
	else:
		state_dict = Dictionary(timeline.get("initial_state_dict", {})).duplicate(true)

	if state_dict.is_empty():
		return Result.failure("StepTimelineBuild: 无法从 existing_timeline 恢复尾部 state")
	var restore_result := GameState.from_dict(state_dict)
	if not restore_result.ok:
		return Result.failure("StepTimelineBuild: 恢复尾部 state 失败: %s" % restore_result.error)
	if not (restore_result.value is GameState):
		return Result.failure("StepTimelineBuild: 恢复尾部 state 返回类型错误（期望 GameState）")
	return restore_result

static func _build_step_dict(kind: String, anchor_command_index: int, state: GameState, extra: Dictionary = {}) -> Dictionary:
	return StepTimelineHelpersClass.build_step_dict(kind, anchor_command_index, state, extra)

static func _update_step_snapshot(step: Dictionary, state: GameState) -> Dictionary:
	return StepTimelineHelpersClass.update_step_snapshot(step, state)

static func _append_events(
	out_events: Array,
	events: Array[Dictionary],
	command_index: int,
	step_index: int,
	phase_segment: String,
	seq_in: int
) -> Result:
	return StepTimelineHelpersClass.append_events(out_events, events, command_index, step_index, phase_segment, seq_in)

static func _filter_deferred_cleanup_milestone_events(events: Array[Dictionary], pending: Array[Dictionary]) -> Result:
	return StepTimelineHelpersClass.filter_deferred_cleanup_milestone_events(events, pending)

static func _read_has_pending_cleanup_actions(state: GameState) -> Result:
	return StepTimelineHelpersClass.read_has_pending_cleanup_actions(state)

static func _sync_seq(out_events: Array, seq_fallback: int) -> int:
	if out_events == null or out_events.is_empty():
		return int(seq_fallback)
	var last = out_events.back()
	if last is Dictionary and Dictionary(last).has("sequence"):
		return int(Dictionary(last).get("sequence", seq_fallback))
	return int(seq_fallback)

static func _slice_dict_items(items: Array, start_idx: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var begin := maxi(0, int(start_idx))
	for idx in range(begin, items.size()):
		var item_val = items[idx]
		if item_val is Dictionary:
			out.append(Dictionary(item_val).duplicate(true))
	return out
