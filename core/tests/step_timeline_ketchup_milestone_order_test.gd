# StepTimelineBuild：Ketchup 里程碑顺序回归测试
# - ketchup_sold_your_demand 必须归属 Dinnertime 段落
# - 且必须出现在 DINNERTIME_REPORT 之后（规则书：晚餐结束后授予，不能影响同一晚餐）
class_name StepTimelineKetchupMilestoneOrderTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const MILESTONE_ID := "ketchup_sold_your_demand"

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0

	state.map = _build_test_map()
	RoadGraphCacheClass.invalidate_road_graph(state)
	_set_house_demands(state, "house_left", [{
		"product": "burger",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}])
	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	# 直接推进到 Dinnertime（与 KetchupMechanismV2Test 对齐）
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	state.round_state["sub_phase_passed"] = {0: true, 1: true}

	# StepTimelineBuild 从 checkpoints[0].state_dict 开始回放：需要同步“初始状态”。
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"}))
	if not adv.ok:
		return Result.failure("advance_phase failed: %s" % adv.error)

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full failed: %s" % build_r.error)
	if not (build_r.value is Dictionary):
		return Result.failure("build_full.value type error (expected Dictionary)")

	var data: Dictionary = build_r.value
	var events_val = data.get("events", null)
	if not (events_val is Array):
		return Result.failure("events type error (expected Array)")
	var events: Array = events_val

	var report_seq := -1
	var ms_seq := -1
	var ms_seg := ""

	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t := str(ev.get("type", "")).strip_edges()
		var seg := str(ev.get("phase_segment", "")).strip_edges()
		var seq := int(ev.get("sequence", -1))

		if t == EventBus.EventType.DINNERTIME_REPORT and report_seq < 0:
			report_seq = seq

		if t == EventBus.EventType.MILESTONE_ACHIEVED:
			var d_val = ev.get("data", null)
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			if str(d.get("milestone_id", "")).strip_edges() == MILESTONE_ID:
				ms_seq = seq
				ms_seg = seg
				break

	if report_seq < 0:
		return Result.failure("expected DINNERTIME_REPORT")
	if ms_seq < 0:
		return Result.failure("expected MILESTONE_ACHIEVED %s" % MILESTONE_ID)
	if ms_seg != DefsClass.PHASE_DINNERTIME:
		return Result.failure("expected %s in Dinnertime segment, got: %s" % [MILESTONE_ID, ms_seg])
	if ms_seq <= report_seq:
		return Result.failure("expected %s after DINNERTIME_REPORT (ms_seq=%d report_seq=%d)" % [MILESTONE_ID, ms_seq, report_seq])

	return Result.success({
		"report_seq": report_seq,
		"ms_seq": ms_seq,
	})

static func _build_test_map() -> Dictionary:
	var grid_size := Vector2i(10, 5)
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false
			})
		cells.append(row)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		cells[2][x]["road_segments"] = [{"dirs": dirs}]

	var house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	for p in house_cells:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": "house_left",
			"house_number": 1,
			"has_garden": false,
			"dynamic": true
		}

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	for p2 in rest0_cells:
		cells[p2.y][p2.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": 0,
			"restaurant_id": "rest_0",
			"dynamic": true
		}
	for p3 in rest1_cells:
		cells[p3.y][p3.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": 1,
			"restaurant_id": "rest_1",
			"dynamic": true
		}

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest0_cells,
			},
			"rest_1": {
				"restaurant_id": "rest_1",
				"owner": 1,
				"anchor_pos": Vector2i(8, 3),
				"entrance_pos": Vector2i(9, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses

