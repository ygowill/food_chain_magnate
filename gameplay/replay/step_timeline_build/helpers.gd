# StepTimelineBuild：局部 helper 拆分
# 用途：收敛 StepTimelineBuild 内部的 step dict / 事件封装 / 阶段归属等样板代码。
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const TimelineEventHelpersClass = preload("res://gameplay/replay/timeline_event_helpers.gd")
const DeferredEventPolicyClass = preload("res://gameplay/replay/step_timeline_build/deferred_event_policy.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

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
) -> Result:
	# seq_in 表示“上一条已写入事件的 sequence”（即 next = seq_in + 1），与 TimelineEventHelpers.append_step_event 保持一致。
	var seq := int(seq_in)
	for i in range(events.size()):
		var ev_r := CommandRunnerClass.normalize_event_envelope(events[i], "StepTimelineBuild events command #%d[%d]" % [command_index, i])
		if not ev_r.ok:
			return Result.failure("StepTimelineBuild: %s" % ev_r.error)
		var ev: Dictionary = ev_r.value
		var t: String = str(ev.get("type", ""))
		var d: Dictionary = Dictionary(ev.get("data")).duplicate(true)
		seq = TimelineEventHelpersClass.append_step_event(out_events, t, d, seq, command_index, step_index, phase_segment)
	return Result.success(seq)

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

static func override_events_phase_fields(events: Array[Dictionary], state: GameState) -> Result:
	# 用于：现金/里程碑等事件在跨阶段时需要“按实际发生点”的 phase/sub_phase/round 字段，而不是 final_state。
	var out: Array[Dictionary] = []
	if events == null or events.is_empty():
		return Result.success(out)
	for i in range(events.size()):
		var ev_r := CommandRunnerClass.normalize_event_envelope(events[i], "StepTimelineBuild override phase event[%d]" % i)
		if not ev_r.ok:
			return Result.failure("StepTimelineBuild: %s" % ev_r.error)
		var ev: Dictionary = Dictionary(ev_r.value).duplicate(true)
		var d: Dictionary = Dictionary(ev.get("data")).duplicate(true)
		if state != null:
			d["phase"] = str(state.phase)
			d["sub_phase"] = str(state.sub_phase)
			d["round"] = int(state.round_number)
		ev["data"] = d
		out.append(ev)
	return Result.success(out)

static func filter_deferred_cleanup_milestone_events(events: Array[Dictionary], pending: Array[Dictionary]) -> Result:
	# 目的：事件 provider 可通过 metadata 标记“清理丢弃后显示”的里程碑；timeline 只消费通用标记。
	var out: Array[Dictionary] = []
	if events == null or events.is_empty():
		return Result.success(out)
	for i in range(events.size()):
		var ev_r := CommandRunnerClass.normalize_event_envelope(events[i], "StepTimelineBuild cleanup milestone event[%d]" % i)
		if not ev_r.ok:
			return Result.failure("StepTimelineBuild: %s" % ev_r.error)
		var ev: Dictionary = ev_r.value
		if str(ev.get("type", "")).strip_edges() != EventBus.EventType.MILESTONE_ACHIEVED:
			out.append(ev)
			continue
		if DeferredEventPolicyClass.should_defer_cleanup_after_discards(ev):
			if pending != null:
				pending.append(ev)
			continue
		out.append(ev)
	return Result.success(out)

static func create_phase_exit_pending_effects() -> Dictionary:
	return {
		"phase": "",
		"origin_command_index": -1,
		"events": [],
	}

static func read_phase_exit_pending_effects(timeline: Dictionary) -> Result:
	var out := create_phase_exit_pending_effects()
	var pending_meta_r := _read_pending_timeline_events_meta(timeline)
	if not pending_meta_r.ok:
		return pending_meta_r
	var pending_meta: Dictionary = pending_meta_r.value
	if not pending_meta.has(DeferredEventPolicyClass.PENDING_PHASE_EXIT_EFFECTS_KEY):
		return Result.success(out)
	var phase_exit_val = pending_meta.get(DeferredEventPolicyClass.PENDING_PHASE_EXIT_EFFECTS_KEY, null)
	if not (phase_exit_val is Dictionary):
		return Result.failure("StepTimelineBuild: _build_meta.pending_timeline_events.phase_exit_effects 类型错误（期望 Dictionary）")
	var phase_exit: Dictionary = phase_exit_val
	var phase := str(phase_exit.get("phase", "")).strip_edges()
	if phase.is_empty():
		return Result.failure("StepTimelineBuild: pending phase_exit_effects.phase 不能为空")
	var origin_command_index := int(phase_exit.get("origin_command_index", -1))
	var events_val = phase_exit.get("events", null)
	if not (events_val is Array):
		return Result.failure("StepTimelineBuild: pending phase_exit_effects.events 类型错误（期望 Array）")
	var events: Array = events_val
	var add_r := append_phase_exit_pending_effects(out, phase, origin_command_index, events)
	if not add_r.ok:
		return add_r
	return Result.success(out)

