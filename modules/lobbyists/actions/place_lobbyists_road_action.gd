class_name PlaceLobbyistsRoadAction
extends ActionExecutor

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const LobbyistsRoadOverlaysClass = preload("res://modules/lobbyists/road_overlays.gd")

const MODULE_ID := LobbyistsRoadOverlaysClass.MODULE_ID

const PENDING_ROADS_KEY := LobbyistsRoadOverlaysClass.PENDING_ROADS_KEY
const ROADWORK_MARKERS_KEY := LobbyistsRoadOverlaysClass.ROADWORK_MARKERS_KEY

const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"
const EXTRA_TILE_LAST_PLACED_KEY := "lobbyists_extra_tile_last_placed"

const ROAD_PIECES: Array[String] = LobbyistsRoadOverlaysClass.ROAD_PIECES
const ROAD_OVERLAYS := LobbyistsRoadOverlaysClass.ROAD_OVERLAYS

func _init() -> void:
	action_id = "place_lobbyists_road"
	display_name = "说客：放置道路（建设中）"
	description = "放置一块建设中的道路，并在相邻道路上放置 roadworks 标记"
	requires_actor = true
	is_mandatory = false
	ui_piece_ids = ROAD_PIECES.duplicate()
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Lobbyists"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 里程碑奖励“扩边”必须当场处理（使用/放弃）。未处理前不允许继续放 road/park。
	if state.round_state is Dictionary:
		var pending_val = state.round_state.get(EXTRA_TILE_PENDING_KEY, null)
		if pending_val is Dictionary:
			var pending: Dictionary = pending_val
			var flag = pending.get(command.actor, null)
			if flag == null and pending.has(str(command.actor)):
				flag = pending.get(str(command.actor), null)
			if bool(flag):
				return Result.failure("请先处理里程碑奖励：扩边放置地图板块（使用/放弃）")

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
	if not ROAD_PIECES.has(piece_id):
		return Result.failure("未知道路 piece_id: %s" % piece_id)

	var supply_key := "%s_supply_remaining" % piece_id
	if not state.map.has(supply_key) or not (state.map[supply_key] is int):
		return Result.failure("缺少道路供应计数（模块未初始化）: %s" % supply_key)
	if int(state.map[supply_key]) <= 0:
		return Result.failure("道路已用尽: %s" % piece_id)

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
	var piece_def_val = PieceRegistryClass.get_def(piece_id)
	if piece_def_val == null:
		return Result.failure("未加载的 piece: %s" % piece_id)
	var piece_def: PieceDef = piece_def_val
	if not piece_def.is_rotation_allowed(rotation):
		return Result.failure("该 piece 不支持 rotation=%d" % rotation)

	var map_ctx_read := _build_map_context(state)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := PieceRegistryClass.get_all_defs()

	var validate := PlacementClass.validate_placement(map_ctx, piece_id, anchor_pos, rotation, piece_registry, {})
	if not validate.ok:
		return validate
	assert(validate.value is Dictionary, "place_lobbyists_road: validate_placement 返回值类型错误（期望 Dictionary）")
	var v: Dictionary = validate.value
	assert(v.has("footprint_cells") and (v["footprint_cells"] is Array), "place_lobbyists_road: validate_placement 缺少 footprint_cells")
	var cells_any: Array = v["footprint_cells"]
	var piece_cells: Array[Vector2i] = []
	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("place_lobbyists_road: cells[%d] 类型错误（期望 Vector2i）" % i)
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

	var overlay = ROAD_OVERLAYS.get(piece_id, null)
	if not (overlay is Dictionary):
		return Result.failure("内部错误：缺少 road overlay: %s" % piece_id)
	var arrows_val = overlay.get("arrows", null)
	if not (arrows_val is Array):
		return Result.failure("内部错误：overlay.arrows 类型错误（期望 Array）")
	var arrows: Array = arrows_val

	var arrow_check := _validate_arrows_have_connection(state, command.actor, anchor_pos, rotation, arrows)
	if not arrow_check.ok:
		return arrow_check
	if not bool(arrow_check.value):
		return Result.failure("道路必须至少有一个箭头指向已有道路")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor

	var piece_id: String = require_string_param(command, "piece_id").value
	var anchor_pos: Vector2i = require_vector2i_param(command, "anchor_pos").value
	var rotation: int = int(optional_int_param(command, "rotation", 0).value)

	var piece_def: PieceDef = PieceRegistryClass.get_def(piece_id)
	var piece_cells: Array[Vector2i] = piece_def.get_world_cells(anchor_pos, rotation)

	var overlay: Dictionary = ROAD_OVERLAYS[piece_id]
	var seg_entries: Array = overlay["segments"]
	var arrows: Array = overlay["arrows"]

	# roadworks markers：对每个箭头指向的“已有道路格”放置 marker
	if not state.map.has(ROADWORK_MARKERS_KEY) or not (state.map[ROADWORK_MARKERS_KEY] is Dictionary):
		state.map[ROADWORK_MARKERS_KEY] = {}
	var markers: Dictionary = state.map[ROADWORK_MARKERS_KEY]
	var placed_markers: Array[Vector2i] = []
	for a_i in range(arrows.size()):
		var a: Dictionary = arrows[a_i]
		var offset: Vector2i = a["offset"]
		var dir: String = str(a["dir"])
		var world_from := anchor_pos + MapUtilsClass.rotate_offset(offset, rotation)
		var world_to: Vector2i = world_from + MapUtilsClass.DIR_OFFSETS[MapUtilsClass.rotate_dir(dir, rotation)]
		if not CoordsClass.is_world_pos_in_grid(state, world_to):
			continue
		var cell_to: Dictionary = CellsClass.get_cell(state, world_to)
		var segs: Array = cell_to.get("road_segments", [])
		if not (segs is Array):
			continue
		if segs.is_empty():
			continue
		var key := "%d,%d" % [world_to.x, world_to.y]
		markers[key] = true
		placed_markers.append(world_to)
	state.map[ROADWORK_MARKERS_KEY] = markers

	# 写入“建设中道路”：占用 structure + pending segments（Cleanup 时生效）
	var segments_by_pos: Dictionary = {}
	for i in range(seg_entries.size()):
		var e: Dictionary = seg_entries[i]
		var off: Vector2i = e["offset"]
		var world_pos := anchor_pos + MapUtilsClass.rotate_offset(off, rotation)
		var dirs: Array = MapUtilsClass.rotate_dirs(e["dirs"], rotation)
		segments_by_pos["%d,%d" % [world_pos.x, world_pos.y]] = [{"dirs": dirs, "bridge": false}]

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

	if not state.map.has(PENDING_ROADS_KEY) or not (state.map[PENDING_ROADS_KEY] is Array):
		state.map[PENDING_ROADS_KEY] = []
	var pending_roads: Array = state.map[PENDING_ROADS_KEY]
	pending_roads.append({
		"owner": player_id,
		"piece_id": piece_id,
		"anchor_pos": anchor_pos,
		"rotation": rotation,
		"cells": piece_cells,
		"segments_by_pos": segments_by_pos,
	})
	state.map[PENDING_ROADS_KEY] = pending_roads

	# 消耗供应
	var supply_key := "%s_supply_remaining" % piece_id
	if not state.map.has(supply_key) or not (state.map[supply_key] is int):
		return Result.failure("缺少道路供应计数（模块未初始化）: %s" % supply_key)
	state.map[supply_key] = int(state.map[supply_key]) - 1

	# 计数：本子阶段使用次数（road/park 共用）
	var inc := RoundStateCountersClass.increment_player_count(state.round_state, "lobbyists_place_counts", player_id, 1)
	if not inc.ok:
		return inc

	# 触发里程碑：UseEmployee (lobbyist) —— 每次放置都触发一次（你已要求）
	var ms := MilestoneSystemClass.process_event(state, "UseEmployee", {
		"player_id": player_id,
		"employee_id": "lobbyist",
	})
	var result := Result.success({
		"player_id": player_id,
		"piece_id": piece_id,
		"anchor_pos": anchor_pos,
		"rotation": rotation,
		"markers": placed_markers,
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(UseEmployee/lobbyist): %s" % ms.error)
	return result

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var piece_id: String = require_string_param(command, "piece_id").value
	var anchor_pos: Vector2i = require_vector2i_param(command, "anchor_pos").value
	var rotation: int = int(optional_int_param(command, "rotation", 0).value)
	return [{
		"type": EventBus.EventType.STATE_CHANGED,
		"data": {
			"module": MODULE_ID,
			"action": "place_road",
			"player_id": command.actor,
			"piece_id": piece_id,
			"anchor_pos": [anchor_pos.x, anchor_pos.y],
			"rotation": rotation,
		}
	}]

func _build_map_context(state: GameState) -> Result:
	var houses_read := MapStateAccessClass.require_houses(state, "place_lobbyists_road")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	var restaurants_read := MapStateAccessClass.require_restaurants(state, "place_lobbyists_road")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value
	var placements_read := MapStateAccessClass.require_marketing_placements(state, "place_lobbyists_road")
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value

	return Result.success({
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": CoordsClass.get_map_origin(state),
		"houses": houses,
		"restaurants": restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": placements,
	})

func _is_adjacent_to_reachable_road(state: GameState, actor: int, piece_cells: Array[Vector2i], max_range: int) -> Result:
	if max_range < 0:
		return Result.failure("max_range 必须 >= 0")
	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")
	var restaurants_read := MapStateAccessClass.require_restaurants(state, "place_lobbyists_road")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	var start_roads: Array[Vector2i] = []
	for rest_id in restaurants.keys():
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if not (rest.get("owner", null) is int) or int(rest["owner"]) != actor:
			continue
		var rid := str(rest_id).strip_edges()
		var points_read := StructuresClass.get_restaurant_entrance_points(state, rid, rest)
		if not points_read.ok:
			return Result.failure("lobbyists: %s" % points_read.error)
		var points: Array[Vector2i] = points_read.value
		for ep in points:
			var adj := _get_adjacent_road_cells(state, ep)
			if not adj.ok:
				return adj
			for p in adj.value:
				if not start_roads.has(p):
					start_roads.append(p)
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

func _get_adjacent_road_cells(state: GameState, pos: Vector2i) -> Result:
	var out: Array[Vector2i] = []
	for dir in MapUtilsClass.DIRECTIONS:
		var npos := MapUtilsClass.get_neighbor_pos(pos, dir)
		if not CoordsClass.is_world_pos_in_grid(state, npos):
			continue
		var cell: Dictionary = CellsClass.get_cell(state, npos)
		var segs: Array = cell.get("road_segments", [])
		if segs is Array and not segs.is_empty():
			out.append(npos)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return Result.success(out)

func _validate_arrows_have_connection(
	state: GameState,
	actor: int,
	anchor_pos: Vector2i,
	rotation: int,
	arrows: Array
) -> Result:
	var has_connection := false
	for i in range(arrows.size()):
		var a_val = arrows[i]
		if not (a_val is Dictionary):
			return Result.failure("overlay.arrows[%d] 类型错误（期望 Dictionary）" % i)
		var a: Dictionary = a_val
		if not (a.get("offset", null) is Vector2i):
			return Result.failure("overlay.arrows[%d].offset 类型错误（期望 Vector2i）" % i)
		var offset: Vector2i = a["offset"]
		if not (a.get("dir", null) is String):
			return Result.failure("overlay.arrows[%d].dir 类型错误（期望 String）" % i)
		var dir: String = str(a["dir"])
		if not MapUtilsClass.DIR_OFFSETS.has(dir):
			return Result.failure("overlay.arrows[%d].dir 无效: %s" % [i, dir])

		var world_from := anchor_pos + MapUtilsClass.rotate_offset(offset, rotation)
		var world_to: Vector2i = world_from + MapUtilsClass.DIR_OFFSETS[MapUtilsClass.rotate_dir(dir, rotation)]
		if not CoordsClass.is_world_pos_in_grid(state, world_to):
			continue

		var cell: Dictionary = CellsClass.get_cell(state, world_to)
		var segs: Array = cell.get("road_segments", [])
		if segs is Array and not segs.is_empty():
			has_connection = true
			break

	return Result.success(has_connection)

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
