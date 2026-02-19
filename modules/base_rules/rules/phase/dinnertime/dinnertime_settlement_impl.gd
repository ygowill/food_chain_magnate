# DinnertimeSettlement（实现）
# 目标：聚合 Dinnertime 阶段“选店/售卖/里程碑/银行破产”逻辑，便于测试与复用。
extends RefCounted

const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DinnertimeEffectsClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_effects.gd")
const DinnertimeHouseSalesClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_house_sales.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

const EFFECT_SEG_DINNERTIME_TIEBREAK := ":dinnertime:tiebreaker:"
const EFFECT_SEG_DINNERTIME_TIPS := ":dinnertime:tips:"
const EFFECT_SEG_DINNERTIME_INCOME_BONUS := ":dinnertime:income_bonus:"
const EFFECT_SEG_DINNERTIME_DISTANCE_DELTA := ":dinnertime:distance_delta:"
const EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS := ":dinnertime:sale_house_bonus:"
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

static func _is_online_mode() -> bool:
	if NetContext == null:
		return false
	return NetContext.mode == NetContext.Mode.ONLINE_CLIENT or NetContext.mode == NetContext.Mode.ONLINE_SERVER

static func _is_online_dinnertime_confirm_enabled(state: GameState) -> bool:
	# 在线模式：必须启用（避免 server/client 在 headless 下状态分叉导致 resync 或错误跳过晚餐确认）。
	if _is_online_mode():
		return true

	# 兼容读取：
	# - 优先读取持久化到 state.rules 的标记（round_state 每回合会重建，不可靠）
	# - 同时兼容历史会话在 round_state 中的旧标记
	var v = _read_online_dinnertime_confirm_marker(state)
	if v is bool:
		return bool(v)
	if v is int:
		return int(v) > 0
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f) > 0
	return _is_online_mode()

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

static func _build_dinnertime_confirm_pending(state: GameState) -> Array:
	if state == null or not (state.players is Array):
		return []
	if not _is_online_dinnertime_confirm_enabled(state):
		return [KIND_CONFIRM_DINNERTIME]
	var confirmed_players := _read_online_dinnertime_confirmed_players(state)
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

static func _build_online_dinnertime_confirmed_players(state: GameState) -> Array[bool]:
	var confirmed: Array[bool] = []
	if state == null or not (state.players is Array):
		return confirmed
	for pid in range(state.players.size()):
		confirmed.append(_is_player_forfeited(state, pid))
	return confirmed

static func _read_online_dinnertime_confirmed_players(state: GameState) -> Array[bool]:
	var out: Array[bool] = []
	if state == null or not (state.players is Array):
		return out
	if not (state.round_state is Dictionary):
		return out
	var rs: Dictionary = state.round_state
	var val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if not (val is Array):
		return out
	var raw: Array = Array(val)
	if raw.size() != state.players.size():
		return out
	for v in raw:
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
		return []
	return out

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

		var tips_result := BankruptcyRulesClass.pay_bank_to_player(state, player_id, tips_amount, "女服务员收入")
		if not tips_result.ok:
			return Result.failure("女服务员收入支付失败：玩家 %d：%s" % [player_id, tips_result.error])
		warnings.append_array(tips_result.warnings)

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

		var cfo_result := BankruptcyRulesClass.pay_bank_to_player(state, player_id, extra, "CFO 加成")
		if not cfo_result.ok:
			return Result.failure("CFO 加成支付失败：玩家 %d：%s" % [player_id, cfo_result.error])
		warnings.append_array(cfo_result.warnings)
		income_cfo[player_id] += extra

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
	}

	# 注入阻塞：晚餐结算需等待玩家确认后才允许 auto-advance 离开 DINNERTIME。
	# 离线/本地 headless 测试仍保持“自动跳过晚餐阶段”，避免影响既有测试与快速流程。
	# 联机模式（包括 ONLINE_SERVER headless）必须注入 pending，确保与客户端状态一致，避免 state_hash 分叉触发 resync。
	# 注意：`godot --headless` 运行在 editor binary 下时，OS.has_feature("headless") 仍可能为 false；
	# 使用 DisplayServer.get_name() 判断显示模式更可靠。
	var online_dinnertime_confirm_enabled := _is_online_dinnertime_confirm_enabled(state)
	var should_inject_pending := (DisplayServer.get_name() != "headless") or online_dinnertime_confirm_enabled
	if should_inject_pending:
		if online_dinnertime_confirm_enabled and state.round_state is Dictionary:
			state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = _build_online_dinnertime_confirmed_players(state)
		var set_pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
			state.round_state, DefsClass.PHASE_DINNERTIME, _build_dinnertime_confirm_pending(state), "晚餐结算"
		)
		if not set_pending.ok:
			return set_pending

	return Result.success().with_warnings(warnings)
