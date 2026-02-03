class_name PlaceLobbyistsExtraMapTileAction
extends ActionExecutor

const TileEditClass = preload("res://core/map/map_runtime/tile_edit.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")

const MODULE_ID := "lobbyists"
const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"
const EXTRA_TILE_LAST_PLACED_KEY := "lobbyists_extra_tile_last_placed"

func _init() -> void:
	action_id = "place_lobbyists_extra_map_tile"
	display_name = "说客里程碑：扩边放置地图板块"
	description = "消耗 First Lobbyist Used 的奖励：从剩余 tile 中选择并在边缘扩边放置"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Lobbyists"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has(EXTRA_TILE_PENDING_KEY) or not (state.round_state[EXTRA_TILE_PENDING_KEY] is Dictionary):
		return Result.failure("当前没有可放置的额外地图板块")
	var pending: Dictionary = state.round_state[EXTRA_TILE_PENDING_KEY]
	if not (pending.get(command.actor, false) is bool) or not bool(pending.get(command.actor, false)):
		return Result.failure("当前没有可放置的额外地图板块")

	if not TileRegistryClass.is_loaded():
		return Result.failure("TileRegistry 未初始化")
	if not PieceRegistryClass.is_loaded():
		return Result.failure("PieceRegistry 未初始化")

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("tile_supply_remaining") or not (state.map["tile_supply_remaining"] is Array):
		return Result.failure("state.map.tile_supply_remaining 缺失或类型错误（期望 Array[String]）")
	var remaining_any: Array = state.map["tile_supply_remaining"]
	var remaining: Array[String] = []
	for i in range(remaining_any.size()):
		var v = remaining_any[i]
		if not (v is String) or str(v).is_empty():
			return Result.failure("tile_supply_remaining[%d] 类型错误（期望非空 String）" % i)
		remaining.append(str(v))

	var tile_id_read := require_string_param(command, "tile_id")
	if not tile_id_read.ok:
		return tile_id_read
	var tile_id: String = tile_id_read.value
	if remaining.find(tile_id) == -1:
		return Result.failure("tile 不在剩余池中: %s" % tile_id)

	if TileRegistryClass.get_def(tile_id) == null:
		return Result.failure("未知 tile: %s" % tile_id)

	var attach_read := require_vector2i_param(command, "attach_to_tile_board_pos")
	if not attach_read.ok:
		return attach_read
	var attach_board_pos: Vector2i = attach_read.value

	var side_read := require_string_param(command, "side")
	if not side_read.ok:
		return side_read
	var side: String = side_read.value
	if side != "N" and side != "E" and side != "S" and side != "W":
		return Result.failure("无效的 side: %s" % side)

	var rotation_read := optional_int_param(command, "rotation", 0)
	if not rotation_read.ok:
		return rotation_read
	var rotation: int = int(rotation_read.value)
	if rotation != 0 and rotation != 90 and rotation != 180 and rotation != 270:
		return Result.failure("rotation 非法: %d" % rotation)

	var new_pos_read := _validate_extra_tile_position(state, attach_board_pos, side)
	if not new_pos_read.ok:
		return new_pos_read
	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var tile_id: String = require_string_param(command, "tile_id").value
	var attach_board_pos: Vector2i = require_vector2i_param(command, "attach_to_tile_board_pos").value
	var side: String = require_string_param(command, "side").value
	var rotation: int = int(optional_int_param(command, "rotation", 0).value)

	var new_board_pos: Vector2i = _offset_for_side(side) + attach_board_pos

	var tile_def: TileDef = TileRegistryClass.get_def(tile_id)
	var piece_registry := PieceRegistryClass.get_all_defs()
	var add := TileEditClass.add_map_tile(state, tile_def, piece_registry, new_board_pos, rotation)
	if not add.ok:
		return add

	# 消耗 tile supply（不放回）
	var remaining_any: Array = state.map["tile_supply_remaining"]
	var remaining: Array = []
	for v in remaining_any:
		if str(v) != tile_id:
			remaining.append(v)
	state.map["tile_supply_remaining"] = remaining

	# 清理 pending
	var pending: Dictionary = state.round_state[EXTRA_TILE_PENDING_KEY]
	pending[player_id] = false
	state.round_state[EXTRA_TILE_PENDING_KEY] = pending

	# 记录本回合本玩家“通过里程碑扩边”放置的 tile（用于允许在新 tile 上放公园/道路不受 range 限制）。
	if state.round_state is Dictionary:
		var last_val = state.round_state.get(EXTRA_TILE_LAST_PLACED_KEY, null)
		var last: Array = []
		if last_val is Array:
			last = last_val
		else:
			for i in range(state.players.size()):
				last.append(null)
		while last.size() < state.players.size():
			last.append(null)
		last[player_id] = [new_board_pos.x, new_board_pos.y]
		state.round_state[EXTRA_TILE_LAST_PLACED_KEY] = last

	return Result.success({
		"player_id": player_id,
		"tile_id": tile_id,
		"board_pos": new_board_pos,
		"rotation": rotation,
	})

