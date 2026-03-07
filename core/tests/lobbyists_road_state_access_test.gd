# lobbyists road 状态访问回归测试
class_name LobbyistsRoadStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_road_action.gd")
const EntryClass = preload("res://modules/lobbyists/rules/entry.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_is_adjacent_returns_false_with_empty_restaurants()
	if not r.ok:
		return r
	r = _test_is_adjacent_fails_fast_on_missing_restaurants()
	if not r.ok:
		return r
	r = _test_build_map_context_succeeds_with_valid_map()
	if not r.ok:
		return r
	r = _test_build_map_context_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_build_map_context_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_build_map_context_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_missing_supply(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_without_partial_mutation(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 8})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": Vector2i(3, 3),
		"cells": [],
		"boundary_index": {},
		"houses": {},
		"restaurants": {},
		"marketing_placements": {},
	}
	var cells := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append({
				"road_segments": [],
				"structure": {},
				"terrain_type": null,
				"drink_source": null,
				"tile_origin": Vector2i.ZERO,
				"blocked": false,
			})
		cells.append(row)
	state.map["cells"] = cells
	state.map["cells"][1][1]["road_segments"] = [{
		"dirs": ["N", "S"],
		"bridge": false,
	}]
	return state

static func _make_ready_state(seed_val: int) -> Result:
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
		"lobbyists",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return init
	var state: GameState = engine.get_state()
	var entry = EntryClass.new()
	var init_r := entry._on_restructuring_before_enter(state)
	if not init_r.ok:
		return Result.failure("初始化 Lobbyists 失败: %s" % init_r.error)
	_force_player0_ready_for_lobbyists(state)
	_take_to_active(state, 0, "lobbyist")
	_inject_dummy_restaurant_for_player0(state)
	return Result.success(state)

static func _test_is_adjacent_returns_false_with_empty_restaurants() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	var piece_cells: Array[Vector2i] = [Vector2i(0, 0)]
	var result := action._is_adjacent_to_reachable_road(state, 0, piece_cells, 2)
	if not result.ok:
		return Result.failure("空 restaurants 时不应失败: %s" % result.error)
	if bool(result.value):
		return Result.failure("空 restaurants 时应返回 false")
	return Result.success()

static func _test_is_adjacent_fails_fast_on_missing_restaurants() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("restaurants")
	var piece_cells: Array[Vector2i] = [Vector2i(0, 0)]
	var result := action._is_adjacent_to_reachable_road(state, 0, piece_cells, 2)
	if result.ok:
		return Result.failure("缺失 restaurants 时应失败")
	var err := str(result.error)
	if err.find("state.map.restaurants") < 0:
		return Result.failure("错误信息应包含 state.map.restaurants，实际: %s" % err)
	return Result.success()

static func _test_build_map_context_succeeds_with_valid_map() -> Result:
	var action = ActionClass.new()
	var result := action._build_map_context(_make_state())
	if not result.ok:
		return Result.failure("合法 map context 不应失败: %s" % result.error)
	var map_ctx: Dictionary = result.value
	if not (map_ctx.get("marketing_placements", null) is Dictionary):
		return Result.failure("map_ctx.marketing_placements 应为 Dictionary")
	return Result.success()

static func _test_build_map_context_fails_fast_on_missing_houses() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := action._build_map_context(state)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_build_map_context_fails_fast_on_missing_marketing_placements() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := action._build_map_context(state)
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_build_map_context_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := action._build_map_context(state)
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_missing_supply(seed_val: int) -> Result:
	var state_r := _make_ready_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case7): %s" % state_r.error)
	var state: GameState = state_r.value
	state.map.erase("lobbyists_road_straight_supply_remaining")
	var action = ActionClass.new()
	var command := Command.create("place_lobbyists_road", 0)
	command.params = {"piece_id": "lobbyists_road_straight"}
	var result := action._validate_specific(state, command)
	if result.ok:
		return Result.failure("缺失道路 supply 时应失败")
	var err := str(result.error)
	if err.find("state.map.lobbyists_road_straight_supply_remaining") < 0:
		return Result.failure("错误信息应包含 state.map.lobbyists_road_straight_supply_remaining，实际: %s" % err)
	return Result.success()

