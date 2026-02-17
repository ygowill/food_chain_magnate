extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseAndMapClass = preload("res://modules/base_rules/rules/phase_and_map.gd")
const EffectsClass = preload("res://modules/base_rules/rules/effects.gd")
const MilestoneEffectsClass = preload("res://modules/base_rules/rules/milestone_effects.gd")
const ModuleEntryHelpersClass = preload("res://core/modules/v2/module_entry_helpers.gd")

const CLEANUP_KIND_FRIDGE_KEEP := "fridge_keep"

func register(registrar) -> Result:
	var parts := [
		PhaseAndMapClass.new(),
		EffectsClass.new(),
		MilestoneEffectsClass.new(),
	]
	var r := ModuleEntryHelpersClass.register_parts(registrar, parts)
	if not r.ok:
		return r

	# UI：Cleanup pending choice 的 fridge_keep modal（base 行为由 core UI scene 提供；通过 ruleset 注册避免 core UI 特判）。
	var modal_r = registrar.register_phase_action_ui_modal(
		PhaseDefsClass.PHASE_CLEANUP,
		CLEANUP_KIND_FRIDGE_KEEP,
		"res://modules/base_rules/ui/components/modal_panel/fridge_keep_modal.tscn",
		100
	)
	if not modal_r.ok:
		return modal_r.with_warnings(r.warnings)

	return Result.success().with_warnings(r.warnings).with_warnings(modal_r.warnings)
