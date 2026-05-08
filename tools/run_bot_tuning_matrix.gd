extends SceneTree

const MatrixToolClass = preload("res://tools/run_bot_selfplay_matrix.gd")
const SelfplayToolClass = preload("res://tools/run_bot_selfplay.gd")
const SummaryClass = preload("res://tools/bot_selfplay_summary.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")

const NAME := "BotTuningMatrix"
const CHILD_MATRIX_SCRIPT := "res://tools/run_bot_selfplay_matrix.gd"
const PARALLEL_RUN_DIR := "res://.godot/bot_tuning_matrix_jobs"
const DEFAULT_PROFILES := [StrategyProfileClass.DEFAULT_PROFILE_ID, "base_revenue_growth_v1"]
const MIN_TUNING_MATCHES := 3

class ProfileProcessWorker:
	extends RefCounted

	func execute(job: Dictionary) -> Dictionary:
		var executable := str(job.get("executable", ""))
		var arguments := PackedStringArray()
		for arg in job.get("arguments", []):
			arguments.append(str(arg))
		var output: Array = []
		var exit_code := OS.execute(executable, arguments, output, true, false)
		var output_text := ""
		for chunk in output:
			output_text += str(chunk)
		if output_text.length() > 4000:
			output_text = output_text.substr(output_text.length() - 4000)
		return {
			"index": int(job.get("index", -1)),
			"profile_config": str(job.get("profile_config", "")),
			"profile_source": str(job.get("profile_source", "")),
			"jsonl_path": str(job.get("jsonl_path", "")),
			"summary_path": str(job.get("summary_path", "")),
			"log_path": str(job.get("log_path", "")),
			"exit_code": exit_code,
			"output_tail": output_text,
		}

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
	print("[%s] PASS profiles=%d configs=%d matches=%d failures=%d" % [
		NAME,
		int(run_result.value.get("profiles", 0)),
		int(run_result.value.get("configs", 0)),
		int(run_result.value.get("matches", 0)),
		int(run_result.value.get("failures", 0)),
	])
	quit(0)

