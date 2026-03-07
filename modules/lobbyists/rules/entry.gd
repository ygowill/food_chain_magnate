extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const GlobalEffectListClass = preload("res://core/rules/global_effect_list.gd")
const RoundStatePlayerBoolFlagsClass = preload("res://core/utils/round_state_player_bool_flags.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const LobbyistsRoadOverlaysClass = preload("res://modules/lobbyists/road_overlays.gd")

const PlaceLobbyistsRoadActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_road_action.gd")
const PlaceLobbyistsParkActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_park_action.gd")
const PlaceLobbyistsExtraMapTileActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_extra_map_tile_action.gd")
const SkipLobbyistsExtraMapTileActionClass = preload("res://modules/lobbyists/actions/skip_lobbyists_extra_map_tile_action.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const MODULE_ID := LobbyistsRoadOverlaysClass.MODULE_ID
const MAP_OVERLAY_PROVIDER_ID := "%s:map_overlays" % MODULE_ID

const ROAD_SUPPLY_BY_PIECE_ID := {
	"lobbyists_road_straight": 4,
	"lobbyists_road_long": 2,
	"lobbyists_road_l": 2,
}

const PARK_SUPPLY_BY_PIECE_ID := {
	"lobbyists_park_line": 1,
	"lobbyists_park_t": 1,
	"lobbyists_park_l": 2,
}
const PENDING_ROADS_KEY := LobbyistsRoadOverlaysClass.PENDING_ROADS_KEY
const ROADWORK_MARKERS_KEY := LobbyistsRoadOverlaysClass.ROADWORK_MARKERS_KEY
const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"
const EXTRA_TILE_LAST_PLACED_KEY := "lobbyists_extra_tile_last_placed"

const EFFECT_ID_ROADWORKS_DISTANCE := "%s:dinnertime:distance_delta:roadworks" % MODULE_ID
const EFFECT_ID_PARK_BONUS := "%s:dinnertime:sale_house_bonus:park" % MODULE_ID

const STATE_SCHEMA_ID_EXTRA_TILE_PENDING := "lobbyists:round_state_int_keys:lobbyists_extra_tile_pending"

func register(registrar) -> Result:
	var steps: Array[Callable] = [
		Callable(registrar, "register_working_sub_phase_insertion").bind("Lobbyists", "PlaceHouses", "PlaceRestaurants", 100),
		Callable(registrar, "register_working_sub_phase_hook").bind("Lobbyists", HookType.BEFORE_EXIT, Callable(self, "_on_lobbyists_before_exit"), 0),
		Callable(registrar, "register_phase_hook").bind(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"), 0),
		Callable(registrar, "register_extension_settlement").bind(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_cleanup_enter_extension"), 100),
		Callable(registrar, "register_effect").bind(EFFECT_ID_ROADWORKS_DISTANCE, Callable(self, "_effect_dinnertime_distance_delta_roadworks")),
		Callable(registrar, "register_effect").bind(EFFECT_ID_PARK_BONUS, Callable(self, "_effect_dinnertime_sale_house_bonus_park")),
		Callable(registrar, "register_milestone_effect").bind("lobbyists_grant_extra_map_tile", Callable(self, "_milestone_effect_grant_extra_map_tile")),
		Callable(registrar, "register_milestone_effect_ui_text").bind("lobbyists_grant_extra_map_tile", "获得一次额外地图板块放置机会（需本回合处理）", 100),
		Callable(registrar, "register_action_executor").bind(PlaceLobbyistsRoadActionClass.new()),
		Callable(registrar, "register_action_executor").bind(PlaceLobbyistsParkActionClass.new()),
		Callable(registrar, "register_action_executor").bind(PlaceLobbyistsExtraMapTileActionClass.new()),
		Callable(registrar, "register_action_executor").bind(SkipLobbyistsExtraMapTileActionClass.new()),
		# round_state.<player_id(int) -> ...> 字典：读档后需要把 "0"/"1" 转回 0/1
		Callable(registrar, "register_round_state_int_key_dict_schema").bind(STATE_SCHEMA_ID_EXTRA_TILE_PENDING, [EXTRA_TILE_PENDING_KEY], 100),
		# UI overlays：把模块私有 map_data（pending_roads/roadworks_markers）转换为通用 overlay 指令，避免 core UI 解析私有结构。
		Callable(registrar, "register_map_overlay_provider").bind(MAP_OVERLAY_PROVIDER_ID, Callable(self, "_build_map_overlays"), 100),
	]
	for step in steps:
		var r: Result = step.call()
		if not r.ok:
			return r

	# UI hints: keep piece classification and overlay definitions out of core UI code.
	var overlays: Dictionary = LobbyistsRoadOverlaysClass.ROAD_OVERLAYS
	for pid_val in LobbyistsRoadOverlaysClass.ROAD_PIECES:
		var pid := str(pid_val).strip_edges()
		if pid.is_empty():
			continue
		var overlay_val = overlays.get(pid, null)
		if not (overlay_val is Dictionary):
			return Result.failure("%s: ROAD_OVERLAYS 缺失: %s" % [MODULE_ID, pid])
		var r_hint: Result = registrar.register_piece_ui_hint(pid, {"kind": "road", "road_overlay": overlay_val}, 100)
		if not r_hint.ok:
			return r_hint

	for pid_val in PARK_SUPPLY_BY_PIECE_ID.keys():
		var pid2 := str(pid_val).strip_edges()
		if pid2.is_empty():
			continue
		var r_hint2: Result = registrar.register_piece_ui_hint(pid2, {"kind": "park"}, 100)
		if not r_hint2.ok:
			return r_hint2
	var r_hint3: Result = registrar.register_piece_ui_hint("lobbyists_park_tile_z", {"kind": "park"}, 100)
	if not r_hint3.ok:
		return r_hint3
	return Result.success()

func _build_map_overlays(map_data: Dictionary) -> Dictionary:
	if map_data == null or not (map_data is Dictionary):
		return {}

	var out := {}
	var pending_dirs := _build_pending_road_connection_dirs(map_data)
	if not pending_dirs.is_empty():
		out["pending_road_connection_dirs_by_pos"] = pending_dirs

	var markers := _build_roadworks_marker_world_positions(map_data)
	if not markers.is_empty():
		out["roadworks_marker_world_positions"] = markers

	return out

func _build_pending_road_connection_dirs(map_data: Dictionary) -> Dictionary:
	if map_data.is_empty():
		return {}
	if not map_data.has(PENDING_ROADS_KEY):
		return {}
	var pending_val = map_data.get(PENDING_ROADS_KEY, null)
	if not (pending_val is Array):
		return {}
	var pending: Array = pending_val
	if pending.is_empty():
		return {}

	var out := {} # Vector2i -> {dir -> true}

	for e_val in pending:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var sbp_val = e.get("segments_by_pos", null)
		if not (sbp_val is Dictionary):
			continue
		var segments_by_pos: Dictionary = sbp_val
		for k in segments_by_pos.keys():
			if not (k is String):
				continue
			var parts := str(k).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				continue
			var world_pos := Vector2i(int(parts[0]), int(parts[1]))
			var seg_list_val = segments_by_pos.get(k, null)
			if not (seg_list_val is Array):
				continue
			for seg_val in Array(seg_list_val):
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				for d_val in Array(dirs_val):
					var d := str(d_val).strip_edges()
					if d.is_empty() or not MapUtils.DIR_OFFSETS.has(d):
						continue
					if not out.has(world_pos):
						out[world_pos] = {}
					var m: Dictionary = out[world_pos]
					m[d] = true
					out[world_pos] = m

	return out

func _build_roadworks_marker_world_positions(map_data: Dictionary) -> Array[Vector2i]:
	if map_data.is_empty():
		return []
	var val = map_data.get(ROADWORK_MARKERS_KEY, null)
	if not (val is Dictionary):
		return []
	var markers: Dictionary = val

	var out: Array[Vector2i] = []
	var seen := {}
	for k in markers.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var key := "%d,%d" % [pos.x, pos.y]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(pos)

	return out

func _on_restructuring_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)

	# Lobbyists rule: parallel adjacent road lanes are connected.
	var opt_key := "road_graph_connect_parallel_lanes"
	var should_invalidate := false
	var opt_val = state.map.get(opt_key, null)
	if opt_val == null:
		should_invalidate = true
	elif opt_val is bool:
		should_invalidate = not bool(opt_val)
	elif opt_val is int:
		should_invalidate = int(opt_val) == 0
	elif opt_val is float:
		var f: float = float(opt_val)
		if f == floor(f):
			should_invalidate = int(f) == 0
		else:
			return Result.failure("%s: state.map.%s 类型错误（期望 bool/int）" % [MODULE_ID, opt_key])
	else:
		return Result.failure("%s: state.map.%s 类型错误（期望 bool/int）" % [MODULE_ID, opt_key])
	if should_invalidate:
		state.map[opt_key] = true
		RoadGraphCacheClass.invalidate_road_graph(state)

	for piece_id in ROAD_SUPPLY_BY_PIECE_ID.keys():
		var supply_key := "%s_supply_remaining" % str(piece_id)
		var supply_read := MapStateAccessClass.require_optional_int_field_or_default(
			state,
			supply_key,
			int(ROAD_SUPPLY_BY_PIECE_ID[piece_id]),
			MODULE_ID
		)
		if not supply_read.ok:
			return supply_read
		var supply_remaining: int = int(supply_read.value)
		if supply_remaining < 0:
			return Result.failure("%s: state.map.%s 不能为负数: %d" % [MODULE_ID, supply_key, supply_remaining])
		state.map[supply_key] = supply_remaining

	for park_piece_id in PARK_SUPPLY_BY_PIECE_ID.keys():
		var park_supply_key := "%s_supply_remaining" % str(park_piece_id)
		var park_supply_read := MapStateAccessClass.require_optional_int_field_or_default(
			state,
			park_supply_key,
			int(PARK_SUPPLY_BY_PIECE_ID[park_piece_id]),
			MODULE_ID
		)
		if not park_supply_read.ok:
			return park_supply_read
		var park_supply_remaining: int = int(park_supply_read.value)
		if park_supply_remaining < 0:
			return Result.failure("%s: state.map.%s 不能为负数: %d" % [MODULE_ID, park_supply_key, park_supply_remaining])
		state.map[park_supply_key] = park_supply_remaining
	if not state.map.has(PENDING_ROADS_KEY):
		state.map[PENDING_ROADS_KEY] = []
	if not state.map.has(ROADWORK_MARKERS_KEY):
		state.map[ROADWORK_MARKERS_KEY] = {}

	# 全局效果：roadworks 距离惩罚 + park 单价加成
	var add_roadworks := GlobalEffectListClass.add_to_map(state, EFFECT_ID_ROADWORKS_DISTANCE)
	if not add_roadworks.ok:
		return add_roadworks
	var add_park := GlobalEffectListClass.add_to_map(state, EFFECT_ID_PARK_BONUS)
	if not add_park.ok:
		return add_park

	# 每回合 pending（同回合内可能被多个玩家获取里程碑；离开子阶段前必须消化）
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has(EXTRA_TILE_PENDING_KEY):
		var pending := {}
		for i in range(state.players.size()):
			pending[i] = false
		state.round_state[EXTRA_TILE_PENDING_KEY] = pending
	# 每回合清空：记录“本回合通过里程碑扩边放置的 tile”（用于 Lobbyists 子阶段内的放置豁免）。
	var last := []
	for i in range(state.players.size()):
		last.append(null)
	state.round_state[EXTRA_TILE_LAST_PLACED_KEY] = last

	return Result.success()

func _parse_segments_by_pos_key(key) -> Result:
	if not (key is String):
		return Result.failure("%s: segments_by_pos key 类型错误（期望 String）" % MODULE_ID)
	var parts := str(key).split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Result.failure("%s: segments_by_pos key 格式错误: %s" % [MODULE_ID, str(key)])
	var wx := int(parts[0])
	var wy := int(parts[1])
	return Result.success(Vector2i(wx, wy))

func _require_row_at_world_pos(state: GameState, cells: Array, world_pos: Vector2i) -> Result:
	var idx := CoordsClass.world_to_index(state, world_pos)
	if idx.x < 0 or idx.y < 0 or idx.y >= cells.size():
		return Result.failure("%s: segments_by_pos 越界: %s" % [MODULE_ID, str(world_pos)])
	var row_val = cells[idx.y]
	if not (row_val is Array) or idx.x >= (row_val as Array).size():
		return Result.failure("%s: segments_by_pos 越界: %s" % [MODULE_ID, str(world_pos)])
	return Result.success({"idx": idx, "row": row_val})

func _require_cell_dict(row: Array, idx: Vector2i) -> Result:
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return Result.failure("%s: cells[%d][%d] 类型错误（期望 Dictionary）" % [MODULE_ID, idx.y, idx.x])
	return Result.success(cell_val)

func _require_cell_road_segments(cell: Dictionary, world_pos: Vector2i) -> Result:
	if not cell.has("road_segments") or not (cell["road_segments"] is Array):
		return Result.failure("%s: cell.road_segments 缺失或类型错误（期望 Array）: %s" % [MODULE_ID, str(world_pos)])
	return Result.success(cell["road_segments"])

func _segments_have_dir(segments: Array, dir: String) -> bool:
	var d := str(dir).strip_edges()
	if d.is_empty():
		return false
	for seg_val in segments:
		if not (seg_val is Dictionary):
			continue
		var seg: Dictionary = seg_val
		var dirs_val = seg.get("dirs", null)
		if dirs_val is Array and d in Array(dirs_val):
			return true
	return false

func _ensure_dir_in_segments(segments: Array, dir: String) -> bool:
	var need_dir := str(dir).strip_edges()
	if need_dir.is_empty():
		return false
	if _segments_have_dir(segments, need_dir):
		return false

	# 优先修改非桥段（Lobbyists 道路为 bridge=false）
	var target_idx := -1
	for j in range(segments.size()):
		var sv = segments[j]
		if not (sv is Dictionary):
			continue
		if not bool(Dictionary(sv).get("bridge", false)):
			target_idx = j
			break
	if target_idx < 0:
		for j2 in range(segments.size()):
			if segments[j2] is Dictionary:
				target_idx = j2
				break
	if target_idx < 0:
		return false

	var seg2: Dictionary = segments[target_idx]
	var dirs2_val = seg2.get("dirs", null)
	var dirs2: Array = dirs2_val if (dirs2_val is Array) else []
	if not dirs2.has(need_dir):
		dirs2.append(need_dir)
	seg2["dirs"] = dirs2
	segments[target_idx] = seg2
	return true

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

	var extra_dirs_by_pos := {} # Vector2i -> {dir -> true}
	var clear_structure_cells := {} # Vector2i -> true

	for i in range(pending_roads.size()):
		var e_val = pending_roads[i]
		if not (e_val is Dictionary):
			return Result.failure("%s: pending_roads[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, i])
		var e: Dictionary = e_val
		var piece_cells_val = e.get("cells", null)
		if piece_cells_val is Array:
			for c_val in Array(piece_cells_val):
				if c_val is Vector2i:
					clear_structure_cells[c_val] = true

		var segments_val = e.get("segments_by_pos", null)
		if not (segments_val is Dictionary):
			return Result.failure("%s: pending_roads[%d].segments_by_pos 类型错误（期望 Dictionary）" % [MODULE_ID, i])
		var segments_by_pos: Dictionary = segments_val
		for k in segments_by_pos.keys():
			var world_read := _parse_segments_by_pos_key(k)
			if not world_read.ok:
				return world_read
			var world_pos: Vector2i = world_read.value

			var row_read := _require_row_at_world_pos(state, cells, world_pos)
			if not row_read.ok:
				return row_read
			var idx: Vector2i = row_read.value["idx"]
			var row: Array = row_read.value["row"]

			var cell_read := _require_cell_dict(row, idx)
			if not cell_read.ok:
				return cell_read
			var cell: Dictionary = cell_read.value

			var segs_read := _require_cell_road_segments(cell, world_pos)
			if not segs_read.ok:
				return segs_read
			var segs: Array = segs_read.value

			var add_val = segments_by_pos[k]
			if not (add_val is Array):
				return Result.failure("%s: segments_by_pos[%s] 类型错误（期望 Array）" % [MODULE_ID, str(k)])

			# 根据新增段，推导“邻居道路”需要补齐的对向连接（用于真实连通 + 贴图）
			for seg_val in Array(add_val):
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				for d_val in Array(dirs_val):
					var d := str(d_val).strip_edges()
					if d.is_empty() or not MapUtils.DIR_OFFSETS.has(d):
						continue
					var npos = world_pos + MapUtils.DIR_OFFSETS[d]
					if not CoordsClass.is_world_pos_in_grid(state, npos):
						continue
					var opp := MapUtils.get_opposite_dir(d)
					if opp.is_empty():
						continue
					var set_val = extra_dirs_by_pos.get(npos, null)
					var set: Dictionary = set_val if (set_val is Dictionary) else {}
					set[opp] = true
					extra_dirs_by_pos[npos] = set

			segs.append_array(add_val)
			cell["road_segments"] = segs
			row[idx.x] = cell
			cells[idx.y] = row

	# 3) 让新增道路与已有道路真正连通：为相邻道路补齐对向 dirs
	for pos_val in extra_dirs_by_pos.keys():
		if not (pos_val is Vector2i):
			continue
		var world_pos2: Vector2i = pos_val
		if not CoordsClass.is_world_pos_in_grid(state, world_pos2):
			continue

		var row_read2 := _require_row_at_world_pos(state, cells, world_pos2)
		if not row_read2.ok:
			return row_read2
		var idx2: Vector2i = row_read2.value["idx"]
		var row2: Array = row_read2.value["row"]

		var cell_read2 := _require_cell_dict(row2, idx2)
		if not cell_read2.ok:
			return cell_read2
		var cell2: Dictionary = cell_read2.value

		var segs_read2 := _require_cell_road_segments(cell2, world_pos2)
		if not segs_read2.ok:
			return segs_read2
		var segs2: Array = segs_read2.value
		if segs2.is_empty():
			continue

		var needed_val = extra_dirs_by_pos.get(world_pos2, null)
		if not (needed_val is Dictionary):
			continue
		var needed: Dictionary = needed_val

		for dir_key in needed.keys():
			var need_dir := str(dir_key).strip_edges()
			if need_dir.is_empty():
				continue
			var already := false
			for s_val in segs2:
				if not (s_val is Dictionary):
					continue
				var s: Dictionary = s_val
				var dirs3_val = s.get("dirs", null)
				if dirs3_val is Array and need_dir in Array(dirs3_val):
					already = true
					break
			if already:
				continue

			# 优先修改非桥段（Lobbyists 道路为 bridge=false）
			var target_idx := -1
			for j in range(segs2.size()):
				var sv = segs2[j]
				if not (sv is Dictionary):
					continue
				if not bool(Dictionary(sv).get("bridge", false)):
					target_idx = j
					break
			if target_idx < 0:
				for j2 in range(segs2.size()):
					if segs2[j2] is Dictionary:
						target_idx = j2
						break
			if target_idx < 0:
				continue

			var seg2: Dictionary = segs2[target_idx]
			var dirs2_val = seg2.get("dirs", null)
			var dirs2: Array = dirs2_val if (dirs2_val is Array) else []
			if not dirs2.has(need_dir):
				dirs2.append(need_dir)
			seg2["dirs"] = dirs2
			segs2[target_idx] = seg2

		cell2["road_segments"] = segs2
		row2[idx2.x] = cell2
		cells[idx2.y] = row2

	# 3.5) 邻接道路互联：新增道路格与相邻道路格应互相补齐对向 dirs。
	# 这一步不要求“原段已开放该方向”：只要相邻格子存在道路，就视为可连通（从而驱动路口贴图与 RoadGraph 升级）。
	for cpos_val in clear_structure_cells.keys():
		if not (cpos_val is Vector2i):
			continue
		var world_pos4: Vector2i = cpos_val
		if not CoordsClass.is_world_pos_in_grid(state, world_pos4):
			continue

		var row_read4 := _require_row_at_world_pos(state, cells, world_pos4)
		if not row_read4.ok:
			return row_read4
		var idx4: Vector2i = row_read4.value["idx"]
		var row4: Array = row_read4.value["row"]

		var cell_read4 := _require_cell_dict(row4, idx4)
		if not cell_read4.ok:
			return cell_read4
		var cell4: Dictionary = cell_read4.value

		var segs_read4 := _require_cell_road_segments(cell4, world_pos4)
		if not segs_read4.ok:
			return segs_read4
		var segs4: Array = segs_read4.value
		if segs4.is_empty():
			continue

		var changed_self := false
		for dir in MapUtils.DIRECTIONS:
			var npos4: Vector2i = world_pos4 + MapUtils.DIR_OFFSETS[dir]
			if not CoordsClass.is_world_pos_in_grid(state, npos4):
				continue

			var row_read5 := _require_row_at_world_pos(state, cells, npos4)
			if not row_read5.ok:
				return row_read5
			var idx5: Vector2i = row_read5.value["idx"]
			var row5: Array = row_read5.value["row"]

			var ncell_read := _require_cell_dict(row5, idx5)
			if not ncell_read.ok:
				return ncell_read
			var ncell: Dictionary = ncell_read.value

			var nsegs_read := _require_cell_road_segments(ncell, npos4)
			if not nsegs_read.ok:
				return nsegs_read
			var nsegs: Array = nsegs_read.value
			if nsegs.is_empty():
				continue

			var opp := MapUtils.get_opposite_dir(str(dir))
			if opp.is_empty():
				continue

			var changed_neighbor := false
			if _ensure_dir_in_segments(nsegs, opp):
				changed_neighbor = true
			if _ensure_dir_in_segments(segs4, str(dir)):
				changed_self = true

			if changed_neighbor:
				ncell["road_segments"] = nsegs
				row5[idx5.x] = ncell
				cells[idx5.y] = row5

		if changed_self:
			cell4["road_segments"] = segs4
			row4[idx4.x] = cell4
			cells[idx4.y] = row4

	# 4) 清理“建设中道路”的结构占用（仅保留 road_segments，使其变为真正道路）
	for cpos_val in clear_structure_cells.keys():
		if not (cpos_val is Vector2i):
			continue
		var cpos: Vector2i = cpos_val
		if not CoordsClass.is_world_pos_in_grid(state, cpos):
			continue

		var row_read3 := _require_row_at_world_pos(state, cells, cpos)
		if not row_read3.ok:
			return row_read3
		var idx3: Vector2i = row_read3.value["idx"]
		var row3: Array = row_read3.value["row"]

		var cell_read3 := _require_cell_dict(row3, idx3)
		if not cell_read3.ok:
			return cell_read3
		var cell3: Dictionary = cell_read3.value

		var s_val = cell3.get("structure", null)
		if s_val is Dictionary:
			var s: Dictionary = s_val
			var pid := str(s.get("piece_id", ""))
			if pid.begins_with("lobbyists_road_") and bool(s.get("dynamic", false)):
				cell3["structure"] = {}
				row3[idx3.x] = cell3
				cells[idx3.y] = row3

	state.map["cells"] = cells
	state.map[PENDING_ROADS_KEY] = []
	RoadGraphCacheClass.invalidate_road_graph(state)
	return Result.success()

func _on_lobbyists_before_exit(state: GameState) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("%s: round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	var pending_players_read := RoundStatePlayerBoolFlagsClass.list_true_players(
		state.round_state,
		[EXTRA_TILE_PENDING_KEY],
		state.players.size(),
		MODULE_ID
	)
	if not pending_players_read.ok:
		return pending_players_read
	var pending_players: Array = pending_players_read.value
	if not pending_players.is_empty():
		return Result.failure("存在未处理的“额外地图板块”放置（必须先放置或放弃）: player=%d" % int(pending_players[0]))
	if state.round_state.has(EXTRA_TILE_LAST_PLACED_KEY):
		state.round_state.erase(EXTRA_TILE_LAST_PLACED_KEY)
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

	var normalize_pending := RoundStatePlayerBoolFlagsClass.normalize_player_flags(
		state.round_state,
		[EXTRA_TILE_PENDING_KEY],
		state.players.size(),
		MODULE_ID
	)
	if not normalize_pending.ok:
		return normalize_pending
	var mark_pending := RoundStatePlayerBoolFlagsClass.set_player_flag(
		state.round_state,
		[EXTRA_TILE_PENDING_KEY],
		player_id,
		true,
		MODULE_ID
	)
	if not mark_pending.ok:
		return mark_pending
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
	for i in range(path_any.size()):
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

	var houses_read := MapStateAccessClass.require_houses(state, "%s: park" % MODULE_ID)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
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

	var add := unit_price * qty
	ctx["bonus"] = int(ctx["bonus"]) + add
	if ctx.has("bonus_breakdown") and (ctx["bonus_breakdown"] is Dictionary):
		var breakdown: Dictionary = ctx["bonus_breakdown"]
		breakdown["park"] = int(breakdown.get("park", 0)) + add
		ctx["bonus_breakdown"] = breakdown
	return Result.success()

static func _is_park_piece_id(piece_id: String) -> bool:
	var id := str(piece_id).strip_edges()
	if id.is_empty():
		return false
	return id == "park" or id.begins_with("lobbyists_park_")

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
			if not CoordsClass.is_world_pos_in_grid(state, npos):
				continue

			var idx: Vector2i = CoordsClass.world_to_index(state, npos)
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
			if _is_park_piece_id(str(s.get("piece_id", ""))):
				return Result.success(true)

	return Result.success(false)
