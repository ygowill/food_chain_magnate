class_name PlaceLobbyistsParkAction
extends ActionExecutor

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

const MODULE_ID := "lobbyists"

const PARK_PIECES: Array[String] = ["lobbyists_park_line", "lobbyists_park_t", "lobbyists_park_l"]
const EXTRA_TILE_LAST_PLACED_KEY := "lobbyists_extra_tile_last_placed"

func _init() -> void:
	action_id = "place_lobbyists_park"
	display_name = "说客：放置公园"
	description = "放置一个公园（影响晚餐单价）"
	requires_actor = true
	is_mandatory = false
	ui_piece_ids = PARK_PIECES.duplicate()
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Lobbyists"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var player := state.get_player(command.actor)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:lobbyists")
	if capacity <= 0:
		return Result.failure("需要在岗的说客才能放置道路/公园")

	var used_read := RoundStateCountersClass.get_player_count(state.round_state, "lobbyists_place_counts", command.actor)
	if not used_read.ok:
		return used_read
	var used := int(used_read.value)
	if used >= capacity:
		return Result.failure("本子阶段可用说客次数已用完: %d/%d" % [used, capacity])

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	var piece_id_read := require_string_param(command, "piece_id")
	if not piece_id_read.ok:
		return piece_id_read
	var piece_id: String = piece_id_read.value
	if not PARK_PIECES.has(piece_id):
		return Result.failure("未知的公园 piece_id: %s" % piece_id)

	var supply_key := "%s_supply_remaining" % piece_id
	if not state.map.has(supply_key) or not (state.map[supply_key] is int):
		return Result.failure("缺少公园供应计数（模块未初始化）: %s" % supply_key)
	if int(state.map[supply_key]) <= 0:
		return Result.failure("公园已用尽: %s" % piece_id)

	var pos_read := require_vector2i_param(command, "anchor_pos")
	if not pos_read.ok:
		return pos_read
	var anchor_pos: Vector2i = pos_read.value

	var rotation_read := optional_int_param(command, "rotation", 0)
	if not rotation_read.ok:
		return rotation_read
	var rotation: int = int(rotation_read.value)
	if rotation != 0 and rotation != 90 and rotation != 180 and rotation != 270:
		return Result.failure("rotation 非法: %d" % rotation)

	if not PieceRegistryClass.is_loaded():
		return Result.failure("PieceRegistry 未初始化")
	if PieceRegistryClass.get_def(piece_id) == null:
		return Result.failure("未加载的 piece: %s" % piece_id)

	var map_ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": CoordsClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}
	var piece_registry := PieceRegistryClass.get_all_defs()
	var validate := PlacementClass.validate_placement(map_ctx, piece_id, anchor_pos, rotation, piece_registry, {})
	if not validate.ok:
		return validate
	assert(validate.value is Dictionary, "place_lobbyists_park: validate_placement 返回值类型错误（期望 Dictionary）")
	var v: Dictionary = validate.value
	assert(v.has("footprint_cells") and (v["footprint_cells"] is Array), "place_lobbyists_park: validate_placement 缺少 footprint_cells")
	var cells_any: Array = v["footprint_cells"]
	var piece_cells: Array[Vector2i] = []
	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("place_lobbyists_park: cells[%d] 类型错误（期望 Vector2i）" % i)
		piece_cells.append(c)

	var is_on_extra_tile := _is_placement_on_last_extra_tile(state, command.actor, piece_cells)
	if not is_on_extra_tile.ok:
		return is_on_extra_tile
	if not bool(is_on_extra_tile.value):
		var reachable := _is_adjacent_to_reachable_road(state, command.actor, piece_cells, 2)
		if not reachable.ok:
			return reachable
		if not bool(reachable.value):
			return Result.failure("必须放置在可达道路旁（range=2 by road）")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var piece_id: String = require_string_param(command, "piece_id").value
	var anchor_pos: Vector2i = require_vector2i_param(command, "anchor_pos").value
	var rotation: int = int(optional_int_param(command, "rotation", 0).value)

	var piece_def: PieceDef = PieceRegistryClass.get_def(piece_id)
	var piece_cells: Array[Vector2i] = piece_def.get_world_cells(anchor_pos, rotation)

	for pos in piece_cells:
		var idx := CoordsClass.world_to_index(state, pos)
		var is_anchor := pos == anchor_pos
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": piece_id,
			"owner": player_id,
			"anchor_cell": is_anchor,
			"parent_anchor": anchor_pos,
			"rotation": rotation,
			"dynamic": true,
		}

	var supply_key := "%s_supply_remaining" % piece_id
	if not state.map.has(supply_key) or not (state.map[supply_key] is int):
		return Result.failure("缺少公园供应计数（模块未初始化）: %s" % supply_key)
	state.map[supply_key] = int(state.map[supply_key]) - 1

	var inc := RoundStateCountersClass.increment_player_count(state.round_state, "lobbyists_place_counts", player_id, 1)
	if not inc.ok:
		return inc

	var ms := MilestoneSystemClass.process_event(state, "UseEmployee", {
		"player_id": player_id,
		"employee_id": "lobbyist",
	})
	var result := Result.success({
		"player_id": player_id,
		"piece_id": piece_id,
		"anchor_pos": anchor_pos,
		"rotation": rotation,
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(UseEmployee/lobbyist): %s" % ms.error)
	return result

func _is_adjacent_to_reachable_road(state: GameState, actor: int, piece_cells: Array[Vector2i], max_range: int) -> Result:
	if max_range < 0:
		return Result.failure("max_range 必须 >= 0")
	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")
	if not (state.map is Dictionary) or not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = state.map["restaurants"]

	var start_roads: Array[Vector2i] = []
	for rest_id in restaurants.keys():
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if not (rest.get("owner", null) is int) or int(rest["owner"]) != actor:
			continue
		if not (rest.get("entrance_pos", null) is Vector2i):
			continue
		var entrance_pos: Vector2i = rest["entrance_pos"]
		for dir in MapUtilsClass.DIRECTIONS:
			var npos := MapUtilsClass.get_neighbor_pos(entrance_pos, dir)
			if not CoordsClass.is_world_pos_in_grid(state, npos):
				continue
			var cell: Dictionary = CellsClass.get_cell(state, npos)
			var segs: Array = cell.get("road_segments", [])
			if segs is Array and not segs.is_empty():
				if not start_roads.has(npos):
					start_roads.append(npos)
	if start_roads.is_empty():
		return Result.success(false)

	var targets: Array[Vector2i] = []
	for pos in piece_cells:
		for dir in MapUtilsClass.DIRECTIONS:
			var npos := MapUtilsClass.get_neighbor_pos(pos, dir)
			if not CoordsClass.is_world_pos_in_grid(state, npos):
				continue
			var cell: Dictionary = CellsClass.get_cell(state, npos)
			var segs: Array = cell.get("road_segments", [])
			if segs is Array and not segs.is_empty():
				if not targets.has(npos):
					targets.append(npos)
	if targets.is_empty():
		return Result.success(false)

	for s in start_roads:
		for t in targets:
			var d: int = int(road_graph.get_distance(s, t))
			if d >= 0 and d <= max_range:
				return Result.success(true)
	return Result.success(false)

func _is_placement_on_last_extra_tile(state: GameState, actor: int, piece_cells: Array[Vector2i]) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	var last_val = state.round_state.get(EXTRA_TILE_LAST_PLACED_KEY, null)
	if last_val == null:
		return Result.success(false)
	if not (last_val is Array):
		return Result.failure("round_state.%s 类型错误（期望 Array）" % EXTRA_TILE_LAST_PLACED_KEY)
	var last: Array = last_val
	if actor < 0 or actor >= last.size():
		return Result.success(false)
	var bp_val = last[actor]
	if bp_val == null:
		return Result.success(false)
	var bp_read := _parse_vec2i_array(bp_val, "round_state.%s[%d]" % [EXTRA_TILE_LAST_PLACED_KEY, actor])
	if not bp_read.ok:
		return bp_read
	var bp: Vector2i = bp_read.value

	for cell in piece_cells:
		var info: Dictionary = MapUtilsClass.world_to_tile(cell)
		var board_pos_val = info.get("board_pos", null)
		if not (board_pos_val is Vector2i) or Vector2i(board_pos_val) != bp:
			return Result.success(false)

	return Result.success(true)

func _parse_vec2i_array(v, path: String) -> Result:
	if v is Vector2i:
		return Result.success(Vector2i(v))
	if v is Array:
		var arr: Array = v
		if arr.size() != 2:
			return Result.failure("%s 长度错误（期望 2），实际: %d" % [path, arr.size()])
		var x_val = arr[0]
		var y_val = arr[1]
		if not (x_val is int or x_val is float) or not (y_val is int or y_val is float):
			return Result.failure("%s 类型错误（期望 [int,int]）" % path)
		var x := int(x_val)
		var y := int(y_val)
		if float(x_val) != float(x) or float(y_val) != float(y):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(v)])
		return Result.success(Vector2i(x, y))
	return Result.failure("%s 类型错误（期望 Vector2i 或 [x,y]）" % path)
