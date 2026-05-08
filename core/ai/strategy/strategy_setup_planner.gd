class_name StrategySetupPlanner
extends RefCounted

static func evaluate_action(observation: ObservationState, command: Command) -> Dictionary:
	var features := {}
	if command == null:
		return {"value": 0.0, "features": features}
	var action_id := str(command.action_id)
	var payload := {}
	match action_id:
		"select_reserve_card":
			payload = reserve_card_value(observation, command.params)
			_append_reserve_card_features(features, payload)
		"choose_turn_order":
			payload = turn_order_value(command.params)
			_append_turn_order_features(features, payload)
		_:
			return {"value": 0.0, "features": features}
	return {
		"value": float(payload.get("value", 0.0)),
		"features": features,
	}

static func reserve_card_value(observation: ObservationState, params: Dictionary) -> Dictionary:
	var selected_index := _read_int(params.get("selected_index", -1), -1)
	var cards_val = observation.own_player.get("reserve_cards", []) if observation != null else []
	if not (cards_val is Array):
		return {
			"value": -100.0,
			"selected_index": selected_index,
			"valid": false,
		}
	var cards: Array = cards_val
	if selected_index < 0 or selected_index >= cards.size():
		return {
			"value": -100.0,
			"selected_index": selected_index,
			"valid": false,
		}
	var card_val = cards[selected_index]
	if not (card_val is Dictionary):
		return {
			"value": -100.0,
			"selected_index": selected_index,
			"valid": false,
		}
	var card: Dictionary = card_val
	var cash := _read_non_negative_int(card.get("cash", 0), 0)
	var ceo_slots := _read_non_negative_int(card.get("ceo_slots", 0), 0)
	var card_type := _read_non_negative_int(card.get("type", 0), 0)
	var value := float(ceo_slots) * 8.0 + float(cash) * 0.05
	if ceo_slots <= 0:
		value -= 50.0
	return {
		"value": value,
		"selected_index": selected_index,
		"valid": true,
		"type": card_type,
		"cash": cash,
		"ceo_slots": ceo_slots,
	}

static func turn_order_value(params: Dictionary) -> Dictionary:
	var position := _read_non_negative_int(params.get("position", 0), 0)
	var value := maxf(0.0, 8.0 - float(position) * 2.0)
	return {
		"value": value,
		"position": position,
	}

static func _append_reserve_card_features(features: Dictionary, reserve_payload: Dictionary) -> void:
	features["reserve_card_value"] = float(reserve_payload.get("value", 0.0))
	features["reserve_card_selected_index"] = int(reserve_payload.get("selected_index", -1))
	features["reserve_card_valid"] = bool(reserve_payload.get("valid", false))
	features["reserve_card_type"] = int(reserve_payload.get("type", 0))
	features["reserve_card_cash"] = int(reserve_payload.get("cash", 0))
	features["reserve_card_ceo_slots"] = int(reserve_payload.get("ceo_slots", 0))

static func _append_turn_order_features(features: Dictionary, turn_order_payload: Dictionary) -> void:
	features["turn_order_value"] = float(turn_order_payload.get("value", 0.0))
	features["turn_order_position"] = int(turn_order_payload.get("position", 0))

static func _read_non_negative_int(value, fallback: int) -> int:
	if value is int:
		return maxi(0, int(value))
	if value is float:
		return maxi(0, int(value))
	if value is String and str(value).is_valid_int():
		return maxi(0, int(str(value)))
	return fallback

static func _read_int(value, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String and str(value).is_valid_int():
		return int(str(value))
	return fallback
