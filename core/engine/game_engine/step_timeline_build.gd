# GameEngine：语义步进时间线构建（step_index）
# 目标：
# - 在“命令（Command）”之外，引入可停留的阶段切分点（phase step），避免 auto-advance 把多个大阶段合并成一个位置。
# - Working 内的小阶段（sub_phase）尽可能打包：sub_phase 变化不额外生成 step，仅更新当前 step 的状态快照与事件归属。
#
# 约定（与 docs/replay_log_timeline_refactor_plan.md#M4.2 对齐）：
# - step=-1 表示初始状态（checkpoint[0]），不计入 steps 数组。
# - “阶段 step”的状态快照以“进入该阶段后的状态（含 enter settlement/enter hooks）”为准；
#   但若该阶段内部发生 sub_phase 自动推进（不跨 phase），会被打包到同一个 step，并更新该 step 的快照。
# - `*_REPORT` 等“离开阶段时发射”的事件归属到离开前阶段（phase_segment=old_phase）。
extends RefCounted

const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

static func build_full(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("StepTimelineBuild: engine 为空")

	var init_check := engine._ensure_initialized()
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
	var seq := 0

	# 初始化事件（step=-1）
	seq += 1
	events_out.append({
		"type": EventBus.EventType.GAME_STARTED,
		"data": {
			"player_count": replay_state.players.size() if (replay_state.players is Array) else -1,
			"seed": int(replay_state.seed),
			"state_hash": replay_state.compute_hash(),
			"command_index": -1,
			"step_index": -1,
		},
		"sequence": seq,
		"timestamp": seq,
		"command_index": -1,
		"step_index": -1,
		"phase_segment": str(replay_state.phase),
	})

	if engine.command_history.is_empty():
		return Result.success({
			"initial_state_dict": state_dict_val.duplicate(true),
			"steps": steps,
			"events": events_out,
		}).with_warnings(warnings)

	# 按命令重放 + 分段 auto-advance（在 phase 变化处插入 step）
	for i in range(engine.command_history.size()):
		var cmd: Command = engine.command_history[i]
		if cmd == null:
			return Result.failure("StepTimelineBuild: command_history[%d] 为空" % i).with_warnings(warnings)

		var executor := engine.action_registry.get_executor(cmd.action_id)
		if executor == null:
			return Result.failure("StepTimelineBuild: 回放时找不到执行器: %s" % str(cmd.action_id)).with_warnings(warnings)

		var force_execute := _should_force_execute_in_replay(cmd)
		if force_execute and executor.requires_actor:
			# 与 ReplayClass/EventHistoryRebuild 保持一致：强制命令仍要求 actor 为当前玩家，避免破坏时间线一致性。
			var current_player_id := replay_state.get_current_player_id()
			if cmd.actor != current_player_id:
				return Result.failure("StepTimelineBuild: 回放强制命令 #%d actor 非当前玩家: actor=%d current=%d" % [i, cmd.actor, current_player_id]).with_warnings(warnings)

		var step_result := executor.compute_new_state_force(replay_state, cmd) if force_execute else executor.compute_new_state(replay_state, cmd)
		if not step_result.ok:
			return Result.failure("StepTimelineBuild: 回放命令 #%d 失败: %s" % [i, step_result.error]).with_warnings(warnings)
		warnings.append_array(step_result.warnings)

		var old_state := replay_state
		var state_in: GameState = step_result.value
		if state_in == null:
			return Result.failure("StepTimelineBuild: 回放命令 #%d 失败: state 为空" % i).with_warnings(warnings)

		# 在创建新 step 前记录“命令执行前”的 step_index：
		# - 用于把离开阶段时发射的 *_REPORT 归属到旧阶段（避免被压到新阶段/同一个 step 里）。
		var prev_step_index := steps.size() - 1

		# Working：跳过“被跳过子阶段”的冗余步进（例如 skip_sub_phase 非最后子阶段），避免出现“单步推进无变化”。
		# 这些命令的效果会被合并到上一条可见 step（anchor_command_index 保持不变）。
		var merge_into_prev_step := false
		if str(cmd.action_id).strip_edges() == "skip_sub_phase" and str(old_state.phase) == "Working":
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
		var command_events := executor.generate_events(old_state, state_in, cmd)
		var cash_events_cmd := CommandRunnerClass._build_player_cash_changed_events(old_state, state_in, cmd)
		var milestone_events_cmd := CommandRunnerClass._build_milestone_achieved_events(old_state, state_in, cmd)
		# 若命令本身发生了 phase 切换（如 advance_phase），则：
		# - PHASE_CHANGED 之前的事件（含 *_REPORT）归属到“命令前”的 step（旧阶段）
		# - PHASE_CHANGED 及之后的事件归属到“玩家行动 step”（新阶段）
		# 这能避免 Payday/Marketing/Cleanup 等阶段被压到同一个 step。
		var phase_changed_in_command := (str(old_state.phase) != str(state_in.phase))
		if phase_changed_in_command and prev_step_index >= -1:
			var before_phase_events: Array[Dictionary] = []
			var after_phase_events: Array[Dictionary] = []
			var seen_phase_changed := false
			for ev_val in command_events:
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

			# 结算/里程碑/现金变化：按结算触发点归属（避免 Payday exit settlement 被推到 Marketing 段落）。
			var to_old_segment := _should_attribute_settlement_effects_to_old_phase(engine, str(old_state.phase), str(state_in.phase))

			if not before_phase_events.is_empty():
				_append_events(events_out, before_phase_events, i, prev_step_index, str(old_state.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
			if to_old_segment:
				if not cash_events_cmd.is_empty():
					_append_events(events_out, _override_events_phase_fields(cash_events_cmd, old_state), i, prev_step_index, str(old_state.phase), seq)
					seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
				if not milestone_events_cmd.is_empty():
					_append_events(events_out, _override_events_phase_fields(milestone_events_cmd, old_state), i, prev_step_index, str(old_state.phase), seq)
					seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

			if not after_phase_events.is_empty():
				_append_events(events_out, after_phase_events, i, command_step_index, str(state_in.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
			if not to_old_segment:
				if not cash_events_cmd.is_empty():
					_append_events(events_out, _override_events_phase_fields(cash_events_cmd, state_in), i, command_step_index, str(state_in.phase), seq)
					seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
				if not milestone_events_cmd.is_empty():
					_append_events(events_out, _override_events_phase_fields(milestone_events_cmd, state_in), i, command_step_index, str(state_in.phase), seq)
					seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
		else:
			_append_events(events_out, command_events, i, command_step_index, str(state_in.phase), seq)
			seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
			if not cash_events_cmd.is_empty():
				_append_events(events_out, cash_events_cmd, i, command_step_index, str(state_in.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
			if not milestone_events_cmd.is_empty():
				_append_events(events_out, milestone_events_cmd, i, command_step_index, str(state_in.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

		# auto-advance：逐步执行。sub_phase 变化打包在当前 step；phase 变化插入新 step。
		var current_step_index := command_step_index
		var safety := 0
		while safety < 32:
			safety += 1
			var before := state_in.duplicate_state()
			var adv: Result = AutoAdvanceClass.try_advance_one(state_in, engine.phase_manager, engine.action_registry)
			if not adv.ok:
				return Result.failure("StepTimelineBuild: auto_advance 失败(命令 #%d): %s" % [i, adv.error]).with_warnings(warnings).with_warnings(adv.warnings)
			warnings.append_array(adv.warnings)
			if not bool(adv.value):
				break

			var phase_changed := (str(before.phase) != str(state_in.phase))

			# 构建阶段/子阶段变化事件（与 CommandRunner._drain_auto_advances 对齐）
			var phase_events := CommandRunnerClass._build_phase_change_events(before, state_in)
			var cash_events := CommandRunnerClass._build_player_cash_changed_events(before, state_in, Command.create_system("auto_advance"))
			var milestone_events := CommandRunnerClass._build_milestone_achieved_events(before, state_in, cmd)

			if phase_changed:
				# 冻结旧 step 的快照：停在“离开前阶段”的最后稳定状态
				steps[current_step_index] = _update_step_snapshot(steps[current_step_index], before)

				# 新建“阶段切换 step”：状态为进入新阶段后的 state（含 enter settlement/enter hooks）
				var phase_step_index := steps.size()
				steps.append(_build_step_dict("phase", i, state_in, {
					"from_phase": str(before.phase),
					"to_phase": str(state_in.phase),
				}))

				# 事件归属：
				# - `*_REPORT` 等离开阶段事件：归属到旧阶段（old_phase）
				# - PHASE_CHANGED/ROUND_* 等：归属到新阶段（new_phase）
				# 同时：现金/里程碑按结算触发点归属，避免 Payday exit settlement 被推到 Marketing 段落。
				var before_phase_events: Array[Dictionary] = []
				var after_phase_events: Array[Dictionary] = []
				var seen_phase_changed := false
				for ev_val in phase_events:
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

				if not before_phase_events.is_empty():
					_append_events(events_out, before_phase_events, i, current_step_index, str(before.phase), seq)
					seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

				var to_old_segment := _should_attribute_settlement_effects_to_old_phase(engine, str(before.phase), str(state_in.phase))
				if to_old_segment:
					if not cash_events.is_empty():
						_append_events(events_out, _override_events_phase_fields(cash_events, before), i, current_step_index, str(before.phase), seq)
						seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
					if not milestone_events.is_empty():
						_append_events(events_out, _override_events_phase_fields(milestone_events, before), i, current_step_index, str(before.phase), seq)
						seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

				if not after_phase_events.is_empty():
					_append_events(events_out, after_phase_events, i, phase_step_index, str(state_in.phase), seq)
					seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

				if not to_old_segment:
					if not cash_events.is_empty():
						_append_events(events_out, _override_events_phase_fields(cash_events, state_in), i, phase_step_index, str(state_in.phase), seq)
						seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
					if not milestone_events.is_empty():
						_append_events(events_out, _override_events_phase_fields(milestone_events, state_in), i, phase_step_index, str(state_in.phase), seq)
						seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

				current_step_index = phase_step_index
			else:
				# sub_phase 等变化：打包在当前 step，并更新快照到最新稳定状态
				steps[current_step_index] = _update_step_snapshot(steps[current_step_index], state_in)
				_append_events(events_out, phase_events, i, current_step_index, str(state_in.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
				_append_events(events_out, cash_events, i, current_step_index, str(state_in.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq
				_append_events(events_out, milestone_events, i, current_step_index, str(state_in.phase), seq)
				seq = int(events_out.back().get("sequence", seq)) if not events_out.is_empty() else seq

		if safety >= 32:
			return Result.failure("StepTimelineBuild: auto_advance exceeded max steps (possible loop)").with_warnings(warnings)

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

	return Result.success({
		"initial_state_dict": state_dict_val.duplicate(true),
		"steps": steps,
		"events": events_out,
	}).with_warnings(warnings)

static func _should_force_execute_in_replay(command: Command) -> bool:
	if command == null:
		return false
	if OS.has_feature("release"):
		return false
	if not (command.metadata is Dictionary):
		return false
	return bool(Dictionary(command.metadata).get("debug_force", false))

static func _build_step_dict(kind: String, anchor_command_index: int, state: GameState, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = extra.duplicate(true) if (extra is Dictionary) else {}
	out["kind"] = str(kind).strip_edges()
	out["anchor_command_index"] = int(anchor_command_index)
	out["round"] = int(state.round_number) if state != null else -1
	out["phase"] = str(state.phase) if state != null else ""
	out["sub_phase"] = str(state.sub_phase) if state != null else ""
	out["state_dict"] = state.to_dict() if state != null else {}
	return out

static func _update_step_snapshot(step: Dictionary, state: GameState) -> Dictionary:
	# 更新 step 的状态快照，但保留 anchor_command_index / kind / from_phase 等元信息。
	if step == null or not (step is Dictionary):
		return _build_step_dict("command", -1, state)
	var out: Dictionary = step.duplicate(true)
	out["round"] = int(state.round_number) if state != null else -1
	out["phase"] = str(state.phase) if state != null else ""
	out["sub_phase"] = str(state.sub_phase) if state != null else ""
	out["state_dict"] = state.to_dict() if state != null else {}
	return out

static func _append_events(
	out_events: Array[Dictionary],
	events: Array[Dictionary],
	command_index: int,
	step_index: int,
	phase_segment: String,
	seq_in: int
) -> void:
	var seq := int(seq_in)
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		_append_single_event(out_events, Dictionary(ev_val), command_index, step_index, phase_segment, seq)
		seq += 1

static func _append_single_event(
	out_events: Array[Dictionary],
	ev: Dictionary,
	command_index: int,
	step_index: int,
	phase_segment: String,
	seq: int
) -> void:
	var t: String = str(ev.get("type", "")).strip_edges()
	if t.is_empty():
		return
	var d_val = ev.get("data", {})
	var d: Dictionary = d_val if (d_val is Dictionary) else {}
	d["command_index"] = int(command_index)
	d["step_index"] = int(step_index)
	ev["data"] = d

	out_events.append({
		"type": t,
		"data": d,
		"sequence": seq,
		"timestamp": seq,
		"command_index": int(command_index),
		"step_index": int(step_index),
		"phase_segment": str(phase_segment),
	})

static func _should_attribute_settlement_effects_to_old_phase(engine: GameEngine, old_phase: String, new_phase: String) -> bool:
	# 目的：避免“离开 Payday 的 EXIT settlement”产生的现金/里程碑被归到新阶段（典型：Marketing）。
	# 规则（保守）：
	# - 若旧阶段配置了 EXIT settlement：归属旧阶段
	# - 否则若新阶段配置了 ENTER settlement：归属新阶段
	# - 默认归属新阶段
	if engine == null or engine.phase_manager == null:
		return false
	var pm = engine.phase_manager

	var old_enum := PhaseDefsClass.get_phase_enum(str(old_phase).strip_edges())
	if old_enum != -1 and pm._is_settlement_scheduled(old_enum, SettlementRegistryClass.Point.EXIT):
		return true

	var new_enum := PhaseDefsClass.get_phase_enum(str(new_phase).strip_edges())
	if new_enum != -1 and pm._is_settlement_scheduled(new_enum, SettlementRegistryClass.Point.ENTER):
		return false

	return false

static func _override_events_phase_fields(events: Array[Dictionary], state: GameState) -> Array[Dictionary]:
	# 用于：现金/里程碑等事件在跨阶段时需要“按实际发生点”的 phase/sub_phase/round 字段，而不是 final_state。
	var out: Array[Dictionary] = []
	if events == null or events.is_empty():
		return out
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = Dictionary(ev_val).duplicate(true)
		var d_val = ev.get("data", {})
		var d: Dictionary = d_val if (d_val is Dictionary) else {}
		if state != null:
			d["phase"] = str(state.phase)
			d["sub_phase"] = str(state.sub_phase)
			d["round"] = int(state.round_number)
		ev["data"] = d
		out.append(ev)
	return out
