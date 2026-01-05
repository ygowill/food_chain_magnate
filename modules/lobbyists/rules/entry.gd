extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

const PlaceLobbyistsRoadActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_road_action.gd")
const PlaceLobbyistsParkActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_park_action.gd")
const PlaceLobbyistsExtraMapTileActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_extra_map_tile_action.gd")
const SkipLobbyistsExtraMapTileActionClass = preload("res://modules/lobbyists/actions/skip_lobbyists_extra_map_tile_action.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const MODULE_ID := "lobbyists"

const ROAD_SUPPLY_TOTAL := 8
const PARK_SUPPLY_TOTAL := 8

const ROAD_SUPPLY_KEY := "lobbyists_road_supply_remaining"
const PARK_SUPPLY_KEY := "lobbyists_park_supply_remaining"
const PENDING_ROADS_KEY := "lobbyists_pending_roads"
const ROADWORK_MARKERS_KEY := "lobbyists_roadworks_markers"
const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"

const GLOBAL_EFFECT_IDS_KEY := "global_effect_ids"
const EFFECT_ID_ROADWORKS_DISTANCE := "%s:dinnertime:distance_delta:roadworks" % MODULE_ID
const EFFECT_ID_PARK_BONUS := "%s:dinnertime:sale_house_bonus:park" % MODULE_ID

func register(registrar) -> Result:
	var r: Result = registrar.register_working_sub_phase_insertion("Lobbyists", "PlaceHouses", "PlaceRestaurants", 100)
	if not r.ok:
		return r
	r = registrar.register_working_sub_phase_hook("Lobbyists", HookType.BEFORE_EXIT, Callable(self, "_on_lobbyists_before_exit"), 0)
	if not r.ok:
		return r

	r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"), 0)
	if not r.ok:
		return r

	r = registrar.register_extension_settlement(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_cleanup_enter_extension"), 100)
	if not r.ok:
		return r

	r = registrar.register_effect(EFFECT_ID_ROADWORKS_DISTANCE, Callable(self, "_effect_dinnertime_distance_delta_roadworks"))
	if not r.ok:
		return r
	r = registrar.register_effect(EFFECT_ID_PARK_BONUS, Callable(self, "_effect_dinnertime_sale_house_bonus_park"))
	if not r.ok:
		return r

	r = registrar.register_milestone_effect("lobbyists_grant_extra_map_tile", Callable(self, "_milestone_effect_grant_extra_map_tile"))
	if not r.ok:
		return r

	r = registrar.register_action_executor(PlaceLobbyistsRoadActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlaceLobbyistsParkActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlaceLobbyistsExtraMapTileActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(SkipLobbyistsExtraMapTileActionClass.new())
	if not r.ok:
		return r

	return Result.success()

func _on_restructuring_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)

	if not state.map.has(ROAD_SUPPLY_KEY):
		state.map[ROAD_SUPPLY_KEY] = ROAD_SUPPLY_TOTAL
	if not state.map.has(PARK_SUPPLY_KEY):
		state.map[PARK_SUPPLY_KEY] = PARK_SUPPLY_TOTAL
	if not state.map.has(PENDING_ROADS_KEY):
		state.map[PENDING_ROADS_KEY] = []
	if not state.map.has(ROADWORK_MARKERS_KEY):
		state.map[ROADWORK_MARKERS_KEY] = {}

	# 全局效果：roadworks 距离惩罚 + park 单价加成
	if not state.map.has(GLOBAL_EFFECT_IDS_KEY):
		state.map[GLOBAL_EFFECT_IDS_KEY] = []
	if not (state.map[GLOBAL_EFFECT_IDS_KEY] is Array):
		return Result.failure("%s: state.map.%s 类型错误（期望 Array）" % [MODULE_ID, GLOBAL_EFFECT_IDS_KEY])
	var ids: Array = state.map[GLOBAL_EFFECT_IDS_KEY]
	if ids.find(EFFECT_ID_ROADWORKS_DISTANCE) == -1:
		ids.append(EFFECT_ID_ROADWORKS_DISTANCE)
	if ids.find(EFFECT_ID_PARK_BONUS) == -1:
		ids.append(EFFECT_ID_PARK_BONUS)
	state.map[GLOBAL_EFFECT_IDS_KEY] = ids

	# 每回合 pending（同回合内可能被多个玩家获取里程碑；离开子阶段前必须消化）
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has(EXTRA_TILE_PENDING_KEY):
		var pending := {}
		for i in range(state.players.size()):
			pending[i] = false
		state.round_state[EXTRA_TILE_PENDING_KEY] = pending

	return Result.success()

func _on_cleanup_enter_extension(state: GameState, _phase_manager) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("%s: Cleanup 扩展失败：state.map 类型错误" % MODULE_ID)

	# 1) 移除 roadworks markers
	if state.map.has(ROADWORK_MARKERS_KEY):
		state.map[ROADWORK_MARKERS_KEY] = {}

	# 2) 将“建设中道路”写入 road_segments，并清空 pending
	if not state.map.has(PENDING_ROADS_KEY):
		return Result.success()
	var pending_val = state.map.get(PENDING_ROADS_KEY, null)
	if pending_val == null:
		return Result.success()
	if not (pending_val is Array):
		return Result.failure("%s: state.map.%s 类型错误（期望 Array）" % [MODULE_ID, PENDING_ROADS_KEY])
	var pending_roads: Array = pending_val
	if pending_roads.is_empty():
		return Result.success()

	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("%s: state.map.cells 缺失或类型错误（期望 Array）" % MODULE_ID)
	var cells: Array = state.map["cells"]

	for i in range(pending_roads.size()):
		var e_val = pending_roads[i]
		if not (e_val is Dictionary):
			return Result.failure("%s: pending_roads[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, i])
		var e: Dictionary = e_val
		var segments_val = e.get("segments_by_pos", null)
		if not (segments_val is Dictionary):
			return Result.failure("%s: pending_roads[%d].segments_by_pos 类型错误（期望 Dictionary）" % [MODULE_ID, i])
		var segments_by_pos: Dictionary = segments_val
		for k in segments_by_pos.keys():
			if not (k is String):
				return Result.failure("%s: segments_by_pos key 类型错误（期望 String）" % MODULE_ID)
			var parts := str(k).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				return Result.failure("%s: segments_by_pos key 格式错误: %s" % [MODULE_ID, str(k)])
			var wx := int(parts[0])
			var wy := int(parts[1])
			var world_pos := Vector2i(wx, wy)
			var idx := MapRuntimeClass.world_to_index(state, world_pos)
			if idx.x < 0 or idx.y < 0 or idx.y >= cells.size():
				return Result.failure("%s: segments_by_pos 越界: %s" % [MODULE_ID, str(world_pos)])
			var row_val = cells[idx.y]
			if not (row_val is Array) or idx.x >= (row_val as Array).size():
				return Result.failure("%s: segments_by_pos 越界: %s" % [MODULE_ID, str(world_pos)])
			var row: Array = row_val
			var cell_val = row[idx.x]
			if not (cell_val is Dictionary):
				return Result.failure("%s: cells[%d][%d] 类型错误（期望 Dictionary）" % [MODULE_ID, idx.y, idx.x])
			var cell: Dictionary = cell_val
			if not cell.has("road_segments") or not (cell["road_segments"] is Array):
				return Result.failure("%s: cell.road_segments 缺失或类型错误（期望 Array）: %s" % [MODULE_ID, str(world_pos)])
			var segs: Array = cell["road_segments"]
			var add_val = segments_by_pos[k]
			if not (add_val is Array):
				return Result.failure("%s: segments_by_pos[%s] 类型错误（期望 Array）" % [MODULE_ID, str(k)])
			segs.append_array(add_val)
			cell["road_segments"] = segs
			row[idx.x] = cell
			cells[idx.y] = row

	state.map["cells"] = cells
	state.map[PENDING_ROADS_KEY] = []
	MapRuntimeClass.invalidate_road_graph(state)
	return Result.success()

func _on_lobbyists_before_exit(state: GameState) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("%s: round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has(EXTRA_TILE_PENDING_KEY):
		return Result.success()
	var pending_val = state.round_state.get(EXTRA_TILE_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("%s: round_state.%s 类型错误（期望 Dictionary）" % [MODULE_ID, EXTRA_TILE_PENDING_KEY])
	var pending: Dictionary = pending_val
	for pid_val in pending.keys():
		var pid: int = int(pid_val)
		var v = pending.get(pid, false)
		if not (v is bool):
			return Result.failure("%s: round_state.%s[%d] 类型错误（期望 bool）" % [MODULE_ID, EXTRA_TILE_PENDING_KEY, pid])
		if bool(v):
			return Result.failure("存在未处理的“额外地图板块”放置（必须先放置或放弃）: player=%d" % pid)
	return Result.success()

func _milestone_effect_grant_extra_map_tile(state: GameState, player_id: int, _milestone_id: String, _eff: Dictionary) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("%s: milestone_effect: state.round_state 类型错误" % MODULE_ID)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("%s: milestone_effect: player_id 越界: %d" % [MODULE_ID, player_id])
	if not (state.map is Dictionary):
		return Result.failure("%s: milestone_effect: state.map 类型错误" % MODULE_ID)
	if state.map.has("tile_supply_remaining") and (state.map["tile_supply_remaining"] is Array):
		var arr: Array = state.map["tile_supply_remaining"]
		if arr.is_empty():
			return Result.success()
	if not state.round_state.has(EXTRA_TILE_PENDING_KEY) or not (state.round_state[EXTRA_TILE_PENDING_KEY] is Dictionary):
		return Result.failure("%s: milestone_effect: 缺少 round_state.%s（模块未正确初始化）" % [MODULE_ID, EXTRA_TILE_PENDING_KEY])
	var pending: Dictionary = state.round_state[EXTRA_TILE_PENDING_KEY]
	pending[player_id] = true
	state.round_state[EXTRA_TILE_PENDING_KEY] = pending
	return Result.success()

func _effect_dinnertime_distance_delta_roadworks(state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("%s: roadworks: state.map 类型错误" % MODULE_ID)
	if not ctx.has("distance") or not (ctx["distance"] is int):
		return Result.failure("%s: roadworks: ctx.distance 缺失或类型错误（期望 int）" % MODULE_ID)
	if not ctx.has("path") or not (ctx["path"] is Array):
		return Result.failure("%s: roadworks: ctx.path 缺失或类型错误（期望 Array）" % MODULE_ID)

	if not state.map.has(ROADWORK_MARKERS_KEY):
		return Result.success()
	var markers_val = state.map.get(ROADWORK_MARKERS_KEY, null)
	if not (markers_val is Dictionary):
		return Result.failure("%s: state.map.%s 类型错误（期望 Dictionary）" % [MODULE_ID, ROADWORK_MARKERS_KEY])
	var markers: Dictionary = markers_val
	if markers.is_empty():
		return Result.success()

	var path_any: Array = ctx["path"]
	var penalty := 0
	for i in range(1, path_any.size()):
		var p = path_any[i]
		if not (p is Vector2i):
			return Result.failure("%s: roadworks: ctx.path[%d] 类型错误（期望 Vector2i）" % [MODULE_ID, i])
		var key := "%d,%d" % [p.x, p.y]
		if markers.has(key):
			penalty += 1

	if penalty > 0:
		ctx["distance"] = int(ctx["distance"]) + penalty
	return Result.success()

func _effect_dinnertime_sale_house_bonus_park(state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("%s: park: state.map 类型错误" % MODULE_ID)
	if not ctx.has("bonus") or not (ctx["bonus"] is int):
		return Result.failure("%s: park: ctx.bonus 缺失或类型错误（期望 int）" % MODULE_ID)
	if not ctx.has("unit_price") or not (ctx["unit_price"] is int):
		return Result.failure("%s: park: ctx.unit_price 缺失或类型错误（期望 int）" % MODULE_ID)
	if not ctx.has("quantity") or not (ctx["quantity"] is int):
		return Result.failure("%s: park: ctx.quantity 缺失或类型错误（期望 int）" % MODULE_ID)
	if not ctx.has("house_id") or not (ctx["house_id"] is String) or str(ctx["house_id"]).is_empty():
		return Result.failure("%s: park: ctx.house_id 缺失或类型错误（期望 String）" % MODULE_ID)

	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return Result.failure("%s: park: state.map.houses 缺失或类型错误（期望 Dictionary）" % MODULE_ID)
	var houses: Dictionary = houses_val
	var house_id: String = str(ctx["house_id"])
	if not houses.has(house_id) or not (houses[house_id] is Dictionary):
		return Result.failure("%s: park: 未知房屋: %s" % [MODULE_ID, house_id])
	var house: Dictionary = houses[house_id]
	if not house.has("cells") or not (house["cells"] is Array):
		return Result.failure("%s: park: houses[%s].cells 缺失或类型错误（期望 Array）" % [MODULE_ID, house_id])

	var has_adjacent_park := _house_has_adjacent_park(state, house["cells"])
	if not has_adjacent_park.ok:
		return has_adjacent_park
	if not bool(has_adjacent_park.value):
		return Result.success()

	var unit_price: int = int(ctx["unit_price"])
	var qty: int = int(ctx["quantity"])
	if unit_price <= 0 or qty <= 0:
		return Result.success()

	ctx["bonus"] = int(ctx["bonus"]) + unit_price * qty
	return Result.success()

func _house_has_adjacent_park(state: GameState, cells_any: Array) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("%s: park_adj: state.map 类型错误" % MODULE_ID)
	if not (cells_any is Array):
		return Result.failure("%s: park_adj: cells 类型错误（期望 Array）" % MODULE_ID)
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("%s: park_adj: state.map.cells 缺失或类型错误（期望 Array）" % MODULE_ID)
	var grid_cells: Array = state.map["cells"]

	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("%s: park_adj: house.cells[%d] 类型错误（期望 Vector2i）" % [MODULE_ID, i])
		var pos: Vector2i = c
		for dir in ["N", "E", "S", "W"]:
			var npos: Vector2i = pos
			match dir:
				"N":
					npos = pos + Vector2i(0, -1)
				"E":
					npos = pos + Vector2i(1, 0)
				"S":
					npos = pos + Vector2i(0, 1)
				"W":
					npos = pos + Vector2i(-1, 0)
			if not MapRuntimeClass.is_world_pos_in_grid(state, npos):
				continue

			var idx: Vector2i = MapRuntimeClass.world_to_index(state, npos)
			var row_val = grid_cells[idx.y]
			if not (row_val is Array):
				continue
			var row: Array = row_val
			var cell_val = row[idx.x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var s_val = cell.get("structure", null)
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			if str(s.get("piece_id", "")) == "park":
				return Result.success(true)

	return Result.success(false)
