# 语义步进时间线构建（step_index）
# 该文件位于 gameplay 层：属于 UI/回放/日志派生视图构建，不是 core 执行内核。
# 目标：
# - 在“命令（Command）”之外，引入可停留的阶段切分点（phase step），避免 auto-advance 把多个大阶段合并成一个位置。
# - Working 内的小阶段（sub_phase）尽可能打包：sub_phase 变化不额外生成 step，仅更新当前 step 的状态快照与事件归属。
#
# 约定（与 docs/design/archive/replay_log_timeline_refactor_plan.md#M4.2 对齐）：
# - step=-1 表示初始状态（checkpoint[0]），不计入 steps 数组。
# - “阶段 step”的状态快照以“进入该阶段后的状态（含 enter settlement/enter hooks）”为准；
#   但若该阶段内部发生 sub_phase 自动推进（不跨 phase），会被打包到同一个 step，并更新该 step 的快照。
# - `*_REPORT` 等“离开阶段时发射”的事件归属到离开前阶段（phase_segment=old_phase）。
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const GameStartedEventBuildClass = preload("res://core/engine/game_engine/game_started_event_build.gd")
const ReplayStepRunnerClass = preload("res://core/engine/game_engine/replay_step_runner.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const PhaseTransitionClass = preload("res://gameplay/replay/step_timeline_build/phase_transition.gd")
const AutoAdvanceDrainClass = preload("res://gameplay/replay/step_timeline_build/auto_advance_drain.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func build_full_impl(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("StepTimelineBuild: engine 为空")

	var init_check := engine.ensure_initialized()
	if not init_check.ok:
		return init_check
	if engine.checkpoints.is_empty():
		return Result.failure("StepTimelineBuild: 缺少初始 checkpoint")

	# 从初始 checkpoint 恢复（尚未执行任何命令）
	var initial_checkpoint := engine.checkpoints[0]
	if not (initial_checkpoint is Dictionary):
		return Result.failure("StepTimelineBuild: checkpoints[0] 类型错误（期望 Dictionary）")
	var state_dict_val = Dictionary(initial_checkpoint).get("state_dict", null)
	if not (state_dict_val is Dictionary):
		return Result.failure("StepTimelineBuild: checkpoints[0].state_dict 缺失或类型错误（期望 Dictionary）")

	var restore_result := GameState.from_dict(state_dict_val)
	if not restore_result.ok:
		return Result.failure("StepTimelineBuild: 恢复初始 state 失败: %s" % restore_result.error)
	var replay_state: GameState = restore_result.value
	if replay_state == null:
		return Result.failure("StepTimelineBuild: 恢复初始 state 失败: state 为空")

	var steps: Array[Dictionary] = []
	var events_out: Array[Dictionary] = []
	var warnings: Array[String] = []
	var pending_marketing_enter_effect_events: Array[Dictionary] = []
	var pending_marketing_enter_anchor_command_index := -1
	var pending_cleanup_throw_away_milestone_events: Array[Dictionary] = []
	var seq := 0

	# 初始化事件（step=-1）
	var started_data_read := GameStartedEventBuildClass.build_from_state(replay_state)
	if not started_data_read.ok:
		return Result.failure("StepTimelineBuild: GAME_STARTED 构建失败: %s" % started_data_read.error).with_warnings(warnings)
	var started_data: Dictionary = started_data_read.value
	started_data["command_index"] = -1
	started_data["step_index"] = -1

	seq += 1
	events_out.append({
		"type": EventBus.EventType.GAME_STARTED,
		"data": started_data,
		"sequence": seq,
		"timestamp": seq,
		"command_index": -1,
		"step_index": -1,
		"phase_segment": str(replay_state.phase),
	})

	if engine.command_history.is_empty():
		return Result.success(StepTimelineHelpersClass.attach_build_meta({
			"initial_state_dict": state_dict_val.duplicate(true),
			"steps": steps,
			"events": events_out,
		}, 0, seq)).with_warnings(warnings)

	# 按命令重放 + 分段 auto-advance（在 phase 变化处插入 step）
	for i in range(engine.command_history.size()):
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

		# 在创建新 step 前记录“命令执行前”的 step_index：
		# - 用于把离开阶段时发射的 *_REPORT 归属到旧阶段（避免被压到新阶段/同一个 step 里）。
		var prev_step_index := steps.size() - 1

		# Working：跳过“被跳过子阶段”的冗余步进（例如 skip_sub_phase 非最后子阶段），避免出现“单步推进无变化”。
		# 这些命令的效果会被合并到上一条可见 step（anchor_command_index 保持不变）。
		var merge_into_prev_step := false
		if str(cmd.action_id).strip_edges() == ActionIdsClass.SKIP_SUB_PHASE and str(old_state.phase) == DefsClass.PHASE_WORKING:
			var order_names := engine.phase_manager.get_working_sub_phase_order_names()
			if not order_names.is_empty():
				var last_sub_phase: String = str(order_names[order_names.size() - 1])
				if str(old_state.sub_phase) != last_sub_phase and prev_step_index >= 0:
					merge_into_prev_step = true

		# 新建“玩家行动 step”（默认存在）；若 merge，则复用上一 step 并更新其快照。
		var command_step_index := -1
		if merge_into_prev_step:
			command_step_index = prev_step_index
			steps[command_step_index] = _update_step_snapshot(steps[command_step_index], state_in)
		else:
			command_step_index = steps.size()
			# 为 UI 摘要提供最少的“玩家行动”信息：当该 step 没有可见事件时，仍可显示玩家做了什么（例如重组阶段）。
			steps.append(_build_step_dict("command", i, state_in, {
				"action_id": str(cmd.action_id),
				"actor": int(cmd.actor),
				"action_display_name": str(executor.display_name),
			}))

		# 命令本体事件（归属到 command step）
		var command_events: Array = executor.generate_events(old_state, state_in, cmd)
		var cash_events_cmd: Array = CommandRunnerClass.build_player_cash_changed_events(old_state, state_in, cmd)
		var milestone_events_cmd: Array = CommandRunnerClass.build_milestone_achieved_events(old_state, state_in, cmd)
		var milestone_filter_r := _filter_deferred_cleanup_milestone_events(milestone_events_cmd, pending_cleanup_throw_away_milestone_events)
		if not milestone_filter_r.ok:
			return milestone_filter_r.with_warnings(warnings)
		milestone_events_cmd = milestone_filter_r.value

		# 若命令本身发生了 phase 切换（如 advance_phase），则：
		# - PHASE_CHANGED 之前的事件（含 *_REPORT）归属到“命令前”的 step（旧阶段）
		# - PHASE_CHANGED 及之后的事件归属到“玩家行动 step”（新阶段）
		# 这能避免 Payday/Marketing/Cleanup 等阶段被压到同一个 step。
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
			pending_marketing_enter_anchor_command_index = int(update.get("pending_marketing_enter_anchor_command_index", pending_marketing_enter_anchor_command_index))
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
			if (not bool(cleanup_pending_read.value)) and not pending_cleanup_throw_away_milestone_events.is_empty():
				var append_cleanup_r := _append_events(events_out, pending_cleanup_throw_away_milestone_events, i, command_step_index, str(state_in.phase), seq)
				if not append_cleanup_r.ok:
					return append_cleanup_r.with_warnings(warnings)
				seq = int(append_cleanup_r.value)
				pending_cleanup_throw_away_milestone_events.clear()

		# auto-advance：逐步执行。sub_phase 变化打包在当前 step；phase 变化插入新 step。
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
		var drain_val = drain.value
		if not (drain_val is Dictionary):
			return Result.failure("StepTimelineBuild: auto_advance drain 返回值类型错误（期望 Dictionary）").with_warnings(warnings)
		var drain_dict: Dictionary = drain_val
		var state_out_val = drain_dict.get("state", null)
		if not (state_out_val is GameState):
			return Result.failure("StepTimelineBuild: auto_advance drain 返回 state 类型错误（期望 GameState）").with_warnings(warnings)
		state_in = state_out_val
		current_step_index = int(drain_dict.get("current_step_index", current_step_index))
		seq = int(drain_dict.get("seq", seq))
		pending_marketing_enter_anchor_command_index = int(drain_dict.get("pending_marketing_enter_anchor_command_index", pending_marketing_enter_anchor_command_index))

		# 命令已执行（便于回放验证与旧逻辑兼容；默认归属到玩家行动 step）
		seq += 1
		events_out.append({
			"type": EventBus.EventType.COMMAND_EXECUTED,
			"data": {
				"command_index": i,
				"action_id": str(cmd.action_id),
				"actor": int(cmd.actor),
				# 注意：为保证 events 的 step_index 单调不减，这里将 COMMAND_EXECUTED 归属到“该命令链路结束后的当前 step”。
				# （COMMAND_EXECUTED 默认不展示；仅少数定价类动作使用带 price_modifier 的 COMMAND_EXECUTED）
				"step_index": current_step_index,
				"command_step_index": command_step_index,
			},
			"sequence": seq,
			"timestamp": seq,
			"command_index": i,
			"step_index": current_step_index,
			"phase_segment": str(state_in.phase),
		})

		# 下一条命令的起点 state（应为“执行该命令并完成所有 auto-advance”的稳定状态）
		replay_state = state_in

	# 兜底：若时间线构建结束仍处于 Marketing，且存在未刷出的 enter effects，则追加到最后一个 step（避免丢日志）。
	if not pending_marketing_enter_effect_events.is_empty():
		var flush_step_index := steps.size() - 1
		if flush_step_index >= 0:
			var flush_ci := pending_marketing_enter_anchor_command_index
			if flush_ci < 0:
				flush_ci = engine.command_history.size() - 1
			var append_marketing_flush_r := _append_events(events_out, pending_marketing_enter_effect_events, flush_ci, flush_step_index, DefsClass.PHASE_MARKETING, seq)
			if not append_marketing_flush_r.ok:
				return append_marketing_flush_r.with_warnings(warnings)
			seq = int(append_marketing_flush_r.value)
		pending_marketing_enter_effect_events = []
		pending_marketing_enter_anchor_command_index = -1

	# 兜底：避免丢失被延后的 cleanup 里程碑（理论上应在最后一次 pending cleanup 动作或 Cleanup:enter 时刷出）。
	if not pending_cleanup_throw_away_milestone_events.is_empty():
		var flush_step_index2 := steps.size() - 1
		if flush_step_index2 >= 0:
			var flush_ci2 := engine.command_history.size() - 1
			var append_cleanup_flush_r := _append_events(events_out, pending_cleanup_throw_away_milestone_events, flush_ci2, flush_step_index2, DefsClass.PHASE_CLEANUP, seq)
			if not append_cleanup_flush_r.ok:
				return append_cleanup_flush_r.with_warnings(warnings)
			seq = int(append_cleanup_flush_r.value)
		pending_cleanup_throw_away_milestone_events = []

	return Result.success(StepTimelineHelpersClass.attach_build_meta({
		"initial_state_dict": state_dict_val.duplicate(true),
		"steps": steps,
		"events": events_out,
	}, int(engine.command_history.size()), seq)).with_warnings(warnings)

static func _build_step_dict(kind: String, anchor_command_index: int, state: GameState, extra: Dictionary = {}) -> Dictionary:
	return StepTimelineHelpersClass.build_step_dict(kind, anchor_command_index, state, extra)

static func _update_step_snapshot(step: Dictionary, state: GameState) -> Dictionary:
	return StepTimelineHelpersClass.update_step_snapshot(step, state)

static func _append_events(
	out_events: Array[Dictionary],
	events: Array[Dictionary],
	command_index: int,
	step_index: int,
	phase_segment: String,
	seq_in: int
) -> Result:
	return StepTimelineHelpersClass.append_events(out_events, events, command_index, step_index, phase_segment, seq_in)

static func _should_attribute_settlement_effects_to_old_phase(engine: GameEngine, old_phase: String, new_phase: String) -> bool:
	return StepTimelineHelpersClass.should_attribute_settlement_effects_to_old_phase(engine, old_phase, new_phase)

static func _override_events_phase_fields(events: Array[Dictionary], state: GameState) -> Result:
	return StepTimelineHelpersClass.override_events_phase_fields(events, state)

static func _filter_deferred_cleanup_milestone_events(events: Array[Dictionary], pending: Array[Dictionary]) -> Result:
	return StepTimelineHelpersClass.filter_deferred_cleanup_milestone_events(events, pending)

static func _read_has_pending_cleanup_actions(state: GameState) -> Result:
	return StepTimelineHelpersClass.read_has_pending_cleanup_actions(state)
