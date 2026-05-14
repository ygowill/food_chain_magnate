class_name BotSelfplaySummary
extends RefCounted

const PLAYER_METRIC_KEYS := {
	"player_cash": "cash",
	"player_cash_min_seen": "cash_min_seen",
	"player_cash_min_after_first_positive": "cash_min_after_first_positive",
	"player_cash_max_seen": "cash_max_seen",
	"player_employees": "employees",
	"player_inventory_units": "inventory_units",
	"player_milestones": "milestones",
	"player_restaurants": "restaurants",
}

const TUNING_OBJECTIVE_WEIGHTS := {
	"success_rate": 1000.0,
	"avg_round": 20.0,
	"cash_avg": 1.0,
	"cash_min_after_first_positive_avg": 5.0,
	"cash_max_seen_avg": 1.0,
	"inventory_units_avg": -0.25,
	"milestones_avg_per_match": 10.0,
	"opening_players_without_positive_cash_avg": -120.0,
	"opening_first_positive_cash_round_avg": -20.0,
	"opening_first_positive_cash_step_avg": -0.05,
	"opening_food_recruit_to_produce_round_delay_avg": -25.0,
	"opening_food_recruit_to_produce_step_delay_avg": -0.1,
	"pre_revenue_errand_boy_recruit_avg": -80.0,
	"pre_revenue_pricing_manager_recruit_avg": -60.0,
	"pre_revenue_procure_drinks_avg": -80.0,
	"avg_command_count": -0.25,
}