static func run(options: Dictionary) -> Result:
	var profiles := _profile_array(options.get("profiles", DEFAULT_PROFILES))
	if profiles.is_empty():
		profiles = _profile_array(DEFAULT_PROFILES)
	var configs := MatrixToolClass._config_array(options.get("configs", MatrixToolClass.DEFAULT_CONFIGS))
	if configs.is_empty():
		configs = MatrixToolClass._config_array(MatrixToolClass.DEFAULT_CONFIGS)
	var player_count := int(options.get("player_count", SelfplayToolClass.DEFAULT_PLAYER_COUNT))
	var start_seed := int(options.get("start_seed", SelfplayToolClass.DEFAULT_START_SEED))
	var matches := int(options.get("matches", maxi(SelfplayToolClass.DEFAULT_MATCHES, MIN_TUNING_MATCHES)))
	if matches < MIN_TUNING_MATCHES:
		return Result.failure("--matches must be >= %d for tuning matrix" % MIN_TUNING_MATCHES)
	var target_round := int(options.get("target_round", SelfplayToolClass.DEFAULT_TARGET_ROUND))
	var max_steps := int(options.get("max_steps", SelfplayToolClass.DEFAULT_MAX_STEPS))
	var budget_ms := int(options.get("budget_ms", SelfplayToolClass.DEFAULT_BUDGET_MS))
	var trace_tail := int(options.get("trace_tail", SelfplayToolClass.DEFAULT_TRACE_TAIL))
	var output_jsonl := str(options.get("output_jsonl", "")).strip_edges()
	var output_json := str(options.get("output_json", "")).strip_edges()
	var parallel_jobs := int(options.get("parallel_jobs", 1))
	if parallel_jobs < 1:
		parallel_jobs = 1

	print("[%s] START profiles=%d configs=%d players=%d seed=%d matches=%d target_round=%d max_steps=%d budget_ms=%d jobs=%d" % [
		NAME,
		profiles.size(),
		configs.size(),
		player_count,
		start_seed,
		matches,
		target_round,
		max_steps,
		budget_ms,
		parallel_jobs,
	])

	if parallel_jobs > 1:
		var parallel_read := _run_profiles_parallel(
			profiles,
			configs,
			player_count,
			start_seed,
			matches,
			target_round,
			max_steps,
			budget_ms,
			trace_tail,
			parallel_jobs
		)
		if not parallel_read.ok:
			return parallel_read
		return _finish_run(
			profiles,
			configs,
			Array(parallel_read.value.get("profile_results", [])),
			output_jsonl,
			output_json,
			str(parallel_read.value.get("job_output_dir", ""))
		)

	var profile_results: Array[Dictionary] = []
	for profile_index in range(profiles.size()):
		var profile_source := str(profiles[profile_index])
		var profile_config := SelfplayToolClass._profile_config_id(profile_source)
		if profile_config.is_empty():
			profile_config = StrategyProfileClass.DEFAULT_PROFILE_ID
		var matrix_options := {
			"configs": configs,
			"player_count": player_count,
			"start_seed": start_seed,
			"matches": matches,
			"target_round": target_round,
			"max_steps": max_steps,
			"budget_ms": budget_ms,
			"trace_tail": trace_tail,
			"profile": profile_source,
			"output_jsonl": "",
			"output_json": "",
		}
		print("[%s] PROFILE index=%d id=%s source=%s" % [NAME, profile_index, profile_config, profile_source])
		var matrix_read := MatrixToolClass.run(matrix_options)
		if not matrix_read.ok:
			return matrix_read
		var summary: Dictionary = Dictionary(matrix_read.value.get("summary", {}))
		var rows: Array[Dictionary] = []
		for row_val in Array(matrix_read.value.get("rows", [])):
			if row_val is Dictionary:
				rows.append(Dictionary(row_val).duplicate(true))
		profile_results.append({
			"index": profile_index,
			"profile_config": profile_config,
			"profile_source": profile_source,
			"summary": summary,
			"rows": rows,
			"failures": int(matrix_read.value.get("failures", 0)),
		})

	return _finish_run(profiles, configs, profile_results, output_jsonl, output_json)

