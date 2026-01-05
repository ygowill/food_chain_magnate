extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MapDefClass = preload("res://core/map/map_def.gd")
const MapOptionDefClass = preload("res://core/map/map_option_def.gd")

const Phase = PhaseDefsClass.Phase

func register(registrar) -> Result:
	var r = registrar.register_primary_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_noop"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT, Callable(self, "_noop"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.MARKETING, SettlementRegistryClass.Point.ENTER, Callable(self, "_noop"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER, Callable(self, "_noop"))
	if not r.ok:
		return r
	r = registrar.register_primary_map_generator(Callable(self, "_generate_map_def"))
	if not r.ok:
		return r
	return Result.success()

func _noop(_state: GameState, _phase_manager: PhaseManager) -> Result:
	return Result.success()

func _generate_map_def(_player_count: int, _catalog, map_option, _rng_manager) -> Result:
	if map_option == null or not (map_option is MapOptionDefClass):
		return Result.failure("fixtures: dup_primary/a: map_option 类型错误（期望 MapOptionDef）")
	var opt = map_option
	if opt.layout_mode != "fixed":
		return Result.failure("fixtures: dup_primary/a: 仅支持 fixed layout_mode")
	var map_def := MapDefClass.create_fixed(opt.id, opt.tiles)
	map_def.display_name = opt.display_name
	map_def.min_players = opt.min_players
	map_def.max_players = opt.max_players
	return Result.success(map_def)
