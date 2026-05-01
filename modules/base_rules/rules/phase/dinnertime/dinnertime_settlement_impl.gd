# DinnertimeSettlement（实现）
# 目标：聚合 Dinnertime 阶段“选店/售卖/里程碑/银行破产”逻辑，便于测试与复用。
extends RefCounted

const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const DinnertimeTimelineClass = preload("res://core/rules/dinnertime_timeline.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DinnertimeEffectsClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_effects.gd")
const DinnertimeHouseSalesClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_house_sales.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

const EFFECT_SEG_DINNERTIME_TIEBREAK := ":dinnertime:tiebreaker:"
const EFFECT_SEG_DINNERTIME_TIPS := ":dinnertime:tips:"
const EFFECT_SEG_DINNERTIME_INCOME_BONUS := ":dinnertime:income_bonus:"
const EFFECT_SEG_DINNERTIME_DISTANCE_DELTA := ":dinnertime:distance_delta:"
const EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS := ":dinnertime:sale_house_bonus:"
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"
const REQUIRE_DINNERTIME_CONFIRM_KEY := "require_dinnertime_confirm"
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

static func _bool_array_preview(arr: Array, limit: int = 12) -> String:
	if arr == null:
		return "null"
	var parts: Array[String] = []
	for i in range(min(arr.size(), limit)):
		parts.append("1" if bool(arr[i]) else "0")
	var suffix := "..." if arr.size() > parts.size() else ""
	return "%d[%s%s]" % [arr.size(), "".join(parts), suffix]

static func _pending_preview(pending: Array, limit: int = 6) -> String:
	if pending == null:
		return "null"
	var parts: Array[String] = []
	for i in range(min(pending.size(), limit)):
		var it = pending[i]
		if it is String:
			parts.append(str(it))
		elif it is Dictionary:
			var d: Dictionary = it
			parts.append("%s:%s" % [str(d.get("kind", "?")), str(d.get("player_id", "?"))])
		else:
			parts.append(str(typeof(it)))
	var suffix := "..." if pending.size() > parts.size() else ""
	return "len=%d [%s%s]" % [pending.size(), ", ".join(parts), suffix]

static func _is_online_dinnertime_confirm_enabled(state: GameState) -> bool:
	var v = _read_online_dinnertime_confirm_marker(state)
	if v is bool:
		return bool(v)
	if v is int:
		return int(v) > 0
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f) > 0
	return false

static func _read_online_dinnertime_confirm_marker(state: GameState):
	if state == null:
		return null
	if state.rules is Dictionary:
		var rules: Dictionary = state.rules
		if rules.has(ONLINE_DINNERTIME_CONFIRM_KEY):
			return rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, null)
	if state.round_state is Dictionary:
		var rs: Dictionary = state.round_state
		if rs.has(ONLINE_DINNERTIME_CONFIRM_KEY):
			return rs.get(ONLINE_DINNERTIME_CONFIRM_KEY, null)
	return null

static func _is_local_dinnertime_confirm_enabled(state: GameState) -> Result:
	if state == null:
		return Result.failure("DinnertimeSettlement: state 为空")
	if not (state.rules is Dictionary):
		return Result.failure("DinnertimeSettlement: state.rules 类型错误（期望 Dictionary）")
	var rules: Dictionary = state.rules
	if not rules.has(REQUIRE_DINNERTIME_CONFIRM_KEY):
		return Result.success(false)
	var v = rules.get(REQUIRE_DINNERTIME_CONFIRM_KEY, null)
	if v is bool:
		return Result.success(bool(v))
	if v is int:
		return Result.success(int(v) != 0)
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return Result.success(int(f) != 0)
	return Result.failure("DinnertimeSettlement: state.rules.%s 类型错误（期望 bool/int/float）" % REQUIRE_DINNERTIME_CONFIRM_KEY)

static func _build_dinnertime_confirm_pending(state: GameState, confirmed_players: Array[bool] = []) -> Array:
	if state == null or not (state.players is Array):
		return []
	if not _is_online_dinnertime_confirm_enabled(state):
		return [KIND_CONFIRM_DINNERTIME]
	if confirmed_players.is_empty():
		confirmed_players = _build_online_dinnertime_confirmed_players(state)
	var pending: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var is_confirmed := false
		if pid >= 0 and pid < confirmed_players.size():
			is_confirmed = bool(confirmed_players[pid])
		if is_confirmed:
			continue
		pending.append({
			"kind": KIND_CONFIRM_DINNERTIME,
			"player_id": pid,
		})
	return pending

