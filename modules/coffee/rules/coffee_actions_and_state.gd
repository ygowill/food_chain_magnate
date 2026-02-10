extends RefCounted

const PlaceOrMoveCoffeeShopActionClass = preload("res://modules/coffee/actions/place_or_move_coffee_shop_action.gd")
const ResolveFirstCoffeeSoldBonusCoffeeShopActionClass = preload("res://modules/coffee/actions/resolve_first_coffee_sold_bonus_coffee_shop_action.gd")

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
	if not (state.map is Dictionary):
		return Result.failure("coffee:init_state: state.map 类型错误（期望 Dictionary）")

	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("coffee:init_state: player[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		player["coffee_shop_tokens_remaining"] = 3
		state.players[pid] = player

	if not state.map.has("coffee_shops"):
		state.map["coffee_shops"] = {}
	if not (state.map["coffee_shops"] is Dictionary):
		return Result.failure("coffee:init_state: state.map.coffee_shops 类型错误（期望 Dictionary）")
	if not state.map.has("next_coffee_shop_id"):
		state.map["next_coffee_shop_id"] = 1
	if not (state.map["next_coffee_shop_id"] is int):
		return Result.failure("coffee:init_state: state.map.next_coffee_shop_id 类型错误（期望 int）")

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
	if not (state.map is Dictionary):
		return Result.failure("coffee:range_origins: state.map 类型错误（期望 Dictionary）")

	var shops_val = state.map.get("coffee_shops", null)
	if shops_val == null:
		return Result.success([] as Array[Vector2i])
	if not (shops_val is Dictionary):
		return Result.failure("coffee:range_origins: state.map.coffee_shops 类型错误（期望 Dictionary）")
	var shops: Dictionary = shops_val

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
