class_name StepTimelineIncrementalAppendTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(seed_val: int = 12345) -> Result:
	var payday_r := _test_payday_report_appends_on_triggering_skip(seed_val + 17)
	if not payday_r.ok:
		return payday_r

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_number = 2
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""

	if not (state.round_state is Dictionary):
		state.round_state = {}
	state.round_state["restructuring"] = {
		"submitted": {0: false, 1: false},
		"finalized": false,
	}
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_RESTRUCTURING: [0, 1]
	}

	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	var submit0 := engine.execute_command(Command.create("submit_restructuring", 0))
	if not submit0.ok:
		return Result.failure("submit_restructuring p0 failed: %s" % submit0.error)
	var submit1 := engine.execute_command(Command.create("submit_restructuring", 1))
	if not submit1.ok:
		return Result.failure("submit_restructuring p1 failed: %s" % submit1.error)

	var state_after := engine.get_state()
	if state_after.phase != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("expected phase OrderOfBusiness, got: %s" % str(state_after.phase))

	var pick0_actor := state_after.get_current_player_id()
	var pick0 := engine.execute_command(Command.create("choose_turn_order", pick0_actor, {"position": 0}))
	if not pick0.ok:
		return Result.failure("choose_turn_order #1 failed: %s" % pick0.error)

	var base_r: Result = StepTimelineBuildClass.build_full(engine)
	if not base_r.ok:
		return Result.failure("build_full(base) failed: %s" % base_r.error)
	if not (base_r.value is Dictionary):
		return Result.failure("build_full(base).value type error (expected Dictionary)")
	var base_timeline: Dictionary = Dictionary(base_r.value).duplicate(true)
	var base_timeline_before_append: Dictionary = base_timeline.duplicate(true)
	var base_processed_count := StepTimelineHelpersClass.read_processed_command_count(base_timeline)
	if base_processed_count != int(engine.command_history.size()):
		return Result.failure(
			"base timeline processed_command_count mismatch: %d vs %d"
				% [base_processed_count, int(engine.command_history.size())]
		)
	var corrupted_cache_r := _assert_corrupted_append_cache_rejected(engine, base_timeline)
	if not corrupted_cache_r.ok:
		return corrupted_cache_r
	var bad_prebuilt_r := _assert_prebuilt_entries_reject_bad_items(base_timeline)
	if not bad_prebuilt_r.ok:
		return bad_prebuilt_r

	state_after = engine.get_state()
	var pick1_actor := state_after.get_current_player_id()
	var pick1 := engine.execute_command(Command.create("choose_turn_order", pick1_actor, {"position": 1}))
	if not pick1.ok:
		return Result.failure("choose_turn_order #2 failed: %s" % pick1.error)

	var append_r: Result = StepTimelineBuildClass.append_from_existing(engine, base_timeline)
	if not append_r.ok:
		return Result.failure("append_from_existing failed: %s" % append_r.error)
	if not (append_r.value is Dictionary):
		return Result.failure("append_from_existing.value type error (expected Dictionary)")
	if base_timeline != base_timeline_before_append:
		return Result.failure("append_from_existing must not mutate the baseline timeline")
	var append_info: Dictionary = Dictionary(append_r.value)
	if not bool(append_info.get("append_applied", false)):
		return Result.failure("append_from_existing should append for tail growth")

	var appended_steps_val = append_info.get("appended_steps", null)
	if not (appended_steps_val is Array) or (appended_steps_val as Array).is_empty():
		return Result.failure("append_from_existing should produce appended_steps")
	var appended_events_val = append_info.get("appended_events", null)
	if not (appended_events_val is Array) or (appended_events_val as Array).is_empty():
		return Result.failure("append_from_existing should produce appended_events")

	var append_timeline: Dictionary = Dictionary(append_info.get("timeline", {})).duplicate(true)
	var append_processed_count := StepTimelineHelpersClass.read_processed_command_count(append_timeline)
	if append_processed_count != int(engine.command_history.size()):
		return Result.failure(
			"append timeline processed_command_count mismatch: %d vs %d"
				% [append_processed_count, int(engine.command_history.size())]
		)

	var full_r: Result = StepTimelineBuildClass.build_full(engine)
	if not full_r.ok:
		return Result.failure("build_full(final) failed: %s" % full_r.error)
	if not (full_r.value is Dictionary):
		return Result.failure("build_full(final).value type error (expected Dictionary)")
	var full_timeline: Dictionary = Dictionary(full_r.value).duplicate(true)

	if append_timeline != full_timeline:
		return Result.failure("incremental append timeline does not match full rebuild")

	var steps_val = append_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	var events_val = append_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var appended_steps: Array = appended_steps_val if (appended_steps_val is Array) else []
	var appended_events: Array = appended_events_val if (appended_events_val is Array) else []

	return Result.success({
		"commands": int(engine.command_history.size()),
		"steps": int(steps.size()),
		"events": int(events.size()),
		"appended_steps": int(appended_steps.size()),
		"appended_events": int(appended_events.size()),
	})

