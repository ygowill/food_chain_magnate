extends SceneTree

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const MapBakeClass = preload("res://core/map/map_baker/bake.gd")
const RandomManagerClass = preload("res://core/random/random_manager.gd")
const AnalyzerClass = preload("res://core/map/map_balance/analyzer.gd")
const ThresholdsClass = preload("res://core/map/map_balance/thresholds.gd")
const ResultClass = preload("res://core/types/result.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")

const NAME := "MapBalanceReport"
const DEFAULT_PLAYER_COUNTS: Array[int] = [2]
const DEFAULT_START_SEED := 12345
const DEFAULT_SAMPLE_COUNT := 1

func _initialize() -> void:
	var parse_result = _parse_args(OS.get_cmdline_user_args())
	if not parse_result.ok:
		push_error("[%s] FAIL %s" % [NAME, parse_result.error])
		quit(2)
		return

	var options: Dictionary = parse_result.value
	var player_counts: Array[int] = options.get("player_counts", DEFAULT_PLAYER_COUNTS.duplicate())
	var start_seed := int(options.get("start_seed", DEFAULT_START_SEED))
	var sample_count := int(options.get("sample_count", DEFAULT_SAMPLE_COUNT))
	var fast_map_only := bool(options.get("fast_map_only", false))
	var summary_only := bool(options.get("summary_only", false))
	var output_json := str(options.get("output_json", "")).strip_edges()

	print("[%s] START players=%s seed=%d samples=%d fast_map_only=%s" % [NAME, str(player_counts), start_seed, sample_count, str(fast_map_only)])
	var run_result = run(player_counts, start_seed, sample_count, fast_map_only)
	if not run_result.ok:
		push_error("[%s] FAIL %s" % [NAME, run_result.error])
		quit(1)
		return

	if not output_json.is_empty():
		var write_result := _write_json(output_json, run_result.value)
		if not write_result.ok:
			push_error("[%s] FAIL %s" % [NAME, write_result.error])
			quit(1)
			return
		print("[%s] WROTE_JSON %s" % [NAME, output_json])

	_print_summary(run_result.value, summary_only)
	if PerfTraceClass.enabled():
		PerfTraceClass.report(20)
	print("[%s] PASS" % NAME)
	quit(0)

static func run(player_counts: Array[int], start_seed: int, sample_count: int, fast_map_only: bool = false):
	if sample_count <= 0:
		return ResultClass.failure("samples 必须大于 0")

	var supported := ThresholdsClass.supported_player_counts()
	for player_count in player_counts:
		if not supported.has(player_count):
			return ResultClass.failure("暂不支持玩家数 %d（支持: %s）" % [player_count, str(supported)])

	var rows: Array[Dictionary] = []
	var summaries: Dictionary = {}
	var fast_contexts: Dictionary = {}

	if fast_map_only:
		for player_count in player_counts:
			var ctx_read := _build_fast_context(player_count, start_seed)
			if not ctx_read.ok:
				return ctx_read
			fast_contexts[player_count] = ctx_read.value

	for player_count in player_counts:
		var summary := _make_player_summary(player_count)
		for i in range(sample_count):
			var seed := start_seed + i
			var span_sample := PerfTraceClass.begin_span("map_balance:sample_total")
			var analysis_result: Result
			if fast_map_only:
				analysis_result = _analyze_fast_candidate(fast_contexts[player_count], player_count, seed)
			else:
				analysis_result = _analyze_initialized_game(player_count, seed)
			if not analysis_result.ok:
				PerfTraceClass.end_span(span_sample)
				return ResultClass.failure("分析失败 player=%d seed=%d: %s" % [player_count, seed, analysis_result.error])

			var analysis: Dictionary = analysis_result.value
			var evaluation_val = analysis.get("evaluation", {})
			var evaluation: Dictionary = evaluation_val if evaluation_val is Dictionary else {}
			var failed_val = evaluation.get("failed_checks", [])
			var failed_checks: Array = failed_val if failed_val is Array else []
			var score := float(evaluation.get("score", 0.0))
			var passed := bool(evaluation.get("passed", false))

			var row := {
				"player_count": player_count,
				"seed": seed,
				"passed": passed,
				"score": score,
				"failed_checks": failed_checks.duplicate(),
				"total_starting_houses": int(analysis.get("total_starting_houses", 0)),
				"total_drink_locations": int(analysis.get("total_drink_locations", 0)),
				"neighborhood_count": int(analysis.get("neighborhood_count", 0)),
				"road_system_count": int(analysis.get("road_system_count", 0)),
				"max_starting_houses_in_neighborhood": int(analysis.get("max_starting_houses_in_neighborhood", 0)),
				"max_starting_houses_on_road_system": int(analysis.get("max_starting_houses_on_road_system", 0)),
				"max_drink_locations_on_road_system": int(analysis.get("max_drink_locations_on_road_system", 0)),
				"largest_neighborhood_empty_spaces": int(analysis.get("largest_neighborhood_empty_spaces", 0)),
				"largest_road_system_route_count": int(analysis.get("largest_road_system_route_count", 0)),
			}
			rows.append(row)
			_update_summary(summary, row)
			PerfTraceClass.end_span(span_sample)

		_finish_summary(summary)
		summaries[player_count] = summary

	return ResultClass.success({
		"rows": rows,
		"summaries": summaries,
		"start_seed": start_seed,
		"sample_count": sample_count,
		"fast_map_only": fast_map_only,
	})

