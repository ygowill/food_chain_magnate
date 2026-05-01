# lobbyists road 状态访问回归测试
class_name LobbyistsRoadStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_road_action.gd")
const ParkActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_park_action.gd")
const EntryClass = preload("res://modules/lobbyists/rules/entry.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

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
	r = _test_apply_changes_fails_fast_on_missing_roadwork_markers(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_missing_pending_roads(seed_val)
	if not r.ok:
		return r
	r = _test_lobbyists_staff_id_is_authoritative(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 11})

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

static func _test_apply_changes_fails_fast_on_missing_roadwork_markers(seed_val: int) -> Result:
	var state_r := _make_ready_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case9): %s" % state_r.error)
	var state: GameState = state_r.value
	var setup := _prepare_valid_apply_case(state)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var supply_key := str(data.get("supply_key", ""))
	var initial_supply := int(state.map.get(supply_key, -1))
	state.map.erase(ActionClass.ROADWORK_MARKERS_KEY)

	var action = ActionClass.new()
	var result := action._apply_changes(state, data["command"])
	if result.ok:
		return Result.failure("缺失 roadwork markers 时 _apply_changes 应失败")
	var err := str(result.error)
	if err.find("state.map.%s" % ActionClass.ROADWORK_MARKERS_KEY) < 0:
		return Result.failure("错误信息应包含 state.map.%s，实际: %s" % [ActionClass.ROADWORK_MARKERS_KEY, err])
	return _assert_no_apply_mutation(state, data, initial_supply)

static func _test_apply_changes_fails_fast_on_missing_pending_roads(seed_val: int) -> Result:
	var state_r := _make_ready_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case10): %s" % state_r.error)
	var state: GameState = state_r.value
	var setup := _prepare_valid_apply_case(state)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var supply_key := str(data.get("supply_key", ""))
	var initial_supply := int(state.map.get(supply_key, -1))
	state.map.erase(ActionClass.PENDING_ROADS_KEY)

	var action = ActionClass.new()
	var result := action._apply_changes(state, data["command"])
	if result.ok:
		return Result.failure("缺失 pending roads 时 _apply_changes 应失败")
	var err := str(result.error)
	if err.find("state.map.%s" % ActionClass.PENDING_ROADS_KEY) < 0:
		return Result.failure("错误信息应包含 state.map.%s，实际: %s" % [ActionClass.PENDING_ROADS_KEY, err])
	return _assert_no_apply_mutation(state, data, initial_supply)

