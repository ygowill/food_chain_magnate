# GameEngine：动作注册（内建 actions）
# 负责：构建 ActionRegistry 并注册所有内建 ActionExecutor。
extends RefCounted

const AdvancePhaseActionClass = preload("res://gameplay/actions/advance_phase_action.gd")
const SkipActionClass = preload("res://gameplay/actions/skip_action.gd")
const SkipSubPhaseActionClass = preload("res://gameplay/actions/skip_sub_phase_action.gd")
const EndTurnActionClass = preload("res://gameplay/actions/end_turn_action.gd")
const ChooseTurnOrderActionClass = preload("res://gameplay/actions/choose_turn_order_action.gd")
const RecruitActionClass = preload("res://gameplay/actions/recruit_action.gd")
const TrainActionClass = preload("res://gameplay/actions/train_action.gd")
const InitiateMarketingActionClass = preload("res://gameplay/actions/initiate_marketing_action.gd")
const FireActionClass = preload("res://gameplay/actions/fire_action.gd")
const PlaceRestaurantActionClass = preload("res://gameplay/actions/place_restaurant_action.gd")
const MoveRestaurantActionClass = preload("res://gameplay/actions/move_restaurant_action.gd")
const PlaceHouseActionClass = preload("res://gameplay/actions/place_house_action.gd")
const AddGardenActionClass = preload("res://gameplay/actions/add_garden_action.gd")

const SetPriceActionClass = preload("res://gameplay/actions/set_price_action.gd")
const SetDiscountActionClass = preload("res://gameplay/actions/set_discount_action.gd")
const SetLuxuryPriceActionClass = preload("res://gameplay/actions/set_luxury_price_action.gd")

const ProduceFoodActionClass = preload("res://gameplay/actions/produce_food_action.gd")
const ProcureDrinksActionClass = preload("res://gameplay/actions/procure_drinks_action.gd")
const ActionAvailabilityRegistryClass = preload("res://core/actions/action_availability_registry.gd")

static func build_registry(phase_manager: PhaseManager, piece_registry: Dictionary = {}) -> ActionRegistry:
	assert(phase_manager != null, "phase_manager 不能为空")

	var registry := ActionRegistry.new()
	registry.register_executors([
		AdvancePhaseActionClass.new(phase_manager),
		SkipActionClass.new(phase_manager),
		SkipSubPhaseActionClass.new(phase_manager),
		EndTurnActionClass.new(),
		ChooseTurnOrderActionClass.new(phase_manager),
		RecruitActionClass.new(),
		TrainActionClass.new(),
		InitiateMarketingActionClass.new(),
		FireActionClass.new(),
		PlaceRestaurantActionClass.new(piece_registry),
		MoveRestaurantActionClass.new(piece_registry),
		PlaceHouseActionClass.new(piece_registry),
		AddGardenActionClass.new(piece_registry),
		SetPriceActionClass.new(),
		SetDiscountActionClass.new(),
		SetLuxuryPriceActionClass.new(),
		ProduceFoodActionClass.new(),
		ProcureDrinksActionClass.new(),
	])

	# 默认动作可用性（phase/sub_phase -> action_ids），避免在非 GameEngine 场景下 ActionRegistry 缺少 gating。
	var availability := ActionAvailabilityRegistryClass.new()
	var all_execs: Array = []
	for aid_val in registry.get_all_action_ids():
		if not (aid_val is String):
			continue
		var aid: String = str(aid_val)
		if aid.is_empty():
			continue
		var ex := registry.get_executor(aid)
		if ex != null:
			all_execs.append(ex)
	var defaults_r := availability.build_defaults_from_executors(all_execs)
	if defaults_r.ok:
		var compile_r := availability.compile_with_validation(registry.get_all_action_ids())
		if compile_r.ok:
			registry.set_availability_registry(availability)
		else:
			GameLog.error("ActionSetup", "初始化默认 ActionAvailability 失败: %s" % compile_r.error)
	else:
		GameLog.error("ActionSetup", "初始化默认 ActionAvailability 失败: %s" % defaults_r.error)
	return registry