static func _test_payday_report_appends_on_triggering_skip(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("payday append: init failed: %s" % init.error)

	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_PAYDAY, 200)
	if not to_payday.ok:
		return Result.failure("payday append: advance_until_phase failed: %s" % to_payday.error)

	var state := engine.get_state()
	if state.bank is Dictionary:
		state.bank["broke_count"] = maxi(2, int(state.bank.get("broke_count", 0)))
	for pid in range(state.players.size()):
		var give := StateUpdaterClass.player_receive_from_bank(state, pid, 1000)
		if not give.ok:
			return Result.failure("payday append: give cash to player %d failed: %s" % [pid, give.error])

	var first_actor := int(engine.get_state().get_current_player_id())
	var first_skip := engine.execute_command(Command.create(ActionIdsClass.SKIP, first_actor))
	if not first_skip.ok:
		return Result.failure("payday append: first skip failed: %s" % first_skip.error)
	if str(engine.get_state().phase) != DefsClass.PHASE_PAYDAY:
		return Result.failure("payday append: first skip should stay in Payday, got: %s" % str(engine.get_state().phase))

	var base_r: Result = StepTimelineBuildClass.build_full(engine)
	if not base_r.ok:
		return Result.failure("payday append: build_full(base) failed: %s" % base_r.error)
	if not (base_r.value is Dictionary):
		return Result.failure("payday append: build_full(base).value type error (expected Dictionary)")
	var base_timeline: Dictionary = Dictionary(base_r.value).duplicate(true)
	var base_step_count := _read_array_size(base_timeline.get("steps", []))
	var base_event_count := _read_array_size(base_timeline.get("events", []))
	var base_processed_count := StepTimelineHelpersClass.read_processed_command_count(base_timeline)
	if base_processed_count != int(engine.command_history.size()):
		return Result.failure(
			"payday append: base processed_command_count mismatch: %d vs %d"
				% [base_processed_count, int(engine.command_history.size())]
		)

	var triggering_command_index := int(engine.command_history.size())
	var final_actor := int(engine.get_state().get_current_player_id())
	var final_skip := engine.execute_command(Command.create(ActionIdsClass.SKIP, final_actor))
	if not final_skip.ok:
		return Result.failure("payday append: final skip failed: %s" % final_skip.error)
	if str(engine.get_state().phase) == DefsClass.PHASE_PAYDAY:
		return Result.failure("payday append: final skip should leave Payday")

	var append_r: Result = StepTimelineBuildClass.append_from_existing(engine, base_timeline)
	if not append_r.ok:
		return Result.failure("payday append: append_from_existing failed: %s" % append_r.error)
	if not (append_r.value is Dictionary):
		return Result.failure("payday append: append_from_existing.value type error (expected Dictionary)")
	var append_info: Dictionary = append_r.value
	if not bool(append_info.get("append_applied", false)):
		return Result.failure("payday append: append_from_existing should append for final skip")

	var appended_events_val = append_info.get("appended_events", null)
	if not (appended_events_val is Array):
		return Result.failure("payday append: appended_events type error (expected Array)")
	var appended_events: Array = appended_events_val

	var appended_reports: Array[Dictionary] = []
	var appended_phase_changed: Dictionary = {}
	for ev_val in appended_events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var event_type := str(ev.get("type", "")).strip_edges()
		if event_type == EventBus.EventType.PAYDAY_REPORT:
			appended_reports.append(ev)
		elif event_type == EventBus.EventType.PHASE_CHANGED and appended_phase_changed.is_empty():
			appended_phase_changed = ev

	if appended_reports.is_empty():
		return Result.failure("payday append: appended_events should include PAYDAY_REPORT")
	if appended_phase_changed.is_empty():
		return Result.failure("payday append: appended_events should include PHASE_CHANGED")

	var report: Dictionary = appended_reports[0]
	var report_step := int(report.get("step_index", -999999))
	var report_cmd := int(report.get("command_index", -999999))
	var report_segment := str(report.get("phase_segment", "")).strip_edges()
	if report_cmd != triggering_command_index:
		return Result.failure("payday append: PAYDAY_REPORT command_index should be final skip command %d, got %d" % [triggering_command_index, report_cmd])
	if report_step < base_step_count:
		return Result.failure("payday append: PAYDAY_REPORT should be in appended step range (step=%d base_steps=%d)" % [report_step, base_step_count])
	if report_segment != DefsClass.PHASE_PAYDAY:
		return Result.failure("payday append: PAYDAY_REPORT phase_segment should stay Payday, got: %s" % report_segment)

	var phase_step := int(appended_phase_changed.get("step_index", -999999))
	var phase_segment := str(appended_phase_changed.get("phase_segment", "")).strip_edges()
	if phase_step != report_step:
		return Result.failure("payday append: PAYDAY_REPORT should share the triggering command step with PHASE_CHANGED (report=%d phase=%d)" % [report_step, phase_step])
	if phase_segment != DefsClass.PHASE_MARKETING:
		return Result.failure("payday append: PHASE_CHANGED segment should be Marketing, got: %s" % phase_segment)

	var append_timeline: Dictionary = Dictionary(append_info.get("timeline", {})).duplicate(true)
	var full_r: Result = StepTimelineBuildClass.build_full(engine)
	if not full_r.ok:
		return Result.failure("payday append: build_full(final) failed: %s" % full_r.error)
	if not (full_r.value is Dictionary):
		return Result.failure("payday append: build_full(final).value type error (expected Dictionary)")
	if append_timeline != Dictionary(full_r.value):
		return Result.failure("payday append: incremental append timeline does not match full rebuild")

	var final_event_count := _read_array_size(append_timeline.get("events", []))
	if final_event_count <= base_event_count:
		return Result.failure("payday append: final events should grow after append")

	return Result.success({
		"base_steps": base_step_count,
		"report_step": report_step,
		"command_index": report_cmd,
	})

