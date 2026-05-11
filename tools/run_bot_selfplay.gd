extends SceneTree

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")
const GreedyBotClass = preload("res://core/ai/bot/greedy_bot.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const OSLABotClass = preload("res://core/ai/bot/osla_bot.gd")
const BeamBotClass = preload("res://core/ai/bot/beam_bot.gd")
const StrategicBotClass = preload("res://core/ai/bot/strategic_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")

const NAME := "BotSelfplay"
const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_START_SEED := 12345
const DEFAULT_MATCHES := 1
const DEFAULT_TARGET_ROUND := 3
const DEFAULT_MAX_STEPS := 720
const DEFAULT_BUDGET_MS := 80
const DEFAULT_MATCH_TIMEOUT_MS := 0
const DEFAULT_TRACE_TAIL := 8
const DEFAULT_TRACE_DETAIL := "compact"
const DEFAULT_BOT_ID := "strategy"
const SUPPORTED_BOT_IDS := ["random", "greedy", "strategy", "osla", "beam", "strategic"]
const SUPPORTED_TRACE_DETAILS := ["compact", "decision"]
const FOOD_PRODUCER_EMPLOYEE_IDS := [
	"kitchen_trainee",
	"burger_cook",
	"pizza_cook",
	"burger_chef",
	"pizza_chef",
	"noodle_cook",
	"noodle_chef",
	"barista_trainee",
	"barista",
	"lead_barista",
	"kimchi_master",
	"sushi_cook",
	"sushi_chef",
	"fry_chef",
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		_print_usage()
		quit(0)
		return
	var parse_result := _parse_args(args)
	if not parse_result.ok:
		push_error("[%s] FAIL %s" % [NAME, parse_result.error])
		_print_usage()
		quit(2)
		return

	var options: Dictionary = parse_result.value
	var run_result := run(options)
	if not run_result.ok:
		push_error("[%s] FAIL %s" % [NAME, run_result.error])
		quit(1)
		return
	print("[%s] PASS matches=%d" % [NAME, int(run_result.value.get("matches", 0))])
	quit(0)

static func run(options: Dictionary) -> Result:
	var player_count := int(options.get("player_count", DEFAULT_PLAYER_COUNT))
	var start_seed := int(options.get("start_seed", DEFAULT_START_SEED))
	var matches := int(options.get("matches", DEFAULT_MATCHES))
	var target_round := int(options.get("target_round", DEFAULT_TARGET_ROUND))
	var max_steps := int(options.get("max_steps", DEFAULT_MAX_STEPS))
	var budget_ms := int(options.get("budget_ms", DEFAULT_BUDGET_MS))
	var match_timeout_ms := int(options.get("match_timeout_ms", DEFAULT_MATCH_TIMEOUT_MS))
	var trace_tail := int(options.get("trace_tail", DEFAULT_TRACE_TAIL))
	var trace_detail := str(options.get("trace_detail", DEFAULT_TRACE_DETAIL)).strip_edges()
	var bot_id := str(options.get("bot_id", DEFAULT_BOT_ID)).strip_edges()
	var output_jsonl := str(options.get("output_jsonl", "")).strip_edges()
	var output_archive := str(options.get("output_archive", "")).strip_edges()
	var strategic_options: Dictionary = Dictionary(options.get("strategic_options", {})).duplicate(true)
	var bot_ids_read := _resolve_bot_ids(options, player_count)
	if not bot_ids_read.ok:
		return bot_ids_read
	var bot_ids: Array[String] = bot_ids_read.value
	var bot_config := _bot_config_id(_bot_config_ids_for_display(bot_ids, strategic_options))
	var profile_source := str(options.get("profile", "")).strip_edges()
	var profile_config := _profile_config_id(profile_source)
	if not profile_config.is_empty():
		bot_config = "%s@%s" % [bot_config, profile_config]

	if player_count <= 0:
		return Result.failure("--players must be > 0")
	if matches <= 0:
		return Result.failure("--matches must be > 0")
	if max_steps <= 0:
		return Result.failure("--max-steps must be > 0")
	if budget_ms <= 0:
		return Result.failure("--budget-ms must be > 0")
	if match_timeout_ms < 0:
		return Result.failure("--match-timeout-ms must be >= 0")
	if not SUPPORTED_BOT_IDS.has(bot_id):
		return Result.failure("--bot must be one of: %s" % ", ".join(SUPPORTED_BOT_IDS))
	if not SUPPORTED_TRACE_DETAILS.has(trace_detail):
		return Result.failure("--trace-detail must be one of: %s" % ", ".join(SUPPORTED_TRACE_DETAILS))
	if not output_archive.is_empty() and matches != 1:
		return Result.failure("--output-archive 目前只支持 --matches=1")

	var file: FileAccess = null
	if not output_jsonl.is_empty():
		var prepare_read := _prepare_output_file(output_jsonl)
		if not prepare_read.ok:
			return prepare_read
		file = FileAccess.open(output_jsonl, FileAccess.WRITE)
		if file == null:
			return Result.failure("cannot open --output-jsonl: %s" % output_jsonl)
	if not output_archive.is_empty():
		var prepare_archive_read := _prepare_output_file(output_archive)
		if not prepare_archive_read.ok:
			return prepare_archive_read

	print("[%s] START players=%d seed=%d matches=%d target_round=%d max_steps=%d budget_ms=%d match_timeout_ms=%d bot_config=%s bots=%s profile=%s" % [
		NAME,
		player_count,
		start_seed,
		matches,
		target_round,
		max_steps,
		budget_ms,
		match_timeout_ms,
		bot_config,
		str(bot_ids),
		profile_config if not profile_config.is_empty() else StrategyProfileClass.DEFAULT_PROFILE_ID,
	])

	var rows: Array[Dictionary] = []
	var failures := 0
	for match_index in range(matches):
		var seed := start_seed + match_index
		var row := _run_match(match_index, player_count, seed, target_round, max_steps, budget_ms, match_timeout_ms, trace_tail, trace_detail, bot_ids, bot_config, profile_source, profile_config, strategic_options, output_archive)
		rows.append(row)
		if not bool(row.get("ok", false)):
			failures += 1
		if not output_archive.is_empty() and str(row.get("archive_error", "")).strip_edges():
			if file != null:
				file.close()
			return Result.failure("cannot save archive: %s" % str(row.get("archive_error", "")))
		var line := JSON.stringify(row, "", true)
		print(line)
		if file != null:
			file.store_line(line)

	if file != null:
		file.close()
		print("[%s] WROTE_JSONL %s" % [NAME, output_jsonl])

	print("[%s] SUMMARY matches=%d failures=%d" % [NAME, matches, failures])
	return Result.success({
		"matches": matches,
		"failures": failures,
		"rows": rows,
	})

static func _run_match(
	match_index: int,
	player_count: int,
	seed: int,
	target_round: int,
	max_steps: int,
	budget_ms: int,
	match_timeout_ms: int,
	trace_tail: int,
	trace_detail: String,
	bot_ids: Array[String],
	bot_config: String,
	profile_source: String,
	profile_config: String,
	strategic_options: Dictionary = {},
	output_archive: String = ""
) -> Dictionary:
	var engine := GameEngine.new()
	var init_read := engine.initialize(player_count, seed)
	if not init_read.ok:
		return {
			"match_index": match_index,
			"player_count": player_count,
			"seed": seed,
			"bot": bot_config,
			"bot_config": bot_config,
			"bot_ids": bot_ids.duplicate(),
			"ok": false,
			"error": "initialize failed: %s" % init_read.error,
		}

	var bots := {}
	for player_id in range(player_count):
		var bot_id := bot_ids[player_id]
		var bot_options := strategic_options if bot_id == "strategic" else {}
		var bot_read := _create_bot(bot_id, profile_source, bot_options)
		if not bot_read.ok:
			return {
				"match_index": match_index,
				"player_count": player_count,
				"seed": seed,
				"bot": bot_config,
				"bot_config": bot_config,
				"bot_ids": bot_ids.duplicate(),
				"ok": false,
				"error": bot_read.error,
			}
		bots[player_id] = bot_read.value

	var match_started_ms := Time.get_ticks_msec()
	var match_deadline_ms := -1
	if match_timeout_ms > 0:
		match_deadline_ms = match_started_ms + match_timeout_ms
	var match_stop := {
		"timed_out": false,
		"reason": "",
	}
	var controller := BotControllerClass.new()
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		if state == null:
			match_stop["reason"] = "null_state"
			return true
		if str(state.phase) == DefsClass.PHASE_GAME_OVER:
			match_stop["reason"] = "game_over"
			return true
		if target_round > 0 and int(state.round_number) >= target_round:
			match_stop["reason"] = "target_round"
			return true
		if match_deadline_ms >= 0 and Time.get_ticks_msec() >= match_deadline_ms:
			match_stop["reason"] = "match_timeout"
			match_stop["timed_out"] = true
			return true
		return false
	var run_read := controller.run_until(engine, bots, stop_condition, max_steps, budget_ms)
	var state := engine.get_state()
	var row := _build_match_row(match_index, player_count, seed, state, controller.last_trace, trace_tail, trace_detail)
	var match_elapsed_ms := maxi(0, Time.get_ticks_msec() - match_started_ms)
	var match_timed_out := bool(match_stop.get("timed_out", false))
	var match_stop_reason := str(match_stop.get("reason", ""))
	row["bot"] = bot_config
	row["bot_config"] = bot_config
	row["bot_ids"] = bot_ids.duplicate()
	if not profile_config.is_empty():
		row["bot_profile"] = profile_config
		row["profile_source"] = profile_source
	if not strategic_options.is_empty() and bot_ids.has("strategic"):
		row["strategic_options"] = strategic_options.duplicate(true)
	row["match_timeout_ms"] = match_timeout_ms
	row["match_elapsed_ms"] = match_elapsed_ms
	row["match_timed_out"] = match_timed_out
	if not match_stop_reason.is_empty():
		row["match_stop_reason"] = match_stop_reason
	row["ok"] = run_read.ok and not match_timed_out
	row["steps"] = int(run_read.value.get("steps", controller.last_trace.size())) if run_read.ok and run_read.value is Dictionary else controller.last_trace.size()
	if match_timed_out:
		row["error"] = "match timed out after %d ms" % match_timeout_ms
	elif not run_read.ok:
		row["error"] = run_read.error
	if output_archive.is_empty():
		return row
	var archive_r = engine.create_archive()
	if not archive_r.ok:
		row["archive_error"] = archive_r.error
		return row
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var archive_path := _resolve_output_path_for_match(output_archive, match_index, seed)
	var save_r := ArchiveClass.save_archive_to_file(archive, archive_path)
	if not save_r.ok:
		row["archive_error"] = save_r.error
		return row
	row["archive_path"] = str(save_r.value)
	return row

static func _create_bot(bot_id: String, profile_source: String = "", bot_options: Dictionary = {}) -> Result:
	var bot = null
	match bot_id:
		"random":
			bot = RandomLegalBotClass.new()
		"greedy":
			bot = GreedyBotClass.new()
		"strategy":
			bot = StrategyBotClass.new()
		"osla":
			bot = OSLABotClass.new()
		"beam":
			bot = BeamBotClass.new()
		"strategic":
			bot = StrategicBotClass.new()
		_:
			return Result.failure("unknown bot: %s" % bot_id)
	var profile := profile_source.strip_edges()
	if not profile.is_empty() and bot != null and bot.has_method("configure_profile"):
		var profile_read: Result = bot.configure_profile(profile)
		if not profile_read.ok:
			return profile_read
	if bot_id == "strategic" and not bot_options.is_empty() and bot != null and bot.has_method("configure_search_options"):
		var options_read: Result = bot.configure_search_options(bot_options)
		if not options_read.ok:
			return options_read
	return Result.success(bot)

static func _resolve_bot_ids(options: Dictionary, player_count: int) -> Result:
	var explicit_bots_val = options.get("bot_ids", [])
	if explicit_bots_val is Array and not Array(explicit_bots_val).is_empty():
		var bot_ids: Array[String] = []
		for bot_id_val in Array(explicit_bots_val):
			var bot_id := str(bot_id_val).strip_edges()
			if bot_id.is_empty():
				return Result.failure("--bots cannot contain empty bot ids")
			if not SUPPORTED_BOT_IDS.has(bot_id):
				return Result.failure("--bots contains unsupported bot '%s'; supported: %s" % [bot_id, ", ".join(SUPPORTED_BOT_IDS)])
			bot_ids.append(bot_id)
		if bot_ids.size() != player_count:
			return Result.failure("--bots must provide exactly --players entries (%d), got %d" % [player_count, bot_ids.size()])
		return Result.success(bot_ids)

	var bot_id := str(options.get("bot_id", DEFAULT_BOT_ID)).strip_edges()
	if not SUPPORTED_BOT_IDS.has(bot_id):
		return Result.failure("--bot must be one of: %s" % ", ".join(SUPPORTED_BOT_IDS))
	var out: Array[String] = []
	for _i in range(player_count):
		out.append(bot_id)
	return Result.success(out)

static func _bot_config_id(bot_ids: Array[String]) -> String:
	if bot_ids.is_empty():
		return DEFAULT_BOT_ID
	var first := bot_ids[0]
	var all_same := true
	for bot_id in bot_ids:
		if bot_id != first:
			all_same = false
			break
	if all_same:
		return first
	return "_vs_".join(bot_ids)

static func _bot_config_ids_for_display(bot_ids: Array[String], strategic_options: Dictionary = {}) -> Array[String]:
	var strategic_config := _strategic_config_id(strategic_options)
	var out: Array[String] = []
	for bot_id in bot_ids:
		var display_id := str(bot_id)
		if display_id == "strategic" and not strategic_config.is_empty():
			display_id = "strategic-%s" % strategic_config
		out.append(display_id)
	return out

static func _strategic_config_id(strategic_options: Dictionary) -> String:
	var budget_profile := str(strategic_options.get("strategic_budget_profile", StrategicBotClass.DEFAULT_BUDGET_PROFILE)).strip_edges()
	if not ["play", "tuning"].has(budget_profile):
		budget_profile = StrategicBotClass.DEFAULT_BUDGET_PROFILE
	var explicit_id := str(strategic_options.get("strategic_config_id", "")).strip_edges()
	if not explicit_id.is_empty():
		var config_id := _safe_config_fragment(explicit_id)
		if budget_profile != StrategicBotClass.DEFAULT_BUDGET_PROFILE:
			config_id = "%s-%s" % [config_id, _safe_config_fragment(budget_profile)]
		return config_id
	var parts: Array[String] = []
	parts.append(_safe_config_fragment(budget_profile))
	if strategic_options.has("strategic_search"):
		parts.append(_safe_config_fragment(str(strategic_options.get("strategic_search", ""))))
	if strategic_options.has("strategic_horizon_decisions"):
		parts.append("d%d" % int(strategic_options.get("strategic_horizon_decisions", 0)))
	if strategic_options.has("strategic_horizon_rounds"):
		parts.append("r%d" % int(strategic_options.get("strategic_horizon_rounds", 0)))
	if strategic_options.has("strategic_max_plans"):
		parts.append("p%d" % int(strategic_options.get("strategic_max_plans", 0)))
	if strategic_options.has("strategic_rollout_step_budget_ms"):
		parts.append("s%d" % int(strategic_options.get("strategic_rollout_step_budget_ms", 0)))
	if strategic_options.has("strategic_min_search_budget_ms"):
		parts.append("b%d" % int(strategic_options.get("strategic_min_search_budget_ms", 0)))
	if strategic_options.has("strategic_min_plans_for_rollout"):
		parts.append("m%d" % int(strategic_options.get("strategic_min_plans_for_rollout", 0)))
	if strategic_options.has("mcts_iterations"):
		parts.append("mi%d" % int(strategic_options.get("mcts_iterations", 0)))
	if strategic_options.has("mcts_max_depth"):
		parts.append("md%d" % int(strategic_options.get("mcts_max_depth", 0)))
	if strategic_options.has("mcts_top_k_per_node"):
		parts.append("mk%d" % int(strategic_options.get("mcts_top_k_per_node", 0)))
	if strategic_options.has("mcts_exploration"):
		parts.append("me%d" % int(round(float(strategic_options.get("mcts_exploration", 0.0)) * 100.0)))
	if strategic_options.has("mcts_prior_weight"):
		parts.append("mw%d" % int(round(float(strategic_options.get("mcts_prior_weight", 0.0)) * 100.0)))
	if strategic_options.has("mcts_root_prior_min_visits_per_child"):
		parts.append("mv%d" % int(strategic_options.get("mcts_root_prior_min_visits_per_child", 0)))
	return "-".join(parts)

static func _safe_config_fragment(raw_value: String) -> String:
	var out := raw_value.strip_edges()
	for ch in [" ", "\t", "\n", "\r", ",", ";", ":", "/", "\\", "@", "#", "[", "]", "(", ")"]:
		out = out.replace(ch, "_")
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")

static func _profile_config_id(profile_source: String) -> String:
	var source := profile_source.strip_edges()
	if source.is_empty():
		return ""
	var file_name := source.get_file()
	if file_name.ends_with(".json"):
		return file_name.get_basename()
	return source.replace("res://", "").replace("user://", "").replace("/", "_").replace(":", "_")

static func _build_match_row(
	match_index: int,
	player_count: int,
	seed: int,
	state: GameState,
	trace: Array[Dictionary],
	trace_tail: int,
	trace_detail: String = DEFAULT_TRACE_DETAIL
) -> Dictionary:
	var row := {
		"match_index": match_index,
		"player_count": player_count,
		"seed": seed,
		"round": -1,
		"phase": "",
		"sub_phase": "",
		"command_count": trace.size(),
		"action_counts": _action_counts(trace),
		"player_cash_min_seen": _trace_player_cash_extreme(trace, true),
		"player_cash_min_after_first_positive": _trace_player_cash_min_after_first_positive(trace),
		"player_cash_max_seen": _trace_player_cash_extreme(trace, false),
		"opening_metrics": _trace_opening_metrics(trace, player_count),
		"search_metrics": _trace_search_metrics(trace),
		"trace_tail": _trace_tail(trace, trace_tail, trace_detail),
	}
	row["mandatory_completion_counts"] = _mandatory_completion_counts(trace)
	row["untraced_mandatory_completion_counts"] = _untraced_mandatory_completion_counts(trace)
	row["mandatory_completion_tail"] = _mandatory_completion_tail(trace, trace_tail)
	if state == null:
		return row
	row["round"] = int(state.round_number)
	row["phase"] = str(state.phase)
	row["sub_phase"] = str(state.sub_phase)
	row["current_player_id"] = int(state.get_current_player_id())
	row["player_cash"] = _player_cash(state)
	row["player_restaurants"] = _player_restaurant_counts(state)
	row["player_restaurant_details"] = _player_restaurant_details(state)
	row["player_employees"] = _player_employee_counts(state)
	row["player_employee_groups"] = _player_employee_groups(state)
	row["player_inventory_units"] = _player_inventory_units(state)
	row["player_inventory"] = _player_inventory(state)
	row["player_milestones"] = _player_milestone_counts(state)
	row["player_milestone_ids"] = _player_milestone_ids(state)
	row["bank_total"] = int(state.bank.get("total", 0)) if state.bank is Dictionary else 0
	row["state_hash"] = state.compute_hash()
	return row

static func _action_counts(trace: Array[Dictionary]) -> Dictionary:
	var out := {}
	for item in trace:
		var action_id := str(item.get("action_id", "")).strip_edges()
		if action_id.is_empty():
			continue
		out[action_id] = int(out.get(action_id, 0)) + 1
	return out

static func _trace_tail(trace: Array[Dictionary], count: int, trace_detail: String = DEFAULT_TRACE_DETAIL) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= 0:
		return out
	var start := maxi(0, trace.size() - count)
	for i in range(start, trace.size()):
		var item: Dictionary = trace[i]
		var row := {
			"player_id": int(item.get("player_id", -1)),
			"action_id": str(item.get("action_id", "")),
			"round_before": int(item.get("round_before", -1)),
			"phase_before": str(item.get("phase_before", "")),
			"sub_phase_before": str(item.get("sub_phase_before", "")),
			"round_after": int(item.get("round_after", -1)),
			"phase_after": str(item.get("phase_after", "")),
			"sub_phase_after": str(item.get("sub_phase_after", "")),
			"macro_action_id": str(item.get("macro_action_id", "")),
			"score": float(item.get("score", 0.0)),
		}
		var player_cash_before := _int_array(item.get("player_cash_before", []))
		if not player_cash_before.is_empty():
			row["player_cash_before"] = player_cash_before
		var player_cash_after := _int_array(item.get("player_cash_after", []))
		if not player_cash_after.is_empty():
			row["player_cash_after"] = player_cash_after
		if trace_detail == "decision":
			row["params"] = Dictionary(item.get("params", {})).duplicate(true)
			row["explanation"] = Dictionary(item.get("explanation", {})).duplicate(true)
			row["decision_trace"] = Dictionary(item.get("decision_trace", {})).duplicate(true)
		var mandatory_added := _mandatory_actions_added_for_trace_item(item)
		if not mandatory_added.is_empty():
			row["mandatory_actions_completed_added"] = mandatory_added
		out.append(row)
	return out

static func _trace_player_cash_extreme(trace: Array[Dictionary], use_min: bool) -> Array[int]:
	var out: Array[int] = []
	for item in trace:
		for key in ["player_cash_before", "player_cash_after"]:
			var values := _int_array(item.get(key, []))
			for i in range(values.size()):
				var value := int(values[i])
				if i >= out.size():
					out.append(value)
				elif use_min:
					out[i] = mini(int(out[i]), value)
				else:
					out[i] = maxi(int(out[i]), value)
	return out

static func _trace_player_cash_min_after_first_positive(trace: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	var seen_positive: Array[bool] = []
	for item in trace:
		for key in ["player_cash_before", "player_cash_after"]:
			var values := _int_array(item.get(key, []))
			for i in range(values.size()):
				_ensure_bool_size(seen_positive, i + 1, false)
				var value := int(values[i])
				if not bool(seen_positive[i]) and value <= 0:
					continue
				if not bool(seen_positive[i]):
					seen_positive[i] = true
				_ensure_int_size(out, i + 1, value)
				out[i] = mini(int(out[i]), value)
	return out

static func _trace_search_metrics(trace: Array[Dictionary]) -> Dictionary:
	var out := {
		"decision_count": 0,
		"budget_expired_count": 0,
		"attempted_simulations": 0,
		"expanded_nodes": 0,
		"time_ms_sum": 0,
		"time_ms_max": 0,
		"search_type_counts": {},
		"mcts_route_switch_count": 0,
		"mcts_non_root_populated_nodes": 0,
		"mcts_non_root_expanded_nodes": 0,
		"mcts_non_root_candidate_count": 0,
		"mcts_selected_route_type_counts": {},
	}
	for item in trace:
		var explanation: Dictionary = Dictionary(item.get("explanation", {}))
		var decision_trace: Dictionary = Dictionary(item.get("decision_trace", {}))
		var search_id := str(decision_trace.get("search", "")).strip_edges()
		var attempted := int(explanation.get("attempted_simulations", decision_trace.get("attempted_simulations", 0)))
		var expanded := int(explanation.get("expanded_nodes", decision_trace.get("expanded_nodes", 0)))
		var budget_expired := bool(explanation.get("budget_expired", decision_trace.get("budget_expired", false)))
		var time_ms := int(decision_trace.get("time_ms", explanation.get("time_ms", 0)))
		if search_id.is_empty() and attempted <= 0 and expanded <= 0 and not budget_expired:
			continue
		out["decision_count"] = int(out.get("decision_count", 0)) + 1
		out["budget_expired_count"] = int(out.get("budget_expired_count", 0)) + (1 if budget_expired else 0)
		out["attempted_simulations"] = int(out.get("attempted_simulations", 0)) + maxi(0, attempted)
		out["expanded_nodes"] = int(out.get("expanded_nodes", 0)) + maxi(0, expanded)
		out["time_ms_sum"] = int(out.get("time_ms_sum", 0)) + maxi(0, time_ms)
		out["time_ms_max"] = maxi(int(out.get("time_ms_max", 0)), maxi(0, time_ms))
		if not search_id.is_empty():
			var counts: Dictionary = out["search_type_counts"]
			counts[search_id] = int(counts.get(search_id, 0)) + 1
		var route_types_val = decision_trace.get("mcts_selected_route_types", explanation.get("mcts_selected_route_types", []))
		if route_types_val is Array:
			var route_counts: Dictionary = out["mcts_selected_route_type_counts"]
			for route_type_val in Array(route_types_val):
				var route_type := str(route_type_val).strip_edges()
				if route_type.is_empty():
					continue
				route_counts[route_type] = int(route_counts.get(route_type, 0)) + 1
		var route_switch_count := int(decision_trace.get("mcts_route_switch_count", explanation.get("mcts_route_switch_count", 0)))
		out["mcts_route_switch_count"] = int(out.get("mcts_route_switch_count", 0)) + maxi(0, route_switch_count)
		var non_root_populated := int(decision_trace.get("mcts_non_root_populated_nodes", explanation.get("mcts_non_root_populated_nodes", 0)))
		var non_root_expanded := int(decision_trace.get("mcts_non_root_expanded_nodes", explanation.get("mcts_non_root_expanded_nodes", 0)))
		var non_root_candidates := int(decision_trace.get("mcts_non_root_candidate_count", explanation.get("mcts_non_root_candidate_count", 0)))
		out["mcts_non_root_populated_nodes"] = int(out.get("mcts_non_root_populated_nodes", 0)) + maxi(0, non_root_populated)
		out["mcts_non_root_expanded_nodes"] = int(out.get("mcts_non_root_expanded_nodes", 0)) + maxi(0, non_root_expanded)
		out["mcts_non_root_candidate_count"] = int(out.get("mcts_non_root_candidate_count", 0)) + maxi(0, non_root_candidates)
	var decisions := int(out.get("decision_count", 0))
	out["time_ms_avg_per_decision"] = _avg_float(float(out.get("time_ms_sum", 0)), decisions)
	out["attempted_simulations_avg_per_decision"] = _avg_float(float(out.get("attempted_simulations", 0)), decisions)
	out["expanded_nodes_avg_per_decision"] = _avg_float(float(out.get("expanded_nodes", 0)), decisions)
	out["budget_expired_rate"] = _avg_float(float(out.get("budget_expired_count", 0)), decisions)
	return out

static func _trace_opening_metrics(trace: Array[Dictionary], player_count: int) -> Dictionary:
	var first_positive_seen: Array[bool] = []
	var first_positive_rounds: Array[int] = []
	var first_positive_steps: Array[int] = []
	var first_food_recruit_seen: Array[bool] = []
	var first_food_recruit_rounds: Array[int] = []
	var first_food_recruit_steps: Array[int] = []
	var first_produce_food_seen: Array[bool] = []
	var first_produce_food_rounds: Array[int] = []
	var first_produce_food_steps: Array[int] = []
	for i in range(player_count):
		first_positive_seen.append(false)
		first_positive_rounds.append(-1)
		first_positive_steps.append(-1)
		first_food_recruit_seen.append(false)
		first_food_recruit_rounds.append(-1)
		first_food_recruit_steps.append(-1)
		first_produce_food_seen.append(false)
		first_produce_food_rounds.append(-1)
		first_produce_food_steps.append(-1)
	var pre_revenue_action_counts := {}
	var pre_revenue_recruit_counts := {}
	var pre_revenue_recruit_count := 0
	var pre_revenue_errand_boy_recruit_count := 0
	var pre_revenue_pricing_manager_recruit_count := 0
	var pre_revenue_procure_drinks_count := 0
	for step_index in range(trace.size()):
		var item: Dictionary = trace[step_index]
		_update_first_positive_cash(
			first_positive_seen,
			first_positive_rounds,
			first_positive_steps,
			item.get("player_cash_before", []),
			int(item.get("round_before", -1)),
			step_index
		)
		var player_id := int(item.get("player_id", -1))
		var action_id := str(item.get("action_id", "")).strip_edges()
		if player_id >= 0 and player_id < player_count and not action_id.is_empty():
			if action_id == "recruit":
				var opening_employee_id := _trace_recruit_employee_id(item)
				if _is_food_producer_employee_id(opening_employee_id) and not bool(first_food_recruit_seen[player_id]):
					first_food_recruit_seen[player_id] = true
					first_food_recruit_rounds[player_id] = int(item.get("round_before", -1))
					first_food_recruit_steps[player_id] = step_index
			elif action_id == "produce_food" and not bool(first_produce_food_seen[player_id]):
				first_produce_food_seen[player_id] = true
				first_produce_food_rounds[player_id] = int(item.get("round_before", -1))
				first_produce_food_steps[player_id] = step_index
		if player_id >= 0 and player_id < player_count and not bool(first_positive_seen[player_id]):
			if not action_id.is_empty():
				_increment_count(pre_revenue_action_counts, action_id, 1)
				if action_id == "recruit":
					pre_revenue_recruit_count += 1
					var employee_id := _trace_recruit_employee_id(item)
					if not employee_id.is_empty():
						_increment_count(pre_revenue_recruit_counts, employee_id, 1)
					if employee_id == "errand_boy":
						pre_revenue_errand_boy_recruit_count += 1
					elif employee_id == "pricing_manager":
						pre_revenue_pricing_manager_recruit_count += 1
				elif action_id == "procure_drinks":
					pre_revenue_procure_drinks_count += 1
		_update_first_positive_cash(
			first_positive_seen,
			first_positive_rounds,
			first_positive_steps,
			item.get("player_cash_after", []),
			int(item.get("round_after", -1)),
			step_index
		)
	var players_with_positive_cash := 0
	for seen in first_positive_seen:
		if bool(seen):
			players_with_positive_cash += 1
	var food_recruit_to_produce_round_delays: Array[int] = []
	var food_recruit_to_produce_step_delays: Array[int] = []
	for i in range(player_count):
		if int(first_food_recruit_rounds[i]) >= 0 and int(first_produce_food_rounds[i]) >= 0:
			food_recruit_to_produce_round_delays.append(maxi(0, int(first_produce_food_rounds[i]) - int(first_food_recruit_rounds[i])))
			food_recruit_to_produce_step_delays.append(maxi(0, int(first_produce_food_steps[i]) - int(first_food_recruit_steps[i])))
		else:
			food_recruit_to_produce_round_delays.append(-1)
			food_recruit_to_produce_step_delays.append(-1)
	return {
		"players_with_positive_cash": players_with_positive_cash,
		"players_without_positive_cash": maxi(0, player_count - players_with_positive_cash),
		"first_positive_cash_rounds": first_positive_rounds,
		"first_positive_cash_steps": first_positive_steps,
		"first_food_recruit_rounds": first_food_recruit_rounds,
		"first_food_recruit_steps": first_food_recruit_steps,
		"first_produce_food_rounds": first_produce_food_rounds,
		"first_produce_food_steps": first_produce_food_steps,
		"food_recruit_to_produce_round_delays": food_recruit_to_produce_round_delays,
		"food_recruit_to_produce_step_delays": food_recruit_to_produce_step_delays,
		"pre_revenue_action_counts": _sorted_count_dict(pre_revenue_action_counts),
		"pre_revenue_recruit_counts": _sorted_count_dict(pre_revenue_recruit_counts),
		"pre_revenue_recruit_count": pre_revenue_recruit_count,
		"pre_revenue_errand_boy_recruit_count": pre_revenue_errand_boy_recruit_count,
		"pre_revenue_pricing_manager_recruit_count": pre_revenue_pricing_manager_recruit_count,
		"pre_revenue_procure_drinks_count": pre_revenue_procure_drinks_count,
	}

static func _update_first_positive_cash(
	seen: Array[bool],
	rounds: Array[int],
	steps: Array[int],
	values_val,
	round_number: int,
	step_index: int
) -> void:
	if not (values_val is Array):
		return
	for i in range(Array(values_val).size()):
		if i >= seen.size():
			break
		if bool(seen[i]) or int(Array(values_val)[i]) <= 0:
			continue
		seen[i] = true
		rounds[i] = round_number
		steps[i] = step_index

static func _trace_recruit_employee_id(item: Dictionary) -> String:
	var params_val = item.get("params", {})
	if params_val is Dictionary:
		var employee_id := str(Dictionary(params_val).get("employee_id", "")).strip_edges()
		if employee_id.is_empty():
			employee_id = str(Dictionary(params_val).get("employee_type", "")).strip_edges()
		if not employee_id.is_empty():
			return employee_id
	var macro_action_id := str(item.get("macro_action_id", "")).strip_edges()
	if macro_action_id.begins_with("recruit_"):
		return macro_action_id.trim_prefix("recruit_")
	return ""

static func _is_food_producer_employee_id(employee_id: String) -> bool:
	return FOOD_PRODUCER_EMPLOYEE_IDS.has(employee_id.strip_edges())

static func _increment_count(target: Dictionary, key: String, amount: int) -> void:
	var clean_key := key.strip_edges()
	if clean_key.is_empty():
		return
	target[clean_key] = int(target.get(clean_key, 0)) + amount

static func _sorted_count_dict(value: Dictionary) -> Dictionary:
	var out := {}
	var keys := value.keys()
	keys.sort()
	for key in keys:
		out[str(key)] = int(value.get(key, 0))
	return out

static func _int_array(value) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for item in Array(value):
			out.append(int(item))
	return out

static func _avg_float(total: float, count: int) -> float:
	if count <= 0:
		return 0.0
	return round((total / float(count)) * 1000.0) / 1000.0

static func _ensure_int_size(values: Array[int], size: int, fill_value: int) -> void:
	while values.size() < size:
		values.append(fill_value)

static func _ensure_bool_size(values: Array[bool], size: int, fill_value: bool) -> void:
	while values.size() < size:
		values.append(fill_value)

static func _mandatory_completion_counts(trace: Array[Dictionary]) -> Dictionary:
	var out := {}
	for item in trace:
		for row in _mandatory_actions_added_for_trace_item(item):
			var action_id := str(row.get("action_id", "")).strip_edges()
			if action_id.is_empty():
				continue
			out[action_id] = int(out.get(action_id, 0)) + 1
	return out

static func _untraced_mandatory_completion_counts(trace: Array[Dictionary]) -> Dictionary:
	var out := {}
	for item in trace:
		var command_action_id := str(item.get("action_id", "")).strip_edges()
		for row in _mandatory_actions_added_for_trace_item(item):
			var action_id := str(row.get("action_id", "")).strip_edges()
			if action_id.is_empty() or action_id == command_action_id:
				continue
			out[action_id] = int(out.get(action_id, 0)) + 1
	return out

static func _mandatory_completion_tail(trace: Array[Dictionary], count: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item in trace:
		var command_action_id := str(item.get("action_id", "")).strip_edges()
		var macro_action_id := str(item.get("macro_action_id", "")).strip_edges()
		for added in _mandatory_actions_added_for_trace_item(item):
			var row := Dictionary(added).duplicate(true)
			row["completed_by_action_id"] = command_action_id
			row["completed_by_macro_action_id"] = macro_action_id
			row["phase_before"] = str(item.get("phase_before", ""))
			row["sub_phase_before"] = str(item.get("sub_phase_before", ""))
			row["phase_after"] = str(item.get("phase_after", ""))
			row["sub_phase_after"] = str(item.get("sub_phase_after", ""))
			rows.append(row)
	if count <= 0:
		return []
	var start := maxi(0, rows.size() - count)
	var out: Array[Dictionary] = []
	for i in range(start, rows.size()):
		out.append(rows[i].duplicate(true))
	return out

static func _mandatory_actions_added_for_trace_item(item: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var added_val = item.get("mandatory_actions_completed_added", [])
	if not (added_val is Array):
		return out
	for added_item in Array(added_val):
		if not (added_item is Dictionary):
			continue
		var added: Dictionary = added_item
		var action_id := str(added.get("action_id", "")).strip_edges()
		if action_id.is_empty():
			continue
		out.append({
			"player_id": int(added.get("player_id", -1)),
			"action_id": action_id,
		})
	return out

static func _player_cash(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for player_val in state.players:
		if player_val is Dictionary:
			out.append(int(Dictionary(player_val).get("cash", 0)))
	return out

static func _player_restaurant_counts(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append(0)
			continue
		var restaurants_val = Dictionary(player_val).get("restaurants", [])
		out.append(Array(restaurants_val).size() if restaurants_val is Array else 0)
	return out

static func _player_restaurant_details(state: GameState) -> Array:
	var out := []
	var restaurants_by_id := {}
	if state.map is Dictionary:
		var map_restaurants_val = Dictionary(state.map).get("restaurants", {})
		if map_restaurants_val is Dictionary:
			restaurants_by_id = Dictionary(map_restaurants_val)
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append([])
			continue
		var restaurants_val = Dictionary(player_val).get("restaurants", [])
		if not (restaurants_val is Array):
			out.append([])
			continue
		var restaurants := []
		for restaurant_val in Array(restaurants_val):
			if restaurant_val is Dictionary:
				restaurants.append(Dictionary(restaurant_val).duplicate(true))
			else:
				var restaurant_id := str(restaurant_val)
				var detail := {
					"restaurant_id": restaurant_id,
				}
				var map_detail_val = restaurants_by_id.get(restaurant_id, null)
				if map_detail_val is Dictionary:
					detail = Dictionary(map_detail_val).duplicate(true)
					if not detail.has("restaurant_id"):
						detail["restaurant_id"] = restaurant_id
				else:
					detail["missing_map_detail"] = true
				restaurants.append(detail)
		out.append(restaurants)
	return out

static func _player_employee_counts(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append(0)
			continue
		var player: Dictionary = player_val
		var count := 0
		for key in ["employees", "reserve_employees", "busy_marketers"]:
			var list_val = player.get(key, [])
			if list_val is Array:
				count += Array(list_val).size()
		out.append(count)
	return out

static func _player_employee_groups(state: GameState) -> Array:
	var out := []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append({"active": [], "reserve": [], "busy": []})
			continue
		var player: Dictionary = player_val
		out.append({
			"active": _string_array(player.get("employees", [])),
			"reserve": _string_array(player.get("reserve_employees", [])),
			"busy": _string_array(player.get("busy_marketers", [])),
		})
	return out

static func _player_inventory_units(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append(0)
			continue
		var inventory_val = Dictionary(player_val).get("inventory", {})
		if not (inventory_val is Dictionary):
			out.append(0)
			continue
		var total := 0
		for amount_val in Dictionary(inventory_val).values():
			total += maxi(0, int(amount_val))
		out.append(total)
	return out

static func _player_inventory(state: GameState) -> Array:
	var out := []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append({})
			continue
		var inventory_val = Dictionary(player_val).get("inventory", {})
		if not (inventory_val is Dictionary):
			out.append({})
			continue
		var inventory := {}
		for key in Dictionary(inventory_val).keys():
			var amount := int(Dictionary(inventory_val).get(key, 0))
			if amount > 0:
				inventory[str(key)] = amount
		out.append(inventory)
	return out

static func _player_milestone_counts(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append(0)
			continue
		var milestones_val = Dictionary(player_val).get("milestones", [])
		out.append(Array(milestones_val).size() if milestones_val is Array else 0)
	return out

static func _player_milestone_ids(state: GameState) -> Array:
	var out := []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append([])
			continue
		var milestones_val = Dictionary(player_val).get("milestones", [])
		out.append(_sorted_unique_strings(milestones_val))
	return out

static func _sorted_unique_strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item)
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty():
				out.append(text)
	return out

static func _prepare_output_file(path: String) -> Result:
	var global_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		global_path = ProjectSettings.globalize_path(path)
	var parent := global_path.get_base_dir()
	if parent.is_empty():
		return Result.success()
	var err := DirAccess.make_dir_recursive_absolute(parent)
	if err != OK:
		return Result.failure("cannot create output directory %s: %s" % [parent, error_string(err)])
	return Result.success()

static func _resolve_output_path_for_match(path: String, match_index: int, seed: int) -> String:
	var out := str(path).strip_edges()
	out = out.replace("{match_index}", str(match_index))
	out = out.replace("{seed}", str(seed))
	return out

static func _parse_args(args: Array[String]) -> Result:
	var options := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"start_seed": DEFAULT_START_SEED,
		"matches": DEFAULT_MATCHES,
		"target_round": DEFAULT_TARGET_ROUND,
		"max_steps": DEFAULT_MAX_STEPS,
		"budget_ms": DEFAULT_BUDGET_MS,
		"match_timeout_ms": DEFAULT_MATCH_TIMEOUT_MS,
		"trace_tail": DEFAULT_TRACE_TAIL,
		"trace_detail": DEFAULT_TRACE_DETAIL,
		"bot_id": DEFAULT_BOT_ID,
		"profile": "",
		"output_jsonl": "",
		"output_archive": "",
		"strategic_options": {},
	}
	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg.begins_with("--players="):
			var value := arg.trim_prefix("--players=")
			if not value.is_valid_int():
				return Result.failure("--players must be an integer")
			options["player_count"] = int(value)
		elif arg.begins_with("--seed="):
			var value := arg.trim_prefix("--seed=")
			if not value.is_valid_int():
				return Result.failure("--seed must be an integer")
			options["start_seed"] = int(value)
		elif arg.begins_with("--matches="):
			var value := arg.trim_prefix("--matches=")
			if not value.is_valid_int():
				return Result.failure("--matches must be an integer")
			options["matches"] = int(value)
		elif arg.begins_with("--target-round="):
			var value := arg.trim_prefix("--target-round=")
			if not value.is_valid_int():
				return Result.failure("--target-round must be an integer")
			options["target_round"] = int(value)
		elif arg.begins_with("--max-steps="):
			var value := arg.trim_prefix("--max-steps=")
			if not value.is_valid_int():
				return Result.failure("--max-steps must be an integer")
			options["max_steps"] = int(value)
		elif arg.begins_with("--budget-ms="):
			var value := arg.trim_prefix("--budget-ms=")
			if not value.is_valid_int():
				return Result.failure("--budget-ms must be an integer")
			options["budget_ms"] = int(value)
		elif arg.begins_with("--match-timeout-ms="):
			var value := arg.trim_prefix("--match-timeout-ms=")
			if not value.is_valid_int():
				return Result.failure("--match-timeout-ms must be an integer")
			var timeout_ms := int(value)
			if timeout_ms < 0:
				return Result.failure("--match-timeout-ms must be >= 0")
			options["match_timeout_ms"] = timeout_ms
		elif arg.begins_with("--match-timeout-sec="):
			var value := arg.trim_prefix("--match-timeout-sec=")
			if not value.is_valid_int():
				return Result.failure("--match-timeout-sec must be an integer")
			var timeout_sec := int(value)
			if timeout_sec < 0:
				return Result.failure("--match-timeout-sec must be >= 0")
			options["match_timeout_ms"] = timeout_sec * 1000
		elif arg.begins_with("--trace-tail="):
			var value := arg.trim_prefix("--trace-tail=")
			if not value.is_valid_int():
				return Result.failure("--trace-tail must be an integer")
			options["trace_tail"] = int(value)
		elif arg.begins_with("--trace-detail="):
			var value := arg.trim_prefix("--trace-detail=").strip_edges()
			if not SUPPORTED_TRACE_DETAILS.has(value):
				return Result.failure("--trace-detail must be one of: %s" % ", ".join(SUPPORTED_TRACE_DETAILS))
			options["trace_detail"] = value
		elif arg.begins_with("--bot="):
			options["bot_id"] = arg.trim_prefix("--bot=").strip_edges()
			options["explicit_bot_id"] = true
			if bool(options.get("explicit_bot_ids", false)):
				return Result.failure("--bot and --bots cannot be used together")
		elif arg.begins_with("--bots="):
			if bool(options.get("explicit_bot_id", false)):
				return Result.failure("--bot and --bots cannot be used together")
			var value := arg.trim_prefix("--bots=").strip_edges()
			if value.is_empty():
				return Result.failure("--bots cannot be empty")
			if value.begins_with(",") or value.ends_with(",") or value.contains(",,"):
				return Result.failure("--bots cannot contain empty bot ids")
			var bot_ids: Array[String] = []
			for part in value.split(",", true):
				var bot_id := str(part).strip_edges()
				if bot_id.is_empty():
					return Result.failure("--bots cannot contain empty bot ids")
				bot_ids.append(bot_id)
			options["bot_ids"] = bot_ids
			options["explicit_bot_ids"] = true
		elif arg.begins_with("--profile="):
			var value := arg.trim_prefix("--profile=").strip_edges()
			if value.is_empty():
				return Result.failure("--profile cannot be empty")
			options["profile"] = value
		elif arg.begins_with("--output-jsonl="):
			options["output_jsonl"] = arg.trim_prefix("--output-jsonl=").strip_edges()
		elif arg.begins_with("--output-archive="):
			options["output_archive"] = arg.trim_prefix("--output-archive=").strip_edges()
		elif _is_strategic_option_arg(arg):
			var strategic_read := _parse_strategic_option_arg(options, arg)
			if not strategic_read.ok:
				return strategic_read
		else:
			return Result.failure("unknown argument: %s" % arg)
	return Result.success(options)

static func _is_strategic_option_arg(arg: String) -> bool:
	return arg.begins_with("--strategic-")

static func _parse_strategic_option_arg(options: Dictionary, arg: String) -> Result:
	var strategic_options: Dictionary = Dictionary(options.get("strategic_options", {}))
	if arg.begins_with("--strategic-search="):
		var value := arg.trim_prefix("--strategic-search=").strip_edges()
		if not ["none", "beam", "mcts"].has(value):
			return Result.failure("--strategic-search must be one of: none, beam, mcts")
		strategic_options["strategic_search"] = value
	elif arg.begins_with("--strategic-budget-profile="):
		var value := arg.trim_prefix("--strategic-budget-profile=").strip_edges()
		if not ["tuning", "play"].has(value):
			return Result.failure("--strategic-budget-profile must be one of: tuning, play")
		strategic_options["strategic_budget_profile"] = value
	elif arg.begins_with("--strategic-horizon-decisions="):
		var value := arg.trim_prefix("--strategic-horizon-decisions=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-horizon-decisions must be a positive integer")
		strategic_options["strategic_horizon_decisions"] = int(value)
	elif arg.begins_with("--strategic-horizon-rounds="):
		var value := arg.trim_prefix("--strategic-horizon-rounds=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-horizon-rounds must be a positive integer")
		strategic_options["strategic_horizon_rounds"] = int(value)
	elif arg.begins_with("--strategic-max-plans="):
		var value := arg.trim_prefix("--strategic-max-plans=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-max-plans must be a positive integer")
		strategic_options["strategic_max_plans"] = int(value)
	elif arg.begins_with("--strategic-rollout-step-budget-ms="):
		var value := arg.trim_prefix("--strategic-rollout-step-budget-ms=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-rollout-step-budget-ms must be a positive integer")
		strategic_options["strategic_rollout_step_budget_ms"] = int(value)
	elif arg.begins_with("--strategic-min-search-budget-ms="):
		var value := arg.trim_prefix("--strategic-min-search-budget-ms=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-min-search-budget-ms must be a positive integer")
		strategic_options["strategic_min_search_budget_ms"] = int(value)
	elif arg.begins_with("--strategic-min-plans-for-rollout="):
		var value := arg.trim_prefix("--strategic-min-plans-for-rollout=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-min-plans-for-rollout must be a positive integer")
		strategic_options["strategic_min_plans_for_rollout"] = int(value)
	elif arg.begins_with("--strategic-config-id="):
		var value := arg.trim_prefix("--strategic-config-id=").strip_edges()
		if value.is_empty():
			return Result.failure("--strategic-config-id cannot be empty")
		strategic_options["strategic_config_id"] = value
	elif arg.begins_with("--strategic-mcts-iterations="):
		var value := arg.trim_prefix("--strategic-mcts-iterations=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-mcts-iterations must be a positive integer")
		strategic_options["mcts_iterations"] = int(value)
	elif arg.begins_with("--strategic-mcts-max-depth="):
		var value := arg.trim_prefix("--strategic-mcts-max-depth=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-mcts-max-depth must be a positive integer")
		strategic_options["mcts_max_depth"] = int(value)
	elif arg.begins_with("--strategic-mcts-top-k-per-node="):
		var value := arg.trim_prefix("--strategic-mcts-top-k-per-node=").strip_edges()
		if not value.is_valid_int() or int(value) < 1:
			return Result.failure("--strategic-mcts-top-k-per-node must be a positive integer")
		strategic_options["mcts_top_k_per_node"] = int(value)
	elif arg.begins_with("--strategic-mcts-exploration="):
		var value := arg.trim_prefix("--strategic-mcts-exploration=").strip_edges()
		if not value.is_valid_float() or float(value) < 0.0:
			return Result.failure("--strategic-mcts-exploration must be a non-negative number")
		strategic_options["mcts_exploration"] = float(value)
	elif arg.begins_with("--strategic-mcts-prior-weight="):
		var value := arg.trim_prefix("--strategic-mcts-prior-weight=").strip_edges()
		if not value.is_valid_float() or float(value) < 0.0:
			return Result.failure("--strategic-mcts-prior-weight must be a non-negative number")
		strategic_options["mcts_prior_weight"] = float(value)
	elif arg.begins_with("--strategic-mcts-root-prior-min-visits-per-child="):
		var value := arg.trim_prefix("--strategic-mcts-root-prior-min-visits-per-child=").strip_edges()
		if not value.is_valid_int() or int(value) < 0:
			return Result.failure("--strategic-mcts-root-prior-min-visits-per-child must be a non-negative integer")
		strategic_options["mcts_root_prior_min_visits_per_child"] = int(value)
	else:
		return Result.failure("unknown strategic option: %s" % arg)
	options["strategic_options"] = strategic_options
	return Result.success()

static func _print_usage() -> void:
	print("Usage: tools/run_bot_selfplay.sh [--bot=random|greedy|strategy|osla|beam|strategic] [--bots=strategy,strategic] [--profile=base_revenue_v1] [--players=2] [--seed=12345] [--matches=1] [--target-round=3] [--max-steps=720] [--budget-ms=80] [--match-timeout-ms=0] [--match-timeout-sec=0] [--trace-detail=compact|decision] [--strategic-search=none|beam|mcts] [--strategic-budget-profile=tuning|play] [--strategic-horizon-decisions=16] [--strategic-horizon-rounds=2] [--strategic-max-plans=6] [--strategic-rollout-step-budget-ms=40] [--strategic-min-search-budget-ms=240] [--strategic-min-plans-for-rollout=2] [--strategic-mcts-iterations=24] [--strategic-mcts-max-depth=3] [--strategic-mcts-top-k-per-node=4] [--strategic-mcts-exploration=1.25] [--strategic-mcts-prior-weight=0.25] [--strategic-mcts-root-prior-min-visits-per-child=2] [--strategic-config-id=id] [--output-jsonl=res://.godot/bot_selfplay.jsonl] [--output-archive=res://.godot/bot_selfplay_archive.json]")
