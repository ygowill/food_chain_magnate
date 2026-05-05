class_name AiDecisionContext
extends RefCounted

var player_id: int = -1
var phase: String = ""
var sub_phase: String = ""
var round_number: int = 0
var decision_seed: int = 0
var allowed_internal_actions: Array[String] = []

static func create(
	p_player_id: int,
	p_phase: String,
	p_sub_phase: String,
	p_round_number: int,
	p_decision_seed: int = 0,
	p_allowed_internal_actions: Array[String] = []
) -> AiDecisionContext:
	var context := AiDecisionContext.new()
	context.player_id = p_player_id
	context.phase = p_phase
	context.sub_phase = p_sub_phase
	context.round_number = p_round_number
	context.decision_seed = p_decision_seed
	context.allowed_internal_actions = Array(p_allowed_internal_actions, TYPE_STRING, "", null)
	return context

static func from_observation(observation: ObservationState, decision_seed: int = 0, allowed_internal_actions: Array[String] = []) -> Result:
	if observation == null:
		return Result.failure("AiDecisionContext.from_observation: observation is null")
	return Result.success(create(
		observation.viewer_player_id,
		observation.phase,
		observation.sub_phase,
		observation.round_number,
		decision_seed,
		allowed_internal_actions
	))

func to_debug_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"phase": phase,
		"sub_phase": sub_phase,
		"round_number": round_number,
		"decision_seed": decision_seed,
		"allowed_internal_actions": allowed_internal_actions.duplicate(),
	}
