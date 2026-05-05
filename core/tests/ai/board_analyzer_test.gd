class_name BoardAnalyzerTest
extends RefCounted

const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var basic := _test_builds_public_board_read_model(seed_val)
	if not basic.ok:
		return basic
	var drive_through := _test_drive_through_entrance_points_reuse_structures(seed_val)
	if not drive_through.ok:
		return drive_through
	return Result.success({"cases": 2})

static func _test_builds_public_board_read_model(seed_val: int) -> Result:
	var engine_read := _build_test_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var analysis_read := BoardAnalyzerClass.analyze_state(engine_read.value.get_state())
	if not analysis_read.ok:
		return analysis_read
	var analysis: Dictionary = analysis_read.value
	if analysis.get("house_ids", []) != ["house_left", "house_right"]:
		return Result.failure("house_ids mismatch: %s" % str(analysis.get("house_ids", null)))
	if analysis.get("restaurant_ids", []) != ["rest_0", "rest_1"]:
		return Result.failure("restaurant_ids mismatch: %s" % str(analysis.get("restaurant_ids", null)))
	if not bool(analysis.get("road_graph_available", false)):
		return Result.failure("road graph should be available")

	var distances: Dictionary = analysis.get("restaurant_house_distances", {})
	var r0: Dictionary = distances.get("rest_0", {})
	var r1: Dictionary = distances.get("rest_1", {})
	var r0_left: Dictionary = r0.get("house_left", {})
	var r1_left: Dictionary = r1.get("house_left", {})
	if r0_left.is_empty() or r1_left.is_empty():
		return Result.failure("expected distances for rest_0/rest_1 to house_left: %s" % str(distances))
	if int(r0_left.get("distance", 999999)) >= int(r1_left.get("distance", -1)):
		return Result.failure("rest_0 should be closer to house_left than rest_1: %s vs %s" % [str(r0_left), str(r1_left)])
	return Result.success()

static func _test_drive_through_entrance_points_reuse_structures(seed_val: int) -> Result:
	var engine_read := _build_test_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var state: GameState = engine_read.value.get_state()
	state.players[0]["employees"].append("local_manager")
	var analysis_read := BoardAnalyzerClass.analyze_state(state)
	if not analysis_read.ok:
		return analysis_read
	var entrances: Dictionary = Dictionary(analysis_read.value).get("restaurant_entrance_points", {})
	var rest_0_points: Array = entrances.get("rest_0", [])
	if rest_0_points.size() != 4:
		return Result.failure("drive-through restaurant should expose four entrance points, got: %s" % str(rest_0_points))
	return Result.success()

static func _build_test_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "pizza"}])
	return Result.success(engine)