static func _finish_run(
	profiles: Array[String],
	configs: Array,
	profile_results: Array,
	output_jsonl: String,
	output_json: String,
	job_output_dir: String = ""
) -> Result:
	var summaries := {}
	var all_rows: Array[Dictionary] = []
	var rankings: Array[Dictionary] = []
	var total_failures := 0
	for profile_result_val in profile_results:
		var profile_result: Dictionary = Dictionary(profile_result_val)
		var profile_config := str(profile_result.get("profile_config", ""))
		var summary: Dictionary = Dictionary(profile_result.get("summary", {}))
		summaries[profile_config] = summary
		total_failures += int(profile_result.get("failures", summary.get("total_failures", 0)))
		for row_val in Array(profile_result.get("rows", [])):
			if row_val is Dictionary:
				all_rows.append(Dictionary(row_val).duplicate(true))
		_add_ranking_entries(rankings, profile_config, summary)

	_sort_rankings(rankings)
	for i in range(rankings.size()):
		var row: Dictionary = rankings[i]
		row["rank"] = i + 1
		print("[%s] RANK rank=%d profile=%s bot=%s score=%.3f success=%.3f avg_round=%.3f cash_avg=%.3f first_cash_step=%.3f food_delay_round=%.3f failures=%d no_positive_cash_avg=%.3f pre_revenue_errand_avg=%.3f pre_revenue_drink_avg=%.3f search_time_ms_avg=%.3f budget_expired_avg=%.3f" % [
			NAME,
			i + 1,
			str(row.get("profile", "")),
			str(row.get("bot", "")),
			float(row.get("score", 0.0)),
			float(row.get("success_rate", 0.0)),
			float(row.get("avg_round", 0.0)),
			float(row.get("cash_avg", 0.0)),
			float(row.get("opening_first_positive_cash_step_avg", 0.0)),
			float(row.get("opening_food_recruit_to_produce_round_delay_avg", 0.0)),
			int(row.get("failures", 0)),
			float(row.get("opening_players_without_positive_cash_avg", 0.0)),
			float(row.get("pre_revenue_errand_boy_recruit_avg", 0.0)),
			float(row.get("pre_revenue_procure_drinks_avg", 0.0)),
			float(row.get("search_time_ms_avg_per_match", 0.0)),
			float(row.get("budget_expired_avg_per_match", 0.0)),
		])
	var profile_rankings := _build_profile_rankings(rankings)
	for profile_row_val in profile_rankings:
		var profile_row: Dictionary = Dictionary(profile_row_val)
		print("[%s] PROFILE_RANK rank=%d profile=%s best_bot=%s best_score=%.3f avg_score=%.3f success_avg=%.3f failures=%d" % [
			NAME,
			int(profile_row.get("rank", 0)),
			str(profile_row.get("profile", "")),
			str(profile_row.get("best_bot", "")),
			float(profile_row.get("best_score", 0.0)),
			float(profile_row.get("score_avg", 0.0)),
			float(profile_row.get("success_rate_avg", 0.0)),
			int(profile_row.get("failures", 0)),
		])

	if not output_jsonl.is_empty():
		var write_jsonl := _write_jsonl(output_jsonl, all_rows)
		if not write_jsonl.ok:
			return write_jsonl
		print("[%s] WROTE_JSONL %s" % [NAME, output_jsonl])

	var result := {
		"profiles": profiles.size(),
		"profile_sources": profiles.duplicate(),
		"configs": configs.size(),
		"matches": all_rows.size(),
		"failures": total_failures,
		"matrix_configs": MatrixToolClass._configs_to_strings(configs),
		"profile_summaries": summaries,
		"rankings": rankings,
		"profile_rankings": profile_rankings,
		"rows": all_rows,
	}
	if not job_output_dir.is_empty():
		result["job_output_dir"] = job_output_dir
	if not output_json.is_empty():
		var write_json := _write_json(output_json, JSON.stringify(result, "", true))
		if not write_json.ok:
			return write_json
		print("[%s] WROTE_JSON %s" % [NAME, output_json])

	print("[%s] SUMMARY profiles=%d configs=%d matches=%d failures=%d" % [
		NAME,
		profiles.size(),
		configs.size(),
		all_rows.size(),
		total_failures,
	])
	return Result.success(result)