static func _build_local_dinnertime_confirm_pending(state: GameState) -> Result:
	if state == null:
		return Result.failure("DinnertimeSettlement: state 为空")
	var pid := state.get_current_player_id()
	if pid < 0:
		return Result.failure("DinnertimeSettlement: 当前玩家无效，无法创建晚餐确认 pending")
	return Result.success([{
		"kind": KIND_CONFIRM_DINNERTIME,
		"player_id": pid,
	}])

static func _build_online_dinnertime_confirmed_players(state: GameState) -> Array[bool]:
	var confirmed: Array[bool] = []
	if state == null or not (state.players is Array):
		return confirmed
	for pid in range(state.players.size()):
		confirmed.append(_is_player_forfeited(state, pid))
	return confirmed

static func _ensure_online_dinnertime_confirmed_players(state: GameState) -> Result:
	if state == null or not (state.players is Array):
		return Result.failure("DinnertimeSettlement: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("DinnertimeSettlement: state.round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	if not rs.has(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY):
		var confirmed := _build_online_dinnertime_confirmed_players(state)
		rs[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed
		return Result.success(confirmed)
	return _read_online_dinnertime_confirmed_players(state)

static func _read_online_dinnertime_confirmed_players(state: GameState) -> Result:
	var out: Array[bool] = []
	if state == null or not (state.players is Array):
		return Result.failure("DinnertimeSettlement: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("DinnertimeSettlement: state.round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	if not rs.has(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY):
		return Result.success(out)
	var val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if not (val is Array):
		return Result.failure("DinnertimeSettlement: round_state.%s 类型错误（期望 Array）" % ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY)
	var raw: Array = Array(val)
	if raw.size() != state.players.size():
		return Result.failure("DinnertimeSettlement: round_state.%s 长度错误（期望 %d，实际 %d）" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, state.players.size(), raw.size()])
	for i in range(raw.size()):
		var v = raw[i]
		if v is bool:
			out.append(bool(v))
			continue
		if v is int:
			out.append(int(v) != 0)
			continue
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				out.append(int(f) != 0)
				continue
		return Result.failure("DinnertimeSettlement: round_state.%s[%d] 类型错误（期望 bool/int/float）" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, i])
	return Result.success(out)

static func _is_player_forfeited(state: GameState, player_id: int) -> bool:
	if state == null or not (state.players is Array):
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return false
	return bool(Dictionary(player_val).get("forfeited", false))

static func _validate_apply_inputs(state: GameState, phase_manager) -> Result:
	var map_read := MapStateAccessClass.require_map(state, "DinnertimeSettlement")
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value
	if not (state.players is Array):
		return Result.failure("DinnertimeSettlement: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("DinnertimeSettlement: state.round_state 类型错误（期望 Dictionary）")
	if not (state.bank is Dictionary):
		return Result.failure("DinnertimeSettlement: state.bank 类型错误（期望 Dictionary）")

	var effect_registry = null
	if phase_manager != null and phase_manager.has_method("get_effect_registry"):
		effect_registry = phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("晚餐结算失败：RoadGraph 未初始化")

	if not map.has("grid_size") or not (map["grid_size"] is Vector2i):
		return Result.failure("晚餐结算失败：state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map["grid_size"]

	var houses_read := MapStateAccessClass.require_houses(state, "晚餐结算失败：")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value

	var restaurants_read := MapStateAccessClass.require_restaurants(state, "晚餐结算失败：")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	return Result.success({
		"effect_registry": effect_registry,
		"road_graph": road_graph,
		"grid_size": grid_size,
		"houses": houses,
		"restaurants": restaurants,
	})

static func apply(state: GameState, phase_manager = null) -> Result:
	# 对齐 docs/rules.md：
	# 1) 按房屋编号升序处理有需求的房屋
	# 2) 候选餐厅：道路连通 + 库存满足全部需求
	# 3) 选择：最小（单价 + 距离），平局：女服务员数量多者胜，再平：回合顺序靠前者胜
	# 4) 结算：扣库存 + 入账；花园翻倍“单价部分”；奖励不翻倍；最终收入下限 0
	# 5) 女服务员：所有房屋处理完后，每位在岗女服务员赚取 3/5（里程碑）
	# 6) CFO：拥有在岗 CFO（或“拥有$100”里程碑）者，本回合收入（含女服务员）+50% 向上取整
	var env_read := _validate_apply_inputs(state, phase_manager)
	if not env_read.ok:
		return env_read
	var env: Dictionary = env_read.value

	var warnings: Array[String] = []
	var effect_registry = env.get("effect_registry", null)
	var road_graph = env.get("road_graph", null)
	var grid_size: Vector2i = env.get("grid_size", Vector2i.ZERO)
	var houses: Dictionary = env.get("houses", {})
	var restaurants: Dictionary = env.get("restaurants", {})

	var house_sales_read := DinnertimeHouseSalesClass.apply(
		state,
		effect_registry,
		road_graph,
		grid_size,
		houses,
		restaurants,
		EFFECT_SEG_DINNERTIME_DISTANCE_DELTA,
		EFFECT_SEG_DINNERTIME_TIEBREAK,
		EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS
	)
	if not house_sales_read.ok:
		return house_sales_read
	warnings.append_array(house_sales_read.warnings)

	if not (house_sales_read.value is Dictionary):
		return Result.failure("晚餐结算失败：内部错误（house_sales 返回值类型错误）")
	var house_sales: Dictionary = house_sales_read.value

	var income_sales_val = house_sales.get("income_sales", null)
	if not (income_sales_val is Array):
		return Result.failure("晚餐结算失败：内部错误（income_sales 类型错误）")
	var income_sales: Array = income_sales_val

	var income_sale_house_bonus_val = house_sales.get("income_sale_house_bonus", null)
	if not (income_sale_house_bonus_val is Array):
		return Result.failure("晚餐结算失败：内部错误（income_sale_house_bonus 类型错误）")
	var income_sale_house_bonus: Array = income_sale_house_bonus_val

	var total_income_before_cfo_val = house_sales.get("total_income_before_cfo", null)
	if not (total_income_before_cfo_val is Array):
		return Result.failure("晚餐结算失败：内部错误（total_income_before_cfo 类型错误）")
	var total_income_before_cfo: Array = total_income_before_cfo_val

	var sales_val = house_sales.get("sales", null)
	if not (sales_val is Array):
		return Result.failure("晚餐结算失败：内部错误（sales 类型错误）")
	var sales: Array = sales_val

	var skipped_val = house_sales.get("skipped", null)
	if not (skipped_val is Array):
		return Result.failure("晚餐结算失败：内部错误（skipped 类型错误）")
	var skipped: Array = skipped_val

	var sold_marketed_demand_events_val = house_sales.get("sold_marketed_demand_events", null)
	if not (sold_marketed_demand_events_val is Array):
		return Result.failure("晚餐结算失败：内部错误（sold_marketed_demand_events 类型错误）")
	var sold_marketed_demand_events: Array = sold_marketed_demand_events_val

	var bankruptcy_events_val = house_sales.get("bankruptcy_events", null)
	if bankruptcy_events_val == null:
		bankruptcy_events_val = []
	if not (bankruptcy_events_val is Array):
		return Result.failure("晚餐结算失败：内部错误（bankruptcy_events 类型错误）")
	var bankruptcy_events: Array = (bankruptcy_events_val as Array).duplicate(true)
	var bankruptcy_event_cursor := _read_bankruptcy_events_count(state)

	var timeline_events_val = house_sales.get("timeline_events", null)
	if timeline_events_val == null:
		timeline_events_val = []
	if not (timeline_events_val is Array):
		return Result.failure("晚餐结算失败：内部错误（timeline_events 类型错误）")
	var timeline_events: Array = (timeline_events_val as Array).duplicate(true)

	var income_tips: Array[int] = []
	var income_cfo: Array[int] = []
	var total_income: Array[int] = []
	for _i in range(state.players.size()):
		income_tips.append(0)
		income_cfo.append(0)
		total_income.append(0)

	# 4) tips（可插拔）
	for player_id in range(state.players.size()):
		var player_val = state.players[player_id]
		if not (player_val is Dictionary):
			return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)

		var tips_amount := 0
		var ctx := {
			"tips": 0,
			"use_employee_triggered": false,
		}
		var eff := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, player_id, effect_registry, EFFECT_SEG_DINNERTIME_TIPS, ctx)
		if not eff.ok:
			return eff
		warnings.append_array(eff.warnings)
		var tips_val = ctx.get("tips", 0)
		if not (tips_val is int):
			return Result.failure("晚餐结算失败：tips ctx.tips 类型错误（期望 int）")
		tips_amount = int(tips_val)
		if tips_amount <= 0:
			continue

		var ms_before := DinnertimeTimelineClass.snapshot_player_milestone_set(state, player_id)
		var tips_result := BankruptcyRulesClass.pay_bank_to_player(state, player_id, tips_amount, "女服务员收入")
		if not tips_result.ok:
			return Result.failure("女服务员收入支付失败：玩家 %d：%s" % [player_id, tips_result.error])
		warnings.append_array(tips_result.warnings)
		var tips_breaks := _collect_new_bankruptcy_events(state, bankruptcy_event_cursor, {
			DinnertimeTimelineClass.KEY_STAGE: DinnertimeTimelineClass.STAGE_POST_INCOME,
			DinnertimeTimelineClass.KEY_POST_INCOME_KIND: "tips",
			DinnertimeTimelineClass.KEY_PLAYER_ID: player_id,
			DinnertimeTimelineClass.KEY_PAYMENT_AMOUNT: tips_amount,
		})
		bankruptcy_event_cursor = int(tips_breaks.get("cursor", bankruptcy_event_cursor))
		var tips_break_events_val = tips_breaks.get("events", [])
		if tips_break_events_val is Array:
			for evt_val in tips_break_events_val:
				if evt_val is Dictionary:
					bankruptcy_events.append(evt_val)

		var ms_after := DinnertimeTimelineClass.snapshot_player_milestone_set(state, player_id)
		DinnertimeTimelineClass.append_new_milestone_events_for_player_from_diff(
			timeline_events,
			player_id,
			ms_before,
			ms_after,
			{
				DinnertimeTimelineClass.KEY_STAGE: DinnertimeTimelineClass.STAGE_POST_INCOME,
				DinnertimeTimelineClass.KEY_POST_INCOME_KIND: "tips",
				DinnertimeTimelineClass.KEY_PAYMENT_AMOUNT: tips_amount,
			}
		)

		income_tips[player_id] += tips_amount
		total_income_before_cfo[player_id] += tips_amount

	# 5) income bonus（可插拔；默认 CFO 加成 +50% 向上取整）
	for player_id in range(state.players.size()):
		var base_gain: int = int(total_income_before_cfo[player_id])
		if base_gain <= 0:
			continue

		var ctx := {
			"base_gain": base_gain,
			"extra": 0,
			"once": {},
		}
		var eff_emp := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, player_id, effect_registry, EFFECT_SEG_DINNERTIME_INCOME_BONUS, ctx)
		if not eff_emp.ok:
			return eff_emp
		warnings.append_array(eff_emp.warnings)
		var eff_ms := DinnertimeEffectsClass.apply_milestone_effects_by_segment(state, player_id, effect_registry, EFFECT_SEG_DINNERTIME_INCOME_BONUS, ctx)
		if not eff_ms.ok:
			return eff_ms
		warnings.append_array(eff_ms.warnings)

		var extra_val = ctx.get("extra", 0)
		if not (extra_val is int):
			return Result.failure("晚餐结算失败：income_bonus ctx.extra 类型错误（期望 int）")
		var extra: int = int(extra_val)
		if extra <= 0:
			continue

		var ms_before := DinnertimeTimelineClass.snapshot_player_milestone_set(state, player_id)
		var cfo_result := BankruptcyRulesClass.pay_bank_to_player(state, player_id, extra, "CFO 加成")
		if not cfo_result.ok:
			return Result.failure("CFO 加成支付失败：玩家 %d：%s" % [player_id, cfo_result.error])
		warnings.append_array(cfo_result.warnings)
		var cfo_breaks := _collect_new_bankruptcy_events(state, bankruptcy_event_cursor, {
			DinnertimeTimelineClass.KEY_STAGE: DinnertimeTimelineClass.STAGE_POST_INCOME,
			DinnertimeTimelineClass.KEY_POST_INCOME_KIND: "cfo",
			DinnertimeTimelineClass.KEY_PLAYER_ID: player_id,
			DinnertimeTimelineClass.KEY_PAYMENT_AMOUNT: extra,
		})
		bankruptcy_event_cursor = int(cfo_breaks.get("cursor", bankruptcy_event_cursor))
		var cfo_break_events_val = cfo_breaks.get("events", [])
		if cfo_break_events_val is Array:
			for evt_val in cfo_break_events_val:
				if evt_val is Dictionary:
					bankruptcy_events.append(evt_val)
		income_cfo[player_id] += extra

		var ms_after := DinnertimeTimelineClass.snapshot_player_milestone_set(state, player_id)
		DinnertimeTimelineClass.append_new_milestone_events_for_player_from_diff(
			timeline_events,
			player_id,
			ms_before,
			ms_after,
			{
				DinnertimeTimelineClass.KEY_STAGE: DinnertimeTimelineClass.STAGE_POST_INCOME,
				DinnertimeTimelineClass.KEY_POST_INCOME_KIND: "cfo",
				DinnertimeTimelineClass.KEY_PAYMENT_AMOUNT: extra,
			}
		)

	for player_id in range(state.players.size()):
		total_income[player_id] = int(total_income_before_cfo[player_id]) + int(income_cfo[player_id])

	state.round_state["dinnertime"] = {
		"sales": sales,
		"skipped": skipped,
		"income_sales": income_sales,
		"income_sale_house_bonus": income_sale_house_bonus,
		"income_tips": income_tips,
		"income_cfo_bonus": income_cfo,
		"total_income": total_income,
		"sold_marketed_demand_events": sold_marketed_demand_events,
		"bankruptcy_events": bankruptcy_events,
		"timeline_events": timeline_events,
	}

	var online_dinnertime_confirm_enabled := _is_online_dinnertime_confirm_enabled(state)
	var local_dinnertime_confirm_read := _is_local_dinnertime_confirm_enabled(state)
	if not local_dinnertime_confirm_read.ok:
		return local_dinnertime_confirm_read
	var local_dinnertime_confirm_enabled := bool(local_dinnertime_confirm_read.value)
	var should_inject_pending := online_dinnertime_confirm_enabled or local_dinnertime_confirm_enabled
	if should_inject_pending:
		var confirmed_players: Array[bool] = []
		var pending: Array = []
		if online_dinnertime_confirm_enabled and state.round_state is Dictionary:
			var confirmed_r := _ensure_online_dinnertime_confirmed_players(state)
			if not confirmed_r.ok:
				return confirmed_r
			confirmed_players = Array(confirmed_r.value, TYPE_BOOL, "", null)
			pending = _build_dinnertime_confirm_pending(state, confirmed_players)
		else:
			var local_pending_r := _build_local_dinnertime_confirm_pending(state)
			if not local_pending_r.ok:
				return local_pending_r
			pending = local_pending_r.value
		var set_pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
			state.round_state, DefsClass.PHASE_DINNERTIME, pending, "晚餐结算"
		)
		if not set_pending.ok:
			return set_pending
		if online_dinnertime_confirm_enabled:
			var expected := 0
			for pid in range(state.players.size()):
				if _is_player_forfeited(state, pid):
					continue
				expected += 1
			if pending.size() != expected:
				AutoloadAccessClass.log_warn(
					"Dinnertime",
					"Online pending mismatch round=%d expected=%d actual=%d confirmed=%s pending=%s"
						% [
							int(state.round_number),
							expected,
							pending.size(),
							_bool_array_preview(confirmed_players),
							_pending_preview(pending),
						]
				)
			else:
				AutoloadAccessClass.log_info(
					"Dinnertime",
					"Online pending injected round=%d confirmed=%s pending=%s"
						% [
							int(state.round_number),
							_bool_array_preview(confirmed_players),
							_pending_preview(pending),
						]
				)

	return Result.success().with_warnings(warnings)

