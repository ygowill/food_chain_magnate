extends RefCounted

const MODULE_ID := "balanced_maps"
const CANDIDATE_COUNT := 10

const MapBakeClass = preload("res://core/map/map_baker/bake.gd")
const MapDefClass = preload("res://core/map/map_def.gd")
const AnalyzerClass = preload("res://core/map/map_balance/analyzer.gd")
const ThresholdsClass = preload("res://core/map/map_balance/thresholds.gd")

func register(registrar) -> Result:
	return registrar.register_map_candidate_selector(Callable(self, "_select_best_candidate"))

func _select_best_candidate(player_count: int, catalog, map_option, rng_manager, base_generator: Callable) -> Result:
	if not base_generator.is_valid():
		return Result.failure("%s: base_generator 无效" % MODULE_ID)

	var thresholds_read := ThresholdsClass.for_player_count(player_count)
	if not thresholds_read.ok:
		return base_generator.call(player_count, catalog, map_option, rng_manager)

	if catalog == null:
		return Result.failure("%s: catalog 为空" % MODULE_ID)
	if not (catalog.tiles is Dictionary):
		return Result.failure("%s: catalog.tiles 缺失或类型错误（期望 Dictionary）" % MODULE_ID)
	if not (catalog.pieces is Dictionary):
		return Result.failure("%s: catalog.pieces 缺失或类型错误（期望 Dictionary）" % MODULE_ID)

	var best_map_def = null
	var best_score := INF

	for i in range(CANDIDATE_COUNT):
		var candidate_read: Result = base_generator.call(player_count, catalog, map_option, rng_manager)
		if not candidate_read.ok:
			return Result.failure("%s: 生成候选地图 %d/%d 失败: %s" % [MODULE_ID, i + 1, CANDIDATE_COUNT, candidate_read.error])
		if not (candidate_read.value is MapDefClass):
			return Result.failure("%s: 候选地图 %d/%d 类型错误（期望 MapDef）" % [MODULE_ID, i + 1, CANDIDATE_COUNT])
		var map_def = candidate_read.value

		var bake_read := MapBakeClass.bake(map_def, catalog.tiles, catalog.pieces)
		if not bake_read.ok:
			return Result.failure("%s: 烘焙候选地图 %d/%d 失败: %s" % [MODULE_ID, i + 1, CANDIDATE_COUNT, bake_read.error])

		var analysis_read := AnalyzerClass.analyze_map_data(bake_read.value, player_count)
		if not analysis_read.ok:
			return Result.failure("%s: 分析候选地图 %d/%d 失败: %s" % [MODULE_ID, i + 1, CANDIDATE_COUNT, analysis_read.error])
		var analysis: Dictionary = analysis_read.value
		var evaluation_val = analysis.get("evaluation", null)
		if not (evaluation_val is Dictionary):
			return Result.failure("%s: 候选地图 %d/%d 缺少 evaluation" % [MODULE_ID, i + 1, CANDIDATE_COUNT])
		var evaluation: Dictionary = evaluation_val
		var score := float(evaluation.get("score", INF))

		if best_map_def == null or score < best_score:
			best_map_def = map_def
			best_score = score

	if best_map_def == null:
		return Result.failure("%s: 未生成任何候选地图" % MODULE_ID)

	return Result.success(best_map_def)
