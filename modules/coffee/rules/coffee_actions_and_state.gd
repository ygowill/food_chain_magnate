extends RefCounted

const PlaceOrMoveCoffeeShopActionClass = preload("res://modules/coffee/actions/place_or_move_coffee_shop_action.gd")

const MODULE_ID := "coffee"

func register(registrar) -> Result:
	var r = registrar.register_action_executor(PlaceOrMoveCoffeeShopActionClass.new())
	if not r.ok:
		return r

	r = registrar.register_state_initializer("%s:init_state" % MODULE_ID, Callable(self, "_init_state"), 50)
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