static func _run_profiles_parallel(
	profiles: Array[String],
	configs: Array,
	player_count: int,
	start_seed: int,
	matches: int,
	target_round: int,
	max_steps: int,
	budget_ms: int,
	trace_tail: int,
	parallel_jobs: int
) -> Result:
	var run_dir := "%s/run_%d" % [PARALLEL_RUN_DIR, Time.get_ticks_usec()]
	var prepare := _prepare_dir(run_dir)
	if not prepare.ok:
		return prepare
	var executable := OS.get_executable_path()
	if executable.strip_edges().is_empty():
		return Result.failure("cannot resolve Godot executable for parallel jobs")

	var jobs: Array[Dictionary] = []
	for profile_index in range(profiles.size()):
		var profile_source := str(profiles[profile_index])
		var profile_config := SelfplayToolClass._profile_config_id(profile_source)
		if profile_config.is_empty():
			profile_config = StrategyProfileClass.DEFAULT_PROFILE_ID
		var jsonl_path := "%s/profile_%03d.jsonl" % [run_dir, profile_index]
		var summary_path := "%s/profile_%03d_summary.json" % [run_dir, profile_index]
		var log_path := ProjectSettings.globalize_path("%s/profile_%03d.log" % [run_dir, profile_index])
		var arguments := _build_child_matrix_arguments(
			configs,
			player_count,
			start_seed,
			matches,
			target_round,
			max_steps,
			budget_ms,
			trace_tail,
			profile_source,
			jsonl_path,
			summary_path,
			log_path
		)
		jobs.append({
			"index": profile_index,
			"profile_config": profile_config,
			"profile_source": profile_source,
			"executable": executable,
			"arguments": arguments,
			"jsonl_path": jsonl_path,
			"summary_path": summary_path,
			"log_path": log_path,
		})

	print("[%s] PARALLEL_START jobs=%d workers=%d output=%s" % [NAME, jobs.size(), parallel_jobs, run_dir])
	var profile_results: Array = []
	profile_results.resize(jobs.size())
	var active: Array[Dictionary] = []
	var next_job := 0
	while next_job < jobs.size() or not active.is_empty():
		while active.size() < parallel_jobs and next_job < jobs.size():
			var job: Dictionary = jobs[next_job]
			var worker := ProfileProcessWorker.new()
			var thread := Thread.new()
			var err := thread.start(Callable(worker, "execute").bind(job))
			if err != OK:
				_wait_for_active_jobs(active)
				return Result.failure("cannot start profile job %d: %s" % [next_job, error_string(err)])
			active.append({
				"thread": thread,
				"worker": worker,
				"job": job,
			})
			print("[%s] PROFILE_START index=%d id=%s" % [NAME, int(job.get("index", -1)), str(job.get("profile_config", ""))])
			next_job += 1

		var finished_index := _first_finished_thread_index(active)
		if finished_index < 0:
			OS.delay_msec(100)
			continue
		var finished_active: Dictionary = active[finished_index]
		var finished_thread: Thread = finished_active.get("thread")
		var child_result = finished_thread.wait_to_finish()
		active.remove_at(finished_index)
		if not (child_result is Dictionary):
			_wait_for_active_jobs(active)
			return Result.failure("profile job returned an invalid result")
		var parsed := _read_finished_profile_job(Dictionary(child_result))
		if not parsed.ok:
			_wait_for_active_jobs(active)
			return parsed
		var parsed_result: Dictionary = parsed.value
		var result_index := int(parsed_result.get("index", -1))
		if result_index < 0 or result_index >= profile_results.size():
			return Result.failure("profile job returned invalid index: %d" % result_index)
		profile_results[result_index] = parsed_result
		print("[%s] PROFILE_DONE index=%d id=%s matches=%d failures=%d log=%s" % [
			NAME,
			result_index,
			str(parsed_result.get("profile_config", "")),
			Array(parsed_result.get("rows", [])).size(),
			int(parsed_result.get("failures", 0)),
			str(parsed_result.get("log_path", "")),
		])

	for result_val in profile_results:
		if result_val == null:
			return Result.failure("parallel profile job did not produce a result")
	return Result.success({
		"profile_results": profile_results,
		"job_output_dir": run_dir,
	})

static func _build_child_matrix_arguments(
	configs: Array,
	player_count: int,
	start_seed: int,
	matches: int,
	target_round: int,
	max_steps: int,
	budget_ms: int,
	trace_tail: int,
	profile_source: String,
	output_jsonl: String,
	output_json: String,
	log_path: String
) -> Array[String]:
	var args: Array[String] = []
	args.append("--headless")
	args.append("--log-file")
	args.append(log_path)
	args.append("--path")
	args.append(ProjectSettings.globalize_path("res://"))
	args.append("--script")
	args.append(CHILD_MATRIX_SCRIPT)
	args.append("--")
	for config in configs:
		args.append("--config=%s" % _config_arg(config))
	args.append("--players=%d" % player_count)
	args.append("--seed=%d" % start_seed)
	args.append("--matches=%d" % matches)
	args.append("--target-round=%d" % target_round)
	args.append("--max-steps=%d" % max_steps)
	args.append("--budget-ms=%d" % budget_ms)
	args.append("--trace-tail=%d" % trace_tail)
	args.append("--profile=%s" % profile_source)
	args.append("--output-jsonl=%s" % output_jsonl)
	args.append("--output-json=%s" % output_json)
	return args

static func _config_arg(config: Array) -> String:
	return ",".join(MatrixToolClass._string_config(config))

