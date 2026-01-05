class_name PlaceLobbyistsRoadAction
extends ActionExecutor

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

const MODULE_ID := "lobbyists"

const ROAD_SUPPLY_KEY := "lobbyists_road_supply_remaining"
const PENDING_ROADS_KEY := "lobbyists_pending_roads"
const ROADWORK_MARKERS_KEY := "lobbyists_roadworks_markers"

const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"

const ROAD_PIECES: Array[String] = ["lobbyists_road_straight", "lobbyists_road_l"]

const ROAD_OVERLAYS := {
	"lobbyists_road_straight": {
		"segments": [
			{"offset": Vector2i(0, 0), "dirs": ["E", "W"]},
			{"offset": Vector2i(1, 0), "dirs": ["E", "W"]},
		],
		"arrows": [
			{"offset": Vector2i(0, 0), "dir": "W"},
			{"offset": Vector2i(1, 0), "dir": "E"},
		],
	},
	"lobbyists_road_l": {
		"segments": [
			{"offset": Vector2i(0, 0), "dirs": ["N", "S"]},
			{"offset": Vector2i(0, 1), "dirs": ["N", "E"]},
			{"offset": Vector2i(1, 1), "dirs": ["W", "E"]},
		],
		"arrows": [
			{"offset": Vector2i(0, 0), "dir": "N"},
			{"offset": Vector2i(1, 1), "dir": "E"},
		],
	},
}

func _init() -> void:
	action_id = "place_lobbyists_road"
	display_name = "说客：放置道路（建设中）"
	description = "放置一块建设中的道路，并在相邻道路上放置 roadworks 标记"
	requires_actor = true
	is_mandatory = false
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
	if not state.map.has(ROAD_SUPPLY_KEY) or not (state.map[ROAD_SUPPLY_KEY] is int):
		return Result.failure("缺少道路供应计数（模块未初始化）")
	if int(state.map[ROAD_SUPPLY_KEY]) <= 0:
		return Result.failure("道路已用尽")

	var piece_id_read := require_string_param(command, "piece_id")
	if not piece_id_read.ok:
		return piece_id_read
	var piece_id: String = piece_id_read.value
	if not ROAD_PIECES.has(piece_id):
		return Result.failure("未知道路 piece_id: %s" % piece_id)

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

	var map_ctx := _build_map_context(state)
	var piece_registry := PieceRegistryClass.get_all_defs()

	var validate := PlacementValidatorClass.validate_placement(map_ctx, piece_id, anchor_pos, rotation, piece_registry, {})
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
		return Result.failure("道路必须至少有一个箭头指向已有道路或你的餐厅入口")

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
		if not MapRuntimeClass.is_world_pos_in_grid(state, world_to):
			continue
		var cell_to: Dictionary = MapRuntimeClass.get_cell(state, world_to)
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
		var idx := MapRuntimeClass.world_to_index(state, pos)
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": piece_id,
			"owner": player_id,
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
	state.map[ROAD_SUPPLY_KEY] = int(state.map[ROAD_SUPPLY_KEY]) - 1

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

func _build_map_context(state: GameState) -> Dictionary:
	return {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": MapRuntimeClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants
	}

func _is_adjacent_to_reachable_road(state: GameState, actor: int, piece_cells: Array[Vector2i], max_range: int) -> Result:
	if max_range < 0:
		return Result.failure("max_range 必须 >= 0")
	var road_graph = MapRuntimeClass.get_road_graph(state)
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
		var adj := _get_adjacent_road_cells(state, entrance_pos)
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
			if not MapRuntimeClass.is_world_pos_in_grid(state, npos):
				continue
			var cell: Dictionary = MapRuntimeClass.get_cell(state, npos)
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
		if not MapRuntimeClass.is_world_pos_in_grid(state, npos):
			continue
		var cell: Dictionary = MapRuntimeClass.get_cell(state, npos)
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
		if not MapRuntimeClass.is_world_pos_in_grid(state, world_to):
			continue

		var cell: Dictionary = MapRuntimeClass.get_cell(state, world_to)
		var segs: Array = cell.get("road_segments", [])
		if segs is Array and not segs.is_empty():
			has_connection = true
			break

		# 或指向自己的餐厅入口格
		var s_val = cell.get("structure", null)
		if s_val is Dictionary:
			var s: Dictionary = s_val
			if str(s.get("piece_id", "")) == "restaurant" and bool(s.get("anchor_cell", false)):
				if int(s.get("owner", -999)) == actor:
					has_connection = true
					break

	return Result.success(has_connection)