static func append_phase_exit_pending_effects(
	pending: Dictionary,
	phase: String,
	origin_command_index: int,
	events: Array
) -> Result:
	if pending == null or not (pending is Dictionary):
		return Result.failure("StepTimelineBuild: phase exit pending 类型错误（期望 Dictionary）")
	var phase_name := str(phase).strip_edges()
	if phase_name.is_empty():
		return Result.failure("StepTimelineBuild: phase exit pending phase 不能为空")
	var events_list: Array = events if (events is Array) else []
	if events_list.is_empty():
		return Result.success()
	var existing_phase := str(pending.get("phase", "")).strip_edges()
	if not existing_phase.is_empty() and existing_phase != phase_name:
		return Result.failure("StepTimelineBuild: pending phase exit effects phase 冲突: %s vs %s" % [existing_phase, phase_name])
	var pending_events_val = pending.get("events", null)
	if not (pending_events_val is Array):
		pending_events_val = []
	var pending_events: Array = pending_events_val
	for i in range(events_list.size()):
		var ev_r := CommandRunnerClass.normalize_event_envelope(events_list[i], "StepTimelineBuild pending phase exit event[%d]" % i)
		if not ev_r.ok:
			return Result.failure("StepTimelineBuild: %s" % ev_r.error)
		pending_events.append(Dictionary(ev_r.value).duplicate(true))
	pending["phase"] = phase_name
	if int(pending.get("origin_command_index", -1)) < 0:
		pending["origin_command_index"] = int(origin_command_index)
	pending["events"] = pending_events
	return Result.success()

static func has_phase_exit_pending_effects(pending: Dictionary) -> bool:
	if pending == null or not (pending is Dictionary):
		return false
	var events_val = pending.get("events", null)
	return events_val is Array and not (events_val as Array).is_empty()

static func should_flush_phase_exit_pending_effects(pending: Dictionary, phase: String) -> bool:
	if not has_phase_exit_pending_effects(pending):
		return false
	return str(pending.get("phase", "")).strip_edges() == str(phase).strip_edges()

