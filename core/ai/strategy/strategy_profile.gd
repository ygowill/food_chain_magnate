class_name StrategyProfile
extends RefCounted

var id: String = "base_revenue_v1"
var max_valid_per_action: int = 12
var action_weights: Dictionary = {}
var employee_priorities: Dictionary = {}
var product_priorities: Dictionary = {}

func configure_base_revenue() -> void:
	id = "base_revenue_v1"
	max_valid_per_action = 12
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

func action_weight(action_id: String) -> float:
	return float(action_weights.get(action_id, 0.0))

func employee_priority(employee_id: String) -> float:
	return float(employee_priorities.get(employee_id, 1.0))

func product_priority(product_id: String) -> float:
	return float(product_priorities.get(product_id, 1.0))