static func _test_apply_changes_fails_fast_without_partial_mutation(seed_val: int) -> Result:
	var state_r := _make_ready_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case8): %s" % state_r.error)
	var state: GameState = state_r.value
	var cmd_r := _find_valid_command(state)
	if not cmd_r.ok:
		return cmd_r
	var command: Command = cmd_r.value
	var piece_cells_r := _get_piece_cells(command)
	if not piece_cells_r.ok:
		return piece_cells_r
	var piece_cells: Array[Vector2i] = piece_cells_r.value
	var piece_id: String = str(command.params.get("piece_id", ""))
	var supply_key := "%s_supply_remaining" % piece_id
	state.map.erase(supply_key)

	var action = ActionClass.new()
	var result := action._apply_changes(state, command)
	if result.ok:
		return Result.failure("缺失道路 supply 时 _apply_changes 应失败")
	var err := str(result.error)
	if err.find("state.map.%s" % supply_key) < 0:
		return Result.failure("错误信息应包含 state.map.%s，实际: %s" % [supply_key, err])
	for pos in piece_cells:
		var cell: Dictionary = CellsClass.get_cell(state, pos)
		var structure_val = cell.get("structure", null)
		if structure_val is Dictionary and not (structure_val as Dictionary).is_empty():
			return Result.failure("失败时不应提前写入 structure: %s" % str(pos))
	var pending_val = state.map.get(ActionClass.PENDING_ROADS_KEY, null)
	if pending_val is Array and not (pending_val as Array).is_empty():
		return Result.failure("失败时不应提前写入 pending roads")
	var markers_val = state.map.get(ActionClass.ROADWORK_MARKERS_KEY, null)
	if markers_val is Dictionary and not (markers_val as Dictionary).is_empty():
		return Result.failure("失败时不应提前写入 roadwork markers")
	return Result.success()

static func _find_valid_command(state: GameState) -> Result:
	var action = ActionClass.new()
	var grid: Vector2i = state.map["grid_size"]
	for piece_id in ActionClass.ROAD_PIECES:
		for y in range(grid.y):
			for x in range(grid.x):
				for rot in [0, 90, 180, 270]:
					var command := Command.create("place_lobbyists_road", 0)
					command.params = {
						"piece_id": piece_id,
						"anchor_pos": [x, y],
						"rotation": rot,
					}
					var result := action._validate_specific(state, command)
					if result.ok:
						return Result.success(command)
	return Result.failure("未找到可放置道路的位置（状态访问测试）")

static func _get_piece_cells(command: Command) -> Result:
	var piece_id: String = str(command.params.get("piece_id", ""))
	var piece_def_val = PieceRegistryClass.get_def(piece_id)
	if piece_def_val == null:
		return Result.failure("未加载的 piece: %s" % piece_id)
	var piece_def: PieceDef = piece_def_val
	var anchor_arr = command.params.get("anchor_pos", null)
	if not (anchor_arr is Array) or (anchor_arr as Array).size() != 2:
		return Result.failure("anchor_pos 类型错误（期望 [x,y]）")
	var anchor_vals: Array = anchor_arr
	if not (anchor_vals[0] is int) or not (anchor_vals[1] is int):
		return Result.failure("anchor_pos 元素类型错误（期望 int）")
	var anchor := Vector2i(int(anchor_vals[0]), int(anchor_vals[1]))
	var rotation := int(command.params.get("rotation", 0))
	return Result.success(piece_def.get_world_cells(anchor, rotation))

static func _force_player0_ready_for_lobbyists(state: GameState) -> void:
	state.phase = "Working"
	state.sub_phase = "Lobbyists"
	state.turn_order = [0, 1]
	state.current_player_index = 0
	if state.round_state is Dictionary:
		state.round_state["sub_phase_passed"] = {0: false, 1: false}

static func _inject_dummy_restaurant_for_player0(state: GameState) -> void:
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
			var structure_val = cell.get("structure", null)
			if structure_val is Dictionary and not (structure_val as Dictionary).is_empty():
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
	var employees: Array = player["employees"]
	employees.append(employee_id)
	player["employees"] = employees
	state.players[player_id] = player
