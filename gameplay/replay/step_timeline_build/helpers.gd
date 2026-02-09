# StepTimelineBuild：局部 helper 拆分
# 用途：收敛 StepTimelineBuild 内部的 step dict / 事件封装 / 阶段归属等样板代码。
extends RefCounted

const TimelineEventHelpersClass = preload("res://gameplay/replay/timeline_event_helpers.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

static func build_step_dict(kind: String, anchor_command_index: int, state: GameState, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = extra.duplicate(true) if (extra is Dictionary) else {}
	out["kind"] = str(kind).strip_edges()
	out["anchor_command_index"] = int(anchor_command_index)
	out["round"] = int(state.round_number) if state != null else -1
	out["phase"] = str(state.phase) if state != null else ""
	out["sub_phase"] = str(state.sub_phase) if state != null else ""
	out["state_dict"] = state.to_dict() if state != null else {}
	return out

static func update_step_snapshot(step: Dictionary, state: GameState) -> Dictionary:
	# 更新 step 的状态快照，但保留 anchor_command_index / kind / from_phase 等元信息。
	if step == null or not (step is Dictionary):
		return build_step_dict("command", -1, state)
	var out: Dictionary = step.duplicate(true)
	out["round"] = int(state.round_number) if state != null else -1
	out["phase"] = str(state.phase) if state != null else ""
	out["sub_phase"] = str(state.sub_phase) if state != null else ""
	out["state_dict"] = state.to_dict() if state != null else {}
	return out

static func append_events(
	out_events: Array[Dictionary],
	events: Array[Dictionary],
	command_index: int,
	step_index: int,
	phase_segment: String,
	seq_in: int
) -> void:
	# seq_in 表示“上一条已写入事件的 sequence”（即 next = seq_in + 1），与 TimelineEventHelpers.append_step_event 保持一致。
	var seq := int(seq_in)
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t: String = str(ev.get("type", "")).strip_edges()
		if t.is_empty():
			continue
		var d_val = ev.get("data", {})
		var d: Dictionary = d_val if (d_val is Dictionary) else {}
		seq = TimelineEventHelpersClass.append_step_event(out_events, t, d, seq, command_index, step_index, phase_segment)

static func should_attribute_settlement_effects_to_old_phase(engine: GameEngine, old_phase: String, new_phase: String) -> bool:
	# 目的：避免“离开 Payday 的 EXIT settlement”产生的现金/里程碑被归到新阶段（典型：Marketing）。
	# 规则（保守）：
	# - 若旧阶段配置了 EXIT settlement：归属旧阶段
	# - 否则若新阶段配置了 ENTER settlement：归属新阶段
	# - 默认归属新阶段
	if engine == null or engine.phase_manager == null:
		return false
	var pm = engine.phase_manager

	var old_enum := PhaseDefsClass.get_phase_enum(str(old_phase).strip_edges())
	if old_enum != -1 and pm.is_settlement_scheduled(old_enum, SettlementRegistryClass.Point.EXIT):
		return true

	var new_enum := PhaseDefsClass.get_phase_enum(str(new_phase).strip_edges())
	if new_enum != -1 and pm.is_settlement_scheduled(new_enum, SettlementRegistryClass.Point.ENTER):
		return false

	return false

static func override_events_phase_fields(events: Array[Dictionary], state: GameState) -> Array[Dictionary]:
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

static func filter_out_first_throw_away_milestone_events(events: Array[Dictionary], pending: Array[Dictionary]) -> Array[Dictionary]:
	# 目的：首个丢弃里程碑（first_throw_away）显示顺序应在“清理库存”之后，避免出现在清理动作之前。
	var out: Array[Dictionary] = []
	if events == null or events.is_empty():
		return out
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		if str(ev.get("type", "")).strip_edges() != EventBus.EventType.MILESTONE_ACHIEVED:
			out.append(ev)
			continue
		var d_val = ev.get("data", null)
		if not (d_val is Dictionary):
			out.append(ev)
			continue
		var d: Dictionary = d_val
		var mid := str(d.get("milestone_id", "")).strip_edges()
		if mid == "first_throw_away":
			if pending != null:
				pending.append(ev)
			continue
		out.append(ev)
	return out

static func has_pending_cleanup_actions(state: GameState) -> bool:
	if state == null:
		return false
	if not (state.round_state is Dictionary):
		return false
	var ppa_val = Dictionary(state.round_state).get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return false
	var ppa: Dictionary = ppa_val
	if not ppa.has(PhaseDefsClass.PHASE_CLEANUP):
		return false
	var list_val = ppa.get(PhaseDefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return false
	return not Array(list_val).is_empty()