func _validate_extra_tile_position(state: GameState, attach_board_pos: Vector2i, side: String) -> Result:
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")

	var occupied: Dictionary = {}
	var placements: Array = []
	if state.map.has("tile_placements") and (state.map["tile_placements"] is Array):
		placements.append_array(state.map["tile_placements"])
	if state.map.has("external_tile_placements") and (state.map["external_tile_placements"] is Array):
		placements.append_array(state.map["external_tile_placements"])
	for i in range(placements.size()):
		var p_val = placements[i]
		if not (p_val is Dictionary):
			return Result.failure("tile_placements[%d] 类型错误（期望 Dictionary）" % i)
		var p: Dictionary = p_val
		var bp_val = p.get("board_pos", null)
		if not (bp_val is Vector2i):
			return Result.failure("tile_placements[%d].board_pos 类型错误（期望 Vector2i）" % i)
		var bp: Vector2i = bp_val
		occupied["%d,%d" % [bp.x, bp.y]] = true

	var attach_key := "%d,%d" % [attach_board_pos.x, attach_board_pos.y]
	if not occupied.has(attach_key):
		return Result.failure("attach_to_tile_board_pos 不存在: %s" % str(attach_board_pos))

	var new_pos: Vector2i = attach_board_pos + _offset_for_side(side)
	var new_key := "%d,%d" % [new_pos.x, new_pos.y]
	if occupied.has(new_key):
		return Result.failure("目标位置已存在 tile: %s" % str(new_pos))

	# 禁止在“包含 airplane/offramp 的边缘段”扩边
	var conflict := _check_edge_conflicts(state, attach_board_pos, side)
	if not conflict.ok:
		return conflict

	return Result.success(new_pos)