static func _read_finished_profile_job(child_result: Dictionary) -> Result:
	var index := int(child_result.get("index", -1))
	var profile_config := str(child_result.get("profile_config", ""))
	var exit_code := int(child_result.get("exit_code", 1))
	var log_path := str(child_result.get("log_path", ""))
	if exit_code != 0:
		return Result.failure("profile job failed index=%d id=%s exit=%d log=%s output_tail:\n%s" % [
			index,
			profile_config,
			exit_code,
			log_path,
			str(child_result.get("output_tail", "")),
		])
	var summary_path := str(child_result.get("summary_path", ""))
	var summary_read := _read_json(summary_path)
	if not summary_read.ok:
		return summary_read
	var rows_read := SummaryClass.read_jsonl(str(child_result.get("jsonl_path", "")))
	if not rows_read.ok:
		return rows_read
	var rows: Array[Dictionary] = []
	for row_val in Array(rows_read.value):
		if row_val is Dictionary:
			rows.append(Dictionary(row_val).duplicate(true))
	return Result.success({
		"index": index,
		"profile_config": profile_config,
		"profile_source": str(child_result.get("profile_source", "")),
		"summary": Dictionary(summary_read.value),
		"rows": rows,
		"failures": int(Dictionary(summary_read.value).get("total_failures", 0)),
		"log_path": log_path,
	})

