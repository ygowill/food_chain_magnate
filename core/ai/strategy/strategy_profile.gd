class_name StrategyProfile
extends RefCounted

const DataParseHelpersClass = preload("res://core/data/parse_helpers.gd")

const DEFAULT_PROFILE_ID := "base_revenue_v1"
const PROFILE_DIR := "res://data/bots"
const DEFAULT_BASE_REVENUE_PATH := "res://data/bots/base_revenue_v1.json"
const DEFAULT_MILESTONE_PRIORITIES := {
	"first_train": 10.0,
	"first_burger_produced": 8.0,
	"first_pizza_produced": 8.0,
	"first_errand_boy": 7.0,
	"first_cart_operator": 7.0,
	"first_airplane": 7.0,
	"first_billboard": 9.0,
	"first_radio": 9.0,
	"first_burger_marketed": 5.0,
	"first_pizza_marketed": 5.0,
	"first_drink_marketed": 5.0,
	"first_lower_prices": 4.0,
}
const DEFAULT_MILESTONE_EFFECT_WEIGHTS := {
	"salary_total_delta": 1.0,
	"gain_card": 1.0,
	"gain_cards": 1.0,
	"procure_plus_one": 1.0,
	"drinks_per_source_delta": 1.0,
	"distance_plus_one": 1.0,
	"marketing_no_salary": 1.0,
	"marketing_permanent": 1.0,
	"extra_marketing": 1.0,
	"gain_fridge": 1.0,
	"sell_bonus": 1.0,
	"waitress_tips": 1.0,
	"turnorder_empty_slots": 1.0,
	"multi_trainer_on_one": 1.0,
	"peek_reserve_cards": 1.0,
	"ceo_get_cfo": 1.0,
	"ban_card": 1.0,
	"base_price_delta": 1.0,
}
const DEFAULT_ROLE_BONUSES := {
	"strategy_first_produce_food": 8.0,
	"strategy_first_marketing": 7.0,
	"strategy_first_procure_drink": 6.0,
	"strategy_recruit_train_trainable": 5.0,
	"strategy_early_new_shop": 3.0,
	"income_first_produce_food": 4.0,
	"income_no_drink_supply": 4.0,
	"income_marketing_own_restaurant": 2.0,
	"income_first_marketing": 3.0,
	"income_first_new_shop": 10.0,
	"income_unserviceable_new_shop": 4.0,
	"income_recruit_train_trainable": 4.0,
	"income_price_serviceable": 2.0,
}

var id: String = DEFAULT_PROFILE_ID
var max_valid_per_action: int = 12
var strict_marketing_must_affect_houses: bool = true
var action_weights: Dictionary = {}
var employee_priorities: Dictionary = {}
var product_priorities: Dictionary = {}
var milestone_priorities: Dictionary = {}
var milestone_effect_weights: Dictionary = {}
var role_bonuses: Dictionary = {}

func configure_base_revenue() -> void:
	configure(DEFAULT_PROFILE_ID)

func configure(profile_source: String = "") -> Result:
	var source := profile_source.strip_edges()
	if source.is_empty() or source == DEFAULT_PROFILE_ID:
		var loaded := load_from_file(DEFAULT_BASE_REVENUE_PATH)
		if loaded.ok:
			return loaded
		_configure_base_revenue_fallback()
		return Result.success()
	return load_from_file(resolve_profile_path(source))

func load_from_file(path: String) -> Result:
	if path.is_empty():
		return Result.failure("StrategyProfile.load_from_file: path 不能为空")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("StrategyProfile.load_from_file: 无法打开文件: %s" % path)
	var json := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json)
	if not (parsed is Dictionary):
		return Result.failure("StrategyProfile.load_from_file: JSON 解析失败或根节点不是 Dictionary: %s" % path)
	return configure_from_dict(Dictionary(parsed))

static func resolve_profile_path(profile_source: String) -> String:
	var source := profile_source.strip_edges()
	if source.is_empty():
		source = DEFAULT_PROFILE_ID
	if source.begins_with("res://") or source.begins_with("user://") or source.begins_with("/"):
		return source
	if source.ends_with(".json"):
		if source.contains("/"):
			return "res://%s" % source
		return "%s/%s" % [PROFILE_DIR, source]
	return "%s/%s.json" % [PROFILE_DIR, source]

