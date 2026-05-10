extends SceneTree

const SelfplayToolClass = preload("res://tools/run_bot_selfplay.gd")
const SummaryClass = preload("res://tools/bot_selfplay_summary.gd")

const NAME := "BotSelfplayMatrix"
const DEFAULT_CONFIGS := [["strategy"], ["osla"], ["beam"]]

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
	var run_result := run(parse_result.value)
	if not run_result.ok:
		push_error("[%s] FAIL %s" % [NAME, run_result.error])
		quit(1)
		return
	print("[%s] PASS configs=%d matches=%d failures=%d" % [
		NAME,
		int(run_result.value.get("configs", 0)),
		int(run_result.value.get("matches", 0)),
		int(run_result.value.get("failures", 0)),
	])
	quit(0)

static func run(options: Dictionary) -> Result:
	var configs := _config_array(options.get("configs", DEFAULT_CONFIGS))
	if configs.is_empty():
		configs = _config_array(DEFAULT_CONFIGS)
	var player_count := int(options.get("player_count", SelfplayToolClass.DEFAULT_PLAYER_COUNT))
	var start_seed := int(options.get("start_seed", SelfplayToolClass.DEFAULT_START_SEED))
	var matches := int(options.get("matches", SelfplayToolClass.DEFAULT_MATCHES))
	var target_round := int(options.get("target_round", SelfplayToolClass.DEFAULT_TARGET_ROUND))
	var max_steps := int(options.get("max_steps", SelfplayToolClass.DEFAULT_MAX_STEPS))
	var budget_ms := int(options.get("budget_ms", SelfplayToolClass.DEFAULT_BUDGET_MS))
	var trace_tail := int(options.get("trace_tail", SelfplayToolClass.DEFAULT_TRACE_TAIL))
	var output_jsonl := str(options.get("output_jsonl", "")).strip_edges()
	var output_json := str(options.get("output_json", "")).strip_edges()
	var profile_source := str(options.get("profile", "")).strip_edges()
	var profile_config := SelfplayToolClass._profile_config_id(profile_source)
	var strategic_options: Dictionary = Dictionary(options.get("strategic_options", {})).duplicate(true)

	var all_rows: Array[Dictionary] = []
	var failures := 0
	print("[%s] START configs=%d players=%d seed=%d matches=%d target_round=%d max_steps=%d budget_ms=%d profile=%s" % [
		NAME,
		configs.size(),
		player_count,
		start_seed,
		matches,
		target_round,
		max_steps,
		budget_ms,
		profile_config if not profile_config.is_empty() else "default",
	])
	for config_index in range(configs.size()):
		var config := _string_config(configs[config_index])
		var run_options_read := _build_selfplay_options(config, config_index, player_count, start_seed, matches, target_round, max_steps, budget_ms, trace_tail, profile_source, strategic_options)
		if not run_options_read.ok:
			return run_options_read
		var run_options: Dictionary = run_options_read.value
		var config_id := _config_id(config)
		print("[%s] CONFIG index=%d id=%s bots=%s" % [NAME, config_index, config_id, str(config)])
		var run_read := SelfplayToolClass.run(run_options)
		if not run_read.ok:
			return run_read
		failures += int(run_read.value.get("failures", 0))
		for row_val in Array(run_read.value.get("rows", [])):
			if not (row_val is Dictionary):
				continue
			var row: Dictionary = Dictionary(row_val).duplicate(true)
			row["matrix_config_index"] = config_index
			all_rows.append(row)

	if not output_jsonl.is_empty():
		var write_jsonl := _write_jsonl(output_jsonl, all_rows)
		if not write_jsonl.ok:
			return write_jsonl
		print("[%s] WROTE_JSONL %s" % [NAME, output_jsonl])

	var summary_read := SummaryClass.summarize_rows(all_rows)
	if not summary_read.ok:
		return summary_read
	var summary: Dictionary = summary_read.value
	summary["matrix_configs"] = _configs_to_strings(configs, profile_source)
	if not profile_config.is_empty():
		summary["matrix_profile"] = profile_config
	for line in SummaryClass.format_summary(summary):
		print(line)

	if not output_json.is_empty():
		var write_json := _write_json(output_json, JSON.stringify(summary, "", true))
		if not write_json.ok:
			return write_json
		print("[%s] WROTE_JSON %s" % [NAME, output_json])

	print("[%s] SUMMARY configs=%d matches=%d failures=%d" % [NAME, configs.size(), all_rows.size(), failures])
	return Result.success({
		"configs": configs.size(),
		"matches": all_rows.size(),
		"failures": failures,
		"rows": all_rows,
		"summary": summary,
	})

static func _build_selfplay_options(
	config: Array,
	config_index: int,
	player_count: int,
	start_seed: int,
	matches: int,
	target_round: int,
	max_steps: int,
	budget_ms: int,
	trace_tail: int,
	profile_source: String,
	strategic_options: Dictionary = {}
) -> Result:
	if config.is_empty():
		return Result.failure("--config cannot be empty")
	for bot_id in config:
		var bot_id_string := str(bot_id)
		if not SelfplayToolClass.SUPPORTED_BOT_IDS.has(bot_id_string):
			return Result.failure("unsupported bot in --config '%s': %s" % [bot_id, ", ".join(SelfplayToolClass.SUPPORTED_BOT_IDS)])
	if config.size() != 1 and config.size() != player_count:
		return Result.failure("--config must be a single bot or exactly --players entries; config[%d]=%s players=%d" % [config_index, str(config), player_count])
	var options := {
		"player_count": player_count,
		"start_seed": start_seed,
		"matches": matches,
		"target_round": target_round,
		"max_steps": max_steps,
		"budget_ms": budget_ms,
		"trace_tail": trace_tail,
	}
	if config.size() == 1:
		options["bot_id"] = str(config[0])
	else:
		options["bot_ids"] = _string_config(config)
	if not profile_source.strip_edges().is_empty():
		options["profile"] = profile_source.strip_edges()
	if not strategic_options.is_empty():
		options["strategic_options"] = strategic_options.duplicate(true)
	return Result.success(options)

