# Manual logs archives coverage test (UI rendering coverage)
# Covers issue_tracker #50: provide multiple themed manual saves to review log rendering.
class_name ManualLogSavesCoverageTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const GameTimelineLogEntriesBuilderClass = preload("res://ui/scenes/game/timeline/log_entries_builder.gd")
const GameLogUnifiedTimelineBuilderClass = preload("res://ui/components/game_log/game_log_unified_timeline_builder.gd")

const CASES: Array[Dictionary] = [
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_review.json",
		"required_types": [
			EventBus.EventType.MARKETING_PLACED,
			EventBus.EventType.DEMAND_GENERATED,
			EventBus.EventType.DRINKS_PROCURED,
		],
	},
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_employee_recruit_train.json",
		"required_types": [
			EventBus.EventType.EMPLOYEE_RECRUITED,
			EventBus.EventType.EMPLOYEE_TRAINED,
		],
		"required_commands": ["set_price"],
	},
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_employee_fire.json",
		"required_types": [
			EventBus.EventType.EMPLOYEE_FIRED,
		],
	},
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_payday_details.json",
		"required_types": [
			EventBus.EventType.EMPLOYEE_FIRED,
		],
	},
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_build_and_move.json",
		"required_types": [
			EventBus.EventType.HOUSE_PLACED,
			EventBus.EventType.GARDEN_ADDED,
			EventBus.EventType.RESTAURANT_PLACED,
			EventBus.EventType.RESTAURANT_MOVED,
		],
	},
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_produce_and_cleanup.json",
		"required_types": [
			EventBus.EventType.FOOD_PRODUCED,
			EventBus.EventType.FOOD_DISCARDED,
		],
	},
	{
		"path": "res://testdata/saves/manual_cases/logs/event_log_dinnertime_sale.json",
		"required_types": [
			EventBus.EventType.DINNERTIME_REPORT,
			EventBus.EventType.FOOD_SOLD,
			EventBus.EventType.PLAYER_CASH_CHANGED,
		],
	},
]

