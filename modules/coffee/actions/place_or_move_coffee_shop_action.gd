class_name PlaceOrMoveCoffeeShopAction
extends ActionExecutor

const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const MODULE_ID := "coffee"
const PIECE_ID := "coffee_shop"
const TRIGGER_TO_EMPLOYEES: Array[String] = ["barista", "lead_barista"]
const TRAIN_PLACEMENT_MAX_RANGE := 2

func _init() -> void:
	action_id = "place_or_move_coffee_shop"
	display_name = "放置/移动咖啡店"
	description = "在培训咖啡师后，放置或移动一个咖啡店"
	requires_actor = true
	is_mandatory = false
	ui_hide_if_not_initiatable = true
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Train"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.round_state is Dictionary):
		return Result.failure("round_state 未初始化")
	var total_triggers_read := _count_triggers_from_train_events(state.round_state, command.actor)
	if not total_triggers_read.ok:
		return total_triggers_read
	var total_triggers: int = int(total_triggers_read.value)
	var used_triggers_read := _get_used_triggers(state.round_state, command.actor)
	if not used_triggers_read.ok:
		return used_triggers_read
	var used_triggers: int = int(used_triggers_read.value)
	if used_triggers >= total_triggers:
		return Result.failure("当前没有可用的咖啡店放置/移动窗口（需要先培训咖啡师）")

	var player_read := PlayerStateAccessClass.require_player(state, command.actor, action_id)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value

	var tokens_remaining_read := PlayerStateAccessClass.require_int_field(player, "coffee_shop_tokens_remaining", "player[%d]" % command.actor, action_id)
	if not tokens_remaining_read.ok:
		return Result.failure("coffee_shop_tokens_remaining 缺失或类型错误（模块未正确初始化）")
	var tokens_remaining: int = int(tokens_remaining_read.value)

	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", action_id)
	if not shops_read.ok:
		return Result.failure("state.map.coffee_shops 缺失或类型错误（模块未正确初始化）")
	var shops: Dictionary = shops_read.value

	var mode_read := require_string_param(command, "mode")
	if not mode_read.ok:
		return mode_read
	var mode: String = str(mode_read.value)
	if mode != "place" and mode != "move":
		return Result.failure("mode 非法（期望 place/move）: %s" % mode)

	var pos_read := require_vector2i_param(command, "position")
	if not pos_read.ok:
		return pos_read
	var world_anchor: Vector2i = pos_read.value

	# 放置规则：
	# - token 用尽：只能 move
	# - token 仍有：只能 place（规则书未允许“用 move 代替 place”）
	if mode == "place" and tokens_remaining <= 0:
		return Result.failure("咖啡店 token 已用尽，必须移动已有咖啡店")
	if mode == "move" and tokens_remaining > 0:
		return Result.failure("仍有咖啡店 token，不能移动已有咖啡店（请放置新咖啡店）")

	var ignore_shop_id := ""
	if mode == "move":
		var from_read := require_string_param(command, "from_shop_id")
		if not from_read.ok:
			return from_read
		var from_shop_id: String = str(from_read.value)
		if from_shop_id.is_empty():
			return Result.failure("from_shop_id 不能为空")
		if not shops.has(from_shop_id) or not (shops[from_shop_id] is Dictionary):
			return Result.failure("咖啡店不存在: %s" % from_shop_id)
		var shop: Dictionary = shops[from_shop_id]
		if int(shop.get("owner", -1)) != command.actor:
			return Result.failure("只能移动自己的咖啡店: %s" % from_shop_id)
		ignore_shop_id = from_shop_id

	var validate_result := _validate_coffee_shop_placement(state, world_anchor)
	if not validate_result.ok:
		return validate_result

	var tile_check := _validate_tile_has_no_other_shop(state, world_anchor, ignore_shop_id)
	if not tile_check.ok:
		return tile_check

	var range_check := _validate_within_train_range(state, command.actor, world_anchor)
	if not range_check.ok:
		return range_check

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate

	var player_id: int = command.actor

	var mode_read := require_string_param(command, "mode")
	if not mode_read.ok:
		return mode_read
	var mode: String = str(mode_read.value)

	var pos_read := require_vector2i_param(command, "position")
	if not pos_read.ok:
		return pos_read
	var world_anchor: Vector2i = pos_read.value

	var validate_result := _validate_coffee_shop_placement(state, world_anchor)
	if not validate_result.ok:
		return validate_result

	var player_read := PlayerStateAccessClass.require_player(state, player_id, action_id)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", action_id)
	if not shops_read.ok:
		return shops_read
	var shops: Dictionary = shops_read.value

	var shop_id := ""
	var old_anchor: Vector2i = Vector2i.ZERO

	if mode == "place":
		var tokens_remaining_read := PlayerStateAccessClass.require_int_field(player, "coffee_shop_tokens_remaining", "player[%d]" % player_id, action_id)
		if not tokens_remaining_read.ok:
			return tokens_remaining_read
		var tokens_remaining: int = int(tokens_remaining_read.value)
		if tokens_remaining <= 0:
			return Result.failure("咖啡店 token 已用尽，必须移动已有咖啡店")
		var next_shop_id_read := MapStateAccessClass.require_int_field(state, "next_coffee_shop_id", action_id)
		if not next_shop_id_read.ok:
			return next_shop_id_read
		var next_shop_id: int = int(next_shop_id_read.value)
		shop_id = "coffee_shop_%d" % next_shop_id
		state.map["next_coffee_shop_id"] = next_shop_id + 1
		player["coffee_shop_tokens_remaining"] = tokens_remaining - 1
	else:
		var from_read := require_string_param(command, "from_shop_id")
		if not from_read.ok:
			return from_read
		shop_id = str(from_read.value)
		var shop: Dictionary = shops[shop_id]
		old_anchor = shop["anchor_pos"]
		_clear_structure_cell(state, old_anchor)

	# 写入结构
	_write_structure_cell(state, world_anchor, player_id, shop_id)

	# 写入/更新注册表
	shops[shop_id] = {
		"shop_id": shop_id,
		"owner": player_id,
		"anchor_pos": world_anchor,
		"entrance_pos": world_anchor,
	}
	state.map["coffee_shops"] = shops
	state.players[player_id] = player

	var used_r := _increment_used_triggers(state.round_state, player_id, 1)
	if not used_r.ok:
		return used_r

	return Result.success({
		"player_id": player_id,
		"mode": mode,
		"shop_id": shop_id,
		"position": world_anchor,
		"from_position": old_anchor,
	})

