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

	r = registrar.register_effect_ui_text(EFFECT_ID_DISTANCE_DELTA, "晚餐选店距离-1（允许为负数）", 100)
	if not r.ok:
		return r

	r = registrar.register_milestone_effect("ketchup_active", Callable(self, "_milestone_effect_noop"))
	if not r.ok:
		return r

	r = registrar.register_milestone_effect_ui_text("ketchup_active", "晚餐选店距离-1（允许为负数）", 100)
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
	# 对齐规则书：晚餐选店时使用 (unit_price + distance - 1)，且可与 new_milestones 的距离修正叠加。
	# 通过 dist_ctx.allow_negative 支持负数距离（同 first_marketeer_used）。
	if ctx.has("allow_negative") and not (ctx["allow_negative"] is bool):
		return Result.failure("ketchup_mechanism:distance_delta: ctx.allow_negative 类型错误（期望 bool）")
	ctx["allow_negative"] = true
	ctx["distance"] = dist - 1
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

	# 同一晚餐可能有多名玩家的需求被“他人售出”（同一房屋多名 marketeer / 多个房屋）。
	# 里程碑最多每名玩家获得一次；按 player_id 去重并确定性排序后逐个触发。
	var unique_from_players := {}
	for e_val in events:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var from_val = e.get("from_player", null)
		if not (from_val is int):
			continue
		var from_player: int = int(from_val)
		if from_player < 0 or from_player >= state.players.size():
			return Result.failure("ketchup_mechanism: from_player 越界: %d" % from_player)
		unique_from_players[from_player] = true

	if unique_from_players.is_empty():
		return Result.success()

	var from_players: Array[int] = []
	for k in unique_from_players.keys():
		from_players.append(int(k))
	from_players.sort()

	for from_player in from_players:
		var r := MilestoneSystemClass.process_event(state, "KetchupSoldDemand", {
			"player_id": from_player,
			"milestone_id": MILESTONE_ID,
		})
		if not r.ok:
			return r

	return Result.success()
