extends RefCounted

const EffectsClass = preload("res://modules/new_milestones/rules/effects.gd")
const ActionExecutorsClass = preload("res://modules/new_milestones/rules/action_executors.gd")
const MarketingInitiationClass = preload("res://modules/new_milestones/rules/marketing_initiation.gd")
const SettlementAndHooksClass = preload("res://modules/new_milestones/rules/settlement_and_hooks.gd")
const MilestoneEffectsClass = preload("res://modules/new_milestones/rules/milestone_effects.gd")
const ModuleEntryHelpersClass = preload("res://core/modules/v2/module_entry_helpers.gd")

func register(registrar) -> Result:
	var parts := [
		EffectsClass.new(),
		ActionExecutorsClass.new(),
		MarketingInitiationClass.new(),
		SettlementAndHooksClass.new(),
		MilestoneEffectsClass.new(),
	]
	return ModuleEntryHelpersClass.register_parts(registrar, parts)