static func get_phase_exit_pending_events(pending: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if pending == null or not (pending is Dictionary):
		return out
	var events_val = pending.get("events", null)
	if not (events_val is Array):
		return out
	for ev_val in events_val:
		if ev_val is Dictionary:
			out.append(Dictionary(ev_val).duplicate(true))
	return out

static func clear_phase_exit_pending_effects(pending: Dictionary) -> void:
	if pending == null or not (pending is Dictionary):
		return
	pending["phase"] = ""
	pending["origin_command_index"] = -1
	pending["events"] = []

static func read_pending_cleanup_deferred_events(timeline: Dictionary) -> Result:
	var out: Array[Dictionary] = []
	var pending_meta_r := _read_pending_timeline_events_meta(timeline)
	if not pending_meta_r.ok:
		return pending_meta_r
	var pending_meta: Dictionary = pending_meta_r.value
	if not pending_meta.has(DeferredEventPolicyClass.PENDING_CLEANUP_AFTER_DISCARDS_KEY):
		return Result.success(out)
	var cleanup_val = pending_meta.get(DeferredEventPolicyClass.PENDING_CLEANUP_AFTER_DISCARDS_KEY, null)
	if not (cleanup_val is Dictionary):
		return Result.failure("StepTimelineBuild: _build_meta.pending_timeline_events.cleanup_after_discards 类型错误（期望 Dictionary）")
	var cleanup: Dictionary = cleanup_val
	var events_val = cleanup.get("events", null)
	if not (events_val is Array):
		return Result.failure("StepTimelineBuild: pending cleanup_after_discards.events 类型错误（期望 Array）")
	var events: Array = events_val
	for i in range(events.size()):
		var ev_r := CommandRunnerClass.normalize_event_envelope(events[i], "StepTimelineBuild pending cleanup event[%d]" % i)
		if not ev_r.ok:
			return Result.failure("StepTimelineBuild: %s" % ev_r.error)
		out.append(Dictionary(ev_r.value).duplicate(true))
	return Result.success(out)

static func read_has_pending_cleanup_actions(state: GameState) -> Result:
	if state == null:
		return Result.success(false)
	if not (state.round_state is Dictionary):
		return Result.failure("StepTimelineBuild: round_state 类型错误（期望 Dictionary）")
	return RoundStatePendingPhaseActionsClass.is_phase_blocked(
		state.round_state,
		PhaseDefsClass.PHASE_CLEANUP,
		"StepTimelineBuild"
	)

static func has_pending_cleanup_actions(state: GameState) -> bool:
	var read := read_has_pending_cleanup_actions(state)
	if not read.ok:
		return false
	return bool(read.value)

static func attach_build_meta(
	timeline: Dictionary,
	processed_command_count: int,
	last_event_sequence: int,
	pending_phase_exit_effects: Dictionary = {},
	pending_cleanup_events: Array[Dictionary] = []
) -> Dictionary:
	var out: Dictionary = timeline.duplicate(true) if (timeline is Dictionary) else {}
	out["_build_meta"] = {
		"processed_command_count": int(processed_command_count),
		"last_event_sequence": int(last_event_sequence),
	}
	var pending_meta := _build_pending_timeline_events_meta(pending_phase_exit_effects, pending_cleanup_events)
	if not pending_meta.is_empty():
		out["_build_meta"][DeferredEventPolicyClass.PENDING_META_KEY] = pending_meta
	return out

static func attach_build_meta_owned(
	timeline: Dictionary,
	processed_command_count: int,
	last_event_sequence: int,
	pending_phase_exit_effects: Dictionary = {},
	pending_cleanup_events: Array[Dictionary] = []
) -> Dictionary:
	# Incremental append already owns the top-level timeline/steps/events arrays it returns.
	# Avoid deep-copying every historical step.state_dict on each live append; those historical
	# snapshots are immutable for the returned timeline and are expensive on long restored games.
	var out: Dictionary = timeline if (timeline is Dictionary) else {}
	out["_build_meta"] = {
		"processed_command_count": int(processed_command_count),
		"last_event_sequence": int(last_event_sequence),
	}
	var pending_meta := _build_pending_timeline_events_meta(pending_phase_exit_effects, pending_cleanup_events)
	if not pending_meta.is_empty():
		out["_build_meta"][DeferredEventPolicyClass.PENDING_META_KEY] = pending_meta
	return out

static func read_build_meta(timeline: Dictionary) -> Dictionary:
	if timeline == null or not (timeline is Dictionary):
		return {}
	var meta_val = timeline.get("_build_meta", null)
	return Dictionary(meta_val).duplicate(true) if (meta_val is Dictionary) else {}

static func _read_pending_timeline_events_meta(timeline: Dictionary) -> Result:
	var meta := read_build_meta(timeline)
	if meta.is_empty() or not meta.has(DeferredEventPolicyClass.PENDING_META_KEY):
		return Result.success({})
	var pending_val = meta.get(DeferredEventPolicyClass.PENDING_META_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("StepTimelineBuild: _build_meta.pending_timeline_events 类型错误（期望 Dictionary）")
	return Result.success(Dictionary(pending_val).duplicate(true))

static func _build_pending_timeline_events_meta(
	pending_phase_exit_effects: Dictionary,
	pending_cleanup_events: Array[Dictionary]
) -> Dictionary:
	var out: Dictionary = {}
	if has_phase_exit_pending_effects(pending_phase_exit_effects):
		out[DeferredEventPolicyClass.PENDING_PHASE_EXIT_EFFECTS_KEY] = {
			"phase": str(pending_phase_exit_effects.get("phase", "")).strip_edges(),
			"origin_command_index": int(pending_phase_exit_effects.get("origin_command_index", -1)),
			"events": get_phase_exit_pending_events(pending_phase_exit_effects),
		}
	if pending_cleanup_events != null and not pending_cleanup_events.is_empty():
		var cleanup_events: Array[Dictionary] = []
		for ev_val in pending_cleanup_events:
			if ev_val is Dictionary:
				cleanup_events.append(Dictionary(ev_val).duplicate(true))
		if not cleanup_events.is_empty():
			out[DeferredEventPolicyClass.PENDING_CLEANUP_AFTER_DISCARDS_KEY] = {
				"events": cleanup_events,
			}
	return out

static func read_processed_command_count(timeline: Dictionary) -> int:
	var meta := read_build_meta(timeline)
	if meta.has("processed_command_count"):
		return maxi(0, int(meta.get("processed_command_count", 0)))
	return maxi(0, _infer_processed_command_count(timeline))

static func read_last_event_sequence(timeline: Dictionary) -> int:
	var meta := read_build_meta(timeline)
	if meta.has("last_event_sequence"):
		return maxi(0, int(meta.get("last_event_sequence", 0)))
	return maxi(0, _infer_last_event_sequence(timeline))

static func _infer_processed_command_count(timeline: Dictionary) -> int:
	if timeline == null or not (timeline is Dictionary) or timeline.is_empty():
		return 0

	var max_cmd := -1
	var events_val = timeline.get("events", null)
	if events_val is Array:
		for ev_val in events_val:
			if not (ev_val is Dictionary):
				continue
			max_cmd = maxi(max_cmd, int(Dictionary(ev_val).get("command_index", -1)))
	if max_cmd >= 0:
		return max_cmd + 1

	var steps_val = timeline.get("steps", null)
	if steps_val is Array:
		for step_val in steps_val:
			if not (step_val is Dictionary):
				continue
			max_cmd = maxi(max_cmd, int(Dictionary(step_val).get("anchor_command_index", -1)))
	if max_cmd >= 0:
		return max_cmd + 1

	return 0

static func _infer_last_event_sequence(timeline: Dictionary) -> int:
	if timeline == null or not (timeline is Dictionary) or timeline.is_empty():
		return 0
	var events_val = timeline.get("events", null)
	if not (events_val is Array):
		return 0
	var events: Array = events_val
	for idx in range(events.size() - 1, -1, -1):
		var ev_val = events[idx]
		if not (ev_val is Dictionary):
			continue
		return maxi(0, int(Dictionary(ev_val).get("sequence", 0)))
	return 0
