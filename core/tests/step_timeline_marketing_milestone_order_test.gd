# StepTimelineBuild：Marketing 里程碑顺序回归测试（0.1.2）
# - first_burger_marketed 必须归属 Marketing 段落
# - 且必须出现在 DEMAND_GENERATED 之后（因果关系：先生成需求，再获得里程碑/奖励）
class_name StepTimelineMarketingMilestoneOrderTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0

	state.map = _build_billboard_map()
	RoadGraphCacheClass.invalidate_road_graph(state)

	# 注入一个 billboard 营销实例，触发 Marketing:enter 的 DemandMarked 里程碑。
	state.marketing_instances = [{
		"board_number": 11,
		"type": "billboard",
		"owner": 0,
		"employee_type": "marketing_trainee",
		"product": "burger",
		"world_pos": Vector2i(1, 2),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}]

	if not (state.map is Dictionary):
		return Result.failure("map type error (expected Dictionary)")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		state.map["marketing_placements"] = {}
	state.map["marketing_placements"]["11"] = {
		"board_number": 11,
		"type": "billboard",
		"owner": 0,
		"product": "burger",
		"world_pos": Vector2i(1, 2),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}

	var take := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take.ok:
		return Result.failure("take_from_pool marketing_trainee failed: %s" % take.error)
	state.players[0]["busy_marketers"] = ["marketing_trainee"]

	# 从 Payday 推进到 Marketing（典型 exit+enter 叠加：Payday:exit + Marketing:enter）
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""

	# StepTimelineBuild 从 checkpoints[0].state_dict 开始回放：需要同步“初始状态”。
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not adv.ok:
		return Result.failure("advance_phase failed: %s" % adv.error)

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full failed: %s" % build_r.error)

	var data_val = build_r.value
	if not (data_val is Dictionary):
		return Result.failure("build_full.value type error (expected Dictionary)")
	var data: Dictionary = data_val
	var events_val = data.get("events", null)
	if not (events_val is Array):
		return Result.failure("events type error (expected Array)")
	var events: Array = events_val

	var demand_seq := -1
	var milestone_seq := -1
	var milestone_seg := ""

	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t := str(ev.get("type", "")).strip_edges()
		var seg := str(ev.get("phase_segment", "")).strip_edges()
		var seq := int(ev.get("sequence", -1))

		if t == EventBus.EventType.DEMAND_GENERATED and seg == DefsClass.PHASE_MARKETING and demand_seq < 0:
			demand_seq = seq

		if t == EventBus.EventType.MILESTONE_ACHIEVED:
			var d_val = ev.get("data", null)
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			if str(d.get("milestone_id", "")).strip_edges() == "first_burger_marketed":
				milestone_seq = seq
				milestone_seg = seg

	if demand_seq < 0:
		return Result.failure("expected DEMAND_GENERATED in Marketing segment")
	if milestone_seq < 0:
		return Result.failure("expected MILESTONE_ACHIEVED first_burger_marketed")
	if milestone_seg != DefsClass.PHASE_MARKETING:
		return Result.failure("expected first_burger_marketed in Marketing segment, got: %s" % milestone_seg)
	if milestone_seq <= demand_seq:
		return Result.failure("expected first_burger_marketed after DEMAND_GENERATED (milestone_seq=%d demand_seq=%d)" % [milestone_seq, demand_seq])

	return Result.success({
		"demand_seq": demand_seq,
		"milestone_seq": milestone_seq,
	})

static func _build_billboard_map() -> Dictionary:
	var grid_size := Vector2i(3, 3)
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

	# 房屋放在 (1,1)，billboard 放在 (1,2) 时会影响 (1,1)
	cells[1][1]["structure"] = {
		"piece_id": "house",
		"house_id": "house_1",
		"house_number": 1,
		"has_garden": false,
		"dynamic": true
	}

	var houses := {
		"house_1": {
			"house_id": "house_1",
			"house_number": 1,
			"anchor_pos": Vector2i(1, 1),
			"cells": [Vector2i(1, 1)],
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		}
	}

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": houses,
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}
