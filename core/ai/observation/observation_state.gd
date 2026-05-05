class_name ObservationState
extends RefCounted

var viewer_player_id: int = -1
var round_number: int = 0
var phase: String = ""
var sub_phase: String = ""
var current_player_id: int = -1
var turn_order: Array[int] = []
var selection_order: Array[int] = []
var bank_public: Dictionary = {}
var rules_public: Dictionary = {}
var modules: Array[String] = []
var own_player: Dictionary = {}
var public_players: Array[Dictionary] = []
var map_public: Dictionary = {}
var marketing_instances_public: Array = []
var employee_pool_public: Dictionary = {}
var milestone_pool_public: Array[String] = []
var round_state_public: Dictionary = {}
var hidden_summary: Dictionary = {}

func to_debug_dict() -> Dictionary:
	return {
		"viewer_player_id": viewer_player_id,
		"round_number": round_number,
		"phase": phase,
		"sub_phase": sub_phase,
		"current_player_id": current_player_id,
		"turn_order": turn_order.duplicate(),
		"selection_order": selection_order.duplicate(),
		"bank_public": bank_public.duplicate(true),
		"rules_public": rules_public.duplicate(true),
		"modules": modules.duplicate(),
		"own_player": own_player.duplicate(true),
		"public_players": public_players.duplicate(true),
		"map_public": map_public.duplicate(true),
		"marketing_instances_public": marketing_instances_public.duplicate(true),
		"employee_pool_public": employee_pool_public.duplicate(true),
		"milestone_pool_public": milestone_pool_public.duplicate(),
		"round_state_public": round_state_public.duplicate(true),
		"hidden_summary": hidden_summary.duplicate(true),
	}
