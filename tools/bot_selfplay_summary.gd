class_name BotSelfplaySummary
extends RefCounted

const PLAYER_METRIC_KEYS := {
	"player_cash": "cash",
	"player_employees": "employees",
	"player_inventory_units": "inventory_units",
	"player_milestones": "milestones",
	"player_restaurants": "restaurants",
}

static func read_jsonl(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("cannot open JSONL file: %s" % path)
	var rows: Array[Dictionary] = []
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_number += 1
		if line.strip_edges().is_empty():
			continue
		var parser := JSON.new()
		var err := parser.parse(line)
		if err != OK:
			return Result.failure("%s:%d invalid JSON: %s" % [path, line_number, parser.get_error_message()])
		if not (parser.data is Dictionary):
			return Result.failure("%s:%d expected JSON object row" % [path, line_number])
		rows.append(parser.data)
	return Result.success(rows)

static func summarize_files(paths: Array[String]) -> Result:
	if paths.is_empty():
		return Result.failure("at least one --input path is required")
	var rows: Array[Dictionary] = []
	for path in paths:
		var read := read_jsonl(path)
		if not read.ok:
			return read
		for row in read.value:
			rows.append(row)
	var summary_read := summarize_rows(rows)
	if not summary_read.ok:
		return summary_read
	var summary: Dictionary = summary_read.value
	summary["files"] = paths.duplicate()
	return Result.success(summary)

static func summarize_rows(rows: Array[Dictionary]) -> Result:
	if rows.is_empty():
		return Result.failure("no JSONL rows to summarize")
	var overall := _new_bucket("all")
	var by_bot := {}
	for row in rows:
		var bot := _row_group_id(row)
		if bot.is_empty():
			bot = "unknown"
		if not by_bot.has(bot):
			by_bot[bot] = _new_bucket(bot)
		_add_row(by_bot[bot], row)
		_add_row(overall, row)

	var bots := {}
	var bot_names := by_bot.keys()
	bot_names.sort()
	for bot_name in bot_names:
		bots[bot_name] = _finalize_bucket(by_bot[bot_name])

	var overall_summary := _finalize_bucket(overall)
	return Result.success({
		"total_matches": int(overall_summary.get("matches", 0)),
		"total_failures": int(overall_summary.get("failures", 0)),
		"bots": bots,
		"overall": overall_summary,
	})

static func _row_group_id(row: Dictionary) -> String:
	var config := str(row.get("bot_config", "")).strip_edges()
	if not config.is_empty():
		return config
	return str(row.get("bot", "unknown")).strip_edges()

static func format_summary(summary: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var bots_val = summary.get("bots", {})
	var bots: Dictionary = bots_val if bots_val is Dictionary else {}
	lines.append("[BotSelfplaySummary] SUMMARY matches=%d failures=%d bots=%d" % [
		int(summary.get("total_matches", 0)),
		int(summary.get("total_failures", 0)),
		bots.size(),
	])
	var bot_names := bots.keys()
	bot_names.sort()
	for bot_name in bot_names:
		var bot_val = bots[bot_name]
		if not (bot_val is Dictionary):
			continue
		var bot: Dictionary = bot_val
		lines.append("[BotSelfplaySummary] BOT %s matches=%d ok=%d failures=%d success=%.3f avg_round=%.3f avg_steps=%.3f avg_commands=%.3f seeds=%s" % [
			str(bot_name),
			int(bot.get("matches", 0)),
			int(bot.get("ok_matches", 0)),
			int(bot.get("failures", 0)),
			float(bot.get("success_rate", 0.0)),
			float(bot.get("avg_round", 0.0)),
			float(bot.get("avg_steps", 0.0)),
			float(bot.get("avg_command_count", 0.0)),
			_format_seed_range(bot),
		])
		var actions_val = bot.get("action_totals", {})
		var actions: Dictionary = actions_val if actions_val is Dictionary else {}
		lines.append("[BotSelfplaySummary] ACTIONS %s %s" % [str(bot_name), _format_actions(actions)])
		var players_val = bot.get("players", {})
		var players: Dictionary = players_val if players_val is Dictionary else {}
		if not players.is_empty():
			lines.append("[BotSelfplaySummary] PLAYERS %s %s" % [str(bot_name), _format_player_metrics(players)])
	return lines

static func _new_bucket(label: String) -> Dictionary:
	return {
		"label": label,
		"matches": 0,
		"ok_matches": 0,
		"failures": 0,
		"failed_seeds": [],
		"seeds": [],
		"round_sum": 0.0,
		"steps_sum": 0.0,
		"command_count_sum": 0.0,
		"action_totals": {},
		"player_metrics": {},
	}

static func _add_row(bucket: Dictionary, row: Dictionary) -> void:
	bucket["matches"] = int(bucket.get("matches", 0)) + 1
	if bool(row.get("ok", false)):
		bucket["ok_matches"] = int(bucket.get("ok_matches", 0)) + 1
	else:
		bucket["failures"] = int(bucket.get("failures", 0)) + 1
		if row.has("seed"):
			bucket["failed_seeds"].append(int(row.get("seed", 0)))
	if row.has("seed"):
		bucket["seeds"].append(int(row.get("seed", 0)))
	bucket["round_sum"] = float(bucket.get("round_sum", 0.0)) + float(row.get("round", 0.0))
	bucket["steps_sum"] = float(bucket.get("steps_sum", 0.0)) + float(row.get("steps", 0.0))
	bucket["command_count_sum"] = float(bucket.get("command_count_sum", 0.0)) + float(row.get("command_count", 0.0))

	var actions_val = row.get("action_counts", {})
	if actions_val is Dictionary:
		var action_totals: Dictionary = bucket["action_totals"]
		for action_id_val in Dictionary(actions_val).keys():
			var action_id := str(action_id_val)
			action_totals[action_id] = int(action_totals.get(action_id, 0)) + int(Dictionary(actions_val).get(action_id_val, 0))

	var player_metrics: Dictionary = bucket["player_metrics"]
	for row_key in PLAYER_METRIC_KEYS.keys():
		var metric_name := str(PLAYER_METRIC_KEYS[row_key])
		var values_val = row.get(row_key, [])
		if values_val is Array:
			if not player_metrics.has(metric_name):
				player_metrics[metric_name] = _new_player_metric()
			_add_player_metric(player_metrics[metric_name], values_val)

static func _new_player_metric() -> Dictionary:
	return {
		"sum": [],
		"min": [],
		"max": [],
		"counts": [],
	}

static func _add_player_metric(metric: Dictionary, values: Array) -> void:
	var sums: Array = metric["sum"]
	var mins: Array = metric["min"]
	var maxs: Array = metric["max"]
	var counts: Array = metric["counts"]
	for i in range(values.size()):
		_ensure_size(sums, i + 1, 0.0)
		_ensure_size(mins, i + 1, 0.0)
		_ensure_size(maxs, i + 1, 0.0)
		_ensure_size(counts, i + 1, 0)
		var value := float(values[i])
		var old_count := int(counts[i])
		sums[i] = float(sums[i]) + value
		counts[i] = old_count + 1
		if old_count == 0:
			mins[i] = value
			maxs[i] = value
		else:
			mins[i] = minf(float(mins[i]), value)
			maxs[i] = maxf(float(maxs[i]), value)

static func _ensure_size(values: Array, size: int, fill_value) -> void:
	while values.size() < size:
		values.append(fill_value)

static func _finalize_bucket(bucket: Dictionary) -> Dictionary:
	var matches := int(bucket.get("matches", 0))
	var out := {
		"bot": str(bucket.get("label", "")),
		"matches": matches,
		"ok_matches": int(bucket.get("ok_matches", 0)),
		"failures": int(bucket.get("failures", 0)),
		"success_rate": _ratio(float(bucket.get("ok_matches", 0)), float(matches)),
		"avg_round": _avg(float(bucket.get("round_sum", 0.0)), matches),
		"avg_steps": _avg(float(bucket.get("steps_sum", 0.0)), matches),
		"avg_command_count": _avg(float(bucket.get("command_count_sum", 0.0)), matches),
		"failed_seeds": _sorted_int_array(bucket.get("failed_seeds", [])),
		"action_totals": _sorted_dict(bucket.get("action_totals", {})),
		"action_avg_per_match": _action_averages(bucket.get("action_totals", {}), matches),
		"players": _finalize_player_metrics(bucket.get("player_metrics", {})),
	}
	var seeds := _sorted_int_array(bucket.get("seeds", []))
	if not seeds.is_empty():
		out["seed_min"] = int(seeds.front())
		out["seed_max"] = int(seeds.back())
	return out

static func _finalize_player_metrics(metrics_val) -> Dictionary:
	var metrics: Dictionary = metrics_val if metrics_val is Dictionary else {}
	var out := {}
	var names := metrics.keys()
	names.sort()
	for name in names:
		var metric_val = metrics[name]
		if not (metric_val is Dictionary):
			continue
		var metric: Dictionary = metric_val
		out[name] = {
			"avg": _metric_average_array(metric),
			"min": _round_array(metric.get("min", [])),
			"max": _round_array(metric.get("max", [])),
		}
	return out

static func _metric_average_array(metric: Dictionary) -> Array[float]:
	var sums_val = metric.get("sum", [])
	var counts_val = metric.get("counts", [])
	var sums: Array = sums_val if sums_val is Array else []
	var counts: Array = counts_val if counts_val is Array else []
	var out: Array[float] = []
	for i in range(sums.size()):
		var count := int(counts[i]) if i < counts.size() else 0
		out.append(_avg(float(sums[i]), count))
	return out

static func _round_array(values_val) -> Array[float]:
	var values: Array = values_val if values_val is Array else []
	var out: Array[float] = []
	for value in values:
		out.append(_round3(float(value)))
	return out

static func _action_averages(actions_val, matches: int) -> Dictionary:
	var actions: Dictionary = actions_val if actions_val is Dictionary else {}
	var out := {}
	var keys := actions.keys()
	keys.sort()
	for key in keys:
		out[str(key)] = _avg(float(actions[key]), matches)
	return out

static func _sorted_dict(value) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var out := {}
	var keys := source.keys()
	keys.sort()
	for key in keys:
		out[str(key)] = int(source[key])
	return out

static func _sorted_int_array(value) -> Array[int]:
	var source: Array = value if value is Array else []
	var out: Array[int] = []
	for item in source:
		out.append(int(item))
	out.sort()
	return out

static func _avg(sum: float, count: int) -> float:
	if count <= 0:
		return 0.0
	return _round3(sum / float(count))

static func _ratio(numerator: float, denominator: float) -> float:
	if denominator <= 0.0:
		return 0.0
	return _round3(numerator / denominator)

static func _round3(value: float) -> float:
	return round(value * 1000.0) / 1000.0

static func _format_seed_range(bot: Dictionary) -> String:
	if bot.has("seed_min") and bot.has("seed_max"):
		return "%d-%d" % [int(bot.get("seed_min", 0)), int(bot.get("seed_max", 0))]
	return "n/a"

static func _format_actions(actions: Dictionary) -> String:
	if actions.is_empty():
		return "{}"
	var parts: Array[String] = []
	var keys := actions.keys()
	keys.sort()
	for key in keys:
		parts.append("%s=%d" % [str(key), int(actions[key])])
	return " ".join(parts)

static func _format_player_metrics(players: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["cash", "employees", "inventory_units", "milestones", "restaurants"]:
		if not players.has(key):
			continue
		var metric_val = players[key]
		if not (metric_val is Dictionary):
			continue
		var metric: Dictionary = metric_val
		parts.append("%s_avg=%s" % [key, str(metric.get("avg", []))])
	return " ".join(parts)
