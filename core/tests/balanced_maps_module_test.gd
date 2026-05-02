# 平衡地图候选模块回归测试
class_name BalancedMapsModuleTest
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")
const RandomManagerClass = preload("res://core/random/random_manager.gd")
const MapBakeClass = preload("res://core/map/map_baker/bake.gd")
const AnalyzerClass = preload("res://core/map/map_balance/analyzer.gd")

const MODULE_ID := "balanced_maps"
const CANDIDATE_COUNT := 10

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_module_selector_metadata()
	if not r.ok:
		return r
	r = _test_selects_lowest_score_candidate(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_module_selector_metadata() -> Result:
	var manifests_read := ModulePackageLoaderClass.load_all(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	if not manifests_read.ok:
		return manifests_read
	var manifests: Dictionary = manifests_read.value
	if not manifests.has(MODULE_ID):
		return Result.failure("未找到 %s 模块 manifest" % MODULE_ID)
	var manifest = manifests.get(MODULE_ID, null)
	if manifest == null:
		return Result.failure("%s manifest 为空" % MODULE_ID)
	if str(manifest.name) != "平衡地图生成":
		return Result.failure("%s manifest 名称应为 平衡地图生成，实际: %s" % [MODULE_ID, str(manifest.name)])
	var provides: Dictionary = manifest.provides
	var ui_val = provides.get("ui", null)
	if not (ui_val is Dictionary):
		return Result.failure("%s manifest 缺少 provides.ui" % MODULE_ID)
	var ui: Dictionary = ui_val
	var selector_val = ui.get("module_selector", null)
	if not (selector_val is Dictionary):
		return Result.failure("%s manifest 缺少 module_selector" % MODULE_ID)
	var selector: Dictionary = selector_val
	if str(selector.get("group_id", "")) != "map_expansion":
		return Result.failure("%s 应归入地图变体分组，实际: %s" % [MODULE_ID, str(selector.get("group_id", ""))])
	if not bool(selector.get("default_enabled", false)):
		return Result.failure("%s 应在模块选择器中默认勾选" % MODULE_ID)
	return Result.success()

static func _test_selects_lowest_score_candidate(player_count: int, seed_val: int) -> Result:
	var enabled_modules := GameDefaultsClass.build_default_enabled_modules_v2()
	enabled_modules.append(MODULE_ID)

	var balanced_engine := GameEngine.new()
	var init_balanced := balanced_engine.initialize(player_count, seed_val, enabled_modules)
	if not init_balanced.ok:
		return Result.failure("启用 %s 初始化失败: %s" % [MODULE_ID, init_balanced.error])
	if not balanced_engine.get_module_plan_v2().has(MODULE_ID):
		return Result.failure("module_plan_v2 未包含 %s" % MODULE_ID)

	var selected_analysis_read := AnalyzerClass.analyze_state(balanced_engine.get_state(), player_count)
	if not selected_analysis_read.ok:
		return selected_analysis_read
	var selected_analysis: Dictionary = selected_analysis_read.value
	var selected_eval_val = selected_analysis.get("evaluation", null)
	if not (selected_eval_val is Dictionary):
		return Result.failure("启用 %s 后的地图分析缺少 evaluation" % MODULE_ID)
	var selected_score := float(Dictionary(selected_eval_val).get("score", INF))
	var selected_sig := _tile_signature_from_map_data(balanced_engine.get_state().map)

	var expected_read := _compute_expected_best_candidate(player_count, seed_val)
	if not expected_read.ok:
		return expected_read
	var expected: Dictionary = expected_read.value
	var expected_score := float(expected.get("score", INF))
	var expected_sig := str(expected.get("signature", ""))

	if abs(selected_score - expected_score) > 0.0001:
		return Result.failure("%s 未选中 10 张候选中的最低 score：got=%.6f expected=%.6f" % [MODULE_ID, selected_score, expected_score])
	if selected_sig != expected_sig:
		return Result.failure("%s 选中地图布局与最低 score 候选不一致" % MODULE_ID)
	return Result.success({
		"score": selected_score,
	})

static func _compute_expected_best_candidate(player_count: int, seed_val: int) -> Result:
	var base_engine := GameEngine.new()
	var init_base := base_engine.initialize(player_count, seed_val)
	if not init_base.ok:
		return Result.failure("基础引擎初始化失败: %s" % init_base.error)
	if base_engine.ruleset_v2 == null or base_engine.ruleset_v2.map_generation_registry == null:
		return Result.failure("基础引擎缺少 map_generation_registry")

	var map_option_read := base_engine.game_data.get_map_for_player_count(player_count)
	if not map_option_read.ok:
		return map_option_read
	var map_option = map_option_read.value

	var rng := RandomManagerClass.new(seed_val)
	rng.fast_forward(maxi(0, player_count - 1))

	var best_score := INF
	var best_signature := ""
	for i in range(CANDIDATE_COUNT):
		var candidate_read: Result = base_engine.ruleset_v2.map_generation_registry.generate_map_def(
			player_count,
			base_engine.content_catalog_v2,
			map_option,
			rng
		)
		if not candidate_read.ok:
			return Result.failure("生成基础候选 %d/%d 失败: %s" % [i + 1, CANDIDATE_COUNT, candidate_read.error])

		var bake_read := MapBakeClass.bake(candidate_read.value, base_engine.game_data.tiles, base_engine.game_data.pieces)
		if not bake_read.ok:
			return Result.failure("烘焙基础候选 %d/%d 失败: %s" % [i + 1, CANDIDATE_COUNT, bake_read.error])
		var analysis_read := AnalyzerClass.analyze_map_data(bake_read.value, player_count)
		if not analysis_read.ok:
			return analysis_read
		var analysis: Dictionary = analysis_read.value
		var eval_val = analysis.get("evaluation", null)
		if not (eval_val is Dictionary):
			return Result.failure("基础候选 %d/%d 缺少 evaluation" % [i + 1, CANDIDATE_COUNT])
		var score := float(Dictionary(eval_val).get("score", INF))
		if i == 0 or score < best_score:
			best_score = score
			best_signature = _tile_signature_from_map_data(bake_read.value)

	return Result.success({
		"score": best_score,
		"signature": best_signature,
	})

static func _tile_signature_from_map_data(map_data: Dictionary) -> String:
	var placements_val = map_data.get("tile_placements", [])
	var placements: Array = placements_val if placements_val is Array else []
	var parts: Array[String] = []
	for placement_val in placements:
		if not (placement_val is Dictionary):
			continue
		var placement: Dictionary = placement_val
		var pos_val = placement.get("board_pos", Vector2i.ZERO)
		var pos: Vector2i = pos_val if pos_val is Vector2i else Vector2i.ZERO
		parts.append("%d,%d:%s:%d" % [
			pos.x,
			pos.y,
			str(placement.get("tile_id", "")),
			int(placement.get("rotation", 0)),
		])
	parts.sort()
	return "|".join(parts)