static func run() -> Result:
	if EventBus == null:
		return Result.failure("EventBus is not available")

	for c in CASES:
		var res_path := str(c.get("path", "")).strip_edges()
		if res_path.is_empty():
			return Result.failure("case.path is empty")

		_clear_event_history()

		var abs_path := ProjectSettings.globalize_path(res_path)
		var engine := GameEngine.new()
		var load := engine.load_from_file(abs_path)
		if not load.ok:
			return Result.failure("load failed: %s (%s)" % [load.error, res_path])
		if engine.get_state() == null:
			return Result.failure("load succeeded but state is null: %s" % res_path)

		var required_types_val = c.get("required_types", null)
		if required_types_val is Array:
			for t_val in Array(required_types_val):
				var t := str(t_val).strip_edges()
				if t.is_empty():
					continue
				var events: Array = EventBus.get_history_by_type(t)
				if events.is_empty():
					return Result.failure("expected %s event in history after loading: %s" % [t, res_path])

		var required_commands_val = c.get("required_commands", null)
		if required_commands_val is Array and not Array(required_commands_val).is_empty():
			var cmd_events: Array = EventBus.get_history_by_type(EventBus.EventType.COMMAND_EXECUTED)
			var seen := {}
			for ev_val in cmd_events:
				if not (ev_val is Dictionary):
					continue
				var ev: Dictionary = ev_val
				var data_val = ev.get("data", null)
				if not (data_val is Dictionary):
					continue
				var data: Dictionary = data_val
				var action_id := str(data.get("action_id", "")).strip_edges()
				if action_id.is_empty():
					continue
				seen[action_id] = true
			for req in Array(required_commands_val):
				var rid := str(req).strip_edges()
				if rid.is_empty():
					continue
				if not seen.has(rid):
					return Result.failure("expected COMMAND_EXECUTED for %s after loading: %s" % [rid, res_path])

		# The Payday manual case starts before settlement; complete it and ensure the live/timeline
		# log projection shows the detailed PAYDAY_REPORT entries by default.
		if res_path.ends_with("event_log_payday_details.json"):
			var payday_verify := _verify_payday_details_after_interaction(engine, res_path)
			if not payday_verify.ok:
				return payday_verify

		# Ensure ordering for the dinnertime settlement: sold logs first, cash changes after.
		if res_path.ends_with("event_log_dinnertime_sale.json"):
			var sold_events: Array = EventBus.get_history_by_type(EventBus.EventType.FOOD_SOLD)
			var cash_events: Array = EventBus.get_history_by_type(EventBus.EventType.PLAYER_CASH_CHANGED)

			var max_sold_seq := -1
			for ev_val in sold_events:
				if not (ev_val is Dictionary):
					continue
				var ev: Dictionary = ev_val
				max_sold_seq = maxi(max_sold_seq, int(ev.get("sequence", -1)))

			var found_dinnertime_cash := false
			var min_cash_seq := 1 << 30
			for ev_val in cash_events:
				if not (ev_val is Dictionary):
					continue
				var ev: Dictionary = ev_val
				var data_val = ev.get("data", null)
				if not (data_val is Dictionary):
					continue
				var data: Dictionary = data_val
				var breakdown_val = data.get("income_breakdown", null)
				if not (breakdown_val is Dictionary):
					continue
				var breakdown: Dictionary = breakdown_val
				if str(breakdown.get("context", "")).strip_edges() != "dinnertime_income":
					continue
				found_dinnertime_cash = true
				min_cash_seq = mini(min_cash_seq, int(ev.get("sequence", min_cash_seq)))

			if not sold_events.is_empty() and found_dinnertime_cash:
				if max_sold_seq >= min_cash_seq:
					return Result.failure("expected FOOD_SOLD before dinnertime PLAYER_CASH_CHANGED in history after loading: %s" % res_path)

			# Ensure unified timeline doesn't promote settlement-derived player logs to ActionGroup header for flow commands.
			# This prevents visual indent issues where the first FOOD_SOLD becomes the header summary and later sales appear over-indented.
			var timeline_r: Result = StepTimelineBuildClass.build_full(engine)
			if not timeline_r.ok:
				return Result.failure("step_timeline build failed for dinnertime save: %s (%s)" % [timeline_r.error, res_path])
			var timeline_val = timeline_r.value
			if not (timeline_val is Dictionary):
				return Result.failure("step_timeline build returned non-Dictionary for dinnertime save: %s" % res_path)
			var timeline: Dictionary = timeline_val
			var events_val2 = timeline.get("events", null)
			if not (events_val2 is Array):
				return Result.failure("step_timeline.events missing/invalid for dinnertime save: %s" % res_path)

			# Ensure in step_timeline ordering: FOOD_SOLD entries must come before dinnertime cash breakdown entries.
			var max_sold_seq2 := -1
			var found_dinnertime_cash2 := false
			var min_cash_seq2 := 1 << 30
			for ev2_val in Array(events_val2):
				if not (ev2_val is Dictionary):
					continue
				var ev2: Dictionary = ev2_val
				var t2 := str(ev2.get("type", "")).strip_edges()
				if t2 == EventBus.EventType.FOOD_SOLD:
					max_sold_seq2 = maxi(max_sold_seq2, int(ev2.get("sequence", -1)))
					continue
				if t2 != EventBus.EventType.PLAYER_CASH_CHANGED:
					continue
				var data2_val = ev2.get("data", null)
				if not (data2_val is Dictionary):
					continue
				var data2: Dictionary = data2_val
				var breakdown2_val = data2.get("income_breakdown", null)
				if not (breakdown2_val is Dictionary):
					continue
				var breakdown2: Dictionary = breakdown2_val
				if str(breakdown2.get("context", "")).strip_edges() != "dinnertime_income":
					continue
				found_dinnertime_cash2 = true
				min_cash_seq2 = mini(min_cash_seq2, int(ev2.get("sequence", min_cash_seq2)))

			if max_sold_seq2 >= 0 and found_dinnertime_cash2:
				if max_sold_seq2 >= min_cash_seq2:
					return Result.failure("expected FOOD_SOLD before dinnertime PLAYER_CASH_CHANGED in step_timeline: %s" % res_path)

			var entries2: Array[Dictionary] = GameTimelineLogEntriesBuilderClass.build(Array(events_val2))
			var entries_by_step := {}
			for e2_val in entries2:
				if not (e2_val is Dictionary):
					continue
				var e2: Dictionary = e2_val
				var si := int(e2.get("step_index", -999))
				if si < 0:
					continue
				if not entries_by_step.has(si):
					entries_by_step[si] = []
				(entries_by_step[si] as Array).append(e2)

			var steps_val2 = timeline.get("steps", null)
			if not (steps_val2 is Array):
				return Result.failure("step_timeline.steps missing/invalid for dinnertime save: %s" % res_path)
			var steps2: Array = steps_val2
			for si2 in range(steps2.size()):
				var step_val2 = steps2[si2]
				if not (step_val2 is Dictionary):
					continue
				var step2: Dictionary = step_val2
				if str(step2.get("kind", "")).strip_edges() != "command":
					continue
				var action_id := str(step2.get("action_id", "")).strip_edges()
				if action_id not in ["skip", "end_turn", "skip_sub_phase", "advance_phase"]:
					continue
				var step_entries2: Array = entries_by_step.get(si2, [])
				var header := GameLogUnifiedTimelineBuilderClass._build_action_group_header_data(si2, step2, step_entries2, false)
				if not (header is Dictionary):
					return Result.failure("action_group header data type invalid for flow command step: step=%d (%s)" % [si2, res_path])
				var primary_id := int(Dictionary(header).get("primary_entry_id", -2))
				if primary_id != -1:
					return Result.failure("expected flow command ActionGroup to have no primary entry (primary_entry_id=-1), got %d: step=%d action_id=%s (%s)" % [
						primary_id, si2, action_id, res_path
					])

	# Avoid polluting subsequent tests with history from a replay-loaded archive.
	_clear_event_history()

	return Result.success({})

