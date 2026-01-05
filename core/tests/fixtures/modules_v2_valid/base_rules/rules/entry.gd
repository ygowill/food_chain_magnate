extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const PaydaySettlementClass = preload("res://core/rules/phase/payday_settlement.gd")
const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const MapDefClass = preload("res://core/map/map_def.gd")
const MapOptionDefClass = preload("res://core/map/map_option_def.gd")

const Phase = PhaseDefsClass.Phase

func register(registrar) -> Result:
	var r = registrar.register_primary_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_dinnertime_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT, Callable(self, "_on_payday_exit"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.MARKETING, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_marketing_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_cleanup_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_map_generator(Callable(self, "_generate_map_def"))
	if not r.ok:
		return r
	r = registrar.register_milestone_effect("dummy", Callable(self, "_milestone_effect_dummy"))
	if not r.ok:
		return r
	return Result.success()

func _on_dinnertime_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	return DinnertimeSettlementClass.apply(state, _phase_manager)

func _on_payday_exit(state: GameState, _phase_manager: PhaseManager) -> Result:
	return PaydaySettlementClass.apply(state, _phase_manager)

func _on_cleanup_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	return CleanupSettlementClass.apply(state)

func _on_marketing_enter(state: GameState, phase_manager: PhaseManager) -> Result:
	var rounds_read := phase_manager.get_marketing_rounds(state)
	if not rounds_read.ok:
		return rounds_read
	var marketing_rounds: int = int(rounds_read.value)
	return MarketingSettlementClass.apply(state, phase_manager.get_marketing_range_calculator(), marketing_rounds, phase_manager)

func _milestone_effect_dummy(_state: GameState, _player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	return Result.success()

func _generate_map_def(_player_count: int, _catalog, map_option, _rng_manager) -> Result:
	if map_option == null or not (map_option is MapOptionDefClass):
		return Result.failure("fixtures: base_rules: map_option 类型错误（期望 MapOptionDef）")
	var opt = map_option
	if opt.layout_mode != "fixed":
		return Result.failure("fixtures: base_rules: 仅支持 fixed layout_mode")
	var map_def := MapDefClass.create_fixed(opt.id, opt.tiles)
	map_def.display_name = opt.display_name
	map_def.min_players = opt.min_players
	map_def.max_players = opt.max_players
	return Result.success(map_def)
