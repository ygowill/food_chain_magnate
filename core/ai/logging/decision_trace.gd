class_name DecisionTrace
extends RefCounted

const JsonSafeClass = preload("res://core/state/serialization/json_safe.gd")

var round_number: int = 0
var phase: String = ""
var sub_phase: String = ""
var player_id: int = -1
var observation_hash: String = ""
var candidate_count: int = 0
var valid_candidate_count: int = 0
var chosen_action_id: String = ""
var chosen_params: Dictionary = {}
var score: float = 0.0
var top_candidates: Array[Dictionary] = []
var discarded_reasons: Array[String] = []
var belief_samples_summary: Dictionary = {}
var time_ms: int = 0

static func compute_observation_hash(observation: ObservationState) -> String:
	if observation == null:
		return ""
	var safe = JsonSafeClass.to_json_safe(observation.to_debug_dict())
	return JSON.stringify(safe, "", true).md5_text()

func add_top_candidate(candidate: Dictionary) -> void:
	top_candidates.append(candidate.duplicate(true))

func add_discarded_reason(reason: String) -> void:
	discarded_reasons.append(reason)

func to_dict() -> Dictionary:
	return {
		"round_number": round_number,
		"phase": phase,
		"sub_phase": sub_phase,
		"player_id": player_id,
		"observation_hash": observation_hash,
		"candidate_count": candidate_count,
		"valid_candidate_count": valid_candidate_count,
		"chosen_action_id": chosen_action_id,
		"chosen_params": chosen_params.duplicate(true),
		"score": score,
		"top_candidates": top_candidates.duplicate(true),
		"discarded_reasons": discarded_reasons.duplicate(),
		"belief_samples_summary": belief_samples_summary.duplicate(true),
		"time_ms": time_ms,
	}