static func _verify_payday_details_after_interaction(engine: GameEngine, res_path: String) -> Result:
	if engine == null:
		return Result.failure("payday details verification: engine is null (%s)" % res_path)

	var safety := 0
	while str(engine.get_state().phase) == "Payday":
		safety += 1
		if safety > engine.get_state().players.size() + 4:
			return Result.failure("payday details verification exceeded skip safety limit: %s" % res_path)
		var actor := int(engine.get_state().get_current_player_id())
		var sk := engine.execute_command(Command.create("skip", actor))
		if not sk.ok:
			return Result.failure("payday details verification skip failed: %s (%s)" % [sk.error, res_path])

	var payday_events: Array = EventBus.get_history_by_type(EventBus.EventType.PAYDAY_REPORT)
	if payday_events.is_empty():
		return Result.failure("expected PAYDAY_REPORT after completing payday save interaction: %s" % res_path)

	var enriched := false
	for ev_val in payday_events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var data_val = ev.get("data", null)
		if not (data_val is Dictionary):
			continue
		var data: Dictionary = data_val
		var report_val = data.get("report", null)
		if not (report_val is Dictionary):
			continue
		var report: Dictionary = report_val
		var details_val = report.get("details", null)
		if not (details_val is Array):
			continue
		for item_val in Array(details_val):
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			if int(item.get("player_id", -1)) != 0:
				continue
			var employees_val = item.get("employees", null)
			if not (employees_val is Array) or Array(employees_val).is_empty():
				continue
			var discount_sources_val = item.get("salary_discount_sources", null)
			var milestone_adjustments_val = item.get("milestone_salary_adjustments", null)
			if not (discount_sources_val is Array) or Array(discount_sources_val).is_empty():
				return Result.failure("PAYDAY_REPORT missing salary_discount_sources for player 1: %s" % res_path)
			if not (milestone_adjustments_val is Array) or Array(milestone_adjustments_val).is_empty():
				return Result.failure("PAYDAY_REPORT missing milestone_salary_adjustments for player 1: %s" % res_path)
			enriched = true
			break
		if enriched:
			break
	if not enriched:
		return Result.failure("PAYDAY_REPORT should include enriched per-employee payday details for player 1: %s" % res_path)

	var timeline_r: Result = StepTimelineBuildClass.build_full(engine)
	if not timeline_r.ok:
		return Result.failure("step_timeline build failed for payday details save: %s (%s)" % [timeline_r.error, res_path])
	if not (timeline_r.value is Dictionary):
		return Result.failure("step_timeline build returned non-Dictionary for payday details save: %s" % res_path)
	var timeline: Dictionary = timeline_r.value
	var events_val = timeline.get("events", null)
	if not (events_val is Array):
		return Result.failure("step_timeline.events missing/invalid for payday details save: %s" % res_path)

	var entries: Array[Dictionary] = GameTimelineLogEntriesBuilderClass.build(Array(events_val))
	var payday_entry_count := 0
	var text := ""
	for entry_val in entries:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if str(entry.get("event_type", "")).strip_edges() != EventBus.EventType.PAYDAY_REPORT:
			continue
		payday_entry_count += 1
		if bool(entry.get("is_stage_event", true)):
			return Result.failure("PAYDAY_REPORT entries must be visible by default, not stage events: %s" % res_path)
		text += str(entry.get("message", "")) + "\n"

	if payday_entry_count < 2:
		return Result.failure("expected per-player PAYDAY_REPORT log entries in timeline, got %d: %s" % [payday_entry_count, res_path])
	if not text.contains("发薪日"):
		return Result.failure("payday log text missing 发薪日: %s" % res_path)
	if not text.contains("薪资人员："):
		return Result.failure("payday log text missing 薪资人员 section: %s" % res_path)
	if not text.contains("薪资基数："):
		return Result.failure("payday log text missing 薪资基数 section: %s" % res_path)
	if not text.contains("减免："):
		return Result.failure("payday log text missing 减免 section: %s" % res_path)
	if not text.contains("最终支付："):
		return Result.failure("payday log text missing 最终支付 section: %s" % res_path)
	if not (text.contains("人力资源总监") or text.contains("hr_director")):
		return Result.failure("payday log text missing hr_director detail: %s" % res_path)
	if not (text.contains("营销经理") or text.contains("campaign_manager")):
		return Result.failure("payday log text missing campaign_manager detail: %s" % res_path)
	if not text.contains("招聘折扣"):
		return Result.failure("payday log text missing salary discount detail: %s" % res_path)
	if not text.contains("里程碑调整"):
		return Result.failure("payday log text missing milestone adjustment detail: %s" % res_path)
	if not text.contains("免薪"):
		return Result.failure("payday log text missing waived salary detail in reduction summary: %s" % res_path)

	return Result.success({})

static func _clear_event_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()
