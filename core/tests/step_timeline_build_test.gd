# 语义步进时间线构建测试（step_index）
# - build_full() 应返回 {initial_state_dict, steps, events}
# - events 应包含 step_index（单调不减）且落在 [-1, steps.size()-1]
# - 应至少生成一个 phase step（用于验证“auto-advance 跨阶段不合并”）
class_name StepTimelineBuildTest
extends RefCounted

const StepTimelineBuildClass = preload("res://core/engine/game_engine/step_timeline_build.gd")

const SAVE_RES_PATH := "res://.savings/manual_cases/logs/event_log_review.json"

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
	for s_val in steps:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if str(s.get("kind", "")).strip_edges() == "phase":
			has_phase_step = true
			break
	if not has_phase_step:
		return Result.failure("expected at least one phase step in %s" % SAVE_RES_PATH)

	# 每条命令至少一个 step
	if steps.size() < engine.command_history.size():
		return Result.failure("steps should be >= commands: steps=%d commands=%d" % [steps.size(), engine.command_history.size()])

	# step_index 单调不减，且 data.* 映射一致
	var prev_step := -999999
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

	return Result.success({
		"commands": engine.command_history.size(),
		"steps": steps.size(),
		"events": events.size(),
	})

