class_name MacroAction
extends RefCounted

var id: String = ""
var commands: Array[Command] = []
var prior_score: float = 0.0
var tags: Array[String] = []
var debug: Dictionary = {}

static func create(
	p_id: String,
	p_commands: Array[Command] = [],
	p_prior_score: float = 0.0,
	p_tags: Array[String] = [],
	p_debug = null
) -> MacroAction:
	var action := MacroAction.new()
	action.id = str(p_id)
	action.commands = Array(p_commands, TYPE_OBJECT, "RefCounted", Command)
	action.prior_score = p_prior_score
	action.tags = Array(p_tags, TYPE_STRING, "", null)
	if p_debug is Dictionary:
		action.debug = Dictionary(p_debug).duplicate(true)
	return action

func is_empty() -> bool:
	return commands.is_empty()

func to_debug_dict() -> Dictionary:
	var command_dicts := []
	for cmd in commands:
		command_dicts.append(cmd.to_dict() if cmd != null else {})
	return {
		"id": id,
		"commands": command_dicts,
		"prior_score": prior_score,
		"tags": tags.duplicate(),
		"debug": debug.duplicate(true),
	}