static func _read_array_size(value) -> int:
	return Array(value).size() if (value is Array) else 0

static func _assert_corrupted_append_cache_rejected(engine: GameEngine, base_timeline: Dictionary) -> Result:
	var missing_meta := base_timeline.duplicate(true)
	missing_meta.erase("_build_meta")
	var missing_meta_r: Result = StepTimelineBuildClass.append_from_existing(engine, missing_meta)
	if missing_meta_r.ok:
		return Result.failure("append_from_existing 不应接受缺少 _build_meta 的缓存")
	if str(missing_meta_r.error).find("_build_meta") < 0:
		return Result.failure("缺少 _build_meta 的错误信息应包含 _build_meta，实际: %s" % missing_meta_r.error)

	var bad_steps := base_timeline.duplicate(true)
	var steps_val = bad_steps.get("steps", [])
	if not (steps_val is Array):
		return Result.failure("测试基线 timeline.steps 类型错误")
	var bad_steps_arr: Array = []
	for step_val in Array(steps_val):
		bad_steps_arr.append(step_val)
	bad_steps_arr.append("bad_step")
	bad_steps["steps"] = bad_steps_arr
	var bad_steps_r: Result = StepTimelineBuildClass.append_from_existing(engine, bad_steps)
	if bad_steps_r.ok:
		return Result.failure("append_from_existing 不应过滤坏 step 后继续使用缓存")
	if str(bad_steps_r.error).find("steps") < 0:
		return Result.failure("坏 step 错误信息应包含 steps，实际: %s" % bad_steps_r.error)

	var bad_events := base_timeline.duplicate(true)
	var events_val = bad_events.get("events", [])
	if not (events_val is Array):
		return Result.failure("测试基线 timeline.events 类型错误")
	var bad_events_arr: Array = []
	for event_val in Array(events_val):
		bad_events_arr.append(event_val)
	bad_events_arr.append("bad_event")
	bad_events["events"] = bad_events_arr
	var bad_events_r: Result = StepTimelineBuildClass.append_from_existing(engine, bad_events)
	if bad_events_r.ok:
		return Result.failure("append_from_existing 不应过滤坏 event 后继续使用缓存")
	if str(bad_events_r.error).find("events") < 0:
		return Result.failure("坏 event 错误信息应包含 events，实际: %s" % bad_events_r.error)

	return Result.success()

static func _assert_prebuilt_entries_reject_bad_items(base_timeline: Dictionary) -> Result:
	var bad_entries_r: Result = StepTimelineBuildHelpersClass.build_info_from_prebuilt_entries(base_timeline, ["bad_entry"])
	if bad_entries_r.ok:
		return Result.failure("prebuilt entries 不应过滤坏 entry 后继续使用")
	if str(bad_entries_r.error).find("entries") < 0:
		return Result.failure("坏 prebuilt entry 错误信息应包含 entries，实际: %s" % bad_entries_r.error)

	var bad_timeline := base_timeline.duplicate(true)
	bad_timeline["events"] = ["bad_event"]
	var bad_timeline_r: Result = StepTimelineBuildHelpersClass.build_info_from_timeline(bad_timeline)
	if bad_timeline_r.ok:
		return Result.failure("prebuilt timeline 不应过滤坏 event 后继续使用")
	if str(bad_timeline_r.error).find("events") < 0:
		return Result.failure("坏 prebuilt timeline 错误信息应包含 events，实际: %s" % bad_timeline_r.error)

	return Result.success()
