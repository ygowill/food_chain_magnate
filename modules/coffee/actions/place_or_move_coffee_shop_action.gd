class_name PlaceOrMoveCoffeeShopAction
extends ActionExecutor

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")

const MODULE_ID := "coffee"
const PIECE_ID := "coffee_shop"
const TRIGGER_TO_EMPLOYEES: Array[String] = ["barista", "lead_barista"]

func _init() -> void:
	action_id = "place_or_move_coffee_shop"
	display_name = "放置/移动咖啡店"
	description = "在培训咖啡师后，放置或移动一个咖啡店"
	requires_actor = true
	is_mandatory = false
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

	if not (state.players is Array) or command.actor < 0 or command.actor >= state.players.size():
		return Result.failure("player_id 越界: %d" % command.actor)
	var player_val = state.players[command.actor]
	if not (player_val is Dictionary):
		return Result.failure("player 类型错误（期望 Dictionary）")
	var player: Dictionary = player_val

	if not player.has("coffee_shop_tokens_remaining") or not (player["coffee_shop_tokens_remaining"] is int):
		return Result.failure("coffee_shop_tokens_remaining 缺失或类型错误（模块未正确初始化）")
	var tokens_remaining: int = int(player["coffee_shop_tokens_remaining"])

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("coffee_shops") or not (state.map["coffee_shops"] is Dictionary):
		return Result.failure("state.map.coffee_shops 缺失或类型错误（模块未正确初始化）")

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

	# 放置规则：token 用尽则必须 move
	if mode == "place" and tokens_remaining <= 0:
		return Result.failure("咖啡店 token 已用尽，必须移动已有咖啡店")

	if mode == "move":
		var from_read := require_string_param(command, "from_shop_id")
		if not from_read.ok:
			return from_read
		var from_shop_id: String = str(from_read.value)
		if from_shop_id.is_empty():
			return Result.failure("from_shop_id 不能为空")
		var shops: Dictionary = state.map["coffee_shops"]
		if not shops.has(from_shop_id) or not (shops[from_shop_id] is Dictionary):
			return Result.failure("咖啡店不存在: %s" % from_shop_id)
		var shop: Dictionary = shops[from_shop_id]
		if int(shop.get("owner", -1)) != command.actor:
			return Result.failure("只能移动自己的咖啡店: %s" % from_shop_id)

	var validate_result := _validate_coffee_shop_placement(state, world_anchor)
	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
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

	var player: Dictionary = state.players[player_id]
	var shops: Dictionary = state.map["coffee_shops"]

	var shop_id := ""
	var old_anchor: Vector2i = Vector2i.ZERO

	if mode == "place":
		var tokens_remaining: int = int(player["coffee_shop_tokens_remaining"])
		if tokens_remaining <= 0:
			return Result.failure("咖啡店 token 已用尽，必须移动已有咖啡店")
		assert(state.map.has("next_coffee_shop_id") and (state.map["next_coffee_shop_id"] is int), "coffee: next_coffee_shop_id 缺失或类型错误（期望 int）")
		shop_id = "coffee_shop_%d" % int(state.map["next_coffee_shop_id"])
		state.map["next_coffee_shop_id"] = int(state.map["next_coffee_shop_id"]) + 1
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

	var map_ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": MapRuntimeClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

	var r := PlacementValidatorClass.validate_placement(map_ctx, PIECE_ID, world_anchor, 0, piece_defs, {})
	if not r.ok:
		return r
	return Result.success()

func _write_structure_cell(state: GameState, world_anchor: Vector2i, owner: int, shop_id: String) -> void:
	var idx := MapRuntimeClass.world_to_index(state, world_anchor)
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
	var idx := MapRuntimeClass.world_to_index(state, world_anchor)
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
