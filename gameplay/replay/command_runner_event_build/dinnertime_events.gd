# CommandRunnerEventBuild：Dinnertime 事件拆分
# 用途：从 dinnertime 报告中拆分细粒度售卖事件（日志/展示语义）。
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func build_dinnertime_report_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if str(new_state.phase) != DefsClass.PHASE_DINNERTIME:
		return events
	if str(old_state.phase) == str(new_state.phase):
		return events

	var report: Dictionary = {}
	if new_state.round_state is Dictionary:
		var v = Dictionary(new_state.round_state).get("dinnertime", null)
		if v is Dictionary:
			report = Dictionary(v).duplicate(true)
	events.append({
		"type": EventBus.EventType.DINNERTIME_REPORT,
		"data": {
			"round": new_state.round_number,
			"from_phase": str(old_state.phase),
			"to_phase": str(new_state.phase),
			"report": report,
		}
	})
	events.append_array(build_food_sold_events_from_dinnertime_report(new_state, report))
	return events

static func build_food_sold_events_from_dinnertime_report(dinnertime_state: GameState, report: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if dinnertime_state == null:
		return out
	if report == null or not (report is Dictionary):
		return out

	var sales_val = Dictionary(report).get("sales", null)
	if not (sales_val is Array):
		return out
	var round := int(dinnertime_state.round_number)

	for s_val in Array(sales_val):
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var player_id := int(s.get("winner_owner", -1))
		if player_id < 0:
			continue

		var required: Dictionary = {}
		var required_val = s.get("required", null)
		if required_val is Dictionary:
			required = Dictionary(required_val).duplicate(true)

		var house_bonus_breakdown: Dictionary = {}
		var hb_breakdown_val = s.get("house_bonus_breakdown", null)
		if hb_breakdown_val is Dictionary:
			house_bonus_breakdown = Dictionary(hb_breakdown_val).duplicate(true)

		out.append({
			"type": EventBus.EventType.FOOD_SOLD,
			"data": {
				"round": round,
				"player_id": player_id,
				"house_id": str(s.get("house_id", "")).strip_edges(),
				"house_number": s.get("house_number", null),
				"restaurant_id": str(s.get("winner_restaurant_id", "")).strip_edges(),
				"required": required,
				"revenue": int(s.get("revenue", 0)),
				"bonus": int(s.get("bonus", 0)),
				"house_bonus": int(s.get("house_bonus", 0)),
				"house_bonus_breakdown": house_bonus_breakdown,
			}
		})

	return out
