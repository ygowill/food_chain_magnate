extends RefCounted

const CoffeeActionsAndStateClass = preload("res://modules/coffee/rules/coffee_actions_and_state.gd")
const CoffeeCleanupClass = preload("res://modules/coffee/rules/coffee_cleanup.gd")
const CoffeeDinnertimeRouteClass = preload("res://modules/coffee/rules/coffee_dinnertime_route.gd")

var _parts: Array = []

func register(registrar) -> Result:
	_parts = [
		CoffeeActionsAndStateClass.new(),
		CoffeeCleanupClass.new(),
		CoffeeDinnertimeRouteClass.new(),
	]

	for part in _parts:
		var r: Result = part.register(registrar)
		if not r.ok:
			return r

	return Result.success()

static func _build_coffee_stop_index(state: GameState, exclude_restaurant_id: String) -> Result:
	return CoffeeDinnertimeRouteClass._build_coffee_stop_index(state, exclude_restaurant_id)

static func _pos_key(pos: Vector2i) -> String:
	return CoffeeDinnertimeRouteClass._pos_key(pos)
