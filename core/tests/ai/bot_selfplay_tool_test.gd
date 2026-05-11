class_name BotSelfplayToolTest
extends RefCounted

const SelfplayToolClass = preload("res://tools/run_bot_selfplay.gd")
const BotSelfplaySummaryClass = preload("res://tools/bot_selfplay_summary.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var parse := _test_parse_mixed_bot_args()
	if not parse.ok:
		return parse
	var legacy_mcts_removed := _test_legacy_mcts_bot_removed()
	if not legacy_mcts_removed.ok:
		return legacy_mcts_removed
	var strategic_support := _test_strategic_bot_support()
	if not strategic_support.ok:
		return strategic_support
	var mandatory_summary := _test_mandatory_completion_summary_counts_untraced_auto_actions()
	if not mandatory_summary.ok:
		return mandatory_summary
	var smoke := _test_run_mixed_bot_config()
	if not smoke.ok:
		return smoke
	return Result.success({"cases": 5})

static func _test_parse_mixed_bot_args() -> Result:
	var parsed := SelfplayToolClass._parse_args([
		"--players=2",
		"--bots=random,strategy",
		"--profile=base_revenue_growth_v1",
		"--matches=1",
		"--trace-detail=decision",
	])
	if not parsed.ok:
		return parsed
	var options: Dictionary = parsed.value
	var bot_ids: Array = options.get("bot_ids", [])
	if bot_ids.size() != 2 or str(bot_ids[0]) != "random" or str(bot_ids[1]) != "strategy":
		return Result.failure("--bots parse mismatch: %s" % str(options))
	if str(options.get("profile", "")) != "base_revenue_growth_v1":
		return Result.failure("--profile parse mismatch: %s" % str(options))
	if str(options.get("trace_detail", "")) != "decision":
		return Result.failure("--trace-detail parse mismatch: %s" % str(options))
	var resolved := SelfplayToolClass._resolve_bot_ids(options, 2)
	if not resolved.ok:
		return resolved
	if str(resolved.value) != str(["random", "strategy"]):
		return Result.failure("resolved bot ids mismatch: %s" % str(resolved.value))
	var config_id := SelfplayToolClass._bot_config_id(resolved.value)
	if config_id != "random_vs_strategy":
		return Result.failure("bot config id mismatch: %s" % config_id)
	var conflict := SelfplayToolClass._parse_args(["--bot=strategy", "--bots=random,strategy"])
	if conflict.ok:
		return Result.failure("--bot and --bots conflict should fail")
	var empty_bot := SelfplayToolClass._parse_args(["--bots=random,"])
	if empty_bot.ok:
		return Result.failure("--bots should reject empty bot ids")
	var empty_profile := SelfplayToolClass._parse_args(["--profile="])
	if empty_profile.ok:
		return Result.failure("--profile should reject empty profile ids")
	var invalid_trace_detail := SelfplayToolClass._parse_args(["--trace-detail=full"])
	if invalid_trace_detail.ok:
		return Result.failure("--trace-detail should reject unsupported modes")
	return Result.success()

static func _test_legacy_mcts_bot_removed() -> Result:
	if SelfplayToolClass.SUPPORTED_BOT_IDS.has("mcts"):
		return Result.failure("SUPPORTED_BOT_IDS should not expose legacy mcts: %s" % str(SelfplayToolClass.SUPPORTED_BOT_IDS))
	var parsed := SelfplayToolClass._parse_args(["--bot=mcts"])
	if not parsed.ok:
		return parsed
	var resolved := SelfplayToolClass._resolve_bot_ids(Dictionary(parsed.value), 1)
	if resolved.ok:
		return Result.failure("--bot=mcts should no longer resolve as a supported bot")
	var bot_read := SelfplayToolClass._create_bot("mcts", "base_revenue_growth_v1", {})
	if bot_read.ok:
		return Result.failure("_create_bot should reject legacy mcts")
	return Result.success()

static func _test_strategic_bot_support() -> Result:
	if not SelfplayToolClass.SUPPORTED_BOT_IDS.has("strategic"):
		return Result.failure("SUPPORTED_BOT_IDS should include strategic: %s" % str(SelfplayToolClass.SUPPORTED_BOT_IDS))
	var parsed := SelfplayToolClass._parse_args([
		"--bot=strategic",
		"--matches=1",
		"--strategic-search=mcts",
		"--strategic-budget-profile=play",
		"--strategic-horizon-decisions=8",
		"--strategic-horizon-rounds=1",
		"--strategic-max-plans=3",
		"--strategic-rollout-step-budget-ms=12",
		"--strategic-min-search-budget-ms=260",
		"--strategic-min-plans-for-rollout=2",
		"--strategic-mcts-iterations=8",
		"--strategic-mcts-max-depth=2",
		"--strategic-mcts-top-k-per-node=3",
		"--strategic-mcts-exploration=1.1",
		"--strategic-mcts-prior-weight=0.25",
		"--strategic-mcts-root-prior-min-visits-per-child=3",
		"--strategic-config-id=fast_plan",
	])
	if not parsed.ok:
		return parsed
	if str(Dictionary(parsed.value).get("bot_id", "")) != "strategic":
		return Result.failure("--bot should parse strategic: %s" % str(parsed.value))
	var strategic_options: Dictionary = Dictionary(Dictionary(parsed.value).get("strategic_options", {}))
	if str(strategic_options.get("strategic_search", "")) != "mcts":
		return Result.failure("--strategic-search parse mismatch: %s" % str(parsed.value))
	if str(strategic_options.get("strategic_budget_profile", "")) != "play":
		return Result.failure("--strategic-budget-profile parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("strategic_horizon_decisions", 0)) != 8:
		return Result.failure("--strategic-horizon-decisions parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("strategic_horizon_rounds", 0)) != 1:
		return Result.failure("--strategic-horizon-rounds parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("strategic_max_plans", 0)) != 3:
		return Result.failure("--strategic-max-plans parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("strategic_rollout_step_budget_ms", 0)) != 12:
		return Result.failure("--strategic-rollout-step-budget-ms parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("strategic_min_search_budget_ms", 0)) != 260:
		return Result.failure("--strategic-min-search-budget-ms parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("strategic_min_plans_for_rollout", 0)) != 2:
		return Result.failure("--strategic-min-plans-for-rollout parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("mcts_iterations", 0)) != 8:
		return Result.failure("--strategic-mcts-iterations parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("mcts_max_depth", 0)) != 2:
		return Result.failure("--strategic-mcts-max-depth parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("mcts_top_k_per_node", 0)) != 3:
		return Result.failure("--strategic-mcts-top-k-per-node parse mismatch: %s" % str(parsed.value))
	if not is_equal_approx(float(strategic_options.get("mcts_exploration", 0.0)), 1.1):
		return Result.failure("--strategic-mcts-exploration parse mismatch: %s" % str(parsed.value))
	if not is_equal_approx(float(strategic_options.get("mcts_prior_weight", 0.0)), 0.25):
		return Result.failure("--strategic-mcts-prior-weight parse mismatch: %s" % str(parsed.value))
	if int(strategic_options.get("mcts_root_prior_min_visits_per_child", 0)) != 3:
		return Result.failure("--strategic-mcts-root-prior-min-visits-per-child parse mismatch: %s" % str(parsed.value))
	var display_config := SelfplayToolClass._bot_config_id(SelfplayToolClass._bot_config_ids_for_display(["strategic"], strategic_options))
	if display_config != "strategic-fast_plan":
		return Result.failure("strategic display config should include config id: %s" % display_config)
	var default_display_config := SelfplayToolClass._bot_config_id(SelfplayToolClass._bot_config_ids_for_display(["strategic"], {}))
	if default_display_config != "strategic-play":
		return Result.failure("strategic display config should default to play budget profile: %s" % default_display_config)
	var tuning_display_config := SelfplayToolClass._bot_config_id(SelfplayToolClass._bot_config_ids_for_display(["strategic"], {
		"strategic_config_id": "fast_plan",
		"strategic_budget_profile": "tuning",
	}))
	if tuning_display_config != "strategic-fast_plan-tuning":
		return Result.failure("strategic display config should distinguish tuning budget profile: %s" % tuning_display_config)
	var bot_read := SelfplayToolClass._create_bot("strategic", "base_revenue_growth_v1", strategic_options)
	if not bot_read.ok:
		return bot_read
	var bot = bot_read.value
	if bot == null or not bot.has_method("choose_command_with_engine"):
		return Result.failure("strategic bot should expose choose_command_with_engine")
	var bad_search := SelfplayToolClass._parse_args(["--strategic-search=random"])
	if bad_search.ok:
		return Result.failure("--strategic-search should reject unsupported mode")
	var bad_step_budget := SelfplayToolClass._parse_args(["--strategic-rollout-step-budget-ms=0"])
	if bad_step_budget.ok:
		return Result.failure("--strategic-rollout-step-budget-ms should reject non-positive values")
	var bad_min_search := SelfplayToolClass._parse_args(["--strategic-min-search-budget-ms=0"])
	if bad_min_search.ok:
		return Result.failure("--strategic-min-search-budget-ms should reject non-positive values")
	var bad_min_plans := SelfplayToolClass._parse_args(["--strategic-min-plans-for-rollout=0"])
	if bad_min_plans.ok:
		return Result.failure("--strategic-min-plans-for-rollout should reject non-positive values")
	return Result.success()

static func _test_mandatory_completion_summary_counts_untraced_auto_actions() -> Result:
	var bot_trace: Array[Dictionary] = [
		{
			"action_id": "skip_sub_phase",
			"macro_action_id": "working_skip_sub_phase",
			"phase_before": "Working",
			"sub_phase_before": "Recruit",
			"phase_after": "Working",
			"sub_phase_after": "Train",
			"mandatory_actions_completed_added": [
				{"player_id": 1, "action_id": "set_price"},
			],
		},
		{
			"action_id": "set_price",
			"macro_action_id": "mandatory_set_price",
			"mandatory_actions_completed_added": [
				{"player_id": 0, "action_id": "set_price"},
			],
		},
	]

	var counts := SelfplayToolClass._mandatory_completion_counts(bot_trace)
	if int(counts.get("set_price", 0)) != 2:
		return Result.failure("mandatory completion counts should include set_price twice: %s" % str(counts))

	var untraced := SelfplayToolClass._untraced_mandatory_completion_counts(bot_trace)
	if int(untraced.get("set_price", 0)) != 1:
		return Result.failure("untraced mandatory completion counts should include auto set_price once: %s" % str(untraced))

	var trace_tail := SelfplayToolClass._trace_tail(bot_trace, 2)
	if not Dictionary(trace_tail[0]).has("mandatory_actions_completed_added"):
		return Result.failure("trace tail should expose mandatory completions: %s" % str(trace_tail))

	var tail := SelfplayToolClass._mandatory_completion_tail(bot_trace, 1)
	if tail.size() != 1:
		return Result.failure("mandatory completion tail should include direct set_price: %s" % str(tail))
	var tail_row: Dictionary = tail[0]
	if str(tail_row.get("action_id", "")) != "set_price" or str(tail_row.get("completed_by_action_id", "")) != "set_price":
		return Result.failure("mandatory completion tail row mismatch: %s" % str(tail_row))
	var cash_trace: Array[Dictionary] = [
		{
			"player_cash_before": [0, 0],
			"player_cash_after": [0, 4],
		},
		{
			"player_cash_before": [6, 4],
			"player_cash_after": [2, 0],
		},
	]
	var cash_min_after_positive := SelfplayToolClass._trace_player_cash_min_after_first_positive(cash_trace)
	if cash_min_after_positive.size() != 2 or int(cash_min_after_positive[0]) != 2 or int(cash_min_after_positive[1]) != 0:
		return Result.failure("cash min after first positive mismatch: %s" % str(cash_min_after_positive))
	var search_trace: Array[Dictionary] = [
		{
			"explanation": {
				"attempted_simulations": 3,
				"expanded_nodes": 0,
				"budget_expired": false,
			},
			"decision_trace": {
				"search": "osla",
				"time_ms": 11,
			},
		},
		{
			"explanation": {
				"attempted_simulations": 4,
				"expanded_nodes": 2,
				"budget_expired": true,
			},
			"decision_trace": {
				"search": "beam",
				"time_ms": 17,
			},
		},
		{
			"explanation": {},
			"decision_trace": {},
		},
	]
	var search_metrics := SelfplayToolClass._trace_search_metrics(search_trace)
	if int(search_metrics.get("decision_count", 0)) != 2:
		return Result.failure("search metrics should count search decisions: %s" % str(search_metrics))
	if int(search_metrics.get("budget_expired_count", 0)) != 1:
		return Result.failure("search metrics should count budget expiry: %s" % str(search_metrics))
	if int(search_metrics.get("attempted_simulations", 0)) != 7 or int(search_metrics.get("expanded_nodes", 0)) != 2:
		return Result.failure("search metrics should aggregate simulations and expansions: %s" % str(search_metrics))
	if float(search_metrics.get("time_ms_avg_per_decision", 0.0)) != 14.0:
		return Result.failure("search metrics should average time per decision: %s" % str(search_metrics))
	var type_counts: Dictionary = Dictionary(search_metrics.get("search_type_counts", {}))
	if int(type_counts.get("osla", 0)) != 1 or int(type_counts.get("beam", 0)) != 1:
		return Result.failure("search metrics should count search types: %s" % str(search_metrics))
	var strategic_search_trace: Array[Dictionary] = [
		{
			"explanation": {
				"attempted_simulations": 5,
				"expanded_nodes": 3,
				"budget_expired": false,
				"mcts_route_switch_count": 2,
				"mcts_non_root_populated_nodes": 4,
				"mcts_non_root_expanded_nodes": 1,
				"mcts_non_root_candidate_count": 6,
			},
			"decision_trace": {
				"search": "strategic",
				"time_ms": 13,
				"mcts_selected_route_types": ["marketing_income", "price_recovery", "supply_capacity"],
			},
		},
		{
			"explanation": {
				"attempted_simulations": 4,
				"expanded_nodes": 2,
				"budget_expired": true,
				"mcts_route_switch_count": 1,
				"mcts_non_root_populated_nodes": 2,
				"mcts_non_root_expanded_nodes": 1,
				"mcts_non_root_candidate_count": 5,
			},
			"decision_trace": {
				"search": "strategic_cached",
				"time_ms": 17,
				"mcts_selected_route_types": ["price_recovery", "price_recovery", "growth"],
			},
		},
	]
	var strategic_search_metrics := SelfplayToolClass._trace_search_metrics(strategic_search_trace)
	if int(strategic_search_metrics.get("decision_count", 0)) != 2:
		return Result.failure("strategic search metrics should count strategic decisions: %s" % str(strategic_search_metrics))
	if int(strategic_search_metrics.get("mcts_route_switch_count", 0)) != 3:
		return Result.failure("strategic search metrics should sum route switches: %s" % str(strategic_search_metrics))
	if int(strategic_search_metrics.get("mcts_non_root_populated_nodes", 0)) != 6:
		return Result.failure("strategic search metrics should sum non-root populated nodes: %s" % str(strategic_search_metrics))
	if int(strategic_search_metrics.get("mcts_non_root_expanded_nodes", 0)) != 2:
		return Result.failure("strategic search metrics should sum non-root expanded nodes: %s" % str(strategic_search_metrics))
	if int(strategic_search_metrics.get("mcts_non_root_candidate_count", 0)) != 11:
		return Result.failure("strategic search metrics should sum non-root candidate counts: %s" % str(strategic_search_metrics))
	var strategic_route_counts: Dictionary = Dictionary(strategic_search_metrics.get("mcts_selected_route_type_counts", {}))
	if int(strategic_route_counts.get("marketing_income", 0)) != 1 or int(strategic_route_counts.get("price_recovery", 0)) != 3 or int(strategic_route_counts.get("supply_capacity", 0)) != 1 or int(strategic_route_counts.get("growth", 0)) != 1:
		return Result.failure("strategic search metrics should count selected route types: %s" % str(strategic_search_metrics))
	var strategic_summary_read := BotSelfplaySummaryClass.summarize_rows([
		{
			"bot": "strategic-plan@base_revenue_growth_v1",
			"bot_config": "strategic-plan@base_revenue_growth_v1",
			"ok": true,
			"round": 8,
			"steps": 120,
			"command_count": 120,
			"search_metrics": strategic_search_metrics,
		},
	])
	if not strategic_summary_read.ok:
		return strategic_summary_read
	var strategic_summary: Dictionary = strategic_summary_read.value
	var strategic_bots: Dictionary = Dictionary(strategic_summary.get("bots", {}))
	var strategic_bot_summary: Dictionary = Dictionary(strategic_bots.get("strategic-plan@base_revenue_growth_v1", {}))
	var strategic_search_summary: Dictionary = Dictionary(strategic_bot_summary.get("search", {}))
	if int(strategic_search_summary.get("mcts_route_switch_count_total", 0)) != 3:
		return Result.failure("summary should preserve mcts route switch totals: %s" % str(strategic_search_summary))
	if int(strategic_search_summary.get("strategic_decision_count_total", 0)) != 2:
		return Result.failure("summary should preserve strategic decision totals: %s" % str(strategic_search_summary))
	if int(strategic_search_summary.get("strategic_cached_count_total", 0)) != 1:
		return Result.failure("summary should preserve strategic cached totals: %s" % str(strategic_search_summary))
	if float(strategic_search_summary.get("strategic_cached_rate", 0.0)) != 0.5:
		return Result.failure("summary should preserve strategic cached rate: %s" % str(strategic_search_summary))
	if int(strategic_search_summary.get("mcts_non_root_populated_nodes_total", 0)) != 6:
		return Result.failure("summary should preserve non-root populated totals: %s" % str(strategic_search_summary))
	if int(strategic_search_summary.get("mcts_non_root_expanded_nodes_total", 0)) != 2:
		return Result.failure("summary should preserve non-root expanded totals: %s" % str(strategic_search_summary))
	if int(strategic_search_summary.get("mcts_non_root_candidate_count_total", 0)) != 11:
		return Result.failure("summary should preserve non-root candidate totals: %s" % str(strategic_search_summary))
	if int(Dictionary(strategic_search_summary.get("mcts_selected_route_type_counts", {})).get("price_recovery", 0)) != 3:
		return Result.failure("summary should preserve selected route type counts: %s" % str(strategic_search_summary))
	var strategic_lines: Array[String] = BotSelfplaySummaryClass.format_summary(strategic_summary)
	var strategic_search_line := ""
	var strategic_route_line := ""
	for line in strategic_lines:
		if str(line).begins_with("[BotSelfplaySummary] SEARCH strategic-plan@base_revenue_growth_v1 "):
			strategic_search_line = str(line)
		elif str(line).begins_with("[BotSelfplaySummary] MCTS_ROUTE strategic-plan@base_revenue_growth_v1 "):
			strategic_route_line = str(line)
	if strategic_search_line.is_empty():
		return Result.failure("summary should emit strategic search line: %s" % str(strategic_lines))
	if not strategic_search_line.contains("strategic_total=2") or not strategic_search_line.contains("strategic_cached=1") or not strategic_search_line.contains("strategic_cached_rate=0.500"):
		return Result.failure("summary should expose strategic cache diagnostics: %s" % strategic_search_line)
	if strategic_route_line.is_empty():
		return Result.failure("summary should emit MCTS route line: %s" % str(strategic_lines))
	if not strategic_route_line.contains("route_switch_avg=") or not strategic_route_line.contains("route_types="):
		return Result.failure("summary should expose route switch and route type aggregates: %s" % strategic_route_line)
	var opening_trace: Array[Dictionary] = [
		{
			"player_id": 0,
			"action_id": "recruit",
			"macro_action_id": "recruit_kitchen_trainee",
			"params": {"employee_id": "kitchen_trainee"},
			"round_before": 1,
			"round_after": 1,
			"player_cash_before": [0, 0],
			"player_cash_after": [0, 0],
		},
		{
			"player_id": 0,
			"action_id": "recruit",
			"macro_action_id": "recruit_errand_boy",
			"params": {"employee_id": "errand_boy"},
			"round_before": 1,
			"round_after": 1,
			"player_cash_before": [0, 0],
			"player_cash_after": [0, 0],
		},
		{
			"player_id": 1,
			"action_id": "recruit",
			"macro_action_id": "recruit_pricing_manager",
			"round_before": 1,
			"round_after": 1,
			"player_cash_before": [0, 0],
			"player_cash_after": [0, 0],
		},
		{
			"player_id": 1,
			"action_id": "procure_drinks",
			"macro_action_id": "errand_boy_beer",
			"round_before": 2,
			"round_after": 2,
			"player_cash_before": [0, 0],
			"player_cash_after": [0, 0],
		},
		{
			"player_id": 0,
			"action_id": "produce_food",
			"macro_action_id": "produce_burger",
			"round_before": 3,
			"round_after": 3,
			"player_cash_before": [0, 0],
			"player_cash_after": [5, 0],
		},
	]
	var opening_metrics := SelfplayToolClass._trace_opening_metrics(opening_trace, 2)
	if int(opening_metrics.get("players_with_positive_cash", 0)) != 1 or int(opening_metrics.get("players_without_positive_cash", 0)) != 1:
		return Result.failure("opening metrics should count positive-cash players: %s" % str(opening_metrics))
	var first_rounds: Array = opening_metrics.get("first_positive_cash_rounds", [])
	if first_rounds.size() != 2 or int(first_rounds[0]) != 3 or int(first_rounds[1]) != -1:
		return Result.failure("opening metrics should expose first positive cash rounds: %s" % str(opening_metrics))
	var recruit_counts: Dictionary = Dictionary(opening_metrics.get("pre_revenue_recruit_counts", {}))
	if int(recruit_counts.get("kitchen_trainee", 0)) != 1 or int(recruit_counts.get("errand_boy", 0)) != 1 or int(recruit_counts.get("pricing_manager", 0)) != 1:
		return Result.failure("opening metrics should count pre-revenue recruit ids: %s" % str(opening_metrics))
	if int(opening_metrics.get("pre_revenue_errand_boy_recruit_count", 0)) != 1 or int(opening_metrics.get("pre_revenue_pricing_manager_recruit_count", 0)) != 1 or int(opening_metrics.get("pre_revenue_procure_drinks_count", 0)) != 1:
		return Result.failure("opening metrics should expose tunable pre-revenue route signals: %s" % str(opening_metrics))
	var food_delay_rounds: Array = opening_metrics.get("food_recruit_to_produce_round_delays", [])
	var food_delay_steps: Array = opening_metrics.get("food_recruit_to_produce_step_delays", [])
	if food_delay_rounds.size() != 2 or int(food_delay_rounds[0]) != 2 or int(food_delay_rounds[1]) != -1:
		return Result.failure("opening metrics should expose food recruit to produce round delay: %s" % str(opening_metrics))
	if food_delay_steps.size() != 2 or int(food_delay_steps[0]) != 4 or int(food_delay_steps[1]) != -1:
		return Result.failure("opening metrics should expose food recruit to produce step delay: %s" % str(opening_metrics))
	var opening_tail := SelfplayToolClass._trace_tail(opening_trace, 1)
	var opening_tail_row: Dictionary = Dictionary(opening_tail[0])
	if int(opening_tail_row.get("round_before", -1)) != 3 or int(opening_tail_row.get("round_after", -1)) != 3:
		return Result.failure("trace tail should include round diagnostics: %s" % str(opening_tail))
	return Result.success()

static func _test_run_mixed_bot_config() -> Result:
	var run_read := SelfplayToolClass.run({
		"player_count": 2,
		"start_seed": 12345,
		"matches": 1,
		"target_round": 2,
		"max_steps": 180,
		"budget_ms": 80,
		"trace_tail": 4,
		"bot_ids": ["random", "strategy"],
		"profile": "base_revenue_growth_v1",
	})
	if not run_read.ok:
		return run_read
	var rows: Array = Dictionary(run_read.value).get("rows", [])
	if rows.size() != 1:
		return Result.failure("mixed selfplay should emit one row: %s" % str(run_read.value))
	var row: Dictionary = rows[0]
	if str(row.get("bot_config", "")) != "random_vs_strategy@base_revenue_growth_v1":
		return Result.failure("mixed selfplay row missing bot_config: %s" % str(row))
	if str(row.get("bot_ids", [])) != str(["random", "strategy"]):
		return Result.failure("mixed selfplay row missing bot_ids: %s" % str(row))
	if str(row.get("bot_profile", "")) != "base_revenue_growth_v1":
		return Result.failure("mixed selfplay row missing bot_profile: %s" % str(row))
	if not bool(row.get("ok", false)):
		return Result.failure("mixed selfplay should reach target round: %s" % str(row))
	if int(row.get("round", 0)) < 2:
		return Result.failure("mixed selfplay should reach round 2: %s" % str(row))
	var milestone_ids: Array = row.get("player_milestone_ids", [])
	if milestone_ids.size() != 2:
		return Result.failure("mixed selfplay row should include per-player milestone ids: %s" % str(row))
	var cash_min_seen: Array = row.get("player_cash_min_seen", [])
	var cash_min_after_first_positive: Array = row.get("player_cash_min_after_first_positive", [])
	var cash_max_seen: Array = row.get("player_cash_max_seen", [])
	if not row.has("player_cash_min_after_first_positive"):
		return Result.failure("mixed selfplay row should include cash-after-positive diagnostic key: %s" % str(row))
	if cash_min_seen.size() != 2 or cash_max_seen.size() != 2:
		return Result.failure("mixed selfplay row should include per-player cash min/max diagnostics: %s" % str(row))
	if not cash_min_after_first_positive.is_empty() and cash_min_after_first_positive.size() != 2:
		return Result.failure("cash-after-positive diagnostic should be empty or per-player sized: %s" % str(row))
	var employee_groups: Array = row.get("player_employee_groups", [])
	if employee_groups.size() != 2:
		return Result.failure("mixed selfplay row should include per-player employee groups: %s" % str(row))
	var first_employee_groups := Dictionary(employee_groups[0])
	if not first_employee_groups.has("active") or not first_employee_groups.has("reserve") or not first_employee_groups.has("busy"):
		return Result.failure("employee groups should include active/reserve/busy: %s" % str(first_employee_groups))
	var inventory_details: Array = row.get("player_inventory", [])
	if inventory_details.size() != 2:
		return Result.failure("mixed selfplay row should include per-player inventory details: %s" % str(row))
	var restaurant_details: Array = row.get("player_restaurant_details", [])
	if restaurant_details.size() != 2:
		return Result.failure("mixed selfplay row should include per-player restaurant details: %s" % str(row))
	if not (restaurant_details[0] is Array) or Array(restaurant_details[0]).is_empty():
		return Result.failure("mixed selfplay row should include first player restaurant detail rows: %s" % str(row))
	var first_restaurant_val = Array(restaurant_details[0])[0]
	if not (first_restaurant_val is Dictionary):
		return Result.failure("mixed selfplay restaurant detail should resolve ids to map dictionaries: %s" % str(row))
	var first_restaurant: Dictionary = first_restaurant_val
	if str(first_restaurant.get("restaurant_id", "")).is_empty() or not first_restaurant.has("owner"):
		return Result.failure("mixed selfplay restaurant detail should include id and owner: %s" % str(first_restaurant))
	return Result.success()
