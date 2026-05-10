class_name BotSelfplaySummaryTest
extends RefCounted

const SummaryClass = preload("res://tools/bot_selfplay_summary.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var aggregate := _test_summarize_rows()
	if not aggregate.ok:
		return aggregate
	var formatted := _test_format_summary()
	if not formatted.ok:
		return formatted
	var matchup := _test_bot_config_groups_mixed_matchups()
	if not matchup.ok:
		return matchup
	return Result.success({"cases": 3})

static func _test_summarize_rows() -> Result:
	var rows: Array[Dictionary] = [
		{
			"bot": "strategy",
			"ok": true,
			"seed": 1,
			"round": 4,
			"steps": 10,
			"command_count": 10,
			"action_counts": {"recruit": 2, "skip": 1},
			"mandatory_completion_counts": {"set_price": 1},
			"untraced_mandatory_completion_counts": {"set_price": 1},
			"player_cash": [3, 0],
			"player_cash_min_seen": [0, 0],
			"player_cash_min_after_first_positive": [2, 4],
			"player_cash_max_seen": [20, 10],
			"player_employees": [4, 3],
			"player_inventory_units": [1, 0],
			"player_milestones": [2, 1],
			"player_milestone_ids": [["first_burger_produced", "first_train"], ["first_train"]],
			"player_restaurants": [1, 1],
			"opening_metrics": {
				"players_with_positive_cash": 1,
				"players_without_positive_cash": 1,
				"first_positive_cash_rounds": [3, -1],
				"first_positive_cash_steps": [7, -1],
				"first_food_recruit_rounds": [1, -1],
				"first_food_recruit_steps": [2, -1],
				"first_produce_food_rounds": [3, -1],
				"first_produce_food_steps": [7, -1],
				"food_recruit_to_produce_round_delays": [2, -1],
				"food_recruit_to_produce_step_delays": [5, -1],
				"pre_revenue_action_counts": {"recruit": 2},
				"pre_revenue_recruit_counts": {"errand_boy": 1},
				"pre_revenue_recruit_count": 2,
				"pre_revenue_errand_boy_recruit_count": 1,
				"pre_revenue_pricing_manager_recruit_count": 0,
				"pre_revenue_procure_drinks_count": 0,
			},
			"search_metrics": {
				"decision_count": 0,
				"budget_expired_count": 0,
				"attempted_simulations": 0,
				"expanded_nodes": 0,
				"time_ms_sum": 0,
				"time_ms_max": 0,
				"search_type_counts": {},
			},
		},
		{
			"bot": "strategy",
			"ok": false,
			"seed": 2,
			"round": 2,
			"steps": 14,
			"command_count": 13,
			"action_counts": {"recruit": 1, "fire": 1},
			"mandatory_completion_counts": {"set_price": 2},
			"untraced_mandatory_completion_counts": {"set_price": 1},
			"player_cash": [1, 6],
			"player_cash_min_seen": [1, 2],
			"player_cash_min_after_first_positive": [1, 2],
			"player_cash_max_seen": [12, 18],
			"player_employees": [3, 4],
			"player_inventory_units": [0, 2],
			"player_milestones": [1, 3],
			"player_milestone_ids": [["first_train"], ["first_train", "first_waitress"]],
			"player_restaurants": [1, 2],
			"opening_metrics": {
				"players_with_positive_cash": 2,
				"players_without_positive_cash": 0,
				"first_positive_cash_rounds": [2, 2],
				"first_positive_cash_steps": [5, 5],
				"first_food_recruit_rounds": [1, 1],
				"first_food_recruit_steps": [1, 1],
				"first_produce_food_rounds": [2, 2],
				"first_produce_food_steps": [5, 5],
				"food_recruit_to_produce_round_delays": [1, 1],
				"food_recruit_to_produce_step_delays": [4, 4],
				"pre_revenue_action_counts": {"recruit": 1, "procure_drinks": 1},
				"pre_revenue_recruit_counts": {"pricing_manager": 1},
				"pre_revenue_recruit_count": 1,
				"pre_revenue_errand_boy_recruit_count": 0,
				"pre_revenue_pricing_manager_recruit_count": 1,
				"pre_revenue_procure_drinks_count": 1,
			},
			"search_metrics": {
				"decision_count": 0,
				"budget_expired_count": 0,
				"attempted_simulations": 0,
				"expanded_nodes": 0,
				"time_ms_sum": 0,
				"time_ms_max": 0,
				"search_type_counts": {},
			},
		},
		{
			"bot": "osla",
			"ok": true,
			"seed": 3,
			"round": 4,
			"steps": 8,
			"command_count": 8,
			"action_counts": {"recruit": 1, "produce_food": 2},
			"player_cash": [0, 0],
			"player_cash_min_seen": [0, 0],
			"player_cash_min_after_first_positive": [5, 5],
			"player_cash_max_seen": [10, 10],
			"player_employees": [4, 4],
			"player_inventory_units": [1, 1],
			"player_milestones": [4, 4],
			"player_milestone_ids": [["first_train"], ["first_train"]],
			"player_restaurants": [1, 1],
			"opening_metrics": {
				"players_with_positive_cash": 2,
				"players_without_positive_cash": 0,
				"first_positive_cash_rounds": [2, 2],
				"first_positive_cash_steps": [4, 4],
				"first_food_recruit_rounds": [1, 1],
				"first_food_recruit_steps": [1, 1],
				"first_produce_food_rounds": [2, 2],
				"first_produce_food_steps": [4, 4],
				"food_recruit_to_produce_round_delays": [1, 1],
				"food_recruit_to_produce_step_delays": [3, 3],
				"pre_revenue_action_counts": {"recruit": 1, "produce_food": 2},
				"pre_revenue_recruit_counts": {"kitchen_trainee": 1},
				"pre_revenue_recruit_count": 1,
				"pre_revenue_errand_boy_recruit_count": 0,
				"pre_revenue_pricing_manager_recruit_count": 0,
				"pre_revenue_procure_drinks_count": 0,
			},
			"search_metrics": {
				"decision_count": 2,
				"budget_expired_count": 1,
				"attempted_simulations": 7,
				"expanded_nodes": 0,
				"time_ms_sum": 28,
				"time_ms_max": 17,
				"search_type_counts": {"osla": 2},
			},
		},
	]
	var read := SummaryClass.summarize_rows(rows)
	if not read.ok:
		return read
	var summary: Dictionary = read.value
	if int(summary.get("total_matches", 0)) != 3:
		return Result.failure("summary should count total matches: %s" % str(summary))
	if int(summary.get("total_failures", 0)) != 1:
		return Result.failure("summary should count total failures: %s" % str(summary))
	var bots: Dictionary = summary.get("bots", {})
	var strategy: Dictionary = bots.get("strategy", {})
	if int(strategy.get("matches", 0)) != 2 or int(strategy.get("failures", 0)) != 1:
		return Result.failure("strategy aggregate mismatch: %s" % str(strategy))
	if float(strategy.get("avg_steps", 0.0)) != 12.0:
		return Result.failure("strategy avg_steps mismatch: %s" % str(strategy))
	var actions: Dictionary = strategy.get("action_totals", {})
	if int(actions.get("recruit", 0)) != 3 or int(actions.get("fire", 0)) != 1:
		return Result.failure("strategy action totals mismatch: %s" % str(actions))
	var action_avg: Dictionary = strategy.get("action_avg_per_match", {})
	if float(action_avg.get("recruit", 0.0)) != 1.5:
		return Result.failure("strategy action averages mismatch: %s" % str(action_avg))
	var mandatory: Dictionary = strategy.get("mandatory_completion_totals", {})
	if int(mandatory.get("set_price", 0)) != 3:
		return Result.failure("strategy mandatory completion totals mismatch: %s" % str(mandatory))
	var mandatory_avg: Dictionary = strategy.get("mandatory_completion_avg_per_match", {})
	if float(mandatory_avg.get("set_price", 0.0)) != 1.5:
		return Result.failure("strategy mandatory completion averages mismatch: %s" % str(mandatory_avg))
	var untraced: Dictionary = strategy.get("untraced_mandatory_completion_totals", {})
	if int(untraced.get("set_price", 0)) != 2:
		return Result.failure("strategy untraced mandatory completion totals mismatch: %s" % str(untraced))
	var milestone_counts: Dictionary = strategy.get("milestone_counts", {})
	if int(milestone_counts.get("first_train", 0)) != 4:
		return Result.failure("strategy milestone first_train count mismatch: %s" % str(milestone_counts))
	if int(milestone_counts.get("first_burger_produced", 0)) != 1:
		return Result.failure("strategy milestone first_burger_produced count mismatch: %s" % str(milestone_counts))
	if int(milestone_counts.get("first_waitress", 0)) != 1:
		return Result.failure("strategy milestone first_waitress count mismatch: %s" % str(milestone_counts))
	var failed_seeds: Array = strategy.get("failed_seeds", [])
	if failed_seeds.size() != 1 or int(failed_seeds[0]) != 2:
		return Result.failure("strategy failed seeds mismatch: %s" % str(failed_seeds))
	var players: Dictionary = strategy.get("players", {})
	var cash: Dictionary = players.get("cash", {})
	var cash_avg: Array = cash.get("avg", [])
	if cash_avg.size() != 2 or float(cash_avg[0]) != 2.0 or float(cash_avg[1]) != 3.0:
		return Result.failure("strategy cash averages mismatch: %s" % str(cash))
	var cash_min_seen: Dictionary = players.get("cash_min_seen", {})
	var cash_min_seen_min: Array = cash_min_seen.get("min", [])
	if cash_min_seen_min.size() != 2 or float(cash_min_seen_min[0]) != 0.0 or float(cash_min_seen_min[1]) != 0.0:
		return Result.failure("strategy cash min seen mismatch: %s" % str(cash_min_seen))
	var cash_min_after_first_positive: Dictionary = players.get("cash_min_after_first_positive", {})
	var cash_min_after_first_positive_min: Array = cash_min_after_first_positive.get("min", [])
	if cash_min_after_first_positive_min.size() != 2 or float(cash_min_after_first_positive_min[0]) != 1.0 or float(cash_min_after_first_positive_min[1]) != 2.0:
		return Result.failure("strategy cash min after first positive mismatch: %s" % str(cash_min_after_first_positive))
	var cash_max_seen: Dictionary = players.get("cash_max_seen", {})
	var cash_max_seen_max: Array = cash_max_seen.get("max", [])
	if cash_max_seen_max.size() != 2 or float(cash_max_seen_max[0]) != 20.0 or float(cash_max_seen_max[1]) != 18.0:
		return Result.failure("strategy cash max seen mismatch: %s" % str(cash_max_seen))
	var restaurants: Dictionary = players.get("restaurants", {})
	var restaurants_max: Array = restaurants.get("max", [])
	if restaurants_max.size() != 2 or float(restaurants_max[1]) != 2.0:
		return Result.failure("strategy restaurant max mismatch: %s" % str(restaurants))
	var opening: Dictionary = Dictionary(strategy.get("opening", {}))
	if float(opening.get("players_without_positive_cash_avg_per_match", 0.0)) != 0.5:
		return Result.failure("strategy opening no-positive cash average mismatch: %s" % str(opening))
	if float(opening.get("first_positive_cash_round_avg", 0.0)) != 2.333:
		return Result.failure("strategy opening first-positive round average mismatch: %s" % str(opening))
	if float(opening.get("food_recruit_to_produce_round_delay_avg", 0.0)) != 1.333:
		return Result.failure("strategy opening food recruit round delay mismatch: %s" % str(opening))
	if float(opening.get("food_recruit_to_produce_step_delay_avg", 0.0)) != 4.333:
		return Result.failure("strategy opening food recruit step delay mismatch: %s" % str(opening))
	var opening_scalars: Dictionary = Dictionary(opening.get("scalar_avg_per_match", {}))
	if float(opening_scalars.get("pre_revenue_errand_boy_recruit_count", 0.0)) != 0.5 or float(opening_scalars.get("pre_revenue_procure_drinks_count", 0.0)) != 0.5:
		return Result.failure("strategy opening scalar averages mismatch: %s" % str(opening_scalars))
	var osla: Dictionary = bots.get("osla", {})
	if float(osla.get("success_rate", 0.0)) != 1.0:
		return Result.failure("osla success rate mismatch: %s" % str(osla))
	var osla_search: Dictionary = Dictionary(osla.get("search", {}))
	if int(osla_search.get("decision_count_total", 0)) != 2:
		return Result.failure("osla search decision count mismatch: %s" % str(osla_search))
	if float(osla_search.get("budget_expired_rate", 0.0)) != 0.5:
		return Result.failure("osla search budget expired rate mismatch: %s" % str(osla_search))
	if float(osla_search.get("budget_expired_avg_per_match", 0.0)) != 1.0:
		return Result.failure("osla search budget expired average mismatch: %s" % str(osla_search))
	if float(osla_search.get("time_ms_avg_per_match", 0.0)) != 28.0:
		return Result.failure("osla search time average mismatch: %s" % str(osla_search))
	if float(osla_search.get("attempted_simulations_avg_per_decision", 0.0)) != 3.5:
		return Result.failure("osla search attempted avg mismatch: %s" % str(osla_search))
	var osla_tuning: Dictionary = Dictionary(osla.get("tuning_objective", {}))
	if float(osla_tuning.get("score", 0.0)) <= 0.0:
		return Result.failure("osla tuning objective should expose positive score: %s" % str(osla_tuning))
	var osla_tuning_components: Dictionary = Dictionary(osla_tuning.get("components", {}))
	if not osla_tuning_components.has("cash_min_after_first_positive_avg") or not osla_tuning_components.has("cash_max_seen_avg"):
		return Result.failure("osla tuning objective should expose transparent components: %s" % str(osla_tuning))
	if not osla_tuning_components.has("opening_players_without_positive_cash_avg") or not osla_tuning_components.has("pre_revenue_errand_boy_recruit_avg"):
		return Result.failure("osla tuning objective should expose opening-quality components: %s" % str(osla_tuning))
	if not osla_tuning_components.has("opening_food_recruit_to_produce_round_delay_avg") or not osla_tuning_components.has("opening_food_recruit_to_produce_step_delay_avg"):
		return Result.failure("osla tuning objective should expose food tempo components: %s" % str(osla_tuning))
	if not osla_tuning_components.has("cash_avg") or not osla_tuning_components.has("inventory_units_avg") or not osla_tuning_components.has("opening_first_positive_cash_step_avg"):
		return Result.failure("osla tuning objective should expose tie-breaker components: %s" % str(osla_tuning))
	if osla_tuning_components.has("search_time_ms_avg_per_match") or osla_tuning_components.has("search_budget_expired_avg_per_match"):
		return Result.failure("osla tuning objective should not include search-cost penalties: %s" % str(osla_tuning_components))
	var osla_tuning_weights: Dictionary = Dictionary(osla_tuning.get("weights", {}))
	if osla_tuning_weights.has("search_time_ms_avg_per_match") or osla_tuning_weights.has("search_budget_expired_avg_per_match"):
		return Result.failure("osla tuning objective weights should not include search-cost penalties: %s" % str(osla_tuning_weights))
	var comparison: Dictionary = Dictionary(summary.get("comparison", {}))
	if str(comparison.get("baseline", "")) != "strategy":
		return Result.failure("summary comparison should use strategy baseline: %s" % str(comparison))
	var comparison_bots: Dictionary = Dictionary(comparison.get("bots", {}))
	var osla_compare: Dictionary = Dictionary(comparison_bots.get("osla", {}))
	if osla_compare.is_empty():
		return Result.failure("summary comparison should include osla delta: %s" % str(comparison))
	if float(osla_compare.get("success_rate_delta", 0.0)) != 0.5:
		return Result.failure("osla success delta mismatch: %s" % str(osla_compare))
	if float(osla_compare.get("avg_round_delta", 0.0)) != 1.0:
		return Result.failure("osla round delta mismatch: %s" % str(osla_compare))
	if not osla_compare.has("tuning_score_delta") or float(osla_compare.get("tuning_score_delta", 0.0)) <= 0.0:
		return Result.failure("osla tuning objective delta mismatch: %s" % str(osla_compare))
	var action_delta: Dictionary = Dictionary(osla_compare.get("action_avg_per_match_delta", {}))
	if float(action_delta.get("recruit", 0.0)) != -0.5 or float(action_delta.get("produce_food", 0.0)) != 2.0:
		return Result.failure("osla action delta mismatch: %s" % str(action_delta))
	var milestone_delta: Dictionary = Dictionary(osla_compare.get("milestone_count_delta", {}))
	if float(milestone_delta.get("first_burger_produced", 0.0)) != -1.0:
		return Result.failure("osla milestone delta mismatch: %s" % str(milestone_delta))
	var player_delta: Dictionary = Dictionary(osla_compare.get("player_avg_delta", {}))
	var cash_after_delta: Array = Array(player_delta.get("cash_min_after_first_positive", []))
	if cash_after_delta.size() != 2 or float(cash_after_delta[0]) != 3.5 or float(cash_after_delta[1]) != 2.0:
		return Result.failure("osla player cash delta mismatch: %s" % str(player_delta))
	var search_delta: Dictionary = Dictionary(osla_compare.get("search_delta", {}))
	if float(search_delta.get("decision_count_avg_per_match", 0.0)) != 2.0:
		return Result.failure("osla search decision delta mismatch: %s" % str(search_delta))
	if float(search_delta.get("budget_expired_rate", 0.0)) != 0.5:
		return Result.failure("osla search expired delta mismatch: %s" % str(search_delta))
	var opening_delta: Dictionary = Dictionary(osla_compare.get("opening_delta", {}))
	if float(opening_delta.get("players_without_positive_cash_avg_per_match", 0.0)) != -0.5:
		return Result.failure("osla opening delta mismatch: %s" % str(opening_delta))
	if float(opening_delta.get("food_recruit_to_produce_round_delay_avg", 0.0)) != -0.333:
		return Result.failure("osla opening food delay delta mismatch: %s" % str(opening_delta))
	return Result.success()

static func _test_format_summary() -> Result:
	var read := SummaryClass.summarize_rows([
		{
			"bot": "strategy",
			"ok": true,
			"seed": 7,
			"round": 4,
			"steps": 8,
			"command_count": 8,
			"action_counts": {"recruit": 1},
			"player_cash_min_after_first_positive": [3, 5],
			"player_cash_max_seen": [8, 9],
			"player_milestone_ids": [["first_train"], []],
			"opening_metrics": {
				"players_with_positive_cash": 1,
				"players_without_positive_cash": 1,
				"first_positive_cash_rounds": [3, -1],
				"first_positive_cash_steps": [5, -1],
				"first_food_recruit_rounds": [1, -1],
				"first_food_recruit_steps": [1, -1],
				"first_produce_food_rounds": [3, -1],
				"first_produce_food_steps": [5, -1],
				"food_recruit_to_produce_round_delays": [2, -1],
				"food_recruit_to_produce_step_delays": [4, -1],
				"pre_revenue_action_counts": {"recruit": 1},
				"pre_revenue_recruit_counts": {"errand_boy": 1},
				"pre_revenue_recruit_count": 1,
				"pre_revenue_errand_boy_recruit_count": 1,
				"pre_revenue_pricing_manager_recruit_count": 0,
				"pre_revenue_procure_drinks_count": 0,
			},
			"search_metrics": {},
		},
		{
			"bot": "beam",
			"ok": true,
			"seed": 7,
			"round": 4,
			"steps": 9,
			"command_count": 9,
			"action_counts": {"skip": 2},
			"mandatory_completion_counts": {"set_price": 1},
			"untraced_mandatory_completion_counts": {"set_price": 1},
			"player_cash": [0, 0],
			"player_cash_min_seen": [0, 0],
			"player_cash_min_after_first_positive": [4, 6],
			"player_cash_max_seen": [10, 10],
			"player_milestone_ids": [["first_train"], []],
			"opening_metrics": {
				"players_with_positive_cash": 2,
				"players_without_positive_cash": 0,
				"first_positive_cash_rounds": [2, 2],
				"first_positive_cash_steps": [4, 4],
				"first_food_recruit_rounds": [1, 1],
				"first_food_recruit_steps": [1, 1],
				"first_produce_food_rounds": [2, 2],
				"first_produce_food_steps": [4, 4],
				"food_recruit_to_produce_round_delays": [1, 1],
				"food_recruit_to_produce_step_delays": [3, 3],
				"pre_revenue_action_counts": {"produce_food": 1},
				"pre_revenue_recruit_counts": {},
				"pre_revenue_recruit_count": 0,
				"pre_revenue_errand_boy_recruit_count": 0,
				"pre_revenue_pricing_manager_recruit_count": 0,
				"pre_revenue_procure_drinks_count": 0,
			},
			"search_metrics": {
				"decision_count": 1,
				"budget_expired_count": 0,
				"attempted_simulations": 3,
				"expanded_nodes": 2,
				"time_ms_sum": 9,
				"time_ms_max": 9,
				"search_type_counts": {"beam": 1},
			},
		},
	])
	if not read.ok:
		return read
	var lines := SummaryClass.format_summary(read.value)
	if not _has_line_containing(lines, "SUMMARY matches=2 failures=0 bots=2"):
		return Result.failure("formatted summary should include totals: %s" % str(lines))
	if not _has_line_containing(lines, "BOT beam matches=1 ok=1 failures=0"):
		return Result.failure("formatted summary should include beam aggregate: %s" % str(lines))
	if not _has_line_containing(lines, "ACTIONS beam skip=2"):
		return Result.failure("formatted summary should include action totals: %s" % str(lines))
	if not _has_line_containing(lines, "MANDATORY beam set_price=1"):
		return Result.failure("formatted summary should include mandatory completion totals: %s" % str(lines))
	if not _has_line_containing(lines, "UNTRACED_MANDATORY beam set_price=1"):
		return Result.failure("formatted summary should include untraced mandatory completion totals: %s" % str(lines))
	if not _has_line_containing(lines, "MILESTONES beam first_train=1"):
		return Result.failure("formatted summary should include milestone counts: %s" % str(lines))
	if not _has_line_containing(lines, "OPENING beam positive_cash_avg=2.000 no_positive_cash_avg=0.000"):
		return Result.failure("formatted summary should include opening diagnostics: %s" % str(lines))
	if not _has_line_containing(lines, "food_delay_round_avg=1.000 food_delay_step_avg=3.000"):
		return Result.failure("formatted summary should include food tempo diagnostics: %s" % str(lines))
	if not _has_line_containing(lines, "SEARCH beam decisions=1 budget_expired=0"):
		return Result.failure("formatted summary should include search metrics: %s" % str(lines))
	if not _has_line_containing(lines, "TUNING beam score="):
		return Result.failure("formatted summary should include tuning objective: %s" % str(lines))
	if not _has_line_containing(lines, "cash_min_after_first_positive_avg=[4.0, 6.0]"):
		return Result.failure("formatted summary should include cash after positive metric: %s" % str(lines))
	if not _has_line_containing(lines, "BASELINE strategy"):
		return Result.failure("formatted summary should include comparison baseline: %s" % str(lines))
	if not _has_line_containing(lines, "COMPARE beam vs strategy"):
		return Result.failure("formatted summary should include bot comparison: %s" % str(lines))
	if not _has_line_containing(lines, "cash_min_after_positive_delta=[1.0, 1.0]"):
		return Result.failure("formatted summary should include player metric deltas: %s" % str(lines))
	if not _has_line_containing(lines, "search_delta="):
		return Result.failure("formatted summary should include search deltas: %s" % str(lines))
	if not _has_line_containing(lines, "opening_delta="):
		return Result.failure("formatted summary should include opening deltas: %s" % str(lines))
	if not _has_line_containing(lines, "tuning_score_delta="):
		return Result.failure("formatted summary should include tuning objective delta: %s" % str(lines))
	return Result.success()

static func _test_bot_config_groups_mixed_matchups() -> Result:
	var read := SummaryClass.summarize_rows([
		{
			"bot": "mixed",
			"bot_config": "strategy_vs_beam",
			"bot_ids": ["strategy", "beam"],
			"ok": true,
			"seed": 9,
			"round": 2,
			"steps": 5,
			"command_count": 5,
			"action_counts": {"skip": 1},
		},
	])
	if not read.ok:
		return read
	var bots: Dictionary = Dictionary(read.value.get("bots", {}))
	if not bots.has("strategy_vs_beam"):
		return Result.failure("summary should group mixed rows by bot_config: %s" % str(bots))
	if bots.has("mixed"):
		return Result.failure("summary should not group mixed rows by bot when bot_config exists: %s" % str(bots))
	var matchup: Dictionary = bots.get("strategy_vs_beam", {})
	if int(matchup.get("matches", 0)) != 1 or float(matchup.get("success_rate", 0.0)) != 1.0:
		return Result.failure("mixed matchup aggregate mismatch: %s" % str(matchup))
	return Result.success()

static func _has_line_containing(lines: Array, needle: String) -> bool:
	for line in lines:
		if str(line).contains(needle):
			return true
	return false