static func _build_fast_context(player_count: int, seed: int) -> Result:
	var span_ctx := PerfTraceClass.begin_span("map_balance:fast_context")
	var engine = GameEngineClass.new()
	var init_result = engine.initialize(player_count, seed)
	PerfTraceClass.end_span(span_ctx)
	if not init_result.ok:
		return ResultClass.failure("fast context 初始化失败 player=%d seed=%d: %s" % [player_count, seed, init_result.error])
	if engine.ruleset_v2 == null or engine.ruleset_v2.map_generation_registry == null:
		return ResultClass.failure("fast context 缺少 map_generation_registry")
	if engine.content_catalog_v2 == null:
		return ResultClass.failure("fast context 缺少 content_catalog_v2")
	if engine.game_data == null:
		return ResultClass.failure("fast context 缺少 game_data")
	var map_option_read = engine.game_data.get_map_for_player_count(player_count)
	if not map_option_read.ok:
		return map_option_read
	return ResultClass.success({
		"ruleset": engine.ruleset_v2,
		"catalog": engine.content_catalog_v2,
		"map_option": map_option_read.value,
		"tile_registry": engine.game_data.tiles,
		"piece_registry": engine.game_data.pieces,
	})

static func _analyze_initialized_game(player_count: int, seed: int) -> Result:
	var engine = GameEngineClass.new()
	var span_init := PerfTraceClass.begin_span("map_balance:engine.initialize")
	var init_result = engine.initialize(player_count, seed)
	PerfTraceClass.end_span(span_init)
	if not init_result.ok:
		return ResultClass.failure("初始化失败: %s" % init_result.error)

	var state = engine.get_state()
	var span_analyze := PerfTraceClass.begin_span("map_balance:analyze_state")
	var analysis_result = AnalyzerClass.analyze_state(state, player_count)
	PerfTraceClass.end_span(span_analyze)
	return analysis_result

