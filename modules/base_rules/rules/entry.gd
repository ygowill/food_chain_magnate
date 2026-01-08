extends RefCounted

const PhaseAndMapClass = preload("res://modules/base_rules/rules/phase_and_map.gd")
const EffectsClass = preload("res://modules/base_rules/rules/effects.gd")
const MilestoneEffectsClass = preload("res://modules/base_rules/rules/milestone_effects.gd")

var _parts: Array = []

func register(registrar) -> Result:
	_parts = [
		PhaseAndMapClass.new(),
		EffectsClass.new(),
		MilestoneEffectsClass.new(),
	]

	for part in _parts:
		var r: Result = part.register(registrar)
		if not r.ok:
			return r

	return Result.success()

