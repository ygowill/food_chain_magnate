extends RefCounted

const CoffeeActionsAndStateClass = preload("res://modules/coffee/rules/coffee_actions_and_state.gd")
const CoffeeCleanupClass = preload("res://modules/coffee/rules/coffee_cleanup.gd")
const CoffeeDinnertimeRouteClass = preload("res://modules/coffee/rules/coffee_dinnertime_route.gd")
const CoffeeFirstCoffeeSoldClass = preload("res://modules/coffee/rules/coffee_first_coffee_sold.gd")
const ModuleEntryHelpersClass = preload("res://core/modules/v2/module_entry_helpers.gd")

const COFFEE_SHOP_TRIGGERS_USED_KEY := "coffee_shop_triggers_used"
const STATE_SCHEMA_ID_COFFEE_SHOP_TRIGGERS_USED := "coffee:round_state_int_keys:coffee_shop_triggers_used"
const EXTRA_LUXURY_MANAGER_PATCH_ID := "extra_luxury_manager"

func register(registrar) -> Result:
	var parts := [
		CoffeeActionsAndStateClass.new(),
		CoffeeCleanupClass.new(),
		CoffeeDinnertimeRouteClass.new(),
		CoffeeFirstCoffeeSoldClass.new(),
	]
	var r := ModuleEntryHelpersClass.register_parts(registrar, parts)
	if not r.ok:
		return r

	# 额外 +1 张奢侈品经理（多模块同时使用时只加一次）
	r = registrar.register_employee_pool_patch(EXTRA_LUXURY_MANAGER_PATCH_ID, "luxury_manager", 1)
	if not r.ok:
		return r

	# round_state.<player_id(int) -> ...> 字典：读档后需要把 "0"/"1" 转回 0/1
	var schema_r: Result = registrar.register_round_state_int_key_dict_schema(STATE_SCHEMA_ID_COFFEE_SHOP_TRIGGERS_USED, [COFFEE_SHOP_TRIGGERS_USED_KEY], 100)
	if not schema_r.ok:
		return schema_r

	# UI：coffee_shop 的渲染提示（避免 core UI 写死 piece_id / logo 变体）。
	var hint_r: Result = registrar.register_piece_ui_hint(
		"coffee_shop",
		{
			"structure_style": "player_logo",
			"logo_variant_suffix": "_coffee",
		},
		100
	)
	if not hint_r.ok:
		return hint_r

	return Result.success()

static func _build_coffee_stop_index(state: GameState, exclude_restaurant_id: String) -> Result:
	return CoffeeDinnertimeRouteClass._build_coffee_stop_index(state, exclude_restaurant_id)

static func _pos_key(pos: Vector2i) -> String:
	return CoffeeDinnertimeRouteClass._pos_key(pos)
