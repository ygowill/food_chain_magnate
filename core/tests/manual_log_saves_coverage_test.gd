# Manual logs archives coverage test
# Covers issue_tracker #50: provide multiple themed manual saves to review log rendering.
class_name ManualLogSavesCoverageTest
extends RefCounted

const CASES: Array[Dictionary] = [
	{
		"path": "res://.savings/manual_cases/logs/event_log_review.json",
		"required_types": [
			EventBus.EventType.MARKETING_PLACED,
			EventBus.EventType.DEMAND_GENERATED,
			EventBus.EventType.DRINKS_PROCURED,
		],
	},
	{
		"path": "res://.savings/manual_cases/logs/event_log_employee_recruit_train.json",
		"required_types": [
			EventBus.EventType.EMPLOYEE_RECRUITED,
			EventBus.EventType.EMPLOYEE_TRAINED,
		],
		"required_commands": ["set_price"],
	},
	{
		"path": "res://.savings/manual_cases/logs/event_log_employee_fire.json",
		"required_types": [
			EventBus.EventType.EMPLOYEE_FIRED,
		],
	},
	{
		"path": "res://.savings/manual_cases/logs/event_log_build_and_move.json",
		"required_types": [
			EventBus.EventType.HOUSE_PLACED,
			EventBus.EventType.GARDEN_ADDED,
			EventBus.EventType.RESTAURANT_PLACED,
			EventBus.EventType.RESTAURANT_MOVED,
		],
	},
	{
		"path": "res://.savings/manual_cases/logs/event_log_produce_and_cleanup.json",
		"required_types": [
			EventBus.EventType.FOOD_PRODUCED,
			EventBus.EventType.FOOD_DISCARDED,
		],
	},
	{
		"path": "res://.savings/manual_cases/logs/event_log_dinnertime_sale.json",
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

	# Avoid polluting subsequent tests with history from a replay-loaded archive.
	_clear_event_history()

	return Result.success({})

static func _clear_event_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()
