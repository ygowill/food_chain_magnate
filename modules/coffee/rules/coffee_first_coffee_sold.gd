extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const DinnertimeTimelineClass = preload("res://core/rules/dinnertime_timeline.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

const COFFEE_ID := "coffee"
const FIRST_COFFEE_SOLD_MILESTONE_ID := "first_coffee_sold"

const BONUS_PENDING_PLAYERS_KEY := "coffee_first_coffee_sold_bonus_pending_players"
const CLEANUP_TASK_KIND := "coffee_first_coffee_sold_bonus_coffee_shop"

static func _get_cleanup_pending_tasks(state: GameState) -> Result:
	if state == null:
		return Result.failure("coffee:first_coffee_sold: cleanup: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("coffee:first_coffee_sold: cleanup: state.round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has("pending_phase_actions"):
		return Result.success([] as Array[Dictionary])
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("coffee:first_coffee_sold: pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(PhaseDefsClass.PHASE_CLEANUP):
		return Result.success([] as Array[Dictionary])
	var list_val = ppa.get(PhaseDefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return Result.failure("coffee:first_coffee_sold: pending_phase_actions[Cleanup] 类型错误（期望 Array）")
	var list: Array = list_val
	var out: Array[Dictionary] = []
	for i in range(list.size()):
		var item_val = list[i]
		if not (item_val is Dictionary):
			return Result.failure("coffee:first_coffee_sold: pending_phase_actions[Cleanup][%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var kind_val = item.get("kind", null)
		var pid_val = item.get("player_id", null)
		if not (kind_val is String):
			return Result.failure("coffee:first_coffee_sold: pending_phase_actions[Cleanup][%d].kind 类型错误（期望 String）" % i)
		var kind: String = str(kind_val).strip_edges()
		if kind.is_empty():
			return Result.failure("coffee:first_coffee_sold: pending_phase_actions[Cleanup][%d].kind 不能为空" % i)
		var pid_read := _parse_int_value(pid_val, "coffee:first_coffee_sold: pending_phase_actions[Cleanup][%d].player_id" % i)
		if not pid_read.ok:
			return pid_read
		out.append({
			"kind": kind,
			"player_id": int(pid_read.value),
		})
	return Result.success(out)

func register(registrar) -> Result:
	# 晚餐结算后：按 route_purchases 触发 ProductSold(coffee) 事件，并记录“首杯咖啡奖励”待处理玩家列表
	var r = registrar.register_extension_settlement(Phase.DINNERTIME, Point.ENTER, Callable(self, "_after_dinnertime_primary"), 160)
	if not r.ok:
		return r

	# Cleanup 进入后：注入 pending_phase_actions[Cleanup]，按 turn_order 依次处理“额外咖啡店”奖励
	r = registrar.register_extension_settlement(Phase.CLEANUP, Point.ENTER, Callable(self, "_on_cleanup_enter_after_primary"), 160)
	if not r.ok:
		return r

	return Result.success()

func _after_dinnertime_primary(state: GameState, _phase_manager) -> Result:
	if state == null:
		return Result.failure("coffee:first_coffee_sold: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("coffee:first_coffee_sold: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("coffee:first_coffee_sold: state.players 类型错误（期望 Array）")

	var ds_read := _require_dinnertime_report(state)
	if not ds_read.ok:
		return ds_read
	var ds: Dictionary = ds_read.value
	var sales_read := _require_sales_report(ds)
	if not sales_read.ok:
		return sales_read
	var sales: Array = sales_read.value
	if sales.is_empty():
		return Result.success()

	var timeline_events := DinnertimeTimelineClass.ensure_state_timeline_events(state)

	var first_sale_index_by_seller := {}
	for sale_index in range(sales.size()):
		var sale_read := _require_sale_report(sale_index, sales[sale_index])
		if not sale_read.ok:
			return sale_read
		var s: Dictionary = sale_read.value
		var route_purchases: Array = s.get("route_purchases", [])
		for purchase_index in range(route_purchases.size()):
			var purchase_read := _require_route_purchase_report(sale_index, purchase_index, route_purchases[purchase_index])
			if not purchase_read.ok:
				return purchase_read
			var p: Dictionary = purchase_read.value
			if str(p.get("kind", "")) != COFFEE_ID:
				continue
			var seller: int = int(p.get("seller", -1))
			if seller < 0 or seller >= state.players.size():
				return Result.failure("coffee:first_coffee_sold: sales[%d].route_purchases[%d].seller 越界: %d" % [sale_index, purchase_index, seller])
			if not first_sale_index_by_seller.has(seller) or sale_index < int(first_sale_index_by_seller[seller]):
				first_sale_index_by_seller[seller] = sale_index

	if first_sale_index_by_seller.is_empty():
		return Result.success()

	var warnings: Array[String] = []
	var bonus_sellers := {}
	var seller_ids: Array[int] = []
	for k in first_sale_index_by_seller.keys():
		seller_ids.append(int(k))
	seller_ids.sort()
	for seller_id in seller_ids:
		var r2 := MilestoneSystemClass.process_event(state, "ProductSold", {
			"player_id": seller_id,
			"product": COFFEE_ID,
		})
		if not r2.ok:
			return r2
		warnings.append_array(r2.warnings)

		var v = r2.value
		if v is Dictionary:
			var claimed_val = Dictionary(v).get("claimed", [])
			if claimed_val is Array:
				var sale_index := int(first_sale_index_by_seller.get(seller_id, -1))
				for mid_val in Array(claimed_val):
					if not (mid_val is String):
						continue
					var mid := str(mid_val).strip_edges()
					if mid.is_empty():
						continue
					DinnertimeTimelineClass.append_sale_milestone(timeline_events, sale_index, seller_id, mid)
				if Array(claimed_val).has(FIRST_COFFEE_SOLD_MILESTONE_ID):
					bonus_sellers[seller_id] = true

	if bonus_sellers.is_empty():
		return Result.success().with_warnings(warnings)

	# 记录奖励玩家（按 turn_order 排序）
	var pending: Array[int] = []
	for pid_val in state.turn_order:
		var pid: int = int(pid_val)
		if bonus_sellers.has(pid):
			pending.append(pid)
	if not pending.is_empty():
		state.round_state[BONUS_PENDING_PLAYERS_KEY] = pending

	return Result.success().with_warnings(warnings)

func _on_cleanup_enter_after_primary(state: GameState, _phase_manager) -> Result:
	if state == null:
		return Result.failure("coffee:first_coffee_sold: cleanup: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("coffee:first_coffee_sold: cleanup: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("coffee:first_coffee_sold: cleanup: state.players 类型错误（期望 Array）")

	if not state.round_state.has(BONUS_PENDING_PLAYERS_KEY):
		return Result.success()
	var pending_val = state.round_state.get(BONUS_PENDING_PLAYERS_KEY, null)
	if not (pending_val is Array):
		return Result.failure("coffee:first_coffee_sold: %s 类型错误（期望 Array[int]）" % BONUS_PENDING_PLAYERS_KEY)
	var pending_players: Array = pending_val
	if pending_players.is_empty():
		state.round_state.erase(BONUS_PENDING_PLAYERS_KEY)
		return Result.success()

	var bonus_set := {}
	for i in range(pending_players.size()):
		var pid_read := _parse_int_value(pending_players[i], "coffee:first_coffee_sold: %s[%d]" % [BONUS_PENDING_PLAYERS_KEY, i])
		if not pid_read.ok:
			return pid_read
		var pid: int = int(pid_read.value)
		if pid < 0 or pid >= state.players.size():
			return Result.failure("coffee:first_coffee_sold: %s[%d] 玩家越界: %d" % [BONUS_PENDING_PLAYERS_KEY, i, pid])
		bonus_set[pid] = true

	# 读取现有 Cleanup pending（可能来自冰箱选择）
	var existing_read := _get_cleanup_pending_tasks(state)
	if not existing_read.ok:
		return existing_read
	var existing: Array[Dictionary] = existing_read.value

	# tasks_by_player: pid -> Array[Dictionary]
	var tasks_by_player := {}
	for d in existing:
		var pid: int = int(d.get("player_id", -1))
		if pid < 0 or pid >= state.players.size():
			continue
		if not tasks_by_player.has(pid):
			tasks_by_player[pid] = []
		(tasks_by_player[pid] as Array).append(d)

	# 合并：按 turn_order，先追加原任务，再追加 coffee bonus
	var merged: Array[Dictionary] = []
	for pid_val in state.turn_order:
		var pid3: int = int(pid_val)
		if tasks_by_player.has(pid3):
			merged.append_array(tasks_by_player[pid3])
		if bonus_set.has(pid3):
			# 去重：避免重复注入
			var already := false
			for t_val in merged:
				if t_val is Dictionary and str(Dictionary(t_val).get("kind", "")) == CLEANUP_TASK_KIND and int(Dictionary(t_val).get("player_id", -1)) == pid3:
					already = true
					break
			if not already:
				merged.append({
					"kind": CLEANUP_TASK_KIND,
					"player_id": pid3,
				})

	if merged.is_empty():
		state.round_state.erase(BONUS_PENDING_PLAYERS_KEY)
		return Result.success()

	var set_pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state,
		PhaseDefsClass.PHASE_CLEANUP,
		merged,
		"coffee:first_coffee_sold"
	)
	if not set_pending.ok:
		return set_pending

	# 将 current_player_index 对齐到第一位待处理玩家
	var first_task: Dictionary = merged[0]
	var first_pid: int = int(first_task.get("player_id", -1))
	for idx in range(state.turn_order.size()):
		if int(state.turn_order[idx]) == first_pid:
			state.current_player_index = idx
			break

	state.round_state.erase(BONUS_PENDING_PLAYERS_KEY)
	return Result.success()

static func _require_dinnertime_report(state: GameState) -> Result:
	if not state.round_state.has("dinnertime"):
		return Result.failure("coffee:first_coffee_sold: round_state.dinnertime 缺失")
	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.failure("coffee:first_coffee_sold: round_state.dinnertime 类型错误（期望 Dictionary）")
	return Result.success(ds_val)

static func _require_sales_report(dinnertime_report: Dictionary) -> Result:
	if not dinnertime_report.has("sales"):
		return Result.failure("coffee:first_coffee_sold: round_state.dinnertime.sales 缺失")
	var sales_val = dinnertime_report.get("sales", null)
	if not (sales_val is Array):
		return Result.failure("coffee:first_coffee_sold: round_state.dinnertime.sales 类型错误（期望 Array）")
	return Result.success(sales_val)

static func _require_sale_report(sale_index: int, sale_val) -> Result:
	var path := "coffee:first_coffee_sold: sales[%d]" % sale_index
	if not (sale_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var sale: Dictionary = sale_val
	if not sale.has("route_purchases"):
		return Result.failure("%s.route_purchases 缺失" % path)
	var purchases_val = sale.get("route_purchases", null)
	if not (purchases_val is Array):
		return Result.failure("%s.route_purchases 类型错误（期望 Array）" % path)
	return Result.success(sale)

static func _require_route_purchase_report(sale_index: int, purchase_index: int, purchase_val) -> Result:
	var path := "coffee:first_coffee_sold: sales[%d].route_purchases[%d]" % [sale_index, purchase_index]
	if not (purchase_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var purchase: Dictionary = purchase_val
	var kind_val = purchase.get("kind", null)
	if not (kind_val is String):
		return Result.failure("%s.kind 缺失或类型错误（期望 String）" % path)
	var kind := str(kind_val).strip_edges()
	if kind.is_empty():
		return Result.failure("%s.kind 不能为空" % path)
	purchase["kind"] = kind
	if kind != COFFEE_ID:
		return Result.success(purchase)
	var seller_read := _parse_int_value(purchase.get("seller", null), "%s.seller" % path)
	if not seller_read.ok:
		return seller_read
	purchase["seller"] = int(seller_read.value)
	return Result.success(purchase)

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 缺失或类型错误（期望 int）" % path)
