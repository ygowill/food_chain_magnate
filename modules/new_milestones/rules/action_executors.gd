extends RefCounted

const PlaceNewRestaurantMailboxActionClass = preload("res://modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd")
const PlaceCampaignManagerSecondTileActionClass = preload("res://modules/new_milestones/actions/place_campaign_manager_second_tile_action.gd")
const SetBrandManagerAirplaneSecondGoodActionClass = preload("res://modules/new_milestones/actions/set_brand_manager_airplane_second_good_action.gd")
const PlacePizzaRadioActionClass = preload("res://modules/new_milestones/actions/place_pizza_radio_action.gd")

func register(registrar) -> Result:
	var r = registrar.register_action_executor(PlaceNewRestaurantMailboxActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlaceCampaignManagerSecondTileActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(SetBrandManagerAirplaneSecondGoodActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlacePizzaRadioActionClass.new())
	if not r.ok:
		return r
	return Result.success()

