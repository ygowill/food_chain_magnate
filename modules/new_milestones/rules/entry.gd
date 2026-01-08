extends RefCounted

const EffectsClass = preload("res://modules/new_milestones/rules/effects.gd")
const ActionExecutorsClass = preload("res://modules/new_milestones/rules/action_executors.gd")
const MarketingInitiationClass = preload("res://modules/new_milestones/rules/marketing_initiation.gd")
const SettlementAndHooksClass = preload("res://modules/new_milestones/rules/settlement_and_hooks.gd")
const MilestoneEffectsClass = preload("res://modules/new_milestones/rules/milestone_effects.gd")

var _parts: Array = []

func register(registrar) -> Result:
	_parts = [
		EffectsClass.new(),
		ActionExecutorsClass.new(),
		MarketingInitiationClass.new(),
		SettlementAndHooksClass.new(),
		MilestoneEffectsClass.new(),
	]

	for part in _parts:
		var r: Result = part.register(registrar)
		if not r.ok:
			return r

	return Result.success()

