extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

const Phase = PhaseDefsClass.Phase

const EFFECT_ID_DISTANCE_DELTA := "ketchup_mechanism:dinnertime:distance_delta:ketchup"
const MILESTONE_ID := "ketchup_sold_your_demand"

func register(registrar) -> Result:
	var r = registrar.register_effect(EFFECT_ID_DISTANCE_DELTA, Callable(self, "_effect_distance_minus_one"))
	if not r.ok:
		return r

	r = registrar.register_milestone_effect("ketchup_active", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r

	# 晚餐结算后：根据 round_state.dinnertime.sold_marketed_demand_events 触发一次获得
	return registrar.register_extension_settlement(
		Phase.DINNERTIME,
		SettlementRegistryClass.Point.ENTER,
		Callable(self, "_after_dinnertime_primary"),
		150
	)

func _milestone_effect_noop(_state: GameState, _player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	return Result.success()

func _effect_distance_minus_one(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("ketchup_mechanism:distance_delta: ctx 类型错误（期望 Dictionary）")
	if not ctx.has("distance") or not (ctx["distance"] is int):
		return Result.failure("ketchup_mechanism:distance_delta: ctx.distance 缺失或类型错误（期望 int）")
	var dist: int = int(ctx["distance"])
	ctx["distance"] = maxi(0, dist - 1)
	return Result.success()

func _after_dinnertime_primary(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("ketchup_mechanism: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("ketchup_mechanism: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("ketchup_mechanism: state.players 类型错误（期望 Array）")

	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.success()
	var ds: Dictionary = ds_val
	var events_val = ds.get("sold_marketed_demand_events", null)
	if not (events_val is Array):
		return Result.success()
	var events: Array = events_val
	if events.is_empty():
		return Result.success()

	# 触发频率：只处理一次（取事件序列中的第一条，保证确定性）
	var first_val = events[0]
	if not (first_val is Dictionary):
		return Result.success()
	var first: Dictionary = first_val
	var from_val = first.get("from_player", null)
	if not (from_val is int):
		return Result.success()
	var from_player: int = int(from_val)
	if from_player < 0 or from_player >= state.players.size():
		return Result.failure("ketchup_mechanism: from_player 越界: %d" % from_player)

	var r := MilestoneSystemClass.process_event(state, "KetchupSoldDemand", {
		"player_id": from_player,
		"milestone_id": MILESTONE_ID,
	})
	if not r.ok:
		return r

	return Result.success()

