class_name PlaceHighwayOfframpAction
extends ActionExecutor

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

const MODULE_ID := "rural_marketeers"
const OFFRAMP_PENDING_KEY := "rural_marketeers_offramp_pending"
const OFFRAMP_PIECE_ID := "highway_offramp"
const OFFRAMP_PLACEMENTS_KEY := "rural_marketeers_offramps"

const SIDES: Array[String] = ["N", "E", "S", "W"]

func _init() -> void:
	action_id = "place_highway_offramp"
	display_name = "放置高速公路出口"
	description = "放置一个棋盘外的高速公路出口（offramp），必须连接到道路"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has(OFFRAMP_PENDING_KEY):
		return Result.failure("当前没有可放置的 offramp")
	var pending_val = state.round_state[OFFRAMP_PENDING_KEY]
	if not (pending_val is Dictionary):
		return Result.failure("%s: round_state.%s 类型错误（期望 Dictionary）" % [MODULE_ID, OFFRAMP_PENDING_KEY])
	var pending: Dictionary = pending_val
	if not (pending.get(command.actor, false) is bool) or not bool(pending.get(command.actor, false)):
		return Result.failure("当前没有可放置的 offramp")

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("state.map.grid_size 缺失或类型错误")
	if not state.map.has("tile_grid_size") or not (state.map["tile_grid_size"] is Vector2i):
		return Result.failure("state.map.tile_grid_size 缺失或类型错误")
	var grid_size: Vector2i = state.map["grid_size"]
	var tile_grid_size: Vector2i = state.map["tile_grid_size"]

	if not (command.params is Dictionary):
		return Result.failure("command.params 类型错误（期望 Dictionary）")
	if not command.params.has("position"):
		return Result.failure("缺少参数: position")
	var pos_val = command.params.get("position", null)
	if not (pos_val is Array) or (pos_val as Array).size() != 2:
		return Result.failure("position 格式错误（期望 [x,y]）")
	var arr: Array = pos_val
	var x_read := _parse_int_value(arr[0], "position[0]")
	if not x_read.ok:
		return x_read
	var y_read := _parse_int_value(arr[1], "position[1]")
	if not y_read.ok:
		return y_read
	var connect_pos := Vector2i(int(x_read.value), int(y_read.value))
	if not MapRuntimeClass.is_world_pos_in_grid(state, connect_pos):
		return Result.failure("position 越界: %s" % str(connect_pos))
	if not MapRuntimeClass.is_on_map_edge(state, connect_pos):
		return Result.failure("offramp 必须放置在地图边缘格子: %s" % str(connect_pos))

	# 根据边缘位置与“向外道路段”推断 side（角落若有多个 outward dirs 则判定为歧义）
	var side_read := _infer_side_from_edge_and_road(state, connect_pos)
	if not side_read.ok:
		return side_read
	var side: String = str(side_read.value)

	# 同一连接格子不能重复放置 offramp
	if has_offramp_at_pos(state, connect_pos):
		return Result.failure("该边缘格子已存在 offramp: %s" % str(connect_pos))

	# 与 airplane 冲突：同一边缘格子不可同时放置
	if _has_airplane_at_pos(state, connect_pos):
		return Result.failure("offramp 不能放置在已有飞机营销的格子: %s" % str(connect_pos))

	# 必须连接到地图内道路：连接格子必须存在“朝外”的道路段
	var dirs := _get_road_dirs_at(state, connect_pos)
	if dirs.is_empty():
		return Result.failure("offramp 必须连接到道路（连接格不是道路）: %s" % str(connect_pos))
	var outward_dir := _outward_dir_for_side(side)
	if not dirs.has(outward_dir):
		return Result.failure("offramp 必须连接到道路（连接格缺少朝外道路段）: %s side=%s" % [str(connect_pos), side])
	if dirs.size() < 2:
		return Result.failure("offramp 必须连接到地图内道路（连接格道路必须同时连接至少一个内部方向）: %s" % str(connect_pos))

	# 外部占用格子必须不冲突
	var occupied := _get_external_cells_for_piece(connect_pos, side)
	for i in range(occupied.size()):
		var p: Vector2i = occupied[i]
		if MapRuntimeClass.is_world_pos_in_grid(state, p):
			return Result.failure("内部错误：offramp 外部格计算错误（不应落在棋盘内）: %s" % str(p))
		if state.map.has("external_cells") and (state.map["external_cells"] is Dictionary):
			var key := "%d,%d" % [p.x, p.y]
			if (state.map["external_cells"] as Dictionary).has(key):
				return Result.failure("offramp 与已有棋盘外组件冲突: %s" % key)

	return Result.success({
		"piece_id": OFFRAMP_PIECE_ID,
		"position": connect_pos,
		"side": side,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value
	var connect_pos: Vector2i = info["position"]
	var side: String = str(info["side"])

	var apply := _apply_external_offramp_piece(state, int(command.actor), connect_pos, side)
	if not apply.ok:
		return apply

	var pending: Dictionary = state.round_state[OFFRAMP_PENDING_KEY]
	pending[command.actor] = false
	state.round_state[OFFRAMP_PENDING_KEY] = pending

	MapRuntimeClass.invalidate_road_graph(state)

	return Result.success({
		"player_id": int(command.actor),
		"piece_id": OFFRAMP_PIECE_ID,
		"position": connect_pos,
		"side": side,
	})

static func get_offramp_connection_cells(state: GameState) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("get_offramp_connection_cells: state.map 类型错误")
	if not state.map.has(OFFRAMP_PLACEMENTS_KEY):
		return Result.success([])
	var v = state.map.get(OFFRAMP_PLACEMENTS_KEY, null)
	if not (v is Array):
		return Result.failure("get_offramp_connection_cells: state.map.%s 类型错误（期望 Array）" % OFFRAMP_PLACEMENTS_KEY)
	var placements: Array = v
	var out: Array[Vector2i] = []
	for i in range(placements.size()):
		var p_val = placements[i]
		if not (p_val is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [OFFRAMP_PLACEMENTS_KEY, i])
		var p: Dictionary = p_val
		if not (p.get("pos", null) is Vector2i):
			return Result.failure("%s[%d].pos 类型错误（期望 Vector2i）" % [OFFRAMP_PLACEMENTS_KEY, i])
		out.append(p["pos"])
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return Result.success(out)

func _apply_external_offramp_piece(state: GameState, owner_id: int, connect_pos: Vector2i, side: String) -> Result:
	if not state.map.has("external_cells") or not (state.map["external_cells"] is Dictionary):
		return Result.failure("state.map.external_cells 缺失或类型错误（期望 Dictionary）")
	if not state.map.has(OFFRAMP_PLACEMENTS_KEY):
		state.map[OFFRAMP_PLACEMENTS_KEY] = []
	if not (state.map[OFFRAMP_PLACEMENTS_KEY] is Array):
		return Result.failure("state.map.%s 类型错误（期望 Array）" % OFFRAMP_PLACEMENTS_KEY)

	var external_cells: Dictionary = state.map["external_cells"]
	var placements: Array = state.map[OFFRAMP_PLACEMENTS_KEY]

	var occupied := _get_external_cells_for_piece(connect_pos, side)
	for i in range(occupied.size()):
		var p: Vector2i = occupied[i]
		var key := "%d,%d" % [p.x, p.y]
		if external_cells.has(key):
			return Result.failure("offramp 与已有棋盘外组件冲突: %s" % key)

	# 写入 external_cells：在棋盘外造一段“引出道路”
	var outward := _outward_dir_for_side(side)
	var inward := MapUtilsClass.get_opposite_dir(outward)
	var rotation := _rotation_for_side(side)
	for i in range(occupied.size()):
		var p2: Vector2i = occupied[i]
		var key2 := "%d,%d" % [p2.x, p2.y]
		var cell2 := _create_empty_cell(Vector2i(-1, -1))
		if i == 0:
			cell2["road_segments"] = [{"dirs": [inward, outward], "bridge": false}]
		else:
			cell2["road_segments"] = [{"dirs": [inward], "bridge": false}]
		cell2["structure"] = {
			"piece_id": OFFRAMP_PIECE_ID,
			"owner": owner_id,
			"rotation": rotation,
		}
		external_cells[key2] = cell2

	placements.append({
		"pos": connect_pos,
		"side": side,
		"owner": owner_id,
		"rotation": rotation,
		"occupied": occupied,
	})

	state.map["external_cells"] = external_cells
	state.map[OFFRAMP_PLACEMENTS_KEY] = placements
	return Result.success()

static func _create_empty_cell(tile_origin: Vector2i) -> Dictionary:
	return {
		"road_segments": [],
		"structure": {},
		"terrain_type": null,
		"drink_source": null,
		"tile_origin": tile_origin,
		"blocked": false
	}

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _infer_side_from_edge_and_road(state: GameState, pos: Vector2i) -> Result:
	var candidates: Array[String] = []
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	if pos.y == minp.y:
		candidates.append("N")
	if pos.y == maxp.y:
		candidates.append("S")
	if pos.x == minp.x:
		candidates.append("W")
	if pos.x == maxp.x:
		candidates.append("E")
	if candidates.is_empty():
		return Result.failure("内部错误：position 不在边缘: %s" % str(pos))

	var outward: Array[String] = []
	for side in candidates:
		if _get_road_dirs_at(state, pos).has(_outward_dir_for_side(side)):
			outward.append(side)
	if outward.size() == 1:
		return Result.success(outward[0])
	if outward.is_empty():
		return Result.failure("连接格没有朝外道路段，无法确定 offramp 朝向: %s" % str(pos))
	outward.sort()
	return Result.failure("连接格存在多个朝外道路段（角落歧义），无法确定 offramp 朝向: %s candidates=%s" % [str(pos), str(outward)])

static func _outward_dir_for_side(side: String) -> String:
	if side == "N":
		return "N"
	if side == "S":
		return "S"
	if side == "W":
		return "W"
	if side == "E":
		return "E"
	return ""

static func _rotation_for_side(side: String) -> int:
	if side == "N":
		return 0
	if side == "E":
		return 90
	if side == "S":
		return 180
	if side == "W":
		return 270
	return 0

static func _get_external_cells_for_piece(connect_pos: Vector2i, side: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir := _outward_dir_for_side(side)
	var d: Vector2i = MapUtilsClass.DIR_OFFSETS.get(dir, Vector2i.ZERO)
	out.append(connect_pos + d)
	out.append(connect_pos + d * 2)
	return out

static func _get_road_dirs_at(state: GameState, pos: Vector2i) -> Array[String]:
	if state == null or not (state.map is Dictionary):
		return []
	if not MapRuntimeClass.is_world_pos_in_grid(state, pos):
		return []
	var cell: Dictionary = MapRuntimeClass.get_cell(state, pos)
	var segs: Array = cell.get("road_segments", [])
	if segs.is_empty():
		return []
	var set := {}
	for s in segs:
		if not (s is Dictionary):
			continue
		var dirs_val = s.get("dirs", [])
		if not (dirs_val is Array):
			continue
		for d in dirs_val:
			if d is String and not str(d).is_empty():
				set[str(d)] = true
	var out: Array[String] = []
	for k in set.keys():
		out.append(str(k))
	out.sort()
	return out

static func _has_airplane_at_pos(state: GameState, pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return false
	var placements: Dictionary = state.map["marketing_placements"]
	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		if str(p.get("type", "")) != "airplane":
			continue
		var wp = p.get("world_pos", null)
		if wp is Vector2i and wp == pos:
			return true
	return false

static func has_offramp_at_pos(state: GameState, pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	if not state.map.has(OFFRAMP_PLACEMENTS_KEY):
		return false
	var v = state.map.get(OFFRAMP_PLACEMENTS_KEY, null)
	if not (v is Array):
		return false
	var placements: Array = v
	for i in range(placements.size()):
		var p_val = placements[i]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var wp = p.get("pos", null)
		if wp is Vector2i and wp == pos:
			return true
	return false
