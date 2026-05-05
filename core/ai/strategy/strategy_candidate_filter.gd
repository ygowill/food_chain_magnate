class_name StrategyCandidateFilter
extends RefCounted

static func filter_candidates(observation: ObservationState, candidates: Array, profile) -> Dictionary:
	var kept: Array[MacroAction] = []
	var discarded: Array[String] = []
	var stats := {
		"input_count": candidates.size(),
		"kept_count": 0,
		"discarded_count": 0,
		"discarded_marketing_no_affected_houses": 0,
	}
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			discarded.append("strategy_filter: candidate is not MacroAction")
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			discarded.append("%s: strategy_filter empty command list" % macro.id)
			continue
		var command: Command = macro.commands[0]
		if command == null:
			discarded.append("%s: strategy_filter null command" % macro.id)
			continue
		var discard_reason := _discard_reason(observation, macro, command, profile)
		if not discard_reason.is_empty():
			discarded.append(discard_reason)
			if discard_reason.find("affects no houses") >= 0:
				stats["discarded_marketing_no_affected_houses"] = int(stats["discarded_marketing_no_affected_houses"]) + 1
			continue
		kept.append(macro)

	stats["kept_count"] = kept.size()
	stats["discarded_count"] = discarded.size()
	return {
		"candidates": kept,
		"discarded_reasons": discarded,
		"stats": stats,
	}

static func _discard_reason(_observation: ObservationState, macro: MacroAction, command: Command, profile) -> String:
	if macro == null or command == null:
		return "strategy_filter: invalid candidate"
	if str(command.action_id) == "initiate_marketing" and _strict_marketing_must_affect_houses(profile):
		if macro.debug.has("affected_house_ids"):
			var affected_val = macro.debug.get("affected_house_ids", [])
			if not (affected_val is Array):
				return "%s: strategy_filter affected_house_ids is not Array" % macro.id
			if Array(affected_val).is_empty():
				return "%s: strategy_filter affects no houses" % macro.id
	return ""

static func _strict_marketing_must_affect_houses(profile) -> bool:
	if profile == null:
		return true
	if profile.get("strict_marketing_must_affect_houses") != null:
		return bool(profile.strict_marketing_must_affect_houses)
	return true