static func _read_bankruptcy_events_count(state: GameState) -> int:
	if state == null or not (state.round_state is Dictionary):
		return 0
	var bankruptcy_val = state.round_state.get("bankruptcy", null)
	if not (bankruptcy_val is Dictionary):
		return 0
	var events_val = (bankruptcy_val as Dictionary).get("events", null)
	if not (events_val is Array):
		return 0
	return (events_val as Array).size()

static func _collect_new_bankruptcy_events(state: GameState, cursor: int, meta: Dictionary) -> Dictionary:
	var out_events: Array[Dictionary] = []
	if state == null or not (state.round_state is Dictionary):
		return {"cursor": 0, "events": out_events}

	var bankruptcy_val = state.round_state.get("bankruptcy", null)
	if not (bankruptcy_val is Dictionary):
		return {"cursor": 0, "events": out_events}

	var events_val = (bankruptcy_val as Dictionary).get("events", null)
	if not (events_val is Array):
		return {"cursor": 0, "events": out_events}

	var events: Array = events_val
	var start := maxi(0, cursor)
	for i in range(start, events.size()):
		var evt_val = events[i]
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = (evt_val as Dictionary).duplicate(true)
		for k in meta.keys():
			if not (k is String):
				continue
			evt[str(k)] = meta[k]
		out_events.append(evt)
	return {
		"cursor": events.size(),
		"events": out_events,
	}
