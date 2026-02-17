# 语义步进时间线构建测试（step_index）
# - build_full() 应返回 {initial_state_dict, steps, events}
# - events 应包含 step_index（单调不减）且落在 [-1, steps.size()-1]
# - 应至少生成一个 phase step（用于验证“auto-advance 跨阶段不合并”）
class_name StepTimelineBuildTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const SAVE_RES_PATH := "res://testdata/saves/manual_cases/logs/event_log_review.json"

static func run() -> Result:
	var abs_path := ProjectSettings.globalize_path(SAVE_RES_PATH)
	var engine := GameEngine.new()
	var load := engine.load_from_file(abs_path)
	if not load.ok:
		return Result.failure("load failed: %s" % load.error)
	if engine.get_state() == null:
		return Result.failure("load succeeded but state is null")

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

	var events_val = data.get("events", null)
	if not (events_val is Array):
		return Result.failure("events type error (expected Array)")
	var events: Array = events_val
	if events.is_empty():
		return Result.failure("events should not be empty")

	# 至少应有一个 phase step（对应“阶段切分点”）
	var has_phase_step := false
	var has_cleanup_phase_step := false
	var has_restructuring_phase_step := false
	for s_val in steps:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var kind := str(s.get("kind", "")).strip_edges()
		if kind == "phase":
			has_phase_step = true
			var phase := str(s.get("phase", "")).strip_edges()
			if phase == DefsClass.PHASE_CLEANUP:
				has_cleanup_phase_step = true
			if phase == DefsClass.PHASE_RESTRUCTURING:
				has_restructuring_phase_step = true
	if not has_phase_step:
		return Result.failure("expected at least one phase step in %s" % SAVE_RES_PATH)
	# event_log_review 覆盖了 Marketing/Cleanup 的 auto-advance，应该能切出至少 Cleanup/Restructuring 两个大阶段步进点。
	if not has_cleanup_phase_step:
		return Result.failure("expected at least one Cleanup phase step in %s" % SAVE_RES_PATH)
	if not has_restructuring_phase_step:
		return Result.failure("expected at least one Restructuring phase step in %s" % SAVE_RES_PATH)

	# 每条命令至少一个 step
	if steps.size() < engine.command_history.size():
		return Result.failure("steps should be >= commands: steps=%d commands=%d" % [steps.size(), engine.command_history.size()])

	# step_index 单调不减，且 data.* 映射一致
	var prev_step := -999999
	var seen_phase_segments := {}
	for ev_val in events:
		if not (ev_val is Dictionary):
			return Result.failure("event type error (expected Dictionary): %s" % str(ev_val))
		var ev: Dictionary = ev_val
		if not ev.has("step_index"):
			return Result.failure("event missing step_index: %s" % str(ev))
		if not ev.has("command_index"):
			return Result.failure("event missing command_index: %s" % str(ev))
		var si := int(ev.get("step_index", -999999))
		var ci := int(ev.get("command_index", -999999))
		if si < prev_step:
			return Result.failure("step_index should be monotonic non-decreasing: prev=%d cur=%d" % [prev_step, si])
		prev_step = si

		if si < -1 or si >= steps.size():
			return Result.failure("step_index out of range: %d (steps=%d)" % [si, steps.size()])

		var d_val = ev.get("data", null)
		if not (d_val is Dictionary):
			return Result.failure("event.data type error (expected Dictionary): %s" % str(ev))
		var d: Dictionary = d_val
		if int(d.get("command_index", -999999)) != ci:
			return Result.failure("data.command_index mismatch: ci=%d data=%s" % [ci, str(d.get("command_index", null))])
		if int(d.get("step_index", -999999)) != si:
			return Result.failure("data.step_index mismatch: si=%d data=%s" % [si, str(d.get("step_index", null))])

		var seg := str(ev.get("phase_segment", "")).strip_edges()
		if not seg.is_empty():
			seen_phase_segments[seg] = true

	# 至少应出现 Marketing/Cleanup/Payday 三段（验证“离开阶段事件归属 + auto-advance 分段”）
	if not (seen_phase_segments.has(DefsClass.PHASE_PAYDAY) and seen_phase_segments.has(DefsClass.PHASE_MARKETING) and seen_phase_segments.has(DefsClass.PHASE_CLEANUP)):
		return Result.failure("expected phase segments to include Payday/Marketing/Cleanup in %s (seen=%s)" % [SAVE_RES_PATH, str(seen_phase_segments.keys())])

	# 现金变化：Payday 的薪资结算应归属到 Payday 段落（避免被推到 Marketing）。
	var has_payday_report := false
	var cash_segments := {}
	for ev_val2 in events:
		if not (ev_val2 is Dictionary):
			continue
		var ev2: Dictionary = ev_val2
		var t2 := str(ev2.get("type", "")).strip_edges()
		if t2 == EventBus.EventType.PAYDAY_REPORT:
			has_payday_report = true
		if t2 != EventBus.EventType.PLAYER_CASH_CHANGED:
			continue
		var seg2 := str(ev2.get("phase_segment", "")).strip_edges()
		if seg2.is_empty():
			continue
		cash_segments[seg2] = true

	if has_payday_report and not cash_segments.has(DefsClass.PHASE_PAYDAY):
		return Result.failure("expected at least one PLAYER_CASH_CHANGED in Payday segment (cash_segments=%s)" % str(cash_segments.keys()))

	# 里程碑：若该存档触发里程碑，则不应全部被推迟到 Restructuring 段落。
	var milestone_count := 0
	var non_restructuring_milestone := false
	for ev_val3 in events:
		if not (ev_val3 is Dictionary):
			continue
		var ev3: Dictionary = ev_val3
		if str(ev3.get("type", "")).strip_edges() != EventBus.EventType.MILESTONE_ACHIEVED:
			continue
		milestone_count += 1
		if str(ev3.get("phase_segment", "")).strip_edges() != DefsClass.PHASE_RESTRUCTURING:
			non_restructuring_milestone = true

	if milestone_count > 0 and not non_restructuring_milestone:
		return Result.failure("expected at least one MILESTONE_ACHIEVED not in Restructuring (count=%d)" % milestone_count)

	# 0.1.1 回归保护：skip/skip_sub_phase 的事件顺序必须符合语义
	# - 玩家先结束回合，再发生子阶段/阶段推进（避免 turn_ended 被归到新阶段/新子阶段）。
	var cmd2_turn_ended_seq := -1
	var cmd2_sub_phase_seq := -1
	var cmd6_turn_ended_seq := -1
	var cmd6_phase_changed_seq := -1
	var cmd6_turn_ended_seg := ""

	for ev_val4 in events:
		if not (ev_val4 is Dictionary):
			continue
		var ev4: Dictionary = ev_val4
		var ci4 := int(ev4.get("command_index", -999999))
		var t4 := str(ev4.get("type", "")).strip_edges()
		var seq4 := int(ev4.get("sequence", -1))

		if ci4 == 2:
			if t4 == EventBus.EventType.PLAYER_TURN_ENDED and cmd2_turn_ended_seq < 0:
				cmd2_turn_ended_seq = seq4
			elif t4 == EventBus.EventType.SUB_PHASE_CHANGED and cmd2_sub_phase_seq < 0:
				cmd2_sub_phase_seq = seq4

		if ci4 == 6:
			if t4 == EventBus.EventType.PLAYER_TURN_ENDED and cmd6_turn_ended_seq < 0:
				cmd6_turn_ended_seq = seq4
				cmd6_turn_ended_seg = str(ev4.get("phase_segment", "")).strip_edges()
			elif t4 == EventBus.EventType.PHASE_CHANGED and cmd6_phase_changed_seq < 0:
				cmd6_phase_changed_seq = seq4

	if cmd2_turn_ended_seq < 0 or cmd2_sub_phase_seq < 0:
		return Result.failure("expected PLAYER_TURN_ENDED and SUB_PHASE_CHANGED for command_index=2 in %s" % SAVE_RES_PATH)
	if cmd2_turn_ended_seq > cmd2_sub_phase_seq:
		return Result.failure("expected PLAYER_TURN_ENDED before SUB_PHASE_CHANGED for command_index=2 (turn_ended_seq=%d sub_phase_seq=%d)" % [cmd2_turn_ended_seq, cmd2_sub_phase_seq])

	if cmd6_turn_ended_seq < 0 or cmd6_phase_changed_seq < 0:
		return Result.failure("expected PLAYER_TURN_ENDED and PHASE_CHANGED for command_index=6 in %s" % SAVE_RES_PATH)
	if cmd6_turn_ended_seq > cmd6_phase_changed_seq:
		return Result.failure("expected PLAYER_TURN_ENDED before PHASE_CHANGED for command_index=6 (turn_ended_seq=%d phase_changed_seq=%d)" % [cmd6_turn_ended_seq, cmd6_phase_changed_seq])
	if cmd6_turn_ended_seg != DefsClass.PHASE_PAYDAY:
		return Result.failure("expected command_index=6 PLAYER_TURN_ENDED in Payday segment, got: %s" % cmd6_turn_ended_seg)

	return Result.success({
		"commands": engine.command_history.size(),
		"steps": steps.size(),
		"events": events.size(),
	})