func _validate_coffee_shop_placement(state: GameState, world_anchor: Vector2i) -> Result:
	if not PieceRegistryClass.is_loaded():
		return Result.failure("PieceRegistry 未初始化")
	var piece_defs: Dictionary = PieceRegistryClass.get_all_defs()
	if piece_defs.is_empty() or not piece_defs.has(PIECE_ID):
		return Result.failure("缺少 PieceDef: %s" % PIECE_ID)

	var houses_read := MapStateAccessClass.require_houses(state, action_id)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	var restaurants_read := MapStateAccessClass.require_restaurants(state, action_id)
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	var placements_read := MapStateAccessClass.require_marketing_placements(state, action_id)
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value

	var map_ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": CoordsClass.get_map_origin(state),
		"houses": houses,
		"restaurants": restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": placements,
	}

	var r := PlacementClass.validate_placement(map_ctx, PIECE_ID, world_anchor, 0, piece_defs, {})
	if not r.ok:
		return r
	return Result.success()

func _write_structure_cell(state: GameState, world_anchor: Vector2i, owner: int, shop_id: String) -> void:
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

func _clear_structure_cell(state: GameState, world_anchor: Vector2i) -> void:
	var idx := CoordsClass.world_to_index(state, world_anchor)
	state.map.cells[idx.y][idx.x]["structure"] = {}