static func _read_json(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("cannot open JSON file: %s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return Result.failure("expected JSON object: %s" % path)
	return Result.success(Dictionary(parsed))

static func _prepare_dir(path: String) -> Result:
	var global_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		global_path = ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(global_path)
	if err != OK:
		return Result.failure("cannot create directory %s: %s" % [global_path, error_string(err)])
	return Result.success()

static func _first_finished_thread_index(active: Array[Dictionary]) -> int:
	for i in range(active.size()):
		var thread: Thread = Dictionary(active[i]).get("thread")
		if thread != null and not thread.is_alive():
			return i
	return -1

static func _wait_for_active_jobs(active: Array[Dictionary]) -> void:
	for active_val in active:
		var active_item: Dictionary = Dictionary(active_val)
		var thread: Thread = active_item.get("thread")
		if thread != null:
			thread.wait_to_finish()
	active.clear()

static func _parse_args(args: Array[String]) -> Result:
	var profiles: Array[String] = []
	var profile_dirs: Array[String] = []
	var profile_lists: Array[String] = []
	var matrix_args: Array[String] = []
	var parallel_jobs := 1
	var explicit_matches := false
	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg.begins_with("--profile="):
			var value := arg.trim_prefix("--profile=").strip_edges()
			if value.is_empty():
				return Result.failure("--profile cannot be empty")
			profiles.append(value)
		elif arg.begins_with("--profile-dir="):
			var value := arg.trim_prefix("--profile-dir=").strip_edges()
			if value.is_empty():
				return Result.failure("--profile-dir cannot be empty")
			profile_dirs.append(value)
		elif arg.begins_with("--profile-list="):
			var value := arg.trim_prefix("--profile-list=").strip_edges()
			if value.is_empty():
				return Result.failure("--profile-list cannot be empty")
			profile_lists.append(value)
		elif arg.begins_with("--jobs="):
			var value := arg.trim_prefix("--jobs=").strip_edges()
			if not value.is_valid_int():
				return Result.failure("--jobs must be an integer")
			parallel_jobs = int(value)
			if parallel_jobs < 1:
				return Result.failure("--jobs must be >= 1")
		else:
			if arg.begins_with("--matches="):
				explicit_matches = true
			matrix_args.append(arg)
	var matrix_read := MatrixToolClass._parse_args(matrix_args)
	if not matrix_read.ok:
		return matrix_read
	var options: Dictionary = matrix_read.value
	var matches := int(options.get("matches", SelfplayToolClass.DEFAULT_MATCHES))
	if explicit_matches and matches < MIN_TUNING_MATCHES:
		return Result.failure("--matches must be >= %d for tuning matrix" % MIN_TUNING_MATCHES)
	if matches < MIN_TUNING_MATCHES:
		options["matches"] = MIN_TUNING_MATCHES
	var profile_sources := profiles.duplicate()
	for profile_dir in profile_dirs:
		var dir_read := _profiles_from_dir(profile_dir)
		if not dir_read.ok:
			return dir_read
		for profile_source in Array(dir_read.value):
			profile_sources.append(str(profile_source))
	for profile_list in profile_lists:
		var list_read := _profiles_from_manifest(profile_list)
		if not list_read.ok:
			return list_read
		for profile_source in Array(list_read.value):
			profile_sources.append(str(profile_source))
	options["profiles"] = _unique_profiles(profile_sources) if not profile_sources.is_empty() else _profile_array(DEFAULT_PROFILES)
	options["profile_dirs"] = profile_dirs
	options["profile_lists"] = profile_lists
	options["parallel_jobs"] = parallel_jobs
	options["profile"] = ""
	return Result.success(options)

static func _add_ranking_entries(rankings: Array[Dictionary], profile_config: String, summary: Dictionary) -> void:
	var bots: Dictionary = Dictionary(summary.get("bots", {}))
	var bot_names := bots.keys()
	bot_names.sort()
	for bot_name_val in bot_names:
		var bot_name := str(bot_name_val)
		var bot: Dictionary = Dictionary(bots.get(bot_name_val, {}))
		var tuning: Dictionary = Dictionary(bot.get("tuning_objective", {}))
		var search: Dictionary = Dictionary(bot.get("search", {}))
		var opening: Dictionary = Dictionary(bot.get("opening", {}))
		var opening_scalars: Dictionary = Dictionary(opening.get("scalar_avg_per_match", {}))
		var players: Dictionary = Dictionary(bot.get("players", {}))
		rankings.append({
			"profile": profile_config,
			"bot": bot_name,
			"score": float(tuning.get("score", 0.0)),
			"success_rate": float(bot.get("success_rate", 0.0)),
			"avg_round": float(bot.get("avg_round", 0.0)),
			"avg_steps": float(bot.get("avg_steps", 0.0)),
			"avg_command_count": float(bot.get("avg_command_count", 0.0)),
			"matches": int(bot.get("matches", 0)),
			"failures": int(bot.get("failures", 0)),
			"cash_avg": _bot_player_metric_avg(players, "cash"),
			"inventory_units_avg": _bot_player_metric_avg(players, "inventory_units"),
			"opening_players_without_positive_cash_avg": float(opening.get("players_without_positive_cash_avg_per_match", 0.0)),
			"opening_first_positive_cash_round_avg": float(opening.get("first_positive_cash_round_avg", 0.0)),
			"opening_first_positive_cash_step_avg": float(opening.get("first_positive_cash_step_avg", 0.0)),
			"opening_food_recruit_to_produce_round_delay_avg": float(opening.get("food_recruit_to_produce_round_delay_avg", 0.0)),
			"opening_food_recruit_to_produce_step_delay_avg": float(opening.get("food_recruit_to_produce_step_delay_avg", 0.0)),
			"pre_revenue_errand_boy_recruit_avg": float(opening_scalars.get("pre_revenue_errand_boy_recruit_count", 0.0)),
			"pre_revenue_pricing_manager_recruit_avg": float(opening_scalars.get("pre_revenue_pricing_manager_recruit_count", 0.0)),
			"pre_revenue_procure_drinks_avg": float(opening_scalars.get("pre_revenue_procure_drinks_count", 0.0)),
			"search_time_ms_avg_per_match": float(search.get("time_ms_avg_per_match", 0.0)),
			"budget_expired_avg_per_match": float(search.get("budget_expired_avg_per_match", 0.0)),
		})

static func _bot_player_metric_avg(players: Dictionary, metric_key: String) -> float:
	var metric_val = players.get(metric_key, {})
	if not (metric_val is Dictionary):
		return 0.0
	var avg_val = Dictionary(metric_val).get("avg", [])
	if not (avg_val is Array):
		return 0.0
	var values: Array = avg_val
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())

static func _sort_rankings(rankings: Array[Dictionary]) -> void:
	rankings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a.get("score", 0.0))
		var score_b := float(b.get("score", 0.0))
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		var success_a := float(a.get("success_rate", 0.0))
		var success_b := float(b.get("success_rate", 0.0))
		if not is_equal_approx(success_a, success_b):
			return success_a > success_b
		var round_a := float(a.get("avg_round", 0.0))
		var round_b := float(b.get("avg_round", 0.0))
		if not is_equal_approx(round_a, round_b):
			return round_a > round_b
		var bot_a := str(a.get("bot", ""))
		var bot_b := str(b.get("bot", ""))
		if bot_a != bot_b:
			return bot_a < bot_b
		return str(a.get("profile", "")) < str(b.get("profile", ""))
	)