static func _write_jsonl(path: String, rows: Array[Dictionary]) -> Result:
	var prepare := _prepare_output_file(path)
	if not prepare.ok:
		return prepare
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot open --output-jsonl: %s" % path)
	for row in rows:
		file.store_line(JSON.stringify(row, "", true))
	file.close()
	return Result.success()

static func _write_json(path: String, json: String) -> Result:
	var prepare := _prepare_output_file(path)
	if not prepare.ok:
		return prepare
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot open --output-json: %s" % path)
	file.store_string(json)
	file.store_string("\n")
	file.close()
	return Result.success()

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
		"configs": [],
		"player_count": SelfplayToolClass.DEFAULT_PLAYER_COUNT,
		"start_seed": SelfplayToolClass.DEFAULT_START_SEED,
		"matches": SelfplayToolClass.DEFAULT_MATCHES,
		"target_round": SelfplayToolClass.DEFAULT_TARGET_ROUND,
		"max_steps": SelfplayToolClass.DEFAULT_MAX_STEPS,
		"budget_ms": SelfplayToolClass.DEFAULT_BUDGET_MS,
		"trace_tail": SelfplayToolClass.DEFAULT_TRACE_TAIL,
		"profile": "",
		"output_jsonl": "",
		"output_json": "",
		"strategic_options": {},
	}
	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg.begins_with("--config="):
			var config_read := _parse_config_arg(arg.trim_prefix("--config="))
			if not config_read.ok:
				return config_read
			options["configs"].append(config_read.value)
		elif arg.begins_with("--players="):
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
		elif arg.begins_with("--profile="):
			var value := arg.trim_prefix("--profile=").strip_edges()
			if value.is_empty():
				return Result.failure("--profile cannot be empty")
			options["profile"] = value
		elif arg.begins_with("--output-jsonl="):
			options["output_jsonl"] = arg.trim_prefix("--output-jsonl=").strip_edges()
		elif arg.begins_with("--output-json="):
			options["output_json"] = arg.trim_prefix("--output-json=").strip_edges()
		elif SelfplayToolClass._is_strategic_option_arg(arg):
			var strategic_read := SelfplayToolClass._parse_strategic_option_arg(options, arg)
			if not strategic_read.ok:
				return strategic_read
		else:
			return Result.failure("unknown argument: %s" % arg)
	return Result.success(options)

static func _parse_config_arg(raw_value: String) -> Result:
	var value := raw_value.strip_edges()
	if value.is_empty():
		return Result.failure("--config cannot be empty")
	if value.begins_with(",") or value.ends_with(",") or value.contains(",,"):
		return Result.failure("--config cannot contain empty bot ids")
	var out: Array[String] = []
	for part in value.split(",", true):
		var bot_id := str(part).strip_edges()
		if bot_id.is_empty():
			return Result.failure("--config cannot contain empty bot ids")
		out.append(bot_id)
	return Result.success(out)

static func _config_array(value) -> Array:
	var out := []
	if value is Array:
		for item in Array(value):
			if item is Array:
				out.append(_string_config(item))
	return out

static func _configs_to_strings(configs: Array, profile_source: String = "") -> Array[String]:
	var out: Array[String] = []
	var profile_config := SelfplayToolClass._profile_config_id(profile_source)
	for config in configs:
		var config_id := _config_id(config)
		if not profile_config.is_empty():
			config_id = "%s@%s" % [config_id, profile_config]
		out.append(config_id)
	return out

static func _config_id(config: Array) -> String:
	return SelfplayToolClass._bot_config_id(_string_config(config))

static func _string_config(config: Array) -> Array[String]:
	var out: Array[String] = []
	for item in config:
		out.append(str(item))
	return out

static func _print_usage() -> void:
	print("Usage: tools/run_bot_selfplay_matrix.sh [--config=strategy] [--config=strategic] [--config=random,strategy] [--profile=base_revenue_v1] [--players=2] [--seed=12345] [--matches=1] [--target-round=3] [--max-steps=720] [--budget-ms=80] [--strategic-search=none|beam|mcts] [--strategic-budget-profile=tuning|play] [--strategic-horizon-decisions=16] [--strategic-horizon-rounds=2] [--strategic-max-plans=6] [--strategic-rollout-step-budget-ms=40] [--strategic-min-search-budget-ms=240] [--strategic-min-plans-for-rollout=2] [--strategic-mcts-iterations=24] [--strategic-mcts-max-depth=3] [--strategic-mcts-top-k-per-node=4] [--strategic-mcts-exploration=1.25] [--strategic-mcts-prior-weight=0.25] [--strategic-mcts-root-prior-min-visits-per-child=2] [--strategic-config-id=id] [--output-jsonl=res://.godot/bot_selfplay_matrix.jsonl] [--output-json=res://.godot/bot_selfplay_matrix_summary.json]")
