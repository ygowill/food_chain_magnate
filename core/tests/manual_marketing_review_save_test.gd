class_name ManualMarketingReviewSaveTest
extends RefCounted

const SAVE_PATH := "res://testdata/saves/manual_cases/marketing/marketing_phase_animation_review.json"

static func run() -> Result:
	var engine := GameEngine.new()
	var load_r := engine.load_from_file(ProjectSettings.globalize_path(SAVE_PATH))
	if not load_r.ok:
		return Result.failure("load manual marketing review save failed: %s" % load_r.error)

	var state := engine.get_state()
	if state == null:
		return Result.failure("loaded state is null")
	if str(state.phase) != "Marketing":
		return Result.failure("expected Marketing phase, got: %s" % str(state.phase))

	var tile_placements_val = state.map.get("tile_placements", null) if (state.map is Dictionary) else null
	if not (tile_placements_val is Array) or (tile_placements_val as Array).is_empty():
		return Result.failure("manual marketing save must keep real map tile_placements for UI rendering")

	var pending_read := _validate_marketing_pending(state)
	if not pending_read.ok:
		return pending_read

	var placements_read := _validate_marketing_placements(state)
	if not placements_read.ok:
		return placements_read

	var report_read := _validate_marketing_report(state)
	if not report_read.ok:
		return report_read

	return Result.success()

static func _validate_marketing_pending(state: GameState) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("round_state missing")
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions missing")
	var ppa: Dictionary = ppa_val
	var marketing_val = ppa.get("Marketing", null)
	if not (marketing_val is Array):
		return Result.failure("pending_phase_actions.Marketing missing")
	var marketing_pending: Array = marketing_val
	if not marketing_pending.has("confirm_marketing"):
		return Result.failure("pending_phase_actions.Marketing must include confirm_marketing")
	return Result.success()

static func _validate_marketing_placements(state: GameState) -> Result:
	var placements_val = state.map.get("marketing_placements", null) if (state.map is Dictionary) else null
	if not (placements_val is Dictionary):
		return Result.failure("marketing_placements missing")
	var placements: Dictionary = placements_val
	var expected := {
		"1": "radio",
		"6": "airplane",
		"7": "mailbox",
		"14": "billboard",
	}
	for key in expected.keys():
		if not placements.has(key):
			return Result.failure("marketing_placements missing board #%s" % key)
		if not (placements[key] is Dictionary):
			return Result.failure("marketing_placements[%s] is not Dictionary" % key)
		var p: Dictionary = placements[key]
		if str(p.get("type", "")) != str(expected[key]):
			return Result.failure("marketing_placements[%s].type mismatch: %s" % [key, str(p.get("type", ""))])
		if int(p.get("remaining_duration", 0)) <= 0:
			return Result.failure("marketing_placements[%s] must remain visible, duration=%s" % [key, str(p.get("remaining_duration", null))])
	return Result.success()

static func _validate_marketing_report(state: GameState) -> Result:
	var report_val = state.round_state.get("marketing", null) if (state.round_state is Dictionary) else null
	if not (report_val is Dictionary):
		return Result.failure("round_state.marketing missing")
	var report: Dictionary = report_val
	var events_val = report.get("timeline_events", null)
	if not (events_val is Array) or (events_val as Array).is_empty():
		return Result.failure("round_state.marketing.timeline_events missing")

	var processed_val = report.get("processed", null)
	if not (processed_val is Array):
		return Result.failure("round_state.marketing.processed missing")
	var processed: Array = processed_val
	for board_number in [1, 6, 7, 14]:
		var found := false
		for item_val in processed:
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			if int(item.get("board_number", 0)) != int(board_number):
				continue
			found = true
			var affected_val = item.get("affected_houses", null)
			if not (affected_val is Array) or (affected_val as Array).is_empty():
				return Result.failure("processed board #%d has no affected_houses" % board_number)
			var min_count := 1
			if board_number == 1 or board_number == 6:
				min_count = 4
			if (affected_val as Array).size() < min_count:
				return Result.failure("processed board #%d should affect at least %d houses for manual animation review, actual=%d" % [board_number, min_count, (affected_val as Array).size()])
			break
		if not found:
			return Result.failure("processed missing board #%d" % board_number)
	return Result.success()