static func _analyze_fast_candidate(ctx: Dictionary, player_count: int, seed: int) -> Result:
	var ruleset = ctx.get("ruleset", null)
	var catalog = ctx.get("catalog", null)
	var map_option = ctx.get("map_option", null)
	var tile_registry_val = ctx.get("tile_registry", {})
	var piece_registry_val = ctx.get("piece_registry", {})
	if ruleset == null or ruleset.map_generation_registry == null:
		return ResultClass.failure("fast candidate 缺少 map_generation_registry")
	if not (tile_registry_val is Dictionary):
		return ResultClass.failure("fast candidate tile_registry 类型错误")
	if not (piece_registry_val is Dictionary):
		return ResultClass.failure("fast candidate piece_registry 类型错误")
	var rng := RandomManagerClass.new(seed)
	# GameState.create_initial_state_with_rng 会在地图生成前洗牌 turn_order，消耗 player_count - 1 次 RNG。
	rng.fast_forward(maxi(0, player_count - 1))

	var span_gen := PerfTraceClass.begin_span("map_balance:fast_generate_map_def")
	var map_def_read: Result = ruleset.map_generation_registry.generate_map_def(player_count, catalog, map_option, rng)
	PerfTraceClass.end_span(span_gen)
	if not map_def_read.ok:
		return map_def_read

	var span_bake := PerfTraceClass.begin_span("map_balance:fast_bake")
	var bake_read := MapBakeClass.bake(map_def_read.value, tile_registry_val, piece_registry_val)
	PerfTraceClass.end_span(span_bake)
	if not bake_read.ok:
		return bake_read

	var span_analyze := PerfTraceClass.begin_span("map_balance:analyze_map_data")
	var analysis_result = AnalyzerClass.analyze_map_data(bake_read.value, player_count)
	PerfTraceClass.end_span(span_analyze)
	return analysis_result

static func _parse_args(args: Array[String]):
	var player_counts: Array[int] = DEFAULT_PLAYER_COUNTS.duplicate()
	var start_seed := DEFAULT_START_SEED
	var sample_count := DEFAULT_SAMPLE_COUNT
	var fast_map_only := false
	var summary_only := false
	var output_json := ""

	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg.begins_with("--players="):
			var parsed_players = _parse_player_counts(arg.trim_prefix("--players="))
			if not parsed_players.ok:
				return parsed_players
			player_counts = parsed_players.value
		elif arg.begins_with("--seed="):
			var seed_text := arg.trim_prefix("--seed=")
			if not seed_text.is_valid_int():
				return ResultClass.failure("--seed 必须为整数")
			start_seed = int(seed_text)
		elif arg.begins_with("--samples="):
			var samples_text := arg.trim_prefix("--samples=")
			if not samples_text.is_valid_int():
				return ResultClass.failure("--samples 必须为整数")
			sample_count = int(samples_text)
		elif arg == "--fast_map_only" or arg == "fast_map_only":
			fast_map_only = true
		elif arg == "--summary_only" or arg == "summary_only":
			summary_only = true
		elif arg.begins_with("--output_json="):
			output_json = arg.trim_prefix("--output_json=").strip_edges()
		elif arg == "--profile_startup" or arg == "profile_startup" or arg == "--startup_profile" or arg == "startup_profile":
			continue
		elif arg == "--help" or arg == "-h":
			return ResultClass.failure("用法: tools/run_headless_script.sh res://tools/map_balance_report.gd --players=2,3 --seed=12345 --samples=20")
		else:
			return ResultClass.failure("未知参数: %s" % arg)

	return ResultClass.success({
		"player_counts": player_counts,
		"start_seed": start_seed,
		"sample_count": sample_count,
		"fast_map_only": fast_map_only,
		"summary_only": summary_only,
		"output_json": output_json,
	})

static func _parse_player_counts(csv: String):
	var out: Array[int] = []
	for part in csv.split(",", false):
		var text := str(part).strip_edges()
		if text.is_empty():
			continue
		if not text.is_valid_int():
			return ResultClass.failure("--players 包含非整数: %s" % text)
		var value := int(text)
		if value <= 0:
			return ResultClass.failure("--players 必须为正整数")
		if not out.has(value):
			out.append(value)
	out.sort()
	if out.is_empty():
		return ResultClass.failure("--players 至少需要一个玩家数")
	return ResultClass.success(out)

static func _make_player_summary(player_count: int) -> Dictionary:
	return {
		"player_count": player_count,
		"samples": 0,
		"passed": 0,
		"failed": 0,
		"score_total": 0.0,
		"score_min": INF,
		"score_max": 0.0,
		"score_avg": 0.0,
		"failure_counts": {},
	}

