class_name ResolveFirstCoffeeSoldBonusCoffeeShopAction
extends ActionExecutor

const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const PIECE_ID := "coffee_shop"
const PENDING_TASK_KIND := "coffee_first_coffee_sold_bonus_coffee_shop"

func _init() -> void:
	action_id = "resolve_first_coffee_sold_bonus_coffee_shop"
	display_name = "首杯咖啡：额外咖啡店"
	description = "触发“首个卖出咖啡”里程碑后，在 Cleanup 按顺位放置/移动 1 个咖啡店"
	requires_actor = true
	is_mandatory = true
	ui_hide_if_not_initiatable = true
	allowed_phases = [DefsClass.PHASE_CLEANUP]
	allowed_sub_phases = []

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if str(state.phase) != DefsClass.PHASE_CLEANUP:
		return Result.failure("仅可在 Cleanup 阶段执行")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("state.players 类型错误（期望 Array）")
	if command.actor != state.get_current_player_id():
		return Result.failure("不是你的回合")

	var pending_read := _get_pending_cleanup_tasks(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array[Dictionary] = pending_read.value
	if pending.is_empty():
		return Result.failure("当前没有待处理的“首杯咖啡额外咖啡店”")

	var first: Dictionary = pending[0]
	if str(first.get("kind", "")) != PENDING_TASK_KIND:
		return Result.failure("当前待处理动作不是“首杯咖啡额外咖啡店”")
	if int(first.get("player_id", -1)) != int(command.actor):
		return Result.failure("请等待玩家 %d 处理首杯咖啡奖励" % int(first.get("player_id", -1)))

	var mode_read := require_string_param(command, "mode")
	if not mode_read.ok:
		return mode_read
	var mode: String = str(mode_read.value)
	if mode != "place" and mode != "move":
		return Result.failure("mode 非法（期望 place/move）: %s" % mode)

	var player_read := PlayerStateAccessClass.require_player(state, command.actor, action_id)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var tokens_remaining_read := PlayerStateAccessClass.require_int_field(player, "coffee_shop_tokens_remaining", "player[%d]" % command.actor, action_id)
	if not tokens_remaining_read.ok:
		return Result.failure("coffee_shop_tokens_remaining 缺失或类型错误（模块未正确初始化）")
	var tokens_remaining: int = int(tokens_remaining_read.value)

	if mode == "place" and tokens_remaining <= 0:
		return Result.failure("咖啡店 token 已用尽，不能放置新的咖啡店（请改为 move）")
	if mode == "move" and tokens_remaining > 0:
		return Result.failure("仍有咖啡店 token，不能移动已有咖啡店（请改为 place）")

	var pos_read := require_vector2i_param(command, "position")
	if not pos_read.ok:
		return pos_read
	var world_anchor: Vector2i = pos_read.value

	var from_shop_id := ""
	if mode == "move":
		var from_read := require_string_param(command, "from_shop_id")
		if not from_read.ok:
			return from_read
		from_shop_id = str(from_read.value)
		if from_shop_id.is_empty():
			return Result.failure("from_shop_id 不能为空")
		var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", "resolve_first_coffee_sold_bonus_coffee_shop")
		if not shops_read.ok:
			return Result.failure("state.map.coffee_shops 缺失或类型错误")
		var shops: Dictionary = shops_read.value
		if not shops.has(from_shop_id) or not (shops[from_shop_id] is Dictionary):
			return Result.failure("咖啡店不存在: %s" % from_shop_id)
		var shop: Dictionary = shops[from_shop_id]
		if int(shop.get("owner", -1)) != command.actor:
			return Result.failure("只能移动自己的咖啡店: %s" % from_shop_id)

	var validate_result := _validate_coffee_shop_placement(state, world_anchor)
	if not validate_result.ok:
		return validate_result

	var tile_check := _validate_tile_has_no_other_shop(state, world_anchor, from_shop_id)
	if not tile_check.ok:
		return tile_check

	return Result.success({
		"mode": mode,
		"position": world_anchor,
		"from_shop_id": from_shop_id,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value

	var mode: String = str(info.get("mode", ""))

	var player_id: int = command.actor
	var player_read := PlayerStateAccessClass.require_player(state, player_id, action_id)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", action_id)
	if not shops_read.ok:
		return shops_read
	var shops: Dictionary = shops_read.value

	var world_anchor: Vector2i = info.get("position", Vector2i.ZERO)
	var shop_id := ""
	var old_anchor: Vector2i = Vector2i.ZERO

	if mode == "place":
		var tokens_remaining_read := PlayerStateAccessClass.require_int_field(player, "coffee_shop_tokens_remaining", "player[%d]" % player_id, action_id)
		if not tokens_remaining_read.ok:
			return tokens_remaining_read
		var tokens_remaining: int = int(tokens_remaining_read.value)
		assert(tokens_remaining > 0, "coffee: token 用尽时不应走到 place")
		var next_shop_id_read := MapStateAccessClass.require_int_field(state, "next_coffee_shop_id", action_id)
		if not next_shop_id_read.ok:
			return next_shop_id_read
		var next_shop_id: int = int(next_shop_id_read.value)
		shop_id = "coffee_shop_%d" % next_shop_id
		state.map["next_coffee_shop_id"] = next_shop_id + 1
		player["coffee_shop_tokens_remaining"] = tokens_remaining - 1
	else:
		shop_id = str(info.get("from_shop_id", ""))
		var shop: Dictionary = shops[shop_id]
		old_anchor = shop["anchor_pos"]
		_clear_structure_cell(state, old_anchor)

	_write_structure_cell(state, world_anchor, player_id, shop_id)

	shops[shop_id] = {
		"shop_id": shop_id,
		"owner": player_id,
		"anchor_pos": world_anchor,
		"entrance_pos": world_anchor,
	}
	state.map["coffee_shops"] = shops
	state.players[player_id] = player

	return _consume_pending(state, {
		"player_id": player_id,
		"mode": mode,
		"shop_id": shop_id,
		"position": world_anchor,
		"from_position": old_anchor,
	})

static func _get_pending_cleanup_tasks(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val == null:
		return Result.success([] as Array[Dictionary])
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(DefsClass.PHASE_CLEANUP):
		return Result.success([] as Array[Dictionary])
	var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return Result.failure("pending_phase_actions[Cleanup] 类型错误（期望 Array）")
	var list: Array = list_val

	var out: Array[Dictionary] = []
	for i in range(list.size()):
		var v = list[i]
		if not (v is Dictionary):
			return Result.failure("pending_phase_actions[Cleanup][%d] 类型错误（期望 Dictionary）" % i)
		var d: Dictionary = v
		out.append(d)
	return Result.success(out)

static func _consume_pending(state: GameState, payload: Dictionary) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("state/round_state 无效")
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 缺失或类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return Result.failure("pending_phase_actions[Cleanup] 缺失或类型错误（期望 Array）")
	var list: Array = list_val
	if list.is_empty():
		return Result.failure("pending_phase_actions[Cleanup] 为空")
	list.remove_at(0)
	if list.is_empty():
		ppa.erase(DefsClass.PHASE_CLEANUP)
	else:
		ppa[DefsClass.PHASE_CLEANUP] = list
	rs["pending_phase_actions"] = ppa

	if not list.is_empty():
		var next_first = list[0]
		if next_first is Dictionary:
			var next_pid: int = int(Dictionary(next_first).get("player_id", -1))
			for idx in range(state.turn_order.size()):
				if int(state.turn_order[idx]) == next_pid:
					state.current_player_index = idx
					break

	return Result.success(payload)

static func _validate_tile_has_no_other_shop(state: GameState, world_anchor: Vector2i, ignore_shop_id: String) -> Result:
	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", "resolve_first_coffee_sold_bonus_coffee_shop")
	if not shops_read.ok:
		return Result.failure("state.map.coffee_shops 缺失或类型错误")
	var shops: Dictionary = shops_read.value
	var target_board: Vector2i = MapUtilsClass.world_to_tile(world_anchor).board_pos

	for sid_val in shops.keys():
		var sid: String = str(sid_val)
		if sid.is_empty() or sid == ignore_shop_id:
			continue
		var shop_val = shops[sid_val]
		if not (shop_val is Dictionary):
			continue
		var shop: Dictionary = shop_val
		var pos_val = shop.get("anchor_pos", null)
		if not (pos_val is Vector2i):
			continue
		var board: Vector2i = MapUtilsClass.world_to_tile(pos_val).board_pos
		if board == target_board:
			return Result.failure("每个 tile 只能有 1 个咖啡店（该 tile 已有咖啡店）")
	return Result.success()

static func _validate_coffee_shop_placement(state: GameState, world_anchor: Vector2i) -> Result:
	if not PieceRegistryClass.is_loaded():
		return Result.failure("PieceRegistry 未初始化")
	var piece_defs: Dictionary = PieceRegistryClass.get_all_defs()
	if piece_defs.is_empty() or not piece_defs.has(PIECE_ID):
		return Result.failure("缺少 PieceDef: %s" % PIECE_ID)

	var map_ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": CoordsClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var r := PlacementClass.validate_placement(map_ctx, PIECE_ID, world_anchor, 0, piece_defs, {})
	if not r.ok:
		return r
	return Result.success()

static func _write_structure_cell(state: GameState, world_anchor: Vector2i, owner: int, shop_id: String) -> void:
	var idx := CoordsClass.world_to_index(state, world_anchor)
	state.map.cells[idx.y][idx.x]["structure"] = {
		"piece_id": PIECE_ID,
		"owner": owner,
		"shop_id": shop_id,
		"anchor_cell": true,
		"parent_anchor": world_anchor,
		"rotation": 0,
		"dynamic": true
	}

static func _clear_structure_cell(state: GameState, world_anchor: Vector2i) -> void:
	var idx := CoordsClass.world_to_index(state, world_anchor)
	state.map.cells[idx.y][idx.x]["structure"] = {}