static func _test_lobbyists_staff_id_is_authoritative(seed_val: int) -> Result:
	var state_r := _make_ready_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(staff_id): %s" % state_r.error)
	var state: GameState = state_r.value
	_take_to_active(state, 0, "lobbyist")
	var sync_read := StaffStateClass.ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "lobbyist", [StaffStateClass.ZONE_ACTIVE])
	if not ids_read.ok:
		return ids_read
	var ids: Array = ids_read.value
	if ids.size() < 2:
		return Result.failure("测试需要至少 2 个 lobbyist staff_id，实际: %s" % str(ids))
	var first_staff_id := int(ids[0])
	var second_staff_id := int(ids[1])

	var cmd_r := _find_valid_command(state)
	if not cmd_r.ok:
		return cmd_r
	var command: Command = cmd_r.value
	command.params["staff_id"] = second_staff_id
	_mark_first_lobbyist_used_claimed(state, 0)

	var action = ActionClass.new()
	var validate := action._validate_specific(state, command)
	if not validate.ok:
		return Result.failure("指定可用 staff_id 的 road action 不应失败: %s" % validate.error)
	var apply_r := action._apply_changes(state, command)
	if not apply_r.ok:
		return Result.failure("指定可用 staff_id 的 road apply 不应失败: %s" % apply_r.error)

	var first_used := StaffStateClass.get_staff_track_used(state, first_staff_id, "lobbyists")
	var second_used := StaffStateClass.get_staff_track_used(state, second_staff_id, "lobbyists")
	if not first_used.ok or not second_used.ok:
		return Result.failure("读取 lobbyists staff usage 失败: %s / %s" % [str(first_used.error), str(second_used.error)])
	if int(first_used.value) != 0 or int(second_used.value) != 1:
		return Result.failure("road action 应只消耗指定 staff_id，实际 first=%s second=%s" % [str(first_used.value), str(second_used.value)])

	var used_state_r := _make_ready_state(seed_val + 1)
	if not used_state_r.ok:
		return Result.failure("初始化失败(used staff): %s" % used_state_r.error)
	var used_state: GameState = used_state_r.value
	var used_ids_read := StaffStateClass.find_staff_ids_by_employee_type(used_state, 0, "lobbyist", [StaffStateClass.ZONE_ACTIVE])
	if not used_ids_read.ok:
		return used_ids_read
	var used_ids: Array = used_ids_read.value
	if used_ids.is_empty():
		return Result.failure("used staff 测试缺少 lobbyist staff_id")
	var used_staff_id := int(used_ids[0])
	var used_cmd_r := _find_valid_command(used_state)
	if not used_cmd_r.ok:
		return used_cmd_r
	var inc_used := StaffStateClass.increment_staff_track_usage(used_state, used_staff_id, "lobbyists", 1)
	if not inc_used.ok:
		return inc_used
	var used_command: Command = used_cmd_r.value
	used_command.params["staff_id"] = used_staff_id
	var used_validate := action._validate_specific(used_state, used_command)
	if used_validate.ok:
		return Result.failure("已使用的 lobbyist staff_id 应被 road action 拒绝")
	if str(used_validate.error).find("已用完") < 0:
		return Result.failure("已使用 staff_id 错误信息应包含已用完，实际: %s" % used_validate.error)

	var park_state_r := _make_ready_state(seed_val + 2)
	if not park_state_r.ok:
		return Result.failure("初始化失败(park staff): %s" % park_state_r.error)
	var park_state: GameState = park_state_r.value
	var park_ids_read := StaffStateClass.find_staff_ids_by_employee_type(park_state, 0, "lobbyist", [StaffStateClass.ZONE_ACTIVE])
	if not park_ids_read.ok:
		return park_ids_read
	var park_ids: Array = park_ids_read.value
	if park_ids.is_empty():
		return Result.failure("park 测试缺少 lobbyist staff_id")
	var park_staff_id := int(park_ids[0])
	var park_cmd_r := _find_valid_park_command(park_state)
	if not park_cmd_r.ok:
		return park_cmd_r
	var park_command: Command = park_cmd_r.value
	park_command.params["staff_id"] = park_staff_id
	var park_validate := ParkActionClass.new()._validate_specific(park_state, park_command)
	if not park_validate.ok:
		return Result.failure("指定可用 staff_id 的 park action 不应失败: %s" % park_validate.error)
	park_command.params["staff_id"] = 999999
	var bad_park_validate := ParkActionClass.new()._validate_specific(park_state, park_command)
	if bad_park_validate.ok:
		return Result.failure("不存在的 staff_id 应被 park action 拒绝")
	return Result.success()

static func _prepare_valid_apply_case(state: GameState) -> Result:
	var cmd_r := _find_valid_command(state)
	if not cmd_r.ok:
		return cmd_r
	var command: Command = cmd_r.value
	var piece_cells_r := _get_piece_cells(command)
	if not piece_cells_r.ok:
		return piece_cells_r
	var piece_id := str(command.params.get("piece_id", ""))
	return Result.success({
		"command": command,
		"piece_cells": piece_cells_r.value,
		"supply_key": "%s_supply_remaining" % piece_id,
	})

static func _assert_no_apply_mutation(state: GameState, data: Dictionary, initial_supply: int) -> Result:
	var piece_cells: Array[Vector2i] = data["piece_cells"]
	var supply_key := str(data.get("supply_key", ""))
	if int(state.map.get(supply_key, -1)) != initial_supply:
		return Result.failure("失败时不应消耗 supply，%s=%s" % [supply_key, str(state.map.get(supply_key, null))])
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

static func _find_valid_park_command(state: GameState) -> Result:
	var action = ParkActionClass.new()
	var grid: Vector2i = state.map["grid_size"]
	for piece_id in ParkActionClass.PARK_PIECES:
		for y in range(grid.y):
			for x in range(grid.x):
				for rot in [0, 90, 180, 270]:
					var command := Command.create("place_lobbyists_park", 0)
					command.params = {
						"piece_id": piece_id,
						"anchor_pos": [x, y],
						"rotation": rot,
					}
					var result := action._validate_specific(state, command)
					if result.ok:
						return Result.success(command)
	return Result.failure("未找到可放置公园的位置（状态访问测试）")

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

static func _mark_first_lobbyist_used_claimed(state: GameState, player_id: int) -> void:
	if player_id < 0 or player_id >= state.players.size():
		return
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return
	var player: Dictionary = player_val
	var milestones_val = player.get("milestones", [])
	var milestones: Array = milestones_val if milestones_val is Array else []
	if not milestones.has("first_lobbyist_used"):
		milestones.append("first_lobbyist_used")
	player["milestones"] = milestones
	state.players[player_id] = player
