class_name Evaluator
extends RefCounted

static func score_observation(observation: ObservationState, player_id: int) -> Result:
	if observation == null:
		return Result.failure("Evaluator.score_observation: observation is null")
	if player_id != observation.viewer_player_id:
		return Result.failure("Evaluator.score_observation: player_id does not match observation")

	var own := observation.own_player
	var features := {
		"cash": _number(own.get("cash", 0)),
		"inventory_units": float(_sum_inventory(own.get("inventory", {}))),
		"active_employees": float(_array_size(own.get("employees", []))),
		"reserve_employees": float(_array_size(own.get("reserve_employees", []))),
		"restaurants": float(_array_size(own.get("restaurants", []))),
		"milestones": float(_array_size(own.get("milestones", []))),
		"bank_cash": _number(observation.bank_public.get("cash", 0)),
	}
	var score := 0.0
	score += float(features["cash"])
	score += float(features["inventory_units"]) * 3.0
	score += float(features["active_employees"]) * 5.0
	score += float(features["reserve_employees"]) * 2.0
	score += float(features["restaurants"]) * 8.0
	score += float(features["milestones"]) * 6.0
	score += float(features["bank_cash"]) * 0.01

	return Result.success({
		"score": score,
		"features": features,
	})

static func _number(value) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0

static func _array_size(value) -> int:
	if value is Array:
		return Array(value).size()
	return 0

static func _sum_inventory(value) -> int:
	if not (value is Dictionary):
		return 0
	var total := 0
	var dict: Dictionary = value
	for key in dict.keys():
		total += maxi(0, int(dict.get(key, 0)))
	return total
