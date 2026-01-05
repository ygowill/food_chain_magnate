extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
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
	return Result.success()

func _inc_rule(state: GameState, key: String) -> void:
	assert(state.rules is Dictionary, "probe_rules: state.rules 类型错误（期望 Dictionary）")
	var rules: Dictionary = state.rules
	var cur := 0
	if rules.has(key):
		assert(rules[key] is int, "probe_rules: state.rules[%s] 类型错误（期望 int）" % key)
		cur = int(rules[key])
	rules[key] = cur + 1
	state.rules = rules

func _on_dinnertime_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	_inc_rule(state, "probe_dinnertime_enter")
	return Result.success()

func _on_payday_exit(state: GameState, _phase_manager: PhaseManager) -> Result:
	_inc_rule(state, "probe_payday_exit")
	return Result.success()

func _on_marketing_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	_inc_rule(state, "probe_marketing_enter")
	return Result.success()

func _on_cleanup_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	_inc_rule(state, "probe_cleanup_enter")
	return Result.success()

func _generate_map_def(_player_count: int, _catalog, map_option, _rng_manager) -> Result:
	if map_option == null or not (map_option is MapOptionDefClass):
		return Result.failure("fixtures: probe_rules: map_option 类型错误（期望 MapOptionDef）")
	var opt = map_option
	if opt.layout_mode != "fixed":
		return Result.failure("fixtures: probe_rules: 仅支持 fixed layout_mode")
	var map_def := MapDefClass.create_fixed(opt.id, opt.tiles)
	map_def.display_name = opt.display_name
	map_def.min_players = opt.min_players
	map_def.max_players = opt.max_players
	return Result.success(map_def)