static func _update_summary(summary: Dictionary, row: Dictionary) -> void:
	summary["samples"] = int(summary.get("samples", 0)) + 1
	var score := float(row.get("score", 0.0))
	summary["score_total"] = float(summary.get("score_total", 0.0)) + score
	summary["score_min"] = minf(float(summary.get("score_min", INF)), score)
	summary["score_max"] = maxf(float(summary.get("score_max", 0.0)), score)

	if bool(row.get("passed", false)):
		summary["passed"] = int(summary.get("passed", 0)) + 1
	else:
		summary["failed"] = int(summary.get("failed", 0)) + 1
		var failure_counts_val = summary.get("failure_counts", {})
		var failure_counts: Dictionary = failure_counts_val if failure_counts_val is Dictionary else {}
		var failed_val = row.get("failed_checks", [])
		var failed_checks: Array = failed_val if failed_val is Array else []
		for check_id_val in failed_checks:
			var check_id := str(check_id_val)
			failure_counts[check_id] = int(failure_counts.get(check_id, 0)) + 1
		summary["failure_counts"] = failure_counts

static func _finish_summary(summary: Dictionary) -> void:
	var samples := int(summary.get("samples", 0))
	if samples <= 0:
		summary["score_min"] = 0.0
		summary["score_avg"] = 0.0
		return
	summary["score_avg"] = float(summary.get("score_total", 0.0)) / float(samples)
	if float(summary.get("score_min", INF)) == INF:
		summary["score_min"] = 0.0

static func _write_json(path: String, data: Dictionary) -> Result:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ResultClass.failure("无法写入 JSON: %s (error=%s)" % [path, str(FileAccess.get_open_error())])
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return ResultClass.success()

static func _print_summary(result: Dictionary, summary_only: bool = false) -> void:
	var rows_val = result.get("rows", [])
	var rows: Array = rows_val if rows_val is Array else []
	if not summary_only:
		for row_val in rows:
			if not (row_val is Dictionary):
				continue
			var row: Dictionary = row_val
			print("[%s] ROW player=%d seed=%d passed=%s score=%.3f houses=%d drinks=%d neighborhoods=%d road_systems=%d max_house_block=%d max_house_road=%d max_drink_road=%d largest_empty_block=%d largest_road_route=%d failed=%s" % [
				NAME,
				int(row.get("player_count", 0)),
				int(row.get("seed", 0)),
				str(bool(row.get("passed", false))),
				float(row.get("score", 0.0)),
				int(row.get("total_starting_houses", 0)),
				int(row.get("total_drink_locations", 0)),
				int(row.get("neighborhood_count", 0)),
				int(row.get("road_system_count", 0)),
				int(row.get("max_starting_houses_in_neighborhood", 0)),
				int(row.get("max_starting_houses_on_road_system", 0)),
				int(row.get("max_drink_locations_on_road_system", 0)),
				int(row.get("largest_neighborhood_empty_spaces", 0)),
				int(row.get("largest_road_system_route_count", 0)),
				str(row.get("failed_checks", [])),
			])

	var summaries_val = result.get("summaries", {})
	var summaries: Dictionary = summaries_val if summaries_val is Dictionary else {}
	var keys: Array = summaries.keys()
	keys.sort()
	for player_count_val in keys:
		var summary_val = summaries[player_count_val]
		if not (summary_val is Dictionary):
			continue
		var summary: Dictionary = summary_val
		print("[%s] SUMMARY player=%d samples=%d passed=%d failed=%d score_avg=%.3f score_min=%.3f score_max=%.3f failure_counts=%s" % [
			NAME,
			int(summary.get("player_count", 0)),
			int(summary.get("samples", 0)),
			int(summary.get("passed", 0)),
			int(summary.get("failed", 0)),
			float(summary.get("score_avg", 0.0)),
			float(summary.get("score_min", 0.0)),
			float(summary.get("score_max", 0.0)),
			str(summary.get("failure_counts", {})),
		])
