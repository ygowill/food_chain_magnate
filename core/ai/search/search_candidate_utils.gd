class_name SearchCandidateUtils
extends RefCounted

static func dedupe_scored_candidates(scored: Array[Dictionary]) -> Dictionary:
	var kept: Array[Dictionary] = []
	var seen: Dictionary = {}
	var deduped_count := 0
	for entry_val in scored:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_val)
		var signature := scored_candidate_signature(entry)
		if signature.is_empty():
			kept.append(entry)
			continue
		if not seen.has(signature):
			seen[signature] = kept.size()
			kept.append(entry)
			continue
		deduped_count += 1
		var existing_index := int(seen.get(signature, -1))
		if existing_index < 0 or existing_index >= kept.size():
			continue
		var existing: Dictionary = Dictionary(kept[existing_index])
		if scored_candidate_is_better(entry, existing):
			kept[existing_index] = entry
	return {
		"scored": kept,
		"deduped_count": deduped_count,
	}

static func copy_scored_candidates(value) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for item in Array(value):
			if item is Dictionary:
				out.append(Dictionary(item))
	return out

static func scored_candidate_signature(entry: Dictionary) -> String:
	var macro: MacroAction = entry.get("macro", null)
	if macro != null:
		return macro_signature(macro)
	var action_id := str(entry.get("action_id", ""))
	if action_id.is_empty():
		return ""
	var params_val = entry.get("params", {})
	var params := Dictionary(params_val).duplicate(true) if params_val is Dictionary else {}
	return _canonical_json([{
		"action_id": action_id,
		"actor": int(entry.get("actor", -1)),
		"params": params,
	}])

static func macro_signature(macro: MacroAction) -> String:
	if macro == null or macro.commands.is_empty():
		return ""
	var commands: Array = []
	for command in macro.commands:
		if command == null:
			continue
		commands.append({
			"action_id": str(command.action_id),
			"actor": int(command.actor),
			"params": command.params.duplicate(true),
		})
	if commands.is_empty():
		return ""
	return _canonical_json(commands)

static func scored_candidate_is_better(candidate: Dictionary, existing: Dictionary) -> bool:
	var candidate_score := float(candidate.get("strategy_score", -INF))
	var existing_score := float(existing.get("strategy_score", -INF))
	if not is_equal_approx(candidate_score, existing_score):
		return candidate_score > existing_score
	return _macro_action_id(candidate) < _macro_action_id(existing)

static func _macro_action_id(entry: Dictionary) -> String:
	var macro_id := str(entry.get("macro_action_id", ""))
	if not macro_id.is_empty():
		return macro_id
	var macro: MacroAction = entry.get("macro", null)
	return str(macro.id) if macro != null else ""

static func _canonical_json(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict: Dictionary = Dictionary(value)
			var keys: Array = dict.keys()
			keys.sort()
			var parts: Array[String] = []
			for key in keys:
				var key_str := str(key)
				parts.append("%s:%s" % [JSON.stringify(key_str), _canonical_json(dict.get(key, null))])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var arr: Array = Array(value)
			var parts2: Array[String] = []
			for item in arr:
				parts2.append(_canonical_json(item))
			return "[%s]" % ",".join(parts2)
		_:
			return JSON.stringify(value)