static func _build_profile_rankings(rankings: Array[Dictionary]) -> Array[Dictionary]:
	var buckets := {}
	for row_val in rankings:
		var row: Dictionary = Dictionary(row_val)
		var profile := str(row.get("profile", ""))
		if profile.is_empty():
			continue
		if not buckets.has(profile):
			buckets[profile] = {
				"profile": profile,
				"bot_rows": 0,
				"matches": 0,
				"failures": 0,
				"score_sum": 0.0,
				"success_rate_sum": 0.0,
				"best_score": -1000000000.0,
				"best_bot": "",
			}
		var bucket: Dictionary = Dictionary(buckets[profile])
		var score := float(row.get("score", 0.0))
		bucket["bot_rows"] = int(bucket.get("bot_rows", 0)) + 1
		bucket["matches"] = int(bucket.get("matches", 0)) + int(row.get("matches", 0))
		bucket["failures"] = int(bucket.get("failures", 0)) + int(row.get("failures", 0))
		bucket["score_sum"] = float(bucket.get("score_sum", 0.0)) + score
		bucket["success_rate_sum"] = float(bucket.get("success_rate_sum", 0.0)) + float(row.get("success_rate", 0.0))
		if score > float(bucket.get("best_score", -1000000000.0)):
			bucket["best_score"] = score
			bucket["best_bot"] = str(row.get("bot", ""))

	var out: Array[Dictionary] = []
	for profile_val in buckets.keys():
		var bucket: Dictionary = Dictionary(buckets[profile_val])
		var bot_rows := int(bucket.get("bot_rows", 0))
		if bot_rows <= 0:
			continue
		var row := {
			"profile": str(bucket.get("profile", "")),
			"bot_rows": bot_rows,
			"matches": int(bucket.get("matches", 0)),
			"failures": int(bucket.get("failures", 0)),
			"best_score": float(bucket.get("best_score", 0.0)),
			"best_bot": str(bucket.get("best_bot", "")),
			"score_avg": float(bucket.get("score_sum", 0.0)) / float(bot_rows),
			"success_rate_avg": float(bucket.get("success_rate_sum", 0.0)) / float(bot_rows),
		}
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var best_a := float(a.get("best_score", 0.0))
		var best_b := float(b.get("best_score", 0.0))
		if not is_equal_approx(best_a, best_b):
			return best_a > best_b
		var avg_a := float(a.get("score_avg", 0.0))
		var avg_b := float(b.get("score_avg", 0.0))
		if not is_equal_approx(avg_a, avg_b):
			return avg_a > avg_b
		var success_a := float(a.get("success_rate_avg", 0.0))
		var success_b := float(b.get("success_rate_avg", 0.0))
		if not is_equal_approx(success_a, success_b):
			return success_a > success_b
		return str(a.get("profile", "")) < str(b.get("profile", ""))
	)
	for i in range(out.size()):
		var row: Dictionary = out[i]
		row["rank"] = i + 1
	return out

static func _profile_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var profile := str(item).strip_edges()
			if not profile.is_empty():
				out.append(profile)
	return out