func _check_edge_conflicts(state: GameState, attach_board_pos: Vector2i, side: String) -> Result:
	# 规则书语义：airplane / highway offramp 都在棋盘外侧，
	# 若本次扩边的 tile 覆盖到它们占用的棋盘外区域，则禁止扩边。
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")

	var tile_size := int(MapUtilsClass.TILE_SIZE)
	if tile_size <= 0:
		return Result.failure("MapUtils.TILE_SIZE 非法: %d" % tile_size)

	var new_board_pos := attach_board_pos + _offset_for_side(side)
	var new_world_min := new_board_pos * tile_size
	var new_world_size := Vector2i(tile_size, tile_size)

	# 1) external_cells：覆盖到任意棋盘外组件（例如 offramp）即冲突。
	var ext_val = state.map.get("external_cells", null)
	if ext_val != null and not (ext_val is Dictionary):
		return Result.failure("state.map.external_cells 类型错误（期望 Dictionary）")
	var external_cells: Dictionary = ext_val if (ext_val is Dictionary) else {}

	for dy in range(tile_size):
		for dx in range(tile_size):
			var wp := new_world_min + Vector2i(dx, dy)
			var key := "%d,%d" % [wp.x, wp.y]
			if not external_cells.has(key):
				continue
			var cell_val = external_cells.get(key, null)
			if cell_val is Dictionary:
				var s_val = (cell_val as Dictionary).get("structure", null)
				if s_val is Dictionary and str((s_val as Dictionary).get("piece_id", "")) == "highway_offramp":
					return Result.failure("该边缘包含 offramp，禁止扩边: %s" % str(side))
			return Result.failure("该边缘包含棋盘外组件，禁止扩边: %s" % str(side))

	# 2) airplane：其占用区域在棋盘外，需要根据 placement 推导出棋盘外占用矩形。
	var mp_val = state.map.get("marketing_placements", null)
	if mp_val == null:
		return Result.success()
	if not (mp_val is Dictionary):
		return Result.failure("state.map.marketing_placements 类型错误（期望 Dictionary）")
	var placements: Dictionary = mp_val

	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("state.map.marketing_placements[%s] 类型错误（期望 Dictionary）" % str(k))
		var p: Dictionary = p_val
		if str(p.get("type", "")) != "airplane":
			continue

		var wp_val = p.get("world_pos", null)
		if not (wp_val is Vector2i):
			return Result.failure("state.map.marketing_placements[%s].world_pos 类型错误（期望 Vector2i）" % str(k))
		var anchor: Vector2i = wp_val

		var axis := str(p.get("axis", "")).strip_edges()
		if axis != "row" and axis != "col":
			# Fallback inference for older data.
			if anchor.x == minp.x or anchor.x == maxp.x:
				axis = "row"
			elif anchor.y == minp.y or anchor.y == maxp.y:
				axis = "col"
			else:
				continue

		var fs_read := _read_marketing_footprint_size(p, "state.map.marketing_placements[%s]" % str(k))
		if not fs_read.ok:
			return fs_read
		var base_size: Vector2i = fs_read.value
		if base_size.x <= 0 or base_size.y <= 0:
			continue

		var thickness := 2
		var length := 0
		if base_size.x == 2 and base_size.y != 2:
			length = base_size.y
		elif base_size.y == 2 and base_size.x != 2:
			length = base_size.x
		else:
			thickness = mini(base_size.x, base_size.y)
			length = maxi(base_size.x, base_size.y)
		if thickness <= 0 or length <= 0:
			continue

		# Axis determines oriented size (length along edge, thickness outward).
		var size := Vector2i.ZERO
		if axis == "row":
			size = Vector2i(maxi(1, thickness), maxi(1, length))
		else:
			size = Vector2i(maxi(1, length), maxi(1, thickness))

		var attach := ""
		if axis == "row":
			if anchor.x == minp.x:
				attach = "left"
			elif anchor.x >= maxp.x - 1:
				attach = "right"
		else:
			if anchor.y == minp.y:
				attach = "top"
			elif anchor.y >= maxp.y - 1:
				attach = "bottom"
		if attach.is_empty():
			continue

		var offset := Vector2i.ZERO
		match attach:
			"left":
				offset = Vector2i(-size.x, 0)
			"right":
				offset = Vector2i(1, 0)
			"top":
				offset = Vector2i(0, -size.y)
			"bottom":
				offset = Vector2i(0, 1)
		var outside_anchor := anchor + offset

		if _rects_intersect(outside_anchor, size, new_world_min, new_world_size):
			return Result.failure("该边缘包含 airplane，禁止扩边: %s" % str(side))

	return Result.success()

func _read_marketing_footprint_size(p: Dictionary, path: String) -> Result:
	var fs_val = p.get("footprint_size", null)
	if fs_val is Vector2i:
		return Result.success(Vector2i(fs_val))
	if fs_val is Array:
		var arr: Array = fs_val
		if arr.size() != 2:
			return Result.failure("%s.footprint_size 长度错误（期望 2），实际: %d" % [path, arr.size()])
		var w_val = arr[0]
		var h_val = arr[1]
		if not (w_val is int or w_val is float) or not (h_val is int or h_val is float):
			return Result.failure("%s.footprint_size 类型错误（期望 [int,int]）" % path)
		var w := int(w_val)
		var h := int(h_val)
		if float(w_val) != float(w) or float(h_val) != float(h):
			return Result.failure("%s.footprint_size 必须为整数，实际: %s" % [path, str(fs_val)])
		return Result.success(Vector2i(w, h))
	return Result.success(Vector2i.ONE)

func _rects_intersect(a_pos: Vector2i, a_size: Vector2i, b_pos: Vector2i, b_size: Vector2i) -> bool:
	if a_size.x <= 0 or a_size.y <= 0 or b_size.x <= 0 or b_size.y <= 0:
		return false
	var a_right := a_pos.x + a_size.x
	var a_bottom := a_pos.y + a_size.y
	var b_right := b_pos.x + b_size.x
	var b_bottom := b_pos.y + b_size.y
	return not (
		a_right <= b_pos.x
		or b_right <= a_pos.x
		or a_bottom <= b_pos.y
		or b_bottom <= a_pos.y
	)

func _offset_for_side(side: String) -> Vector2i:
	if side == "N":
		return Vector2i(0, -1)
	if side == "S":
		return Vector2i(0, 1)
	if side == "W":
		return Vector2i(-1, 0)
	return Vector2i(1, 0)
