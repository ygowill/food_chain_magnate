# 模块2：说客（Lobbyists）
# - Working 子阶段插入：Lobbyists（PlaceHouses 之后，PlaceRestaurants 之前）
# - 放置公园/道路触发 First Lobbyist Used，并允许立刻扩边放置地图 tile
class_name LobbyistsV2Test
extends RefCounted

const ModuleEntryClass = preload("res://modules/lobbyists/rules/entry.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_milestone_effect_initializes_pending_key(seed_val)
	if not r.ok:
		return r

	r = _test_park_triggers_extra_tile(seed_val)
	if not r.ok:
		return r

	r = _test_pending_blocks_additional_lobbyists_actions(seed_val)
	if not r.ok:
		return r

	r = _test_extra_tile_expand_is_blocked_by_airplane_and_offramp(seed_val)
	if not r.ok:
		return r

	r = _test_extra_tile_allows_free_park_on_new_tile(seed_val)
	if not r.ok:
		return r

	r = _test_lobbyists_road_requires_existing_road_connection(seed_val)
	if not r.ok:
		return r

	r = _test_road_pending_and_cleanup(seed_val)
	if not r.ok:
		return r

	r = _test_road_cleanup_completes_existing_to_new_connections(seed_val)
	if not r.ok:
		return r

	r = _test_road_cleanup_connects_adjacent_cells_without_preexisting_dirs(seed_val)
	if not r.ok:
		return r

	r = _test_roadworks_distance_penalty_is_invoked(seed_val)
	if not r.ok:
		return r

	r = _test_roadworks_distance_penalty_includes_start_cell(seed_val)
	if not r.ok:
		return r

	r = _test_park_bonus_is_invoked(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _test_road_cleanup_connects_adjacent_cells_without_preexisting_dirs(_seed_val: int) -> Result:
	# Regression: adjacency to an existing road cell must create a connection even if neither side
	# previously had the matching dirs (e.g. attaching to the "side" of a straight segment).
	var s := GameState.new()
	s.map = {
		"grid_size": Vector2i(3, 3),
		"cells": [],
		"boundary_index": {},
	}
	CoordsClass.set_map_origin(s, Vector2i.ZERO)

	var cells := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append({
				"road_segments": [],
				"structure": {},
				"terrain_type": null,
				"drink_source": null,
				"tile_origin": Vector2i(-1, -1),
				"blocked": false,
			})
		cells.append(row)
	s.map["cells"] = cells

	# Existing road: vertical straight (no E/W initially).
	s.map["cells"][1][0]["road_segments"] = [{
		"dirs": ["N", "S"],
		"bridge": false,
	}]

	# New road: a corner that doesn't initially face west (no "W").
	# It should gain "W", and the existing straight should gain "E" after Cleanup.
	s.map["cells"][1][1]["structure"] = {"piece_id": "lobbyists_road_l", "dynamic": true}
	s.map["lobbyists_pending_roads"] = [{
		"cells": [Vector2i(1, 1)],
		"segments_by_pos": {
			"1,1": [{"dirs": ["N", "E"], "bridge": false}],
		},
	}]

	var entry := ModuleEntryClass.new()
	var r: Result = entry._on_cleanup_enter_extension(s, null)
	if not r.ok:
		return Result.failure("Cleanup 扩展失败: %s" % r.error)

	var left_cell: Dictionary = CellsClass.get_cell(s, Vector2i(0, 1))
	var left_segs_val = left_cell.get("road_segments", null)
	if not (left_segs_val is Array):
		return Result.failure("cell.road_segments 类型错误: (0,1)")
	var left_segs: Array = left_segs_val
	if left_segs.is_empty():
		return Result.failure("预期 (0,1) 有道路")
	if not _cell_segments_have_dir(left_segs, "E"):
		return Result.failure("Cleanup 后既有道路未补齐对向 dirs: (0,1) should include E")

	var new_cell: Dictionary = CellsClass.get_cell(s, Vector2i(1, 1))
	var new_segs_val = new_cell.get("road_segments", null)
	if not (new_segs_val is Array):
		return Result.failure("cell.road_segments 类型错误: (1,1)")
	var new_segs: Array = new_segs_val
	if new_segs.is_empty():
		return Result.failure("Cleanup 后新道路未写入 road_segments: (1,1)")
	if not _cell_segments_have_dir(new_segs, "W"):
		return Result.failure("Cleanup 后新道路未补齐对向 dirs: (1,1) should include W")

	var road_graph = RoadGraphCacheClass.get_road_graph(s)
	if road_graph == null:
		return Result.failure("道路图未初始化（测试）")
	if int(road_graph.get_distance(Vector2i(0, 1), Vector2i(1, 1))) < 0:
		return Result.failure("Cleanup 后道路未连通: (0,1) <-> (1,1)")

	return Result.success()

static func _cell_segments_have_dir(segs: Array, dir: String) -> bool:
	var d := str(dir).strip_edges()
	if d.is_empty():
		return false
	for seg_val in segs:
		if not (seg_val is Dictionary):
			continue
		var seg: Dictionary = seg_val
		var dirs_val = seg.get("dirs", null)
		if dirs_val is Array and d in Array(dirs_val):
			return true
	return false

static func _test_road_cleanup_completes_existing_to_new_connections(_seed_val: int) -> Result:
	# Regression: when a newly built road cell is adjacent to an existing road "open end",
	# Cleanup must also complete the missing opposite dir on the new cell.
	#
	# Example: place a corner next to a tee; after Cleanup the corner becomes a tee,
	# and the road graph must treat them as connected.
	var s := GameState.new()
	s.map = {
		"grid_size": Vector2i(3, 3),
		"cells": [],
		"boundary_index": {},
	}
	CoordsClass.set_map_origin(s, Vector2i.ZERO)

	var cells := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append({
				"road_segments": [],
				"structure": {},
				"terrain_type": null,
				"drink_source": null,
				"tile_origin": Vector2i(-1, -1),
				"blocked": false,
			})
		cells.append(row)
	s.map["cells"] = cells

	# Existing road: tee pointing to north (into the empty cell where the new road will be built).
	s.map["cells"][1][1]["road_segments"] = [{
		"dirs": ["N", "E", "W"],
		"bridge": false,
	}]

	# New road segment: a corner missing the south dir. It should be upgraded to a tee by Cleanup.
	s.map["cells"][0][1]["structure"] = {"piece_id": "lobbyists_road_l", "dynamic": true}
	s.map["lobbyists_pending_roads"] = [{
		"cells": [Vector2i(1, 0)],
		"segments_by_pos": {
			"1,0": [{"dirs": ["N", "E"], "bridge": false}],
		},
	}]

	var entry := ModuleEntryClass.new()
	var r: Result = entry._on_cleanup_enter_extension(s, null)
	if not r.ok:
		return Result.failure("Cleanup 扩展失败: %s" % r.error)

	if CellsClass.has_structure_at(s, Vector2i(1, 0)):
		return Result.failure("Cleanup 后建设中道路结构占用未清理: (1,0)")

	var new_cell: Dictionary = CellsClass.get_cell(s, Vector2i(1, 0))
	var segs_val = new_cell.get("road_segments", null)
	if not (segs_val is Array):
		return Result.failure("cell.road_segments 类型错误: (1,0)")
	var segs: Array = segs_val
	if segs.is_empty():
		return Result.failure("Cleanup 后新道路未写入 road_segments: (1,0)")

	var has_s := false
	for seg_val in segs:
		if not (seg_val is Dictionary):
			continue
		var seg: Dictionary = seg_val
		var dirs_val = seg.get("dirs", null)
		if dirs_val is Array and "S" in Array(dirs_val):
			has_s = true
			break
	if not has_s:
		return Result.failure("Cleanup 后新道路未补齐对向 dirs: (1,0) should include S")

	var road_graph = RoadGraphCacheClass.get_road_graph(s)
	if road_graph == null:
		return Result.failure("道路图未初始化（测试）")
	if int(road_graph.get_distance(Vector2i(1, 0), Vector2i(1, 1))) < 0:
		return Result.failure("Cleanup 后道路未连通: (1,0) <-> (1,1)")

	return Result.success()

static func _test_extra_tile_expand_is_blocked_by_airplane_and_offramp(seed_val: int) -> Result:
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

	if not s.round_state.has("lobbyists_extra_tile_pending") or not (s.round_state["lobbyists_extra_tile_pending"] is Dictionary):
		return Result.failure("缺少 round_state.lobbyists_extra_tile_pending")
	var pending: Dictionary = s.round_state["lobbyists_extra_tile_pending"]
	pending[0] = true
	s.round_state["lobbyists_extra_tile_pending"] = pending

	if not s.map.has("tile_supply_remaining") or not (s.map["tile_supply_remaining"] is Array) or (s.map["tile_supply_remaining"] as Array).is_empty():
		return Result.failure("tile_supply_remaining 不应为空（否则无法测试扩边）")
	var tile_id_val = (s.map["tile_supply_remaining"] as Array)[0]
	if not (tile_id_val is String) or str(tile_id_val).is_empty():
		return Result.failure("tile_supply_remaining[0] 类型错误")
	var tile_id: String = str(tile_id_val)

	# 1) airplane：占用棋盘外侧区域，应阻挡扩边
	var minp := CoordsClass.get_world_min(s)
	var mp_val = s.map.get("marketing_placements", null)
	if mp_val == null:
		mp_val = {}
	if not (mp_val is Dictionary):
		return Result.failure("state.map.marketing_placements 类型错误（期望 Dictionary）")
	var placements: Dictionary = mp_val
	placements["__test_airplane__"] = {
		"board_number": 999,
		"type": "airplane",
		"world_pos": Vector2i(0, minp.y),
		"axis": "col",
		"footprint_size": Vector2i(5, 2),
	}
	s.map["marketing_placements"] = placements

	var cmd := Command.create("place_lobbyists_extra_map_tile", 0)
	cmd.params = {
		"tile_id": tile_id,
		"attach_to_tile_board_pos": [0, 0],
		"side": "N",
		"rotation": 0,
	}
	var r := e.execute_command(cmd)
	if r.ok:
		return Result.failure("扩边在 airplane 冲突时应失败（实际成功）")
	if not str(r.error).contains("airplane"):
		return Result.failure("扩边错误信息应包含 airplane（实际: %s）" % str(r.error))

	# 2) offramp：external_cells 覆盖到新 tile 区域，应阻挡扩边
	placements.erase("__test_airplane__")
	s.map["marketing_placements"] = placements
	pending = s.round_state["lobbyists_extra_tile_pending"]
	pending[0] = true
	s.round_state["lobbyists_extra_tile_pending"] = pending

	var wp := Vector2i(0, minp.y - 1)
	var ext_val = s.map.get("external_cells", null)
	if not (ext_val is Dictionary):
		return Result.failure("state.map.external_cells 类型错误（期望 Dictionary）")
	var external_cells: Dictionary = ext_val
	external_cells["%d,%d" % [wp.x, wp.y]] = {
		"road_segments": [],
		"structure": {"piece_id": "highway_offramp"},
		"blocked": false,
		"tile_origin": Vector2i(-1, -1),
	}
	s.map["external_cells"] = external_cells

	var r2 := e.execute_command(cmd)
	if r2.ok:
		return Result.failure("扩边在 offramp 冲突时应失败（实际成功）")
	if not str(r2.error).contains("offramp"):
		return Result.failure("扩边错误信息应包含 offramp（实际: %s）" % str(r2.error))

	return Result.success()

static func _test_extra_tile_allows_free_park_on_new_tile(seed_val: int) -> Result:
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

	# 直接设置 pending，避免依赖“先放 road/park”触发里程碑。
	if not s.round_state.has("lobbyists_extra_tile_pending") or not (s.round_state["lobbyists_extra_tile_pending"] is Dictionary):
		return Result.failure("缺少 round_state.lobbyists_extra_tile_pending")
	var pending: Dictionary = s.round_state["lobbyists_extra_tile_pending"]
	pending[0] = true
	s.round_state["lobbyists_extra_tile_pending"] = pending

	if not s.map.has("tile_supply_remaining") or not (s.map["tile_supply_remaining"] is Array) or (s.map["tile_supply_remaining"] as Array).is_empty():
		return Result.failure("tile_supply_remaining 不应为空（否则无法测试扩边）")
	var tile_id_val = (s.map["tile_supply_remaining"] as Array)[0]
	if not (tile_id_val is String) or str(tile_id_val).is_empty():
		return Result.failure("tile_supply_remaining[0] 类型错误")
	var tile_id: String = str(tile_id_val)

	var cmd := Command.create("place_lobbyists_extra_map_tile", 0)
	cmd.params = {
		"tile_id": tile_id,
		"attach_to_tile_board_pos": [0, 0],
		"side": "N",
		"rotation": 0,
	}
	var r := e.execute_command(cmd)
	if not r.ok:
		return Result.failure("扩边放置 tile 失败: %s" % r.error)
	s = e.get_state()

	# 清空 restaurants：若仍执行 reachability 校验则必失败；现在应允许在新 tile 上放 park。
	s.map["restaurants"] = {}
	s.map["drink_sources"] = []

	var new_tile_board_pos := Vector2i(0, -1)
	_clear_tile_area_for_free_placement(s, new_tile_board_pos)
	var placed := _try_place_park_within_tile(e, 0, new_tile_board_pos)
	if not placed.ok:
		return placed

	return Result.success()

static func _test_lobbyists_road_requires_existing_road_connection(seed_val: int) -> Result:
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

	# 设置 pending 并扩边，确保“新 tile 上放 road/park 不受 range=2 限制”的分支可用。
	if not s.round_state.has("lobbyists_extra_tile_pending") or not (s.round_state["lobbyists_extra_tile_pending"] is Dictionary):
		return Result.failure("缺少 round_state.lobbyists_extra_tile_pending")
	var pending: Dictionary = s.round_state["lobbyists_extra_tile_pending"]
	pending[0] = true
	s.round_state["lobbyists_extra_tile_pending"] = pending

	var tile_id_val = (s.map.get("tile_supply_remaining", []) as Array)[0]
	if not (tile_id_val is String) or str(tile_id_val).is_empty():
		return Result.failure("tile_supply_remaining[0] 类型错误")
	var tile_id: String = str(tile_id_val)

	var cmd_tile := Command.create("place_lobbyists_extra_map_tile", 0)
	cmd_tile.params = {
		"tile_id": tile_id,
		"attach_to_tile_board_pos": [0, 0],
		"side": "N",
		"rotation": 0,
	}
	var tr := e.execute_command(cmd_tile)
	if not tr.ok:
		return Result.failure("扩边放置 tile 失败: %s" % tr.error)
	s = e.get_state()

	var new_tile_board_pos := Vector2i(0, -1)
	s.map["drink_sources"] = []
	_clear_tile_area_for_free_placement(s, new_tile_board_pos)

	# 清空 restaurants：避免 reachability 分支误通过（应由“新 tile 豁免”跳过）。
	s.map["restaurants"] = {}

	# 在新 tile 内找一个可放置 road_straight 的位置，使其箭头指向一个“自己的餐厅入口格”（但不指向道路）。
	var candidate := _find_road_straight_anchor_within_tile(s, new_tile_board_pos)
	if not candidate.ok:
		return candidate
	var info: Dictionary = candidate.value
	var anchor: Vector2i = info["anchor"]
	var rotation: int = int(info["rotation"])
	var endpoint: Vector2i = info["endpoint"]

	# 注入“餐厅入口格”（不放道路），验证 road 必须指向已有道路而非餐厅入口。
	var idx2 := CoordsClass.world_to_index(s, endpoint)
	var old_struct = s.map.cells[idx2.y][idx2.x]["structure"]
	s.map.cells[idx2.y][idx2.x]["structure"] = {
		"piece_id": "restaurant",
		"owner": 0,
		"anchor_cell": true,
	}

	var cmd := Command.create("place_lobbyists_road", 0)
	cmd.params = {"piece_id": "lobbyists_road_straight", "anchor_pos": [anchor.x, anchor.y], "rotation": rotation}
	var r := e.execute_command(cmd)

	# 回滚注入，避免污染后续验证（即使本测试提前返回）。
	s.map.cells[idx2.y][idx2.x]["structure"] = old_struct

	if r.ok:
		return Result.failure("道路仅指向餐厅入口且不指向道路时应失败（实际成功）")
	if not str(r.error).contains("箭头"):
		return Result.failure("错误信息应提示箭头连接要求（实际: %s）" % str(r.error))

	return Result.success()

static func _test_milestone_effect_initializes_pending_key(seed_val: int) -> Result:
	# 兼容：旧存档/回放可能缺少 round_state.lobbyists_extra_tile_pending，
	# 但仍可能触发 first_lobbyist_used（UseEmployee/lobbyist）。
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

	if s.round_state is Dictionary and s.round_state.has("lobbyists_extra_tile_pending"):
		s.round_state.erase("lobbyists_extra_tile_pending")

	var entry = ModuleEntryClass.new()
	var eff := {"type": "lobbyists_grant_extra_map_tile"}
	var r := entry._milestone_effect_grant_extra_map_tile(s, 0, "first_lobbyist_used", eff)
	if not r.ok:
		return Result.failure("milestone_effect 应可自动初始化 pending key（实际失败）: %s" % r.error)

	var pending_val = s.round_state.get("lobbyists_extra_tile_pending", null)
	if not (pending_val is Dictionary):
		return Result.failure("milestone_effect 未写入 round_state.lobbyists_extra_tile_pending")
	var pending: Dictionary = pending_val
	if not (pending.get(0, null) is bool) or not bool(pending.get(0, false)):
		return Result.failure("milestone_effect 应设置 pending[0]=true")
	if not (pending.get(1, null) is bool):
		return Result.failure("milestone_effect 应初始化 pending[1]（bool）")

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

static func _test_pending_blocks_additional_lobbyists_actions(seed_val: int) -> Result:
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

	if not s.round_state.has("lobbyists_extra_tile_pending") or not (s.round_state["lobbyists_extra_tile_pending"] is Dictionary):
		return Result.failure("缺少 round_state.lobbyists_extra_tile_pending")
	var pending: Dictionary = s.round_state["lobbyists_extra_tile_pending"]
	if not bool(pending.get(0, false)):
		return Result.failure("预期玩家 0 仍有 extra_tile pending=true")

	# pending 未处理前，不允许继续放 road/park（避免错过“必须当场二选一”的扩边流程）。
	var cmd_road := Command.create("place_lobbyists_road", 0)
	cmd_road.params = {}
	var r1 := e.execute_command(cmd_road)
	if r1.ok:
		return Result.failure("pending 未处理时 place_lobbyists_road 不应允许执行")
	if not str(r1.error).contains("扩边"):
		return Result.failure("place_lobbyists_road 错误信息应提示扩边 pending（实际: %s）" % str(r1.error))

	var cmd_park := Command.create("place_lobbyists_park", 0)
	cmd_park.params = {}
	var r2 := e.execute_command(cmd_park)
	if r2.ok:
		return Result.failure("pending 未处理时 place_lobbyists_park 不应允许执行")
	if not str(r2.error).contains("扩边"):
		return Result.failure("place_lobbyists_park 错误信息应提示扩边 pending（实际: %s）" % str(r2.error))

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
	var pending_roads: Array = s.map["lobbyists_pending_roads"]
	var pending0_val = pending_roads[0]
	if not (pending0_val is Dictionary):
		return Result.failure("pending_roads[0] 类型错误（期望 Dictionary）")
	var pending0: Dictionary = pending0_val
	var pending_segments_by_pos_val = pending0.get("segments_by_pos", null)
	if not (pending_segments_by_pos_val is Dictionary):
		return Result.failure("pending_roads[0].segments_by_pos 类型错误（期望 Dictionary）")
	var pending_segments_by_pos: Dictionary = pending_segments_by_pos_val
	var pending_cells_val = pending0.get("cells", null)
	if not (pending_cells_val is Array):
		return Result.failure("pending_roads[0].cells 类型错误（期望 Array）")
	var pending_cells: Array = pending_cells_val
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

	# Cleanup 后：建设中道路应变为真正道路（road_segments 写入、结构占用清理、与邻路连通）
	for c_val in pending_cells:
		if not (c_val is Vector2i):
			continue
		var cpos: Vector2i = c_val
		if not CoordsClass.is_world_pos_in_grid(s, cpos):
			continue
		if CellsClass.has_structure_at(s, cpos):
			return Result.failure("Cleanup 后建设中道路结构占用未清理: %s" % str(cpos))
		if not CellsClass.has_road_at(s, cpos):
			return Result.failure("Cleanup 后建设中道路未写入 road_segments: %s" % str(cpos))

	# 对每个新增 road segment：若其邻居格存在道路，则邻居必须包含对向 dirs（确保图/测距连通）
	for k in pending_segments_by_pos.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var world_pos := Vector2i(int(parts[0]), int(parts[1]))
		var seg_list_val = pending_segments_by_pos.get(k, null)
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
				var npos = world_pos + MapUtils.DIR_OFFSETS[d]
				if not CoordsClass.is_world_pos_in_grid(s, npos):
					continue
				var ncell: Dictionary = CellsClass.get_cell(s, npos)
				if ncell.is_empty():
					continue
				var rs_val = ncell.get("road_segments", null)
				if not (rs_val is Array):
					return Result.failure("cell.road_segments 类型错误: %s" % str(npos))
				var nsegs: Array = rs_val
				if nsegs.is_empty():
					continue
				var opp := MapUtils.get_opposite_dir(d)
				if opp.is_empty():
					continue
				var ok := false
				for nseg_val in nsegs:
					if not (nseg_val is Dictionary):
						continue
					var nseg: Dictionary = nseg_val
					var ndirs_val = nseg.get("dirs", null)
					if ndirs_val is Array and opp in Array(ndirs_val):
						ok = true
						break
				if not ok:
					return Result.failure("Cleanup 后道路连通缺失: %s -> %s (need %s in neighbor)" % [str(world_pos), str(npos), opp])

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
	var road_graph = RoadGraphCacheClass.get_road_graph(s)
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

static func _test_roadworks_distance_penalty_includes_start_cell(seed_val: int) -> Result:
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

	var road_graph = RoadGraphCacheClass.get_road_graph(s)
	if road_graph == null:
		return Result.failure("道路图未初始化")
	var pick := _pick_connected_road_path(s, road_graph)
	if not pick.ok:
		return pick
	var path: Array[Vector2i] = pick.value
	if path.size() < 3:
		return Result.failure("测试需要 >=3 的道路 path（实际: %d）" % path.size())

	var marker_pos: Vector2i = path[0]
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
		return Result.failure("roadworks 起点格应使 distance +1（实际: %s）" % str(ctx.get("distance", null)))

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
				road_cells.append(CoordsClass.index_to_world(state, Vector2i(ix, iy)))

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
				if not CoordsClass.is_world_pos_in_grid(state, npos):
					continue
				var cell: Dictionary = CellsClass.get_cell(state, npos)
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
	var idx := CoordsClass.world_to_index(state, pos)
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
	for piece_id in ["lobbyists_park_line", "lobbyists_park_t", "lobbyists_park_l"]:
		for y in range(grid.y):
			for x in range(grid.x):
				for rot in [0, 90, 180, 270]:
					var cmd := Command.create("place_lobbyists_park", 0)
					cmd.params = {"piece_id": piece_id, "anchor_pos": [x, y], "rotation": rot}
					var r := engine.execute_command(cmd)
					if r.ok:
						return Result.success()
	return Result.failure("未找到可放置公园的位置（测试环境）")

static func _try_place_road(engine: GameEngine) -> Result:
	var s: GameState = engine.get_state()
	var grid: Vector2i = s.map.grid_size
	for piece_id in ["lobbyists_road_straight", "lobbyists_road_long", "lobbyists_road_l"]:
		for y in range(grid.y):
			for x in range(grid.x):
				for rot in [0, 90, 180, 270]:
					var cmd := Command.create("place_lobbyists_road", 0)
					cmd.params = {"piece_id": piece_id, "anchor_pos": [x, y], "rotation": rot}
					var r := engine.execute_command(cmd)
					if r.ok:
						return Result.success()
	return Result.failure("未找到可放置道路的位置（测试环境）")

static func _try_place_park_within_tile(engine: GameEngine, player_id: int, board_pos: Vector2i) -> Result:
	var tile_world_min := board_pos * MapUtils.TILE_SIZE
	for piece_id in ["lobbyists_park_line", "lobbyists_park_t", "lobbyists_park_l"]:
		for ly in range(MapUtils.TILE_SIZE):
			for lx in range(MapUtils.TILE_SIZE):
				var anchor := tile_world_min + Vector2i(lx, ly)
				for rot in [0, 90, 180, 270]:
					var cmd := Command.create("place_lobbyists_park", player_id)
					cmd.params = {"piece_id": piece_id, "anchor_pos": [anchor.x, anchor.y], "rotation": rot}
					var r := engine.execute_command(cmd)
					if r.ok:
						return Result.success()
	return Result.failure("未找到可放置公园的位置（tile=%s）" % str(board_pos))

static func _clear_tile_area_for_free_placement(state: GameState, board_pos: Vector2i) -> void:
	if state == null or not (state.map is Dictionary):
		return
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return

	var tile_world_min := board_pos * MapUtils.TILE_SIZE
	var cells: Array = state.map["cells"]
	for dy in range(MapUtils.TILE_SIZE):
		for dx in range(MapUtils.TILE_SIZE):
			var wp := tile_world_min + Vector2i(dx, dy)
			if not CoordsClass.is_world_pos_in_grid(state, wp):
				continue
			var idx := CoordsClass.world_to_index(state, wp)
			if idx.y < 0 or idx.y >= cells.size():
				continue
			var row_val = cells[idx.y]
			if not (row_val is Array):
				continue
			var row: Array = row_val
			if idx.x < 0 or idx.x >= row.size():
				continue
			var cell_val = row[idx.x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			cell["blocked"] = false
			cell["road_segments"] = []
			cell["structure"] = {}
			cell["drink_source"] = null
			row[idx.x] = cell
			cells[idx.y] = row
	state.map["cells"] = cells

static func _find_road_straight_anchor_within_tile(state: GameState, board_pos: Vector2i) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	var tile_world_min := board_pos * MapUtils.TILE_SIZE

	var offsets := [Vector2i(0, 0), Vector2i(1, 0)]
	var arrows := [
		{"offset": Vector2i(0, 0), "dir": "W"},
		{"offset": Vector2i(1, 0), "dir": "E"},
	]

	for rot in [0, 90, 180, 270]:
		for ly in range(1, MapUtils.TILE_SIZE - 1):
			for lx in range(1, MapUtils.TILE_SIZE - 2):
				var anchor := tile_world_min + Vector2i(lx, ly)

				# footprint cells：必须全部在 tile 内且为空
				var ok_cells := true
				var piece_cells: Array[Vector2i] = []
				for off in offsets:
					var wp := anchor + MapUtils.rotate_offset(off, rot)
					var tinfo: Dictionary = MapUtils.world_to_tile(wp)
					if not (tinfo.get("board_pos", null) is Vector2i) or Vector2i(tinfo["board_pos"]) != board_pos:
						ok_cells = false
						break
					if not CoordsClass.is_world_pos_in_grid(state, wp):
						ok_cells = false
						break
					var cell: Dictionary = CellsClass.get_cell(state, wp)
					if bool(cell.get("blocked", false)):
						ok_cells = false
						break
					var s_val = cell.get("structure", null)
					if s_val is Dictionary and not (s_val as Dictionary).is_empty():
						ok_cells = false
						break
					piece_cells.append(wp)
				if not ok_cells:
					continue

				# arrows：需要至少一个 endpoint 在 tile 内且为空（用于注入 restaurant）
				for a in arrows:
					var off2: Vector2i = a["offset"]
					var dir: String = str(a["dir"])
					var from := anchor + MapUtils.rotate_offset(off2, rot)
					var to: Vector2i = from + Vector2i(MapUtils.DIR_OFFSETS.get(MapUtils.rotate_dir(dir, rot), Vector2i.ZERO))
					var tinfo2: Dictionary = MapUtils.world_to_tile(to)
					if not (tinfo2.get("board_pos", null) is Vector2i) or Vector2i(tinfo2["board_pos"]) != board_pos:
						continue
					if not CoordsClass.is_world_pos_in_grid(state, to):
						continue
					var cell2: Dictionary = CellsClass.get_cell(state, to)
					if bool(cell2.get("blocked", false)):
						continue
					var s2_val = cell2.get("structure", null)
					if s2_val is Dictionary and not (s2_val as Dictionary).is_empty():
						continue
					# Ensure endpoint has no road segments (we want "restaurant only" connection).
					var rs_val = cell2.get("road_segments", null)
					if rs_val is Array and not (rs_val as Array).is_empty():
						continue
					return Result.success({"anchor": anchor, "rotation": rot, "endpoint": to})

	return Result.failure("未找到可用的 road_straight 放置点用于箭头连接测试（tile=%s）" % str(board_pos))

static func _force_player0_ready_for_lobbyists(state: GameState) -> void:
	state.phase = DefsClass.PHASE_WORKING
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