static func _count_triggers_from_train_events(round_state: Dictionary, player_id: int) -> Result:
	if round_state == null or not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not round_state.has("train_events"):
		return Result.success(0)
	var te_val = round_state.get("train_events", null)
	if not (te_val is Array):
		return Result.failure("round_state.train_events 类型错误（期望 Array）")
	var train_events: Array = te_val

	var total := 0
	for i in range(train_events.size()):
		var ev_val = train_events[i]
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		if int(ev.get("player_id", -1)) != player_id:
			continue
		var to_id: String = str(ev.get("to_employee", ""))
		if TRIGGER_TO_EMPLOYEES.has(to_id):
			total += 1
	return Result.success(total)

static func _get_used_triggers(round_state: Dictionary, player_id: int) -> Result:
	if round_state == null or not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not round_state.has("coffee_shop_triggers_used"):
		return Result.success(0)
	var used_val = round_state.get("coffee_shop_triggers_used", null)
	if not (used_val is Dictionary):
		return Result.failure("round_state.coffee_shop_triggers_used 类型错误（期望 Dictionary）")
	var used: Dictionary = used_val
	if used.has(str(player_id)):
		return Result.failure("round_state.coffee_shop_triggers_used 不应包含字符串玩家 key: %s" % str(player_id))
	var v = used.get(player_id, 0)
	if not (v is int):
		return Result.failure("round_state.coffee_shop_triggers_used[%d] 类型错误（期望 int）" % player_id)
	return Result.success(int(v))

static func _increment_used_triggers(round_state: Dictionary, player_id: int, delta: int) -> Result:
	if round_state == null or not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if delta <= 0:
		return Result.failure("delta 必须 > 0")
	if not round_state.has("coffee_shop_triggers_used"):
		round_state["coffee_shop_triggers_used"] = {}
	var used_val = round_state.get("coffee_shop_triggers_used", null)
	if not (used_val is Dictionary):
		return Result.failure("round_state.coffee_shop_triggers_used 类型错误（期望 Dictionary）")
	var used: Dictionary = used_val
	if used.has(str(player_id)):
		return Result.failure("round_state.coffee_shop_triggers_used 不应包含字符串玩家 key: %s" % str(player_id))
	var before_val = used.get(player_id, 0)
	if not (before_val is int):
		return Result.failure("round_state.coffee_shop_triggers_used[%d] 类型错误（期望 int）" % player_id)
	used[player_id] = int(before_val) + delta
	round_state["coffee_shop_triggers_used"] = used
	return Result.success()

func _validate_tile_has_no_other_shop(state: GameState, world_anchor: Vector2i, ignore_shop_id: String) -> Result:
	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", action_id)
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

func _validate_within_train_range(state: GameState, player_id: int, world_anchor: Vector2i) -> Result:
	# 规则书：通过培训放置/移动咖啡店时，必须在 range 2 内（道路距离，按地图板块边界计）
	var target_roads_r := RangeUtilsClass.get_adjacent_road_cells(state, world_anchor)
	if not target_roads_r.ok:
		return target_roads_r
	var target_road_cells: Array[Vector2i] = target_roads_r.value
	if target_road_cells.is_empty():
		return Result.failure("咖啡店必须邻接道路")

	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	var min_r := RangeUtilsClass.get_min_road_distance_to_any_road_cells(state, player_id, restaurant_ids, target_road_cells)
	if not min_r.ok:
		return min_r
	var min_d: int = int(min_r.value)
	if min_d < 0:
		return Result.failure("无法计算距离：餐厅/咖啡店入口未连通到目标附近道路")
	if min_d > TRAIN_PLACEMENT_MAX_RANGE:
		return Result.failure("超出距离范围：road %d（最短=%d）" % [TRAIN_PLACEMENT_MAX_RANGE, min_d])
	return Result.success()
