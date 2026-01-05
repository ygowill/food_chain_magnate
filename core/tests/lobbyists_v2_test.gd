# 模块2：说客（Lobbyists）
# - Working 子阶段插入：Lobbyists（PlaceHouses 之后，PlaceRestaurants 之前）
# - 放置公园/道路触发 First Lobbyist Used，并允许立刻扩边放置地图 tile
class_name LobbyistsV2Test
extends RefCounted

const ModuleEntryClass = preload("res://modules/lobbyists/rules/entry.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_park_triggers_extra_tile(seed_val)
	if not r.ok:
		return r

	r = _test_road_pending_and_cleanup(seed_val)
	if not r.ok:
		return r

	r = _test_roadworks_distance_penalty_is_invoked(seed_val)
	if not r.ok:
		return r

	r = _test_park_bonus_is_invoked(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _test_park_triggers_extra_tile(seed_val: int) -> Result:
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
		"lobbyists",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	var entry = ModuleEntryClass.new()
	var init_r: Result = entry._on_restructuring_before_enter(s)
	if not init_r.ok:
		return Result.failure("初始化 Lobbyists 失败: %s" % init_r.error)

	_force_player0_ready_for_lobbyists(s)
	_take_to_active(s, 0, "lobbyist")
	_inject_dummy_restaurant_for_player0(s)

	var placed_park := _try_place_park(e)
	if not placed_park.ok:
		return placed_park
	s = e.get_state()

	if not (s.get_player(0).get("milestones", null) is Array) or not (s.get_player(0)["milestones"] as Array).has("first_lobbyist_used"):
		return Result.failure("玩家 0 应获得 first_lobbyist_used")
	if not s.round_state.has("lobbyists_extra_tile_pending") or not (s.round_state["lobbyists_extra_tile_pending"] is Dictionary):
		return Result.failure("缺少 round_state.lobbyists_extra_tile_pending")
	var pending: Dictionary = s.round_state["lobbyists_extra_tile_pending"]
	if not (pending.get(0, false) is bool) or not bool(pending.get(0, false)):
		return Result.failure("玩家 0 应有 extra_tile pending")

	if not s.map.has("tile_supply_remaining") or not (s.map["tile_supply_remaining"] is Array) or (s.map["tile_supply_remaining"] as Array).is_empty():
		return Result.failure("tile_supply_remaining 不应为空（否则无法测试扩边）")
	var tile_id_val = (s.map["tile_supply_remaining"] as Array)[0]
	if not (tile_id_val is String) or str(tile_id_val).is_empty():
		return Result.failure("tile_supply_remaining[0] 类型错误")
	var tile_id: String = str(tile_id_val)

	var cmd2 := Command.create("place_lobbyists_extra_map_tile", 0)
	cmd2.params = {
		"tile_id": tile_id,
		"attach_to_tile_board_pos": [0, 0],
		"side": "N",
		"rotation": 0,
	}
	var r2 := e.execute_command(cmd2)
	if not r2.ok:
		return Result.failure("扩边放置 tile 失败: %s" % r2.error)
	s = e.get_state()

	var pending2: Dictionary = s.round_state["lobbyists_extra_tile_pending"]
	if bool(pending2.get(0, true)):
		return Result.failure("扩边后 pending 应被清除")
	if (s.map["tile_supply_remaining"] as Array).has(tile_id):
		return Result.failure("tile_supply_remaining 应消耗该 tile_id: %s" % tile_id)

	if not s.map.has("external_tile_placements") or not (s.map["external_tile_placements"] is Array):
		return Result.failure("state.map.external_tile_placements 缺失或类型错误")
	var ext: Array = s.map["external_tile_placements"]
	if ext.is_empty():
		return Result.failure("应记录 external_tile_placements")

	return Result.success()

static func _test_road_pending_and_cleanup(seed_val: int) -> Result:
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
		"lobbyists",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	var entry = ModuleEntryClass.new()
	var init_r: Result = entry._on_restructuring_before_enter(s)
	if not init_r.ok:
		return Result.failure("初始化 Lobbyists 失败: %s" % init_r.error)

	_force_player0_ready_for_lobbyists(s)
	_take_to_active(s, 0, "lobbyist")
	_inject_dummy_restaurant_for_player0(s)

	var placed_road := _try_place_road(e)
	if not placed_road.ok:
		return placed_road
	s = e.get_state()

	if not s.map.has("lobbyists_pending_roads") or not (s.map["lobbyists_pending_roads"] is Array):
		return Result.failure("缺少 state.map.lobbyists_pending_roads")
	if (s.map["lobbyists_pending_roads"] as Array).is_empty():
		return Result.failure("应存在 pending_roads")
	if not s.map.has("lobbyists_roadworks_markers") or not (s.map["lobbyists_roadworks_markers"] is Dictionary):
		return Result.failure("缺少 state.map.lobbyists_roadworks_markers")
	if (s.map["lobbyists_roadworks_markers"] as Dictionary).is_empty():
		return Result.failure("应放置 roadworks markers")

	var r2: Result = entry._on_cleanup_enter_extension(s, null)
	if not r2.ok:
		return Result.failure("Cleanup 扩展失败: %s" % r2.error)
	if not (s.map["lobbyists_pending_roads"] as Array).is_empty():
		return Result.failure("Cleanup 后 pending_roads 应清空")
	if not (s.map["lobbyists_roadworks_markers"] as Dictionary).is_empty():
		return Result.failure("Cleanup 后 roadworks_markers 应清空")

	return Result.success()

static func _test_roadworks_distance_penalty_is_invoked(seed_val: int) -> Result:
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
		"lobbyists",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	var entry = ModuleEntryClass.new()
	var init_r: Result = entry._on_restructuring_before_enter(s)
	if not init_r.ok:
		return Result.failure("初始化 Lobbyists 失败: %s" % init_r.error)

	# 找到一段 >=3 的道路路径，并在路径中间放置一个 roadworks marker
	var road_graph = MapRuntimeClass.get_road_graph(s)
	if road_graph == null:
		return Result.failure("道路图未初始化")
	var pick := _pick_connected_road_path(s, road_graph)
	if not pick.ok:
		return pick
	var path: Array[Vector2i] = pick.value
	if path.size() < 3:
		return Result.failure("测试需要 >=3 的道路 path（实际: %d）" % path.size())
	var marker_pos: Vector2i = path[1]

	s.map["lobbyists_roadworks_markers"] = {
		"%d,%d" % [marker_pos.x, marker_pos.y]: true,
	}

	var ctx := {
		"distance": 0,
		"path": path,
	}
	var eff_r := DinnertimeSettlementClass._apply_global_effects_by_segment(
		s,
		0,
		e.ruleset_v2.effect_registry,
		":dinnertime:distance_delta:",
		ctx
	)
	if not eff_r.ok:
		return eff_r
	if int(ctx.get("distance", -1)) != 1:
		return Result.failure("roadworks 应使 distance +1（实际: %s）" % str(ctx.get("distance", null)))

	return Result.success()

static func _test_park_bonus_is_invoked(seed_val: int) -> Result:
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
		"lobbyists",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	var entry = ModuleEntryClass.new()
	var init_r: Result = entry._on_restructuring_before_enter(s)
	if not init_r.ok:
		return Result.failure("初始化 Lobbyists 失败: %s" % init_r.error)

	var found := _find_house_with_empty_neighbor(s)
	if not found.ok:
		return found
	var house_id: String = str((found.value as Dictionary)["house_id"])
	var neighbor: Vector2i = (found.value as Dictionary)["neighbor"]

	# 1) 未放置 park 时，bonus 不应变化
	var ctx0 := {
		"bonus": 0,
		"unit_price": 10,
		"quantity": 2,
		"house_id": house_id,
	}
	var eff0 := DinnertimeSettlementClass._apply_global_effects_by_segment(
		s,
		0,
		e.ruleset_v2.effect_registry,
		":dinnertime:sale_house_bonus:",
		ctx0
	)
	if not eff0.ok:
		return eff0
	if int(ctx0.get("bonus", -1)) != 0:
		return Result.failure("未放置 park 时不应有 bonus（实际: %s）" % str(ctx0.get("bonus", null)))

	# 2) 在房屋旁注入一个 park 结构格，bonus 应 +unit_price*quantity
	_inject_park_at_world_pos(s, neighbor)
	var ctx1 := {
		"bonus": 0,
		"unit_price": 10,
		"quantity": 2,
		"house_id": house_id,
	}
	var eff1 := DinnertimeSettlementClass._apply_global_effects_by_segment(
		s,
		0,
		e.ruleset_v2.effect_registry,
		":dinnertime:sale_house_bonus:",
		ctx1
	)
	if not eff1.ok:
		return eff1
	if int(ctx1.get("bonus", -1)) != 20:
		return Result.failure("park 应使 bonus += unit_price*quantity（期望=20 实际=%s）" % str(ctx1.get("bonus", null)))

	return Result.success()

static func _pick_connected_road_path(state: GameState, road_graph) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("state.map.cells 缺失或类型错误（期望 Array）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("state.map.grid_size 缺失或类型错误（期望 Vector2i）")

	var cells: Array = state.map["cells"]
	var grid: Vector2i = state.map["grid_size"]
	var road_cells: Array[Vector2i] = []
	for iy in range(grid.y):
		var row_val = cells[iy]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for ix in range(grid.x):
			var cell_val = row[ix]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var segs = cell.get("road_segments", null)
			if segs is Array and not (segs as Array).is_empty():
				road_cells.append(MapRuntimeClass.index_to_world(state, Vector2i(ix, iy)))

	for i in range(road_cells.size()):
		var from_pos: Vector2i = road_cells[i]
		for j in range(i + 1, road_cells.size()):
			var to_pos: Vector2i = road_cells[j]
			var path_r = road_graph.find_shortest_path(from_pos, to_pos)
			if not path_r.ok:
				continue
			if not (path_r.value is Dictionary):
				continue
			var info: Dictionary = path_r.value
			var path_val = info.get("path", null)
			if not (path_val is Array):
				continue
			var path_any: Array = path_val
			var path: Array[Vector2i] = []
			for k in range(path_any.size()):
				var p = path_any[k]
				if not (p is Vector2i):
					path = []
					break
				path.append(p)
			if path.size() >= 3:
				return Result.success(path)

	return Result.failure("未找到可用的道路路径（需要 >=3）")

static func _find_house_with_empty_neighbor(state: GameState) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return Result.failure("state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = houses_val

	for house_id_val in houses.keys():
		var house_id: String = str(house_id_val)
		var house_val = houses.get(house_id_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var cells_val = house.get("cells", null)
		if not (cells_val is Array):
			continue
		var cells_any: Array = cells_val
		for i in range(cells_any.size()):
			var c = cells_any[i]
			if not (c is Vector2i):
				continue
			var pos: Vector2i = c
			for off in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var npos = pos + off
				if not MapRuntimeClass.is_world_pos_in_grid(state, npos):
					continue
				var cell: Dictionary = MapRuntimeClass.get_cell(state, npos)
				if bool(cell.get("blocked", false)):
					continue
				var s_val = cell.get("structure", null)
				if s_val is Dictionary and not (s_val as Dictionary).is_empty():
					continue
				return Result.success({
					"house_id": house_id,
					"neighbor": npos,
				})

	return Result.failure("未找到“房屋邻接空格”用于 park 测试")

static func _inject_park_at_world_pos(state: GameState, pos: Vector2i) -> void:
	if state == null or not (state.map is Dictionary):
		return
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return
	var idx := MapRuntimeClass.world_to_index(state, pos)
	var cells: Array = state.map["cells"]
	if idx.y < 0 or idx.y >= cells.size():
		return
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return
	var cell: Dictionary = cell_val
	cell["structure"] = {"piece_id": "park"}
	row[idx.x] = cell
	cells[idx.y] = row
	state.map["cells"] = cells

static func _try_place_park(engine: GameEngine) -> Result:
	var s: GameState = engine.get_state()
	var grid: Vector2i = s.map.grid_size
	for y in range(grid.y):
		for x in range(grid.x):
			for rot in [0, 90, 180, 270]:
				var cmd := Command.create("place_lobbyists_park", 0)
				cmd.params = {"anchor_pos": [x, y], "rotation": rot}
				var r := engine.execute_command(cmd)
				if r.ok:
					return Result.success()
	return Result.failure("未找到可放置公园的位置（测试环境）")

static func _try_place_road(engine: GameEngine) -> Result:
	var s: GameState = engine.get_state()
	var grid: Vector2i = s.map.grid_size
	for piece_id in ["lobbyists_road_straight", "lobbyists_road_l"]:
		for y in range(grid.y):
			for x in range(grid.x):
				for rot in [0, 90, 180, 270]:
					var cmd := Command.create("place_lobbyists_road", 0)
					cmd.params = {"piece_id": piece_id, "anchor_pos": [x, y], "rotation": rot}
					var r := engine.execute_command(cmd)
					if r.ok:
						return Result.success()
	return Result.failure("未找到可放置道路的位置（测试环境）")

static func _force_player0_ready_for_lobbyists(state: GameState) -> void:
	state.phase = "Working"
	state.sub_phase = "Lobbyists"
	state.turn_order = [0, 1]
	state.current_player_index = 0
	if state.round_state is Dictionary:
		state.round_state["sub_phase_passed"] = {0: false, 1: false}

static func _inject_dummy_restaurant_for_player0(state: GameState) -> void:
	# Lobbyists 的 range=2 by road 需要至少一个“自己的餐厅入口”作为起点。
	# 测试中直接注入一个最小 restaurant 记录（无需完整 2x2 结构）。
	if not (state.map is Dictionary):
		return
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		state.map["restaurants"] = {}
	var restaurants: Dictionary = state.map["restaurants"]

	var grid: Vector2i = state.map["grid_size"]
	for y in range(grid.y):
		for x in range(grid.x):
			var cell_val = state.map["cells"][y][x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			if bool(cell.get("blocked", false)):
				continue
			var s_val = cell.get("structure", null)
			if s_val is Dictionary and not (s_val as Dictionary).is_empty():
				continue
			var has_adjacent_road := false
			for dir in ["N", "E", "S", "W"]:
				var nx := x
				var ny := y
				match dir:
					"N":
						ny -= 1
					"E":
						nx += 1
					"S":
						ny += 1
					"W":
						nx -= 1
				if nx < 0 or ny < 0 or nx >= grid.x or ny >= grid.y:
					continue
				var ncell_val = state.map["cells"][ny][nx]
				if not (ncell_val is Dictionary):
					continue
				var ncell: Dictionary = ncell_val
				var segs = ncell.get("road_segments", null)
				if segs is Array and not (segs as Array).is_empty():
					has_adjacent_road = true
					break
			if not has_adjacent_road:
				continue
			var entrance := Vector2i(x, y)
			restaurants["test_restaurant_0"] = {
				"restaurant_id": "test_restaurant_0",
				"owner": 0,
				"anchor_pos": entrance,
				"entrance_pos": entrance,
				"cells": [entrance],
				"rotation": 0,
			}
			state.map["restaurants"] = restaurants
			return

static func _take_to_active(state: GameState, player_id: int, employee_id: String) -> void:
	if not state.employee_pool.has(employee_id):
		state.employee_pool[employee_id] = 0
	state.employee_pool[employee_id] = int(state.employee_pool.get(employee_id, 0)) - 1
	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "player 类型错误")
	var player: Dictionary = player_val
	if not player.has("employees") or not (player["employees"] is Array):
		player["employees"] = []
	var emps: Array = player["employees"]
	emps.append(employee_id)
	player["employees"] = emps
	state.players[player_id] = player
