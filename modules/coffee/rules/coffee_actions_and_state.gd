extends RefCounted

const PlaceOrMoveCoffeeShopActionClass = preload("res://modules/coffee/actions/place_or_move_coffee_shop_action.gd")
const ResolveFirstCoffeeSoldBonusCoffeeShopActionClass = preload("res://modules/coffee/actions/resolve_first_coffee_sold_bonus_coffee_shop_action.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const MODULE_ID := "coffee"
const RANGE_ORIGIN_PROVIDER_ID := "%s:range_origins:coffee_shops" % MODULE_ID

func register(registrar) -> Result:
	var r = registrar.register_action_executor(PlaceOrMoveCoffeeShopActionClass.new())
	if not r.ok:
		return r

	r = registrar.register_action_executor(ResolveFirstCoffeeSoldBonusCoffeeShopActionClass.new())
	if not r.ok:
		return r

	r = registrar.register_state_initializer("%s:init_state" % MODULE_ID, Callable(self, "_init_state"), 50)
	if not r.ok:
		return r

	# coffee_shop 可作为“range 起点”（规则书）
	r = registrar.register_range_origin_provider(RANGE_ORIGIN_PROVIDER_ID, Callable(self, "_get_extra_range_origins"), 50)
	if not r.ok:
		return r

	return Result.success()

func _init_state(state: GameState, _rng_manager) -> Result:
	if state == null:
		return Result.failure("coffee:init_state: state 为空")
	if not (state.players is Array):
		return Result.failure("coffee:init_state: state.players 类型错误（期望 Array）")
	var map_read := MapStateAccessClass.require_map(state, "coffee:init_state")
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	for pid in range(state.players.size()):
		var player_read := PlayerStateAccessClass.require_player(state, pid, "coffee:init_state")
		if not player_read.ok:
			return player_read
		var player: Dictionary = player_read.value
		player["coffee_shop_tokens_remaining"] = 3
		state.players[pid] = player

	if not map.has("coffee_shops"):
		map["coffee_shops"] = {}
	var coffee_shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", "coffee:init_state")
	if not coffee_shops_read.ok:
		return coffee_shops_read
	if not map.has("next_coffee_shop_id"):
		map["next_coffee_shop_id"] = 1
	var next_shop_id_read := MapStateAccessClass.require_int_field(state, "next_coffee_shop_id", "coffee:init_state")
	if not next_shop_id_read.ok:
		return next_shop_id_read

	return Result.success()

func _get_extra_range_origins(state: GameState, ctx: Dictionary) -> Result:
	if state == null:
		return Result.failure("coffee:range_origins: state 为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("coffee:range_origins: ctx 类型错误（期望 Dictionary）")
	var actor_val = ctx.get("actor", null)
	if not (actor_val is int):
		return Result.failure("coffee:range_origins: ctx.actor 类型错误（期望 int）")
	var actor: int = int(actor_val)
	if actor < 0:
		return Result.success([] as Array[Vector2i])
	var map_read := MapStateAccessClass.require_map(state, "coffee:range_origins")
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	if not map.has("coffee_shops"):
		return Result.success([] as Array[Vector2i])
	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", "coffee:range_origins")
	if not shops_read.ok:
		return shops_read
	var shops: Dictionary = shops_read.value

	var out: Array[Vector2i] = []
	var seen := {}
	for sid_val in shops.keys():
		var shop_val = shops.get(sid_val, null)
		if not (shop_val is Dictionary):
			continue
		var shop: Dictionary = shop_val
		if int(shop.get("owner", -1)) != actor:
			continue
		var pos_val = shop.get("entrance_pos", null)
		if not (pos_val is Vector2i):
			pos_val = shop.get("anchor_pos", null)
		if not (pos_val is Vector2i):
			continue
		var pos: Vector2i = pos_val
		if seen.has(pos):
			continue
		seen[pos] = true
		out.append(pos)

	return Result.success(out)
