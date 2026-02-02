# GameLogPanel：日志 entry 字段解析工具
extends RefCounted

static func get_entry_command_index(entry: Dictionary) -> int:
	if entry == null or entry.is_empty():
		return -999
	var ci_val = entry.get("command_index", null)
	if ci_val is int:
		return int(ci_val)
	if ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			return int(f)
	var details_val = entry.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var ci2_val = details.get("command_index", null)
		if ci2_val is int:
			return int(ci2_val)
		if ci2_val is float:
			var f2: float = float(ci2_val)
			if f2 == floor(f2):
				return int(f2)
	return -999

static func get_entry_step_index(entry: Dictionary) -> int:
	if entry == null or entry.is_empty():
		return -999
	var si_val = entry.get("step_index", null)
	if si_val is int:
		return int(si_val)
	if si_val is float:
		var f: float = float(si_val)
		if f == floor(f):
			return int(f)
	var details_val = entry.get("details", null)
	if details_val is Dictionary:
		var details: Dictionary = details_val
		var si2_val = details.get("step_index", null)
		if si2_val is int:
			return int(si2_val)
		if si2_val is float:
			var f2: float = float(si2_val)
			if f2 == floor(f2):
				return int(f2)
	return -999

static func get_entry_timeline_index(entry: Dictionary) -> int:
	# 优先 step_index（M4.2：大阶段可步进），否则回退到 command_index（旧命令时间线）。
	var si := get_entry_step_index(entry)
	return si if si != -999 else get_entry_command_index(entry)

static func entry_is_stage_event(entry: Dictionary) -> bool:
	if entry == null or entry.is_empty():
		return false
	if entry.has("is_stage_event"):
		return bool(entry.get("is_stage_event", false))
	var t := str(entry.get("event_type", "")).strip_edges()
	if t.is_empty():
		var details_val = entry.get("details", null)
		if details_val is Dictionary:
			t = str(Dictionary(details_val).get("event_type", "")).strip_edges()
	if t.is_empty():
		return false
	if t.ends_with("_report"):
		return true
	return t in ["phase_changed", "sub_phase_changed", "round_started", "round_ended"]

static func format_details_for_view(details) -> String:
	if details == null:
		return ""
	# Prefer JSON when possible, fallback to var_to_str for non-JSON variants (Vector2i, Color...).
	if details is Dictionary or details is Array:
		var json := JSON.stringify(details, "\t")
		if not json.is_empty() and json != "null":
			return json
	return var_to_str(details)