const OPENING_SCALAR_KEYS := [
	"pre_revenue_recruit_count",
	"pre_revenue_errand_boy_recruit_count",
	"pre_revenue_pricing_manager_recruit_count",
	"pre_revenue_procure_drinks_count",
]

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
	var comparison := _build_comparison(bots)
	return Result.success({
		"total_matches": int(overall_summary.get("matches", 0)),
		"total_failures": int(overall_summary.get("failures", 0)),
		"total_timeouts": int(overall_summary.get("timeout_matches", 0)),
		"bots": bots,
		"overall": overall_summary,
		"comparison": comparison,
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
	lines.append("[BotSelfplaySummary] SUMMARY matches=%d failures=%d timeouts=%d bots=%d" % [
		int(summary.get("total_matches", 0)),
		int(summary.get("total_failures", 0)),
		int(summary.get("total_timeouts", 0)),
		bots.size(),
	])
	var bot_names := bots.keys()
	bot_names.sort()
	for bot_name in bot_names:
		var bot_val = bots[bot_name]
		if not (bot_val is Dictionary):
			continue
		var bot: Dictionary = bot_val
		lines.append("[BotSelfplaySummary] BOT %s matches=%d ok=%d failures=%d timeouts=%d success=%.3f avg_round=%.3f avg_steps=%.3f avg_commands=%.3f seeds=%s" % [
			str(bot_name),
			int(bot.get("matches", 0)),
			int(bot.get("ok_matches", 0)),
			int(bot.get("failures", 0)),
			int(bot.get("timeout_matches", 0)),
			float(bot.get("success_rate", 0.0)),
			float(bot.get("avg_round", 0.0)),
			float(bot.get("avg_steps", 0.0)),
			float(bot.get("avg_command_count", 0.0)),
			_format_seed_range(bot),
		])
		var actions_val = bot.get("action_totals", {})
		var actions: Dictionary = actions_val if actions_val is Dictionary else {}
		lines.append("[BotSelfplaySummary] ACTIONS %s %s" % [str(bot_name), _format_actions(actions)])
		var mandatory_val = bot.get("mandatory_completion_totals", {})
		var mandatory: Dictionary = mandatory_val if mandatory_val is Dictionary else {}
		if not mandatory.is_empty():
			lines.append("[BotSelfplaySummary] MANDATORY %s %s" % [str(bot_name), _format_actions(mandatory)])
		var untraced_val = bot.get("untraced_mandatory_completion_totals", {})
		var untraced: Dictionary = untraced_val if untraced_val is Dictionary else {}
		if not untraced.is_empty():
			lines.append("[BotSelfplaySummary] UNTRACED_MANDATORY %s %s" % [str(bot_name), _format_actions(untraced)])
		var milestones_val = bot.get("milestone_counts", {})
		var milestones: Dictionary = milestones_val if milestones_val is Dictionary else {}
		if not milestones.is_empty():
			lines.append("[BotSelfplaySummary] MILESTONES %s %s" % [str(bot_name), _format_actions(milestones)])
		var players_val = bot.get("players", {})
		var players: Dictionary = players_val if players_val is Dictionary else {}
		if not players.is_empty():
			lines.append("[BotSelfplaySummary] PLAYERS %s %s" % [str(bot_name), _format_player_metrics(players)])
		var opening_val = bot.get("opening", {})
		var opening: Dictionary = opening_val if opening_val is Dictionary else {}
		if not opening.is_empty():
			lines.append("[BotSelfplaySummary] OPENING %s positive_cash_avg=%.3f no_positive_cash_avg=%.3f first_positive_round_avg=%.3f first_positive_step_avg=%.3f food_delay_round_avg=%.3f food_delay_step_avg=%.3f pre_revenue_actions=%s pre_revenue_recruits=%s scalars=%s" % [
				str(bot_name),
				float(opening.get("players_with_positive_cash_avg_per_match", 0.0)),
				float(opening.get("players_without_positive_cash_avg_per_match", 0.0)),
				float(opening.get("first_positive_cash_round_avg", 0.0)),
				float(opening.get("first_positive_cash_step_avg", 0.0)),
				float(opening.get("food_recruit_to_produce_round_delay_avg", 0.0)),
				float(opening.get("food_recruit_to_produce_step_delay_avg", 0.0)),
				_format_numeric_dict(Dictionary(opening.get("pre_revenue_action_avg_per_match", {}))),
				_format_numeric_dict(Dictionary(opening.get("pre_revenue_recruit_avg_per_match", {}))),
				_format_numeric_dict(Dictionary(opening.get("scalar_avg_per_match", {}))),
			])
		var search: Dictionary = Dictionary(bot.get("search", {}))
		if int(search.get("decision_count_total", 0)) > 0:
			var search_line := "[BotSelfplaySummary] SEARCH %s decisions=%d budget_expired=%d expired_rate=%.3f time_ms_avg=%.3f time_ms_max=%d attempted_avg=%.3f expanded_avg=%.3f" % [
				str(bot_name),
				int(search.get("decision_count_total", 0)),
				int(search.get("budget_expired_total", 0)),
				float(search.get("budget_expired_rate", 0.0)),
				float(search.get("time_ms_avg_per_decision", 0.0)),
				int(search.get("time_ms_max", 0)),
				float(search.get("attempted_simulations_avg_per_decision", 0.0)),
				float(search.get("expanded_nodes_avg_per_decision", 0.0)),
			]
			if int(search.get("strategic_decision_count_total", 0)) > 0:
				search_line += " strategic_total=%d strategic_cached=%d strategic_cached_rate=%.3f strategic_cached_share=%.3f" % [
					int(search.get("strategic_decision_count_total", 0)),
					int(search.get("strategic_cached_count_total", 0)),
					float(search.get("strategic_cached_rate", 0.0)),
					float(search.get("strategic_cached_share", 0.0)),
				]
			if int(search.get("strategic_fallback_count_total", 0)) > 0:
				search_line += " strategic_fallback=%d strategic_fallback_rate=%.3f strategic_failures=%s" % [
					int(search.get("strategic_fallback_count_total", 0)),
					float(search.get("strategic_fallback_rate", 0.0)),
					_format_actions(Dictionary(search.get("strategic_failure_counts", {}))),
				]
			search_line += " types=%s" % _format_actions(Dictionary(search.get("search_type_counts", {})))
			lines.append(search_line)
			if _has_strategic_search_metrics(search):
				lines.append("[BotSelfplaySummary] MCTS_ROUTE %s route_switch_avg=%.3f non_root_populated_avg=%.3f non_root_expanded_avg=%.3f non_root_candidate_avg=%.3f route_types=%s" % [
					str(bot_name),
					float(search.get("mcts_route_switch_count_avg_per_decision", 0.0)),
					float(search.get("mcts_non_root_populated_nodes_avg_per_decision", 0.0)),
					float(search.get("mcts_non_root_expanded_nodes_avg_per_decision", 0.0)),
					float(search.get("mcts_non_root_candidate_count_avg_per_decision", 0.0)),
					_format_actions(Dictionary(search.get("mcts_selected_route_type_counts", {}))),
				])
		var tuning_val = bot.get("tuning_objective", {})
		var tuning: Dictionary = tuning_val if tuning_val is Dictionary else {}
		if not tuning.is_empty():
			lines.append("[BotSelfplaySummary] TUNING %s score=%.3f components=%s" % [
				str(bot_name),
				float(tuning.get("score", 0.0)),
				_format_numeric_dict(Dictionary(tuning.get("components", {}))),
			])
	var comparison_val = summary.get("comparison", {})
	var comparison: Dictionary = comparison_val if comparison_val is Dictionary else {}
	var baseline := str(comparison.get("baseline", ""))
	var comparison_bots_val = comparison.get("bots", {})
	var comparison_bots: Dictionary = comparison_bots_val if comparison_bots_val is Dictionary else {}
	if not baseline.is_empty() and not comparison_bots.is_empty():
		lines.append("[BotSelfplaySummary] BASELINE %s" % baseline)
		var compare_names := comparison_bots.keys()
		compare_names.sort()
		for compare_name in compare_names:
			var compare_val = comparison_bots[compare_name]
			if not (compare_val is Dictionary):
				continue
			var compare: Dictionary = compare_val
			var player_delta: Dictionary = Dictionary(compare.get("player_avg_delta", {}))
			var cash_min_delta = player_delta.get("cash_min_after_first_positive", [])
			var cash_max_delta = player_delta.get("cash_max_seen", [])
			var opening_delta: Dictionary = Dictionary(compare.get("opening_delta", {}))
			lines.append("[BotSelfplaySummary] COMPARE %s vs %s success_delta=%.3f avg_round_delta=%.3f avg_steps_delta=%.3f avg_commands_delta=%.3f tuning_score_delta=%.3f cash_min_after_positive_delta=%s cash_max_seen_delta=%s actions_delta=%s milestones_delta=%s opening_delta=%s search_delta=%s" % [
				str(compare_name),
				baseline,
				float(compare.get("success_rate_delta", 0.0)),
				float(compare.get("avg_round_delta", 0.0)),
				float(compare.get("avg_steps_delta", 0.0)),
				float(compare.get("avg_command_count_delta", 0.0)),
				float(compare.get("tuning_score_delta", 0.0)),
				str(cash_min_delta),
				str(cash_max_delta),
				_format_numeric_dict(Dictionary(compare.get("action_avg_per_match_delta", {}))),
				_format_numeric_dict(Dictionary(compare.get("milestone_count_delta", {}))),
				_format_numeric_dict(opening_delta),
				_format_numeric_dict(Dictionary(compare.get("search_delta", {}))),
			])
	return lines

static func _new_bucket(label: String) -> Dictionary:
	return {
		"label": label,
		"matches": 0,
		"ok_matches": 0,
		"failures": 0,
		"timeout_matches": 0,
		"failed_seeds": [],
		"timeout_seeds": [],
		"seeds": [],
		"round_sum": 0.0,
		"steps_sum": 0.0,
		"command_count_sum": 0.0,
		"action_totals": {},
		"mandatory_completion_totals": {},
		"untraced_mandatory_completion_totals": {},
		"milestone_counts": {},
		"player_metrics": {},
		"opening_metrics": _new_opening_metric(),
		"search_metrics": _new_search_metric(),
	}

static func _add_row(bucket: Dictionary, row: Dictionary) -> void:
	bucket["matches"] = int(bucket.get("matches", 0)) + 1
	if bool(row.get("ok", false)):
		bucket["ok_matches"] = int(bucket.get("ok_matches", 0)) + 1
	else:
		bucket["failures"] = int(bucket.get("failures", 0)) + 1
		if row.has("seed"):
			bucket["failed_seeds"].append(int(row.get("seed", 0)))
	if bool(row.get("match_timed_out", false)):
		bucket["timeout_matches"] = int(bucket.get("timeout_matches", 0)) + 1
		if row.has("seed"):
			bucket["timeout_seeds"].append(int(row.get("seed", 0)))
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

	_add_action_count_dict(bucket["mandatory_completion_totals"], row.get("mandatory_completion_counts", {}))
	_add_action_count_dict(bucket["untraced_mandatory_completion_totals"], row.get("untraced_mandatory_completion_counts", {}))

	var player_metrics: Dictionary = bucket["player_metrics"]
	for row_key in PLAYER_METRIC_KEYS.keys():
		var metric_name := str(PLAYER_METRIC_KEYS[row_key])
		var values_val = row.get(row_key, [])
		if values_val is Array:
			if not player_metrics.has(metric_name):
				player_metrics[metric_name] = _new_player_metric()
			_add_player_metric(player_metrics[metric_name], values_val)

	var milestone_ids_val = row.get("player_milestone_ids", [])
	if milestone_ids_val is Array:
		_add_milestone_counts(bucket["milestone_counts"], Array(milestone_ids_val))
	_add_opening_metric(bucket["opening_metrics"], row.get("opening_metrics", {}))
	_add_search_metric(bucket["search_metrics"], row.get("search_metrics", {}))

static func _add_milestone_counts(target: Dictionary, players_milestones: Array) -> void:
	for milestones_val in players_milestones:
		if not (milestones_val is Array):
			continue
		for milestone_id in _sorted_unique_strings(milestones_val):
			target[milestone_id] = int(target.get(milestone_id, 0)) + 1

static func _add_action_count_dict(target: Dictionary, counts_val) -> void:
	if not (counts_val is Dictionary):
		return
	var counts: Dictionary = counts_val
	for action_id_val in counts.keys():
		var action_id := str(action_id_val).strip_edges()
		if action_id.is_empty():
			continue
		target[action_id] = int(target.get(action_id, 0)) + int(counts.get(action_id_val, 0))

static func _new_player_metric() -> Dictionary:
	return {
		"sum": [],
		"min": [],
		"max": [],
		"counts": [],
	}

static func _new_search_metric() -> Dictionary:
	return {
		"decision_count": 0,
		"budget_expired_count": 0,
		"attempted_simulations": 0,
		"expanded_nodes": 0,
		"time_ms_sum": 0,
		"time_ms_max": 0,
		"search_type_counts": {},
		"strategic_decision_count": 0,
		"strategic_cached_count": 0,
		"strategic_fallback_count": 0,
		"strategic_failure_counts": {},
		"mcts_route_switch_count": 0,
		"mcts_non_root_populated_nodes": 0,
		"mcts_non_root_expanded_nodes": 0,
		"mcts_non_root_candidate_count": 0,
		"mcts_selected_route_type_counts": {},
	}

static func _new_opening_metric() -> Dictionary:
	var scalar_sums := {}
	for key in OPENING_SCALAR_KEYS:
		scalar_sums[key] = 0.0
	return {
		"matches": 0,
		"players_with_positive_cash_sum": 0.0,
		"players_without_positive_cash_sum": 0.0,
		"first_positive_cash_round_sum": 0.0,
		"first_positive_cash_round_count": 0,
		"first_positive_cash_step_sum": 0.0,
		"first_positive_cash_step_count": 0,
		"food_recruit_to_produce_round_delay_sum": 0.0,
		"food_recruit_to_produce_round_delay_count": 0,
		"food_recruit_to_produce_step_delay_sum": 0.0,
		"food_recruit_to_produce_step_delay_count": 0,
		"pre_revenue_action_totals": {},
		"pre_revenue_recruit_totals": {},
		"scalar_sums": scalar_sums,
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

static func _add_search_metric(metric: Dictionary, value) -> void:
	if not (value is Dictionary):
		return
	var row: Dictionary = value
	metric["decision_count"] = int(metric.get("decision_count", 0)) + int(row.get("decision_count", 0))
	metric["budget_expired_count"] = int(metric.get("budget_expired_count", 0)) + int(row.get("budget_expired_count", 0))
	metric["attempted_simulations"] = int(metric.get("attempted_simulations", 0)) + int(row.get("attempted_simulations", 0))
	metric["expanded_nodes"] = int(metric.get("expanded_nodes", 0)) + int(row.get("expanded_nodes", 0))
	metric["time_ms_sum"] = int(metric.get("time_ms_sum", 0)) + int(row.get("time_ms_sum", 0))
	metric["time_ms_max"] = maxi(int(metric.get("time_ms_max", 0)), int(row.get("time_ms_max", 0)))
	_add_action_count_dict(metric["search_type_counts"], row.get("search_type_counts", {}))
	metric["strategic_fallback_count"] = int(metric.get("strategic_fallback_count", 0)) + int(row.get("strategic_fallback_count", 0))
	_add_action_count_dict(metric["strategic_failure_counts"], row.get("strategic_failure_counts", {}))
	var search_counts: Dictionary = Dictionary(row.get("search_type_counts", {}))
	for search_key_val in search_counts.keys():
		var search_key := str(search_key_val).strip_edges()
		var count := int(search_counts.get(search_key_val, 0))
		if search_key.begins_with("strategic"):
			metric["strategic_decision_count"] = int(metric.get("strategic_decision_count", 0)) + count
		if search_key == "strategic_cached":
			metric["strategic_cached_count"] = int(metric.get("strategic_cached_count", 0)) + count
	metric["mcts_route_switch_count"] = int(metric.get("mcts_route_switch_count", 0)) + int(row.get("mcts_route_switch_count", 0))
	metric["mcts_non_root_populated_nodes"] = int(metric.get("mcts_non_root_populated_nodes", 0)) + int(row.get("mcts_non_root_populated_nodes", 0))
	metric["mcts_non_root_expanded_nodes"] = int(metric.get("mcts_non_root_expanded_nodes", 0)) + int(row.get("mcts_non_root_expanded_nodes", 0))
	metric["mcts_non_root_candidate_count"] = int(metric.get("mcts_non_root_candidate_count", 0)) + int(row.get("mcts_non_root_candidate_count", 0))
	_add_action_count_dict(metric["mcts_selected_route_type_counts"], row.get("mcts_selected_route_type_counts", {}))

static func _add_opening_metric(metric: Dictionary, value) -> void:
	if not (value is Dictionary):
		return
	var row: Dictionary = value
	metric["matches"] = int(metric.get("matches", 0)) + 1
	metric["players_with_positive_cash_sum"] = float(metric.get("players_with_positive_cash_sum", 0.0)) + float(row.get("players_with_positive_cash", 0.0))
	metric["players_without_positive_cash_sum"] = float(metric.get("players_without_positive_cash_sum", 0.0)) + float(row.get("players_without_positive_cash", 0.0))
	_add_positive_int_values(
		metric,
		"first_positive_cash_round_sum",
		"first_positive_cash_round_count",
		row.get("first_positive_cash_rounds", [])
	)
	_add_positive_int_values(
		metric,
		"first_positive_cash_step_sum",
		"first_positive_cash_step_count",
		row.get("first_positive_cash_steps", [])
	)
	_add_positive_int_values(
		metric,
		"food_recruit_to_produce_round_delay_sum",
		"food_recruit_to_produce_round_delay_count",
		row.get("food_recruit_to_produce_round_delays", [])
	)
	_add_positive_int_values(
		metric,
		"food_recruit_to_produce_step_delay_sum",
		"food_recruit_to_produce_step_delay_count",
		row.get("food_recruit_to_produce_step_delays", [])
	)
	_add_action_count_dict(metric["pre_revenue_action_totals"], row.get("pre_revenue_action_counts", {}))
	_add_action_count_dict(metric["pre_revenue_recruit_totals"], row.get("pre_revenue_recruit_counts", {}))
	var scalar_sums: Dictionary = metric["scalar_sums"]
	for key in OPENING_SCALAR_KEYS:
		scalar_sums[key] = float(scalar_sums.get(key, 0.0)) + float(row.get(key, 0.0))

static func _add_positive_int_values(metric: Dictionary, sum_key: String, count_key: String, values_val) -> void:
	if not (values_val is Array):
		return
	for value in Array(values_val):
		var number := int(value)
		if number < 0:
			continue
		metric[sum_key] = float(metric.get(sum_key, 0.0)) + float(number)
		metric[count_key] = int(metric.get(count_key, 0)) + 1

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
		"timeout_matches": int(bucket.get("timeout_matches", 0)),
		"success_rate": _ratio(float(bucket.get("ok_matches", 0)), float(matches)),
		"avg_round": _avg(float(bucket.get("round_sum", 0.0)), matches),
		"avg_steps": _avg(float(bucket.get("steps_sum", 0.0)), matches),
		"avg_command_count": _avg(float(bucket.get("command_count_sum", 0.0)), matches),
		"failed_seeds": _sorted_int_array(bucket.get("failed_seeds", [])),
		"timeout_seeds": _sorted_int_array(bucket.get("timeout_seeds", [])),
		"action_totals": _sorted_dict(bucket.get("action_totals", {})),
		"action_avg_per_match": _action_averages(bucket.get("action_totals", {}), matches),
		"mandatory_completion_totals": _sorted_dict(bucket.get("mandatory_completion_totals", {})),
		"mandatory_completion_avg_per_match": _action_averages(bucket.get("mandatory_completion_totals", {}), matches),
		"untraced_mandatory_completion_totals": _sorted_dict(bucket.get("untraced_mandatory_completion_totals", {})),
		"untraced_mandatory_completion_avg_per_match": _action_averages(bucket.get("untraced_mandatory_completion_totals", {}), matches),
		"milestone_counts": _sorted_dict(bucket.get("milestone_counts", {})),
		"players": _finalize_player_metrics(bucket.get("player_metrics", {})),
		"opening": _finalize_opening_metric(bucket.get("opening_metrics", {})),
		"search": _finalize_search_metric(bucket.get("search_metrics", {}), matches),
	}
	var seeds := _sorted_int_array(bucket.get("seeds", []))
	if not seeds.is_empty():
		out["seed_min"] = int(seeds.front())
		out["seed_max"] = int(seeds.back())
	out["timeout_rate"] = _ratio(float(bucket.get("timeout_matches", 0)), float(matches))
	out["tuning_objective"] = _build_tuning_objective(out)
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

static func _finalize_search_metric(metric_val, matches: int) -> Dictionary:
	var metric: Dictionary = metric_val if metric_val is Dictionary else {}
	var decisions := int(metric.get("decision_count", 0))
	var budget_expired := int(metric.get("budget_expired_count", 0))
	var attempted := int(metric.get("attempted_simulations", 0))
	var expanded := int(metric.get("expanded_nodes", 0))
	var time_ms_sum := int(metric.get("time_ms_sum", 0))
	var route_switch_count := int(metric.get("mcts_route_switch_count", 0))
	var non_root_populated := int(metric.get("mcts_non_root_populated_nodes", 0))
	var non_root_expanded := int(metric.get("mcts_non_root_expanded_nodes", 0))
	var non_root_candidates := int(metric.get("mcts_non_root_candidate_count", 0))
	var strategic_decisions := int(metric.get("strategic_decision_count", 0))
	var strategic_cached := int(metric.get("strategic_cached_count", 0))
	var strategic_fallback := int(metric.get("strategic_fallback_count", 0))
	return {
		"decision_count_total": decisions,
		"decision_count_avg_per_match": _avg(float(decisions), matches),
		"budget_expired_total": budget_expired,
		"budget_expired_avg_per_match": _avg(float(budget_expired), matches),
		"budget_expired_rate": _ratio(float(budget_expired), float(decisions)),
		"attempted_simulations_total": attempted,
		"attempted_simulations_avg_per_match": _avg(float(attempted), matches),
		"attempted_simulations_avg_per_decision": _avg(float(attempted), decisions),
		"expanded_nodes_total": expanded,
		"expanded_nodes_avg_per_match": _avg(float(expanded), matches),
		"expanded_nodes_avg_per_decision": _avg(float(expanded), decisions),
		"time_ms_sum": time_ms_sum,
		"time_ms_avg_per_match": _avg(float(time_ms_sum), matches),
		"time_ms_avg_per_decision": _avg(float(time_ms_sum), decisions),
		"time_ms_max": int(metric.get("time_ms_max", 0)),
		"search_type_counts": _sorted_dict(metric.get("search_type_counts", {})),
		"strategic_decision_count_total": strategic_decisions,
		"strategic_decision_count_avg_per_match": _avg(float(strategic_decisions), matches),
		"strategic_cached_count_total": strategic_cached,
		"strategic_cached_count_avg_per_match": _avg(float(strategic_cached), matches),
		"strategic_cached_rate": _ratio(float(strategic_cached), float(strategic_decisions)),
		"strategic_cached_share": _ratio(float(strategic_cached), float(decisions)),
		"strategic_fallback_count_total": strategic_fallback,
		"strategic_fallback_count_avg_per_match": _avg(float(strategic_fallback), matches),
		"strategic_fallback_rate": _ratio(float(strategic_fallback), float(decisions)),
		"strategic_failure_counts": _sorted_dict(metric.get("strategic_failure_counts", {})),
		"mcts_route_switch_count_total": route_switch_count,
		"mcts_route_switch_count_avg_per_match": _avg(float(route_switch_count), matches),
		"mcts_route_switch_count_avg_per_decision": _avg(float(route_switch_count), decisions),
		"mcts_non_root_populated_nodes_total": non_root_populated,
		"mcts_non_root_populated_nodes_avg_per_match": _avg(float(non_root_populated), matches),
		"mcts_non_root_populated_nodes_avg_per_decision": _avg(float(non_root_populated), decisions),
		"mcts_non_root_expanded_nodes_total": non_root_expanded,
		"mcts_non_root_expanded_nodes_avg_per_match": _avg(float(non_root_expanded), matches),
		"mcts_non_root_expanded_nodes_avg_per_decision": _avg(float(non_root_expanded), decisions),
		"mcts_non_root_candidate_count_total": non_root_candidates,
		"mcts_non_root_candidate_count_avg_per_match": _avg(float(non_root_candidates), matches),
		"mcts_non_root_candidate_count_avg_per_decision": _avg(float(non_root_candidates), decisions),
		"mcts_selected_route_type_counts": _sorted_dict(metric.get("mcts_selected_route_type_counts", {})),
	}

static func _finalize_opening_metric(metric_val) -> Dictionary:
	var metric: Dictionary = metric_val if metric_val is Dictionary else {}
	var matches := int(metric.get("matches", 0))
	var scalar_sums: Dictionary = Dictionary(metric.get("scalar_sums", {}))
	var scalar_avg := {}
	for key in OPENING_SCALAR_KEYS:
		scalar_avg[key] = _avg(float(scalar_sums.get(key, 0.0)), matches)
	return {
		"matches": matches,
		"players_with_positive_cash_avg_per_match": _avg(float(metric.get("players_with_positive_cash_sum", 0.0)), matches),
		"players_without_positive_cash_avg_per_match": _avg(float(metric.get("players_without_positive_cash_sum", 0.0)), matches),
		"first_positive_cash_round_avg": _avg(float(metric.get("first_positive_cash_round_sum", 0.0)), int(metric.get("first_positive_cash_round_count", 0))),
		"first_positive_cash_step_avg": _avg(float(metric.get("first_positive_cash_step_sum", 0.0)), int(metric.get("first_positive_cash_step_count", 0))),
		"food_recruit_to_produce_round_delay_avg": _avg(float(metric.get("food_recruit_to_produce_round_delay_sum", 0.0)), int(metric.get("food_recruit_to_produce_round_delay_count", 0))),
		"food_recruit_to_produce_step_delay_avg": _avg(float(metric.get("food_recruit_to_produce_step_delay_sum", 0.0)), int(metric.get("food_recruit_to_produce_step_delay_count", 0))),
		"pre_revenue_action_totals": _sorted_dict(metric.get("pre_revenue_action_totals", {})),
		"pre_revenue_action_avg_per_match": _action_averages(metric.get("pre_revenue_action_totals", {}), matches),
		"pre_revenue_recruit_totals": _sorted_dict(metric.get("pre_revenue_recruit_totals", {})),
		"pre_revenue_recruit_avg_per_match": _action_averages(metric.get("pre_revenue_recruit_totals", {}), matches),
		"scalar_avg_per_match": scalar_avg,
	}

static func _build_comparison(bots: Dictionary) -> Dictionary:
	var baseline := _find_strategy_baseline(bots)
	if baseline.is_empty():
		return {}
	var baseline_val = bots.get(baseline, {})
	if not (baseline_val is Dictionary):
		return {}
	var baseline_bot: Dictionary = baseline_val
	var out_bots := {}
	var bot_names := bots.keys()
	bot_names.sort()
	for bot_name_val in bot_names:
		var bot_name := str(bot_name_val)
		if bot_name == baseline:
			continue
		var bot_val = bots.get(bot_name_val, {})
		if not (bot_val is Dictionary):
			continue
		out_bots[bot_name] = _compare_bot(Dictionary(bot_val), baseline_bot)
	if out_bots.is_empty():
		return {}
	return {
		"baseline": baseline,
		"bots": out_bots,
	}

static func _find_strategy_baseline(bots: Dictionary) -> String:
	if bots.has("strategy"):
		return "strategy"
	var bot_names := bots.keys()
	bot_names.sort()
	for bot_name_val in bot_names:
		var bot_name := str(bot_name_val)
		if bot_name.begins_with("strategy@"):
			return bot_name
	return ""

static func _compare_bot(bot: Dictionary, baseline: Dictionary) -> Dictionary:
	return {
		"success_rate_delta": _round3(float(bot.get("success_rate", 0.0)) - float(baseline.get("success_rate", 0.0))),
		"avg_round_delta": _round3(float(bot.get("avg_round", 0.0)) - float(baseline.get("avg_round", 0.0))),
		"avg_steps_delta": _round3(float(bot.get("avg_steps", 0.0)) - float(baseline.get("avg_steps", 0.0))),
		"avg_command_count_delta": _round3(float(bot.get("avg_command_count", 0.0)) - float(baseline.get("avg_command_count", 0.0))),
		"tuning_score_delta": _round3(_tuning_score(bot) - _tuning_score(baseline)),
		"action_avg_per_match_delta": _numeric_dict_delta(bot.get("action_avg_per_match", {}), baseline.get("action_avg_per_match", {})),
		"mandatory_completion_avg_per_match_delta": _numeric_dict_delta(bot.get("mandatory_completion_avg_per_match", {}), baseline.get("mandatory_completion_avg_per_match", {})),
		"milestone_count_delta": _numeric_dict_delta(bot.get("milestone_counts", {}), baseline.get("milestone_counts", {})),
		"player_avg_delta": _player_avg_delta(bot.get("players", {}), baseline.get("players", {})),
		"opening_delta": _opening_delta(bot.get("opening", {}), baseline.get("opening", {})),
		"search_delta": _search_delta(bot.get("search", {}), baseline.get("search", {})),
	}

static func _build_tuning_objective(bot: Dictionary) -> Dictionary:
	var players_val = bot.get("players", {})
	var players: Dictionary = players_val if players_val is Dictionary else {}
	var opening_val = bot.get("opening", {})
	var opening: Dictionary = opening_val if opening_val is Dictionary else {}
	var opening_scalars: Dictionary = Dictionary(opening.get("scalar_avg_per_match", {}))
	var matches := int(bot.get("matches", 0))
	var milestone_counts_val = bot.get("milestone_counts", {})
	var milestone_counts: Dictionary = milestone_counts_val if milestone_counts_val is Dictionary else {}
	var milestones_per_match := _avg(_sum_numeric_values(milestone_counts), matches)
	var components := {
		"success_rate": _weighted(float(bot.get("success_rate", 0.0)), "success_rate"),
		"avg_round": _weighted(float(bot.get("avg_round", 0.0)), "avg_round"),
		"cash_avg": _weighted(_player_metric_avg(players, "cash"), "cash_avg"),
		"cash_min_after_first_positive_avg": _weighted(_player_metric_avg(players, "cash_min_after_first_positive"), "cash_min_after_first_positive_avg"),
		"cash_max_seen_avg": _weighted(_player_metric_avg(players, "cash_max_seen"), "cash_max_seen_avg"),
		"inventory_units_avg": _weighted(_player_metric_avg(players, "inventory_units"), "inventory_units_avg"),
		"milestones_avg_per_match": _weighted(milestones_per_match, "milestones_avg_per_match"),
		"opening_players_without_positive_cash_avg": _weighted(float(opening.get("players_without_positive_cash_avg_per_match", 0.0)), "opening_players_without_positive_cash_avg"),
		"opening_first_positive_cash_round_avg": _weighted(float(opening.get("first_positive_cash_round_avg", 0.0)), "opening_first_positive_cash_round_avg"),
		"opening_first_positive_cash_step_avg": _weighted(float(opening.get("first_positive_cash_step_avg", 0.0)), "opening_first_positive_cash_step_avg"),
		"opening_food_recruit_to_produce_round_delay_avg": _weighted(float(opening.get("food_recruit_to_produce_round_delay_avg", 0.0)), "opening_food_recruit_to_produce_round_delay_avg"),
		"opening_food_recruit_to_produce_step_delay_avg": _weighted(float(opening.get("food_recruit_to_produce_step_delay_avg", 0.0)), "opening_food_recruit_to_produce_step_delay_avg"),
		"pre_revenue_errand_boy_recruit_avg": _weighted(float(opening_scalars.get("pre_revenue_errand_boy_recruit_count", 0.0)), "pre_revenue_errand_boy_recruit_avg"),
		"pre_revenue_pricing_manager_recruit_avg": _weighted(float(opening_scalars.get("pre_revenue_pricing_manager_recruit_count", 0.0)), "pre_revenue_pricing_manager_recruit_avg"),
		"pre_revenue_procure_drinks_avg": _weighted(float(opening_scalars.get("pre_revenue_procure_drinks_count", 0.0)), "pre_revenue_procure_drinks_avg"),
		"avg_command_count": _weighted(float(bot.get("avg_command_count", 0.0)), "avg_command_count"),
	}
	return {
		"score": _round3(_sum_numeric_values(components)),
		"components": components,
		"weights": TUNING_OBJECTIVE_WEIGHTS.duplicate(),
	}

static func _tuning_score(bot: Dictionary) -> float:
	var tuning_val = bot.get("tuning_objective", {})
	if not (tuning_val is Dictionary):
		return 0.0
	return float(Dictionary(tuning_val).get("score", 0.0))

static func _weighted(value: float, weight_key: String) -> float:
	return _round3(value * float(TUNING_OBJECTIVE_WEIGHTS.get(weight_key, 0.0)))

static func _player_metric_avg(players: Dictionary, metric_key: String) -> float:
	var metric_val = players.get(metric_key, {})
	if not (metric_val is Dictionary):
		return 0.0
	var metric: Dictionary = metric_val
	return _array_average(metric.get("avg", []))

static func _array_average(values_val) -> float:
	var values: Array = values_val if values_val is Array else []
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return _avg(total, values.size())

static func _sum_numeric_values(values: Dictionary) -> float:
	var total := 0.0
	for value in values.values():
		total += float(value)
	return total

static func _numeric_dict_delta(left_val, right_val) -> Dictionary:
	var left: Dictionary = left_val if left_val is Dictionary else {}
	var right: Dictionary = right_val if right_val is Dictionary else {}
	var out := {}
	for key in _sorted_union_keys(left, right):
		out[key] = _round3(float(left.get(key, 0.0)) - float(right.get(key, 0.0)))
	return out

static func _player_avg_delta(left_val, right_val) -> Dictionary:
	var left: Dictionary = left_val if left_val is Dictionary else {}
	var right: Dictionary = right_val if right_val is Dictionary else {}
	var out := {}
	for key in _sorted_union_keys(left, right):
		var left_metric: Dictionary = Dictionary(left.get(key, {}))
		var right_metric: Dictionary = Dictionary(right.get(key, {}))
		out[key] = _array_delta(left_metric.get("avg", []), right_metric.get("avg", []))
	return out

static func _opening_delta(left_val, right_val) -> Dictionary:
	var left: Dictionary = left_val if left_val is Dictionary else {}
	var right: Dictionary = right_val if right_val is Dictionary else {}
	var out := {}
	for key in [
		"players_with_positive_cash_avg_per_match",
		"players_without_positive_cash_avg_per_match",
		"first_positive_cash_round_avg",
		"first_positive_cash_step_avg",
		"food_recruit_to_produce_round_delay_avg",
		"food_recruit_to_produce_step_delay_avg",
	]:
		out[key] = _round3(float(left.get(key, 0.0)) - float(right.get(key, 0.0)))
	var left_scalars: Dictionary = Dictionary(left.get("scalar_avg_per_match", {}))
	var right_scalars: Dictionary = Dictionary(right.get("scalar_avg_per_match", {}))
	var scalar_delta := _numeric_dict_delta(left_scalars, right_scalars)
	for key in scalar_delta.keys():
		out[str(key)] = float(scalar_delta[key])
	return out

static func _search_delta(left_val, right_val) -> Dictionary:
	var left: Dictionary = left_val if left_val is Dictionary else {}
	var right: Dictionary = right_val if right_val is Dictionary else {}
	var keys := [
		"decision_count_avg_per_match",
		"budget_expired_avg_per_match",
		"budget_expired_rate",
		"attempted_simulations_avg_per_match",
		"attempted_simulations_avg_per_decision",
		"expanded_nodes_avg_per_match",
		"expanded_nodes_avg_per_decision",
		"time_ms_avg_per_match",
		"time_ms_avg_per_decision",
		"time_ms_max",
		"strategic_decision_count_avg_per_match",
		"strategic_cached_count_avg_per_match",
		"strategic_cached_rate",
		"strategic_cached_share",
		"strategic_fallback_count_avg_per_match",
		"strategic_fallback_rate",
		"mcts_route_switch_count_avg_per_decision",
		"mcts_non_root_populated_nodes_avg_per_decision",
		"mcts_non_root_expanded_nodes_avg_per_decision",
		"mcts_non_root_candidate_count_avg_per_decision",
	]
	var out := {}
	for key in keys:
		out[key] = _round3(float(left.get(key, 0.0)) - float(right.get(key, 0.0)))
	return out

static func _has_strategic_search_metrics(search: Dictionary) -> bool:
	var counts: Dictionary = Dictionary(search.get("search_type_counts", {}))
	for search_key_val in counts.keys():
		if str(search_key_val).begins_with("strategic"):
			return true
	return not Dictionary(search.get("mcts_selected_route_type_counts", {})).is_empty()

static func _array_delta(left_val, right_val) -> Array[float]:
	var left: Array = left_val if left_val is Array else []
	var right: Array = right_val if right_val is Array else []
	var out: Array[float] = []
	var size := maxi(left.size(), right.size())
	for i in range(size):
		var left_value := float(left[i]) if i < left.size() else 0.0
		var right_value := float(right[i]) if i < right.size() else 0.0
		out.append(_round3(left_value - right_value))
	return out

static func _sorted_union_keys(left: Dictionary, right: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key_val in left.keys():
		var key := str(key_val)
		if not out.has(key):
			out.append(key)
	for key_val in right.keys():
		var key := str(key_val)
		if not out.has(key):
			out.append(key)
	out.sort()
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

static func _sorted_unique_strings(value) -> Array[String]:
	var source: Array = value if value is Array else []
	var out: Array[String] = []
	for item in source:
		var text := str(item)
		if not text.is_empty() and not out.has(text):
			out.append(text)
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

static func _format_numeric_dict(values: Dictionary) -> String:
	if values.is_empty():
		return "{}"
	var parts: Array[String] = []
	var keys := values.keys()
	keys.sort()
	for key in keys:
		parts.append("%s=%.3f" % [str(key), float(values[key])])
	return " ".join(parts)

static func _format_player_metrics(players: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["cash", "cash_min_seen", "cash_min_after_first_positive", "cash_max_seen", "employees", "inventory_units", "milestones", "restaurants"]:
		if not players.has(key):
			continue
		var metric_val = players[key]
		if not (metric_val is Dictionary):
			continue
		var metric: Dictionary = metric_val
		parts.append("%s_avg=%s" % [key, str(metric.get("avg", []))])
	return " ".join(parts)
