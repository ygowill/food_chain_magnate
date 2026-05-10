class_name StrategicPlan
extends RefCounted

const DEFAULT_HORIZON_ROUNDS := 2
const DEFAULT_HORIZON_DECISIONS := 16

var id: String = ""
var owner_player_id: int = -1
var horizon_rounds: int = DEFAULT_HORIZON_ROUNDS
var horizon_decisions: int = DEFAULT_HORIZON_DECISIONS
var target_products: Array[String] = []
var target_houses: Array[String] = []
var target_employees: Array[String] = []
var route_type: String = ""
var constraints: Dictionary = {}
var prior_score: float = 0.0
var tags: Array[String] = []
var execution_sequence: Array[String] = []

static func create(
	p_id: String,
	p_owner_player_id: int,
	p_route_type: String,
	p_prior_score: float = 0.0,
	p_target_products: Array[String] = [],
	p_target_houses: Array[String] = [],
	p_target_employees: Array[String] = [],
	p_constraints: Dictionary = {},
	p_tags: Array[String] = [],
	p_horizon_rounds: int = DEFAULT_HORIZON_ROUNDS,
	p_horizon_decisions: int = DEFAULT_HORIZON_DECISIONS,
	p_execution_sequence: Array[String] = []
):
	var script := load("res://core/ai/planning/strategic_plan.gd")
	var plan = script.new()
	plan.id = str(p_id)
	plan.owner_player_id = int(p_owner_player_id)
	plan.route_type = str(p_route_type)
	plan.prior_score = float(p_prior_score)
	plan.target_products = _string_array(p_target_products)
	plan.target_houses = _string_array(p_target_houses)
	plan.target_employees = _string_array(p_target_employees)
	plan.constraints = p_constraints.duplicate(true)
	plan.tags = _string_array(p_tags)
	plan.horizon_rounds = maxi(0, int(p_horizon_rounds))
	plan.horizon_decisions = maxi(0, int(p_horizon_decisions))
	plan.execution_sequence = _string_array(p_execution_sequence)
	return plan

static func from_dict(data: Dictionary):
	var constraints_val = data.get("constraints", {})
	return create(
		str(data.get("id", "")),
		int(data.get("owner_player_id", -1)),
		str(data.get("route_type", "")),
		float(data.get("prior_score", 0.0)),
		_string_array(data.get("target_products", [])),
		_string_array(data.get("target_houses", [])),
		_string_array(data.get("target_employees", [])),
		Dictionary(constraints_val).duplicate(true) if constraints_val is Dictionary else {},
		_string_array(data.get("tags", [])),
		int(data.get("horizon_rounds", DEFAULT_HORIZON_ROUNDS)),
		int(data.get("horizon_decisions", DEFAULT_HORIZON_DECISIONS)),
		_string_array(data.get("execution_sequence", []))
	)

func duplicate_plan():
	return get_script().from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner_player_id": owner_player_id,
		"horizon_rounds": horizon_rounds,
		"horizon_decisions": horizon_decisions,
		"target_products": target_products.duplicate(),
		"target_houses": target_houses.duplicate(),
		"target_employees": target_employees.duplicate(),
		"route_type": route_type,
		"constraints": constraints.duplicate(true),
		"prior_score": prior_score,
		"tags": tags.duplicate(),
		"execution_sequence": execution_sequence.duplicate(),
	}

func to_trace_dict() -> Dictionary:
	return to_dict()

func is_valid() -> bool:
	return not id.strip_edges().is_empty() and owner_player_id >= 0 and not route_type.strip_edges().is_empty()

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty():
				out.append(text)
	return out
