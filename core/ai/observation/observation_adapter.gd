class_name ObservationAdapter
extends RefCounted

const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func observe_for_player(engine: GameEngine, viewer_player_id: int) -> Result:
	if engine == null:
		return Result.failure("ObservationAdapter.observe_for_player: engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("ObservationAdapter.observe_for_player: engine state is null")
	if viewer_player_id < 0 or viewer_player_id >= state.players.size():
		return Result.failure("ObservationAdapter.observe_for_player: viewer_player_id out of range: %d" % viewer_player_id)

	var viewer_read := PlayerStateAccessClass.require_player(state, viewer_player_id, "ObservationAdapter.observe_for_player")
	if not viewer_read.ok:
		return viewer_read

	var observation := ObservationState.new()
	observation.viewer_player_id = viewer_player_id
	observation.round_number = int(state.round_number)
	observation.phase = str(state.phase)
	observation.sub_phase = str(state.sub_phase)
	observation.current_player_id = _resolve_current_player_id(state)
	observation.turn_order = Array(state.turn_order, TYPE_INT, "", null)
	observation.selection_order = Array(state.selection_order, TYPE_INT, "", null)
	observation.bank_public = state.bank.duplicate(true)
	observation.rules_public = state.rules.duplicate(true)
	observation.modules = Array(state.modules, TYPE_STRING, "", null)
	observation.map_public = state.map.duplicate(true)
	observation.marketing_instances_public = state.marketing_instances.duplicate(true)
	observation.employee_pool_public = state.employee_pool.duplicate(true)
	observation.milestone_pool_public = Array(state.milestone_pool, TYPE_STRING, "", null)
	observation.round_state_public = _sanitize_round_state_for_viewer(state, viewer_player_id)

	var hidden_summary := {
		"reserve_cards_hidden_for_players": [],
		"company_structure_hidden_for_players": [],
		"round_state_hidden_paths": [],
	}
	var public_players: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var player_read := PlayerStateAccessClass.require_player(state, pid, "ObservationAdapter.observe_for_player")
		if not player_read.ok:
			return player_read
		var sanitized := _sanitize_player_for_viewer(state, viewer_player_id, pid, player_read.value, hidden_summary)
		public_players.append(sanitized)
		if pid == viewer_player_id:
			observation.own_player = sanitized.duplicate(true)
	observation.public_players = public_players
	observation.hidden_summary = hidden_summary

	return Result.success(observation)

static func _resolve_current_player_id(state: GameState) -> int:
	if state == null:
		return -1
	var idx := int(state.current_player_index)
	if idx < 0 or idx >= state.turn_order.size():
		return -1
	return int(state.turn_order[idx])

static func _sanitize_player_for_viewer(
	state: GameState,
	viewer_player_id: int,
	target_player_id: int,
	player: Dictionary,
	hidden_summary: Dictionary
) -> Dictionary:
	var out := player.duplicate(true)
	var is_self := viewer_player_id == target_player_id
	var can_view_reserve := is_self or _viewer_can_peek_all_reserve_cards(state, viewer_player_id)
	var reserve_revealed := _is_reserve_card_revealed(state, target_player_id)

	if not can_view_reserve:
		if reserve_revealed:
			_hide_unselected_reserve_cards(out)
		else:
			_hide_all_reserve_cards(out)
			_append_hidden_player(hidden_summary, "reserve_cards_hidden_for_players", target_player_id)

	if not is_self and _should_hide_company_structure(state):
		out["company_structure"] = {"hidden": true}
		_append_hidden_player(hidden_summary, "company_structure_hidden_for_players", target_player_id)

	return out

static func _sanitize_round_state_for_viewer(state: GameState, _viewer_player_id: int) -> Dictionary:
	var out := state.round_state.duplicate(true)
	var restructuring_val = out.get("restructuring", null)
	if restructuring_val is Dictionary:
		var restructuring: Dictionary = Dictionary(restructuring_val).duplicate(true)
		if not bool(restructuring.get("finalized", false)):
			restructuring["company_structures_hidden"] = true
		out["restructuring"] = restructuring
	return out

static func _hide_all_reserve_cards(player: Dictionary) -> void:
	if player.has("reserve_card_selected"):
		player["reserve_card_selected"] = "<hidden>"
	var cards_val = player.get("reserve_cards", null)
	if cards_val is Array:
		var hidden_cards := []
		for _card in cards_val:
			hidden_cards.append("<hidden>")
		player["reserve_cards"] = hidden_cards

static func _hide_unselected_reserve_cards(player: Dictionary) -> void:
	var selected_index := int(player.get("reserve_card_selected", -1))
	var cards_val = player.get("reserve_cards", null)
	if not (cards_val is Array):
		return
	var cards: Array = cards_val
	var sanitized_cards := []
	for i in range(cards.size()):
		if i == selected_index:
			var card_val = cards[i]
			sanitized_cards.append(card_val.duplicate(true) if card_val is Dictionary else card_val)
		else:
			sanitized_cards.append("<hidden>")
	player["reserve_cards"] = sanitized_cards

static func _viewer_can_peek_all_reserve_cards(state: GameState, viewer_player_id: int) -> bool:
	if state == null or viewer_player_id < 0 or viewer_player_id >= state.players.size():
		return false
	var player_val = state.players[viewer_player_id]
	if not (player_val is Dictionary):
		return false
	return bool(Dictionary(player_val).get("can_peek_all_reserve_cards", false))

static func _is_reserve_card_revealed(state: GameState, player_id: int) -> bool:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return false
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return false
	return bool(Dictionary(player_val).get("reserve_card_revealed", false))

static func _should_hide_company_structure(state: GameState) -> bool:
	if state == null:
		return false
	var restructuring_val = state.round_state.get("restructuring", null)
	if not (restructuring_val is Dictionary):
		return false
	var restructuring: Dictionary = restructuring_val
	return not bool(restructuring.get("finalized", false))

static func _append_hidden_player(hidden_summary: Dictionary, key: String, player_id: int) -> void:
	if not hidden_summary.has(key) or not (hidden_summary[key] is Array):
		hidden_summary[key] = []
	var arr: Array = hidden_summary[key]
	if not arr.has(player_id):
		arr.append(player_id)
	hidden_summary[key] = arr
