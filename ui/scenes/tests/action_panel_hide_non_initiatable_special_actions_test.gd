# ActionPanel：特殊动作在不可启动时应直接隐藏
class_name ActionPanelHideNonInitiatableSpecialActionsTest
extends RefCounted

const ActionPanelClass = preload("res://ui/components/action_panel/action_panel.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const PlaceRestaurantActionClass = preload("res://gameplay/actions/place_restaurant_action.gd")
const MoveRestaurantActionClass = preload("res://gameplay/actions/move_restaurant_action.gd")
const ConfirmDinnertimeActionClass = preload("res://gameplay/actions/confirm_dinnertime_action.gd")
const PlaceNewRestaurantMailboxActionClass = preload("res://modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd")
const PlaceCampaignManagerSecondTileActionClass = preload("res://modules/new_milestones/actions/place_campaign_manager_second_tile_action.gd")
const PlacePizzaRadioActionClass = preload("res://modules/new_milestones/actions/place_pizza_radio_action.gd")
const SetBrandManagerAirplaneSecondGoodActionClass = preload("res://modules/new_milestones/actions/set_brand_manager_airplane_second_good_action.gd")

class _MockActionRegistry:
	extends RefCounted

	var _executors: Dictionary = {}
	var _available: Array[String] = []
	var _initiatable: Array[String] = []

	func _init(executors: Dictionary, available: Array, initiatable: Array) -> void:
		_executors = executors.duplicate()
		_available = Array(available, TYPE_STRING, "", null)
		_initiatable = Array(initiatable, TYPE_STRING, "", null)

	func get_available_actions(_state: GameState) -> Array[String]:
		return _available.duplicate()

	func get_player_initiatable_actions(_state: GameState, _player_id: int) -> Array[String]:
		return _initiatable.duplicate()

	func get_mandatory_actions(_state: GameState) -> Array[String]:
		return []

	func get_executor(action_id: String):
		return _executors.get(str(action_id).strip_edges(), null)

class _MockExecutor:
	extends RefCounted

	var display_name: String = ""
	var description: String = ""
	var ui_hide_if_not_initiatable: bool = false

	func _init(name: String, hide_if_not_initiatable: bool) -> void:
		display_name = name
		description = name
		ui_hide_if_not_initiatable = hide_if_not_initiatable

static func run() -> Result:
	var hide_r := _case_hide_non_initiatable_special_actions()
	if not hide_r.ok:
		return hide_r

	var keep_r := _case_keep_initiatable_special_action_visible()
	if not keep_r.ok:
		return keep_r

	var hide_milestone_r := _case_hide_non_initiatable_milestone_actions()
	if not hide_milestone_r.ok:
		return hide_milestone_r

	var keep_milestone_r := _case_keep_initiatable_milestone_action_visible()
	if not keep_milestone_r.ok:
		return keep_milestone_r

	return Result.success({})

static func _case_hide_non_initiatable_special_actions() -> Result:
	var panel := ActionPanelClass.new()
	var registry := _MockActionRegistry.new(
		{
			"place_restaurant": PlaceRestaurantActionClass.new(),
			"move_restaurant": MoveRestaurantActionClass.new(),
			"confirm_dinnertime": ConfirmDinnertimeActionClass.new(),
			ActionIdsClass.SKIP: _MockExecutor.new("确认结束", false),
		},
		["place_restaurant", "move_restaurant", "confirm_dinnertime", ActionIdsClass.SKIP],
		[ActionIdsClass.SKIP]
	)

	panel.set_action_registry(registry)
	panel.set_game_state(_build_state(DefsClass.PHASE_WORKING, DefsClass.SUB_PHASE_PLACE_RESTAURANTS))
	panel.set_current_player(0)

	var visible := panel.get_visible_action_ids()
	var expected: Array[String] = [ActionIdsClass.SKIP]
	if visible != expected:
		_safe_free(panel)
		return Result.failure("不可启动的特殊动作应被隐藏，实际: %s" % str(visible))

	_safe_free(panel)
	return Result.success({})

static func _case_keep_initiatable_special_action_visible() -> Result:
	var panel := ActionPanelClass.new()
	var registry := _MockActionRegistry.new(
		{
			"place_restaurant": PlaceRestaurantActionClass.new(),
			"move_restaurant": MoveRestaurantActionClass.new(),
			ActionIdsClass.SKIP: _MockExecutor.new("确认结束", false),
		},
		["place_restaurant", "move_restaurant", ActionIdsClass.SKIP],
		["place_restaurant", ActionIdsClass.SKIP]
	)

	panel.set_action_registry(registry)
	panel.set_game_state(_build_state(DefsClass.PHASE_WORKING, DefsClass.SUB_PHASE_PLACE_RESTAURANTS))
	panel.set_current_player(0)

	var visible := panel.get_visible_action_ids()
	var expected: Array[String] = ["place_restaurant", ActionIdsClass.SKIP]
	if visible != expected:
		_safe_free(panel)
		return Result.failure("可启动的特殊动作应保留显示，实际: %s" % str(visible))

	_safe_free(panel)
	return Result.success({})

static func _case_hide_non_initiatable_milestone_actions() -> Result:
	var panel := ActionPanelClass.new()
	var registry := _MockActionRegistry.new(
		{
			"place_new_restaurant_mailbox": PlaceNewRestaurantMailboxActionClass.new(),
			"place_campaign_manager_second_tile": PlaceCampaignManagerSecondTileActionClass.new(),
			"set_brand_manager_airplane_second_good": SetBrandManagerAirplaneSecondGoodActionClass.new(),
			"place_pizza_radio": PlacePizzaRadioActionClass.new(),
			ActionIdsClass.SKIP: _MockExecutor.new("确认结束", false),
		},
		[
			"place_new_restaurant_mailbox",
			"place_campaign_manager_second_tile",
			"set_brand_manager_airplane_second_good",
			"place_pizza_radio",
			ActionIdsClass.SKIP,
		],
		[ActionIdsClass.SKIP]
	)

	panel.set_action_registry(registry)
	panel.set_game_state(_build_state(DefsClass.PHASE_DINNERTIME, ""))
	panel.set_current_player(0)

	var visible := panel.get_visible_action_ids()
	var expected: Array[String] = [ActionIdsClass.SKIP]
	if visible != expected:
		_safe_free(panel)
		return Result.failure("不可启动的里程碑动作应被隐藏，实际: %s" % str(visible))

	_safe_free(panel)
	return Result.success({})

static func _case_keep_initiatable_milestone_action_visible() -> Result:
	var panel := ActionPanelClass.new()
	var registry := _MockActionRegistry.new(
		{
			"place_pizza_radio": PlacePizzaRadioActionClass.new(),
			"set_brand_manager_airplane_second_good": SetBrandManagerAirplaneSecondGoodActionClass.new(),
			ActionIdsClass.SKIP: _MockExecutor.new("确认结束", false),
		},
		["place_pizza_radio", "set_brand_manager_airplane_second_good", ActionIdsClass.SKIP],
		["place_pizza_radio", ActionIdsClass.SKIP]
	)

	panel.set_action_registry(registry)
	panel.set_game_state(_build_state(DefsClass.PHASE_DINNERTIME, ""))
	panel.set_current_player(0)

	var visible := panel.get_visible_action_ids()
	var expected: Array[String] = ["place_pizza_radio", ActionIdsClass.SKIP]
	if visible != expected:
		_safe_free(panel)
		return Result.failure("可启动的里程碑动作应保留显示，实际: %s" % str(visible))

	_safe_free(panel)
	return Result.success({})

static func _build_state(phase: String, sub_phase: String) -> GameState:
	var state := GameStateClass.new()
	state.phase = phase
	state.sub_phase = sub_phase
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.players = [
		{"id": 0, "restaurants": [], "cash": 0},
		{"id": 1, "restaurants": [], "cash": 0},
	]
	return state

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
