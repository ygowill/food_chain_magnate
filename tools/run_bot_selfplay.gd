extends SceneTree

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")
const GreedyBotClass = preload("res://core/ai/bot/greedy_bot.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const OSLABotClass = preload("res://core/ai/bot/osla_bot.gd")
const BeamBotClass = preload("res://core/ai/bot/beam_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const NAME := "BotSelfplay"
const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_START_SEED := 12345
const DEFAULT_MATCHES := 1
const DEFAULT_TARGET_ROUND := 3
const DEFAULT_MAX_STEPS := 720
const DEFAULT_BUDGET_MS := 80
const DEFAULT_TRACE_TAIL := 8
const DEFAULT_BOT_ID := "strategy"
const SUPPORTED_BOT_IDS := ["random", "greedy", "strategy", "osla", "beam"]

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
	var trace_tail := int(options.get("trace_tail", DEFAULT_TRACE_TAIL))
	var bot_id := str(options.get("bot_id", DEFAULT_BOT_ID)).strip_edges()
	var output_jsonl := str(options.get("output_jsonl", "")).strip_edges()
	var bot_ids_read := _resolve_bot_ids(options, player_count)
	if not bot_ids_read.ok:
		return bot_ids_read
	var bot_ids: Array[String] = bot_ids_read.value
	var bot_config := _bot_config_id(bot_ids)

	if player_count <= 0:
		return Result.failure("--players must be > 0")
	if matches <= 0:
		return Result.failure("--matches must be > 0")
	if max_steps <= 0:
		return Result.failure("--max-steps must be > 0")
	if budget_ms <= 0:
		return Result.failure("--budget-ms must be > 0")
	if not SUPPORTED_BOT_IDS.has(bot_id):
		return Result.failure("--bot must be one of: %s" % ", ".join(SUPPORTED_BOT_IDS))

	var file: FileAccess = null
	if not output_jsonl.is_empty():
		var prepare_read := _prepare_output_file(output_jsonl)
		if not prepare_read.ok:
			return prepare_read
		file = FileAccess.open(output_jsonl, FileAccess.WRITE)
		if file == null:
			return Result.failure("cannot open --output-jsonl: %s" % output_jsonl)

	print("[%s] START players=%d seed=%d matches=%d target_round=%d max_steps=%d budget_ms=%d bot_config=%s bots=%s" % [
		NAME,
		player_count,
		start_seed,
		matches,
		target_round,
		max_steps,
		budget_ms,
		bot_config,
		str(bot_ids),
	])

	var rows: Array[Dictionary] = []
	var failures := 0
	for match_index in range(matches):
		var seed := start_seed + match_index
		var row := _run_match(match_index, player_count, seed, target_round, max_steps, budget_ms, trace_tail, bot_ids, bot_config)
		rows.append(row)
		if not bool(row.get("ok", false)):
			failures += 1
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
	trace_tail: int,
	bot_ids: Array[String],
	bot_config: String
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
		var bot_read := _create_bot(bot_id)
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

	var controller := BotControllerClass.new()
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		if state == null:
			return true
		if str(state.phase) == DefsClass.PHASE_GAME_OVER:
			return true
		if target_round > 0 and int(state.round_number) >= target_round:
			return true
		return false
	var run_read := controller.run_until(engine, bots, stop_condition, max_steps, budget_ms)
	var state := engine.get_state()
	var row := _build_match_row(match_index, player_count, seed, state, controller.last_trace, trace_tail)
	row["bot"] = bot_config
	row["bot_config"] = bot_config
	row["bot_ids"] = bot_ids.duplicate()
	row["ok"] = run_read.ok
	row["steps"] = int(run_read.value.get("steps", controller.last_trace.size())) if run_read.ok and run_read.value is Dictionary else controller.last_trace.size()
	if not run_read.ok:
		row["error"] = run_read.error
	return row

static func _create_bot(bot_id: String) -> Result:
	match bot_id:
		"random":
			return Result.success(RandomLegalBotClass.new())
		"greedy":
			return Result.success(GreedyBotClass.new())
		"strategy":
			return Result.success(StrategyBotClass.new())
		"osla":
			return Result.success(OSLABotClass.new())
		"beam":
			return Result.success(BeamBotClass.new())
		_:
			return Result.failure("unknown bot: %s" % bot_id)

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

static func _build_match_row(
	match_index: int,
	player_count: int,
	seed: int,
	state: GameState,
	trace: Array[Dictionary],
	trace_tail: int
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
		"trace_tail": _trace_tail(trace, trace_tail),
	}
	if state == null:
		return row
	row["round"] = int(state.round_number)
	row["phase"] = str(state.phase)
	row["sub_phase"] = str(state.sub_phase)
	row["current_player_id"] = int(state.get_current_player_id())
	row["player_cash"] = _player_cash(state)
	row["player_restaurants"] = _player_restaurant_counts(state)
	row["player_employees"] = _player_employee_counts(state)
	row["player_inventory_units"] = _player_inventory_units(state)
	row["player_milestones"] = _player_milestone_counts(state)
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

static func _trace_tail(trace: Array[Dictionary], count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= 0:
		return out
	var start := maxi(0, trace.size() - count)
	for i in range(start, trace.size()):
		var item: Dictionary = trace[i]
		out.append({
			"player_id": int(item.get("player_id", -1)),
			"action_id": str(item.get("action_id", "")),
			"phase_before": str(item.get("phase_before", "")),
			"sub_phase_before": str(item.get("sub_phase_before", "")),
			"phase_after": str(item.get("phase_after", "")),
			"sub_phase_after": str(item.get("sub_phase_after", "")),
			"macro_action_id": str(item.get("macro_action_id", "")),
			"score": float(item.get("score", 0.0)),
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

static func _player_milestone_counts(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append(0)
			continue
		var milestones_val = Dictionary(player_val).get("milestones", [])
		out.append(Array(milestones_val).size() if milestones_val is Array else 0)
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

static func _parse_args(args: Array[String]) -> Result:
	var options := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"start_seed": DEFAULT_START_SEED,
		"matches": DEFAULT_MATCHES,
		"target_round": DEFAULT_TARGET_ROUND,
		"max_steps": DEFAULT_MAX_STEPS,
		"budget_ms": DEFAULT_BUDGET_MS,
		"trace_tail": DEFAULT_TRACE_TAIL,
		"bot_id": DEFAULT_BOT_ID,
		"output_jsonl": "",
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
		elif arg.begins_with("--trace-tail="):
			var value := arg.trim_prefix("--trace-tail=")
			if not value.is_valid_int():
				return Result.failure("--trace-tail must be an integer")
			options["trace_tail"] = int(value)
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
			var bot_ids: Array[String] = []
			for part in value.split(",", false):
				bot_ids.append(str(part).strip_edges())
			options["bot_ids"] = bot_ids
			options["explicit_bot_ids"] = true
		elif arg.begins_with("--output-jsonl="):
			options["output_jsonl"] = arg.trim_prefix("--output-jsonl=").strip_edges()
		else:
			return Result.failure("unknown argument: %s" % arg)
	return Result.success(options)

static func _print_usage() -> void:
	print("Usage: tools/run_bot_selfplay.sh [--bot=random|greedy|strategy|osla|beam] [--bots=strategy,beam] [--players=2] [--seed=12345] [--matches=1] [--target-round=3] [--max-steps=720] [--budget-ms=80] [--output-jsonl=res://.godot/bot_selfplay.jsonl]")
