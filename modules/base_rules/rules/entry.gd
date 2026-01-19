extends RefCounted

const PhaseAndMapClass = preload("res://modules/base_rules/rules/phase_and_map.gd")
const EffectsClass = preload("res://modules/base_rules/rules/effects.gd")
const MilestoneEffectsClass = preload("res://modules/base_rules/rules/milestone_effects.gd")
const ModuleEntryHelpersClass = preload("res://modules/module_entry_helpers.gd")

func register(registrar) -> Result:
	var parts := [
		PhaseAndMapClass.new(),
		EffectsClass.new(),
		MilestoneEffectsClass.new(),
	]
	return ModuleEntryHelpersClass.register_parts(registrar, parts)
