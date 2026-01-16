extends RefCounted

const CoffeeActionsAndStateClass = preload("res://modules/coffee/rules/coffee_actions_and_state.gd")
const CoffeeCleanupClass = preload("res://modules/coffee/rules/coffee_cleanup.gd")
const CoffeeDinnertimeRouteClass = preload("res://modules/coffee/rules/coffee_dinnertime_route.gd")

const COFFEE_SHOP_TRIGGERS_USED_KEY := "coffee_shop_triggers_used"
const STATE_SCHEMA_ID_COFFEE_SHOP_TRIGGERS_USED := "coffee:round_state_int_keys:coffee_shop_triggers_used"

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

	# round_state.<player_id(int) -> ...> 字典：读档后需要把 "0"/"1" 转回 0/1
	var schema_r: Result = registrar.register_round_state_int_key_dict_schema(STATE_SCHEMA_ID_COFFEE_SHOP_TRIGGERS_USED, [COFFEE_SHOP_TRIGGERS_USED_KEY], 100)
	if not schema_r.ok:
		return schema_r

	return Result.success()

static func _build_coffee_stop_index(state: GameState, exclude_restaurant_id: String) -> Result:
	return CoffeeDinnertimeRouteClass._build_coffee_stop_index(state, exclude_restaurant_id)

static func _pos_key(pos: Vector2i) -> String:
	return CoffeeDinnertimeRouteClass._pos_key(pos)