static func _profiles_from_dir(raw_path: String) -> Result:
	var dir_path := _normalize_profile_dir(raw_path)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.failure("cannot open --profile-dir: %s" % dir_path)
	var profiles: Array[String] = []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir() or not file_name.ends_with(".json"):
			continue
		var profile_path := "%s/%s" % [dir_path.trim_suffix("/"), file_name]
		if _is_profile_dir_metadata_file(profile_path, file_name):
			continue
		profiles.append(profile_path)
	dir.list_dir_end()
	profiles.sort()
	if profiles.is_empty():
		return Result.failure("--profile-dir contains no .json profiles: %s" % dir_path)
	return Result.success(profiles)

static func _is_profile_dir_metadata_file(path: String, file_name: String) -> bool:
	if file_name == "manifest.json":
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = Dictionary(parsed)
	if data.has("action_weights") or data.has("employee_priorities") or data.has("product_priorities"):
		return false
	if data.has("variants") and (data.has("base_profile") or data.has("output_dir")):
		return true
	if data.has("profiles") or data.has("profile_sources"):
		return true
	return false

static func _profiles_from_manifest(raw_path: String) -> Result:
	var path := raw_path.strip_edges()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("cannot open --profile-list: %s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		return _profiles_from_manifest_values(Array(parsed), path)
	if parsed is Dictionary:
		var data: Dictionary = Dictionary(parsed)
		if data.has("variants"):
			return _profiles_from_manifest_values(Array(data.get("variants", [])), path)
		if data.has("profiles"):
			return _profiles_from_manifest_values(Array(data.get("profiles", [])), path)
		if data.has("profile_sources"):
			return _profiles_from_manifest_values(Array(data.get("profile_sources", [])), path)
	return Result.failure("--profile-list must be an Array or a Dictionary with variants/profiles/profile_sources: %s" % path)

static func _profiles_from_manifest_values(values: Array, source_path: String) -> Result:
	var profiles: Array[String] = []
	for item in values:
		if item is Dictionary:
			var row: Dictionary = Dictionary(item)
			var profile := str(row.get("path", "")).strip_edges()
			if profile.is_empty():
				profile = str(row.get("profile", "")).strip_edges()
			if profile.is_empty():
				profile = str(row.get("id", "")).strip_edges()
			if profile.is_empty():
				return Result.failure("--profile-list has an entry without path/profile/id: %s" % source_path)
			profiles.append(profile)
		else:
			var profile := str(item).strip_edges()
			if not profile.is_empty():
				profiles.append(profile)
	if profiles.is_empty():
		return Result.failure("--profile-list contains no profiles: %s" % source_path)
	return Result.success(_unique_profiles(profiles))

static func _normalize_profile_dir(raw_path: String) -> String:
	var path := raw_path.strip_edges()
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path.trim_suffix("/")
	return "res://%s" % path.trim_prefix("./").trim_suffix("/")

static func _unique_profiles(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		var profile := str(value).strip_edges()
		if not profile.is_empty() and not out.has(profile):
			out.append(profile)
	return out

static func _write_jsonl(path: String, rows: Array[Dictionary]) -> Result:
	var prepare := MatrixToolClass._prepare_output_file(path)
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
	var prepare := MatrixToolClass._prepare_output_file(path)
	if not prepare.ok:
		return prepare
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot open --output-json: %s" % path)
	file.store_string(json)
	file.store_string("\n")
	file.close()
	return Result.success()

static func _print_usage() -> void:
	print("Usage: tools/run_bot_tuning_matrix.sh [--profile=base_revenue_v1] [--profile-dir=res://data/bots] [--profile-list=res://.godot/bot_profile_variants/manifest.json] [--config=strategy] [--jobs=2] [--players=2] [--seed=12345] [--matches=3] [--target-round=3] [--max-steps=720] [--budget-ms=80] [--output-jsonl=res://.godot/bot_tuning_matrix.jsonl] [--output-json=res://.godot/bot_tuning_matrix_summary.json]")