func configure_from_dict(data: Dictionary) -> Result:
	var id_read := DataParseHelpersClass.parse_string(data.get("id", null), "StrategyProfile.id", false)
	if not id_read.ok:
		return id_read
	var max_read := DataParseHelpersClass.parse_non_negative_int(data.get("max_valid_per_action", null), "StrategyProfile.max_valid_per_action")
	if not max_read.ok:
		return max_read
	if int(max_read.value) <= 0:
		return Result.failure("StrategyProfile.max_valid_per_action 必须 > 0")
	var strict_read := DataParseHelpersClass.parse_bool(data.get("strict_marketing_must_affect_houses", null), "StrategyProfile.strict_marketing_must_affect_houses")
	if not strict_read.ok:
		return strict_read
	var action_read := _parse_float_dictionary(data.get("action_weights", null), "StrategyProfile.action_weights")
	if not action_read.ok:
		return action_read
	var employee_read := _parse_float_dictionary(data.get("employee_priorities", null), "StrategyProfile.employee_priorities")
	if not employee_read.ok:
		return employee_read
	var product_read := _parse_float_dictionary(data.get("product_priorities", null), "StrategyProfile.product_priorities")
	if not product_read.ok:
		return product_read
	var milestone_read := _parse_optional_float_dictionary(
		data.get("milestone_priorities", null),
		DEFAULT_MILESTONE_PRIORITIES,
		"StrategyProfile.milestone_priorities"
	)
	if not milestone_read.ok:
		return milestone_read
	var milestone_effect_read := _parse_optional_float_dictionary(
		data.get("milestone_effect_weights", null),
		DEFAULT_MILESTONE_EFFECT_WEIGHTS,
		"StrategyProfile.milestone_effect_weights"
	)
	if not milestone_effect_read.ok:
		return milestone_effect_read
	var role_bonus_read := _parse_optional_float_dictionary(
		data.get("role_bonuses", null),
		DEFAULT_ROLE_BONUSES,
		"StrategyProfile.role_bonuses"
	)
	if not role_bonus_read.ok:
		return role_bonus_read

	id = str(id_read.value)
	max_valid_per_action = int(max_read.value)
	strict_marketing_must_affect_houses = bool(strict_read.value)
	action_weights = Dictionary(action_read.value)
	employee_priorities = Dictionary(employee_read.value)
	product_priorities = Dictionary(product_read.value)
	milestone_priorities = Dictionary(milestone_read.value)
	milestone_effect_weights = Dictionary(milestone_effect_read.value)
	role_bonuses = Dictionary(role_bonus_read.value)
	return Result.success()

func _configure_base_revenue_fallback() -> void:
	id = "base_revenue_v1"
	max_valid_per_action = 12
	strict_marketing_must_affect_houses = true
	action_weights = {
		"confirm_dinnertime": 1000.0,
		"confirm_marketing": 1000.0,
		"set_price": 900.0,
		"set_discount": 900.0,
		"set_luxury_price": 900.0,
		"choose_fridge_keep": 120.0,
		"submit_restructuring": 90.0,
		"set_company_structure_direct": 85.0,
		"set_company_structure_report": 82.0,
		"restructure_employee": 80.0,
		"place_restaurant": 72.0,
		"recruit": 68.0,
		"train": 66.0,
		"initiate_marketing": 64.0,
		"produce_food": 62.0,
		"procure_drinks": 60.0,
		"place_house": 45.0,
		"add_garden": 38.0,
		"move_restaurant": 32.0,
		"fire": 25.0,
		"choose_turn_order": 20.0,
		"select_reserve_card": 10.0,
		"skip_sub_phase": -20.0,
		"skip": -25.0,
	}
	employee_priorities = {
		"burger_cook": 9.0,
		"pizza_cook": 8.5,
		"kitchen_trainee": 7.0,
		"campaign_manager": 8.0,
		"marketing_trainee": 6.5,
		"errand_boy": 7.5,
		"trainer": 6.0,
		"management_trainee": 5.5,
		"new_business_developer": 5.0,
		"recruiting_girl": 4.0,
	}
	product_priorities = {
		"burger": 5.0,
		"pizza": 4.5,
		"beer": 4.0,
		"soda": 3.5,
		"lemonade": 3.0,
	}
	milestone_priorities = DEFAULT_MILESTONE_PRIORITIES.duplicate()
	milestone_effect_weights = DEFAULT_MILESTONE_EFFECT_WEIGHTS.duplicate()
	role_bonuses = DEFAULT_ROLE_BONUSES.duplicate()

func action_weight(action_id: String) -> float:
	return float(action_weights.get(action_id, 0.0))

func employee_priority(employee_id: String) -> float:
	return float(employee_priorities.get(employee_id, 1.0))

func product_priority(product_id: String) -> float:
	return float(product_priorities.get(product_id, 1.0))

func milestone_priority(milestone_id: String, fallback: float = 3.0) -> float:
	return float(milestone_priorities.get(milestone_id, fallback))

func milestone_effect_weight(effect_type: String) -> float:
	return float(milestone_effect_weights.get(effect_type, 1.0))

func role_bonus(key: String, fallback: float = 0.0) -> float:
	return float(role_bonuses.get(key, fallback))

static func _parse_float_dictionary(value, path: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var out := {}
	for key_val in Dictionary(value).keys():
		var key := str(key_val).strip_edges()
		if key.is_empty():
			return Result.failure("%s 包含空 key" % path)
		var item = Dictionary(value).get(key_val, null)
		if item is int or item is float:
			out[key] = float(item)
			continue
		return Result.failure("%s.%s 类型错误（期望 number）" % [path, key])
	return Result.success(out)

static func _parse_optional_float_dictionary(value, fallback: Dictionary, path: String) -> Result:
	if value == null:
		return Result.success(fallback.duplicate())
	return _parse_float_dictionary(value, path)
