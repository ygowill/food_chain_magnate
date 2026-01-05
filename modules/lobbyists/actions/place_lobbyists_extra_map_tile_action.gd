class_name PlaceLobbyistsExtraMapTileAction
extends ActionExecutor

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")

const MODULE_ID := "lobbyists"
const EXTRA_TILE_PENDING_KEY := "lobbyists_extra_tile_pending"

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
	var add := MapRuntimeClass.add_map_tile(state, tile_def, piece_registry, new_board_pos, rotation)
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
	# 计算 attach tile 的该侧边缘 5 个世界格
	var edge_cells: Array[Vector2i] = []
	match side:
		"N":
			for lx in range(MapUtilsClass.TILE_SIZE):
				edge_cells.append(attach_board_pos * MapUtilsClass.TILE_SIZE + Vector2i(lx, 0))
		"S":
			for lx in range(MapUtilsClass.TILE_SIZE):
				edge_cells.append(attach_board_pos * MapUtilsClass.TILE_SIZE + Vector2i(lx, MapUtilsClass.TILE_SIZE - 1))
		"W":
			for ly in range(MapUtilsClass.TILE_SIZE):
				edge_cells.append(attach_board_pos * MapUtilsClass.TILE_SIZE + Vector2i(0, ly))
		"E":
			for ly in range(MapUtilsClass.TILE_SIZE):
				edge_cells.append(attach_board_pos * MapUtilsClass.TILE_SIZE + Vector2i(MapUtilsClass.TILE_SIZE - 1, ly))

	# airplane
	if state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var mp: Dictionary = state.map["marketing_placements"]
		for k in mp.keys():
			var v = mp.get(k, null)
			if not (v is Dictionary):
				continue
			var d: Dictionary = v
			if str(d.get("type", "")) != "airplane":
				continue
			var wp = d.get("world_pos", null)
			if not (wp is Vector2i):
				continue
			if edge_cells.has(wp):
				return Result.failure("该边缘包含 airplane，禁止扩边: %s" % str(side))

	# offramp（若 rural_marketeers 模块存在，则其 connection cell 在 map 中）
	if state.map.has("rural_marketeers_offramps") and (state.map["rural_marketeers_offramps"] is Array):
		var arr: Array = state.map["rural_marketeers_offramps"]
		for i in range(arr.size()):
			var p_val = arr[i]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var pos_val = p.get("pos", null)
			if not (pos_val is Vector2i):
				continue
			if edge_cells.has(pos_val):
				return Result.failure("该边缘包含 offramp，禁止扩边: %s" % str(side))

	return Result.success()

func _offset_for_side(side: String) -> Vector2i:
	if side == "N":
		return Vector2i(0, -1)
	if side == "S":
		return Vector2i(0, 1)
	if side == "W":
		return Vector2i(-1, 0)
	return Vector2i(1, 0)

