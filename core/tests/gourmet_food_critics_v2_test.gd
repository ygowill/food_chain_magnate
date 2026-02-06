# 模块13：美食评论家（Gourmet Food Critics）
class_name GourmetFoodCriticsV2Test
extends RefCounted

const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_registration_and_range(seed_val)
	if not r.ok:
		return r
	r = _test_global_limit_and_offramp_conflict(seed_val)
	if not r.ok:
		return r
	r = _test_gourmet_guide_onboard_placement(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _test_registration_and_range(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"gourmet_food_critics",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	if not MarketingTypeRegistryClass.has_type("gourmet_guide"):
		return Result.failure("MarketingTypeRegistry 缺少 gourmet_guide（模块未注册）")
	if MarketingTypeRegistryClass.requires_edge("gourmet_guide"):
		return Result.failure("gourmet_guide 不应要求边缘放置（requires_edge=false）")

	var marketer = EmployeeRegistryClass.get_def("marketing_trainee")
	if marketer == null:
		return Result.failure("缺少员工定义: marketing_trainee")
	if not marketer.train_to.has("gourmet_food_critic"):
		return Result.failure("marketing_trainee.train_to 应包含 gourmet_food_critic（模块 patch 未生效）")

	# 构造最小 houses（不依赖结构格）：仅验证 range handler 选中 has_garden 的房屋
	if not (s.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	s.map["houses"] = {
		"h_garden": {"house_id": "h_garden", "house_number": 1, "has_garden": true, "demands": []},
		"h_plain": {"house_id": "h_plain", "house_number": 2, "has_garden": false, "demands": []},
		"rural_area": {"house_id": "rural_area", "house_number": "zzzz_rural_area", "has_garden": false, "demands": []},
	}

	var handler := MarketingTypeRegistryClass.get_range_handler("gourmet_guide")
	if not handler.is_valid():
		return Result.failure("gourmet_guide handler 无效")
	var rr = handler.call(s, {"type": "gourmet_guide"})
	if not (rr is Result):
		return Result.failure("gourmet_guide handler 返回值类型错误（期望 Result）")
	var rres: Result = rr
	if not rres.ok:
		return Result.failure("gourmet_guide handler 失败: %s" % rres.error)
	var affected: Array = rres.value
	if affected.size() != 1 or str(affected[0]) != "h_garden":
		return Result.failure("gourmet_guide 应仅影响有花园的房屋（期望 [h_garden]），实际: %s" % str(affected))

	return Result.success()

static func _test_global_limit_and_offramp_conflict(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"gourmet_food_critics",
		"rural_marketeers",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	# 伪造已存在的 3 个 gourmet_guide 实例，下一次放置应被拒绝（全局最多 3 个）
	s.marketing_instances = [
		{"type": "gourmet_guide", "board_number": 17},
		{"type": "gourmet_guide", "board_number": 18},
		{"type": "gourmet_guide", "board_number": 19},
	]

	var entry = load("res://modules/gourmet_food_critics/rules/entry.gd").new()

	var cmd := Command.create("initiate_marketing", 0)
	cmd.params = {
		"employee_type": "gourmet_food_critic",
		"board_number": 20,
		"product": "burger",
		"position": [0, 0],
		"duration": 1,
	}
	var r1: Result = entry._validate_initiate_marketing(s, cmd)
	if r1.ok:
		return Result.failure("超过全局 3 个 gourmet_guide 时应被拒绝")

	# 冲突：同格已有 offramp 时应拒绝（通过 PlacementConflictRegistry 查询）
	s.marketing_instances = []
	s.map["rural_marketeers_offramps"] = [{"pos": Vector2i(0, 0)}]
	var r2: Result = entry._validate_initiate_marketing(s, cmd)
	if r2.ok:
		return Result.failure("与 offramp 同格应被拒绝")

	# sanity：board_number=4（airplane）不应被该 validator 影响
	var cmd_air := Command.create("initiate_marketing", 0)
	cmd_air.params = {"board_number": 4, "position": [0, 0]}
	var r3: Result = entry._validate_initiate_marketing(s, cmd_air)
	if not r3.ok:
		return Result.failure("非 gourmet_guide 不应被该 validator 拒绝: %s" % r3.error)

	# sanity：MarketingRegistry 中 17–20 的 type 应为 gourmet_guide
	for bn in [17, 18, 19, 20]:
		var def = MarketingRegistryClass.get_def(bn)
		if def == null:
			return Result.failure("缺少营销板件定义: #%d" % bn)
		if str(def.type) != "gourmet_guide":
			return Result.failure("营销板件 #%d type 应为 gourmet_guide，实际: %s" % [bn, str(def.type)])
		if def is MarketingDef and (def as MarketingDef).footprint_size != Vector2i(2, 2):
			return Result.failure("营销板件 #%d footprint_size 应为 2x2，实际: %s" % [bn, str((def as MarketingDef).footprint_size)])

	return Result.success()

static func _test_gourmet_guide_onboard_placement(seed_val: int) -> Result:
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
		"gourmet_food_critics",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING

	# Minimal map: empty grid + 1 owned restaurant (marketing requires player has a restaurant).
	# gourmet_guide is a 2x2 on-board marketing tile; it must be placed on empty cells adjacent to a road.
	var grid_size := Vector2i(5, 5)
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false,
				"drink_source": null,
			})
		cells.append(row)

	# Add a road adjacent to anchor (1,1)'s 2x2 footprint (covers (1,1)-(2,2)).
	cells[1][0]["road_segments"] = [{"bridge": false, "dirs": ["N", "S"]}]

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"map_origin": Vector2i.ZERO,
		"cells": cells,
		"houses": {},
		"restaurants": {"rest_0": {"owner": 0}},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	}

	# Ensure the employee is active for the current player.
	if not (state.players[0] is Dictionary):
		return Result.failure("players[0] 类型错误（期望 Dictionary）")
	if not state.players[0].has("employees") or not (state.players[0]["employees"] is Array):
		return Result.failure("players[0].employees 缺失或类型错误（期望 Array）")
	if not (state.employee_pool is Dictionary):
		return Result.failure("employee_pool 类型错误（期望 Dictionary）")
	var pool_count := int(state.employee_pool.get("gourmet_food_critic", 0))
	if pool_count <= 0:
		return Result.failure("员工池中没有 gourmet_food_critic")
	state.employee_pool["gourmet_food_critic"] = pool_count - 1
	(state.players[0]["employees"] as Array).append("gourmet_food_critic")

	var r := engine.execute_command(Command.create("initiate_marketing", 0, {
		"employee_type": "gourmet_food_critic",
		"board_number": 17,
		"product": "burger",
		"duration": 1,
		"position": [1, 1],
	}))
	if not r.ok:
		return Result.failure("发起 gourmet_guide 营销失败: %s" % r.error)

	var s2 := engine.get_state()
	if not (s2.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	var placements_val = s2.map.get("marketing_placements", null)
	if not (placements_val is Dictionary):
		return Result.failure("state.map.marketing_placements 类型错误（期望 Dictionary）")
	var placements: Dictionary = placements_val
	if not placements.has("17"):
		return Result.failure("gourmet_guide 放置后应写入 marketing_placements[17]")
	var p_val = placements.get("17", null)
	if not (p_val is Dictionary):
		return Result.failure("marketing_placements[17] 类型错误（期望 Dictionary）")
	var p: Dictionary = p_val
	if str(p.get("type", "")) != "gourmet_guide":
		return Result.failure("marketing_placements[17].type 应为 gourmet_guide，实际: %s" % str(p.get("type", null)))
	if str(p.get("axis", "")) != "":
		return Result.failure("marketing_placements[17].axis 应为空（仅 airplane 使用），实际: %s" % str(p.get("axis", null)))

	# Sanity: road remains (on-board placement should not modify roads).
	var road_cell: Dictionary = (s2.map.get("cells", []) as Array)[1][0]
	var rs_val = road_cell.get("road_segments", null)
	if not (rs_val is Array) or (rs_val as Array).is_empty():
		return Result.failure("营销放置后 road_segments 不应被清空（预期道路仍存在）")

	# Sanity: marketer becomes busy.
	var p0: Dictionary = s2.players[0]
	var busy_val = p0.get("busy_marketers", null)
	if not (busy_val is Array) or not (busy_val as Array).has("gourmet_food_critic"):
		return Result.failure("发起营销后 gourmet_food_critic 应进入 busy_marketers")

	return Result.success()
