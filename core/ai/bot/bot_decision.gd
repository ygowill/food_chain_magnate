class_name BotDecision
extends RefCounted

var command: Command = null
var macro_action_id: String = ""
var score: float = 0.0
var explanation: Dictionary = {}
var trace: Dictionary = {}
var failure_reason: String = ""

static func create(
	p_command: Command,
	p_macro_action_id: String = "",
	p_score: float = 0.0,
	p_explanation = null,
	p_trace = null
) -> BotDecision:
	var decision := BotDecision.new()
	decision.command = p_command
	decision.macro_action_id = p_macro_action_id
	decision.score = p_score
	decision.explanation = _copy_dict(p_explanation)
	decision.trace = _copy_dict(p_trace)
	return decision

static func failure(reason: String) -> BotDecision:
	var decision := BotDecision.new()
	decision.failure_reason = str(reason)
	decision.explanation = {"reason": decision.failure_reason}
	return decision

func is_failure() -> bool:
	return not failure_reason.is_empty()

func to_debug_dict() -> Dictionary:
	return {
		"command": command.to_dict() if command != null else {},
		"macro_action_id": macro_action_id,
		"score": score,
		"explanation": explanation.duplicate(true),
		"trace": trace.duplicate(true),
		"failure_reason": failure_reason,
	}

static func _copy_dict(value) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	return {}
