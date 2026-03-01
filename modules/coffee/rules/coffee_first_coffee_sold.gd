extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const DinnertimeTimelineClass = preload("res://core/rules/dinnertime_timeline.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

const COFFEE_ID := "coffee"
const FIRST_COFFEE_SOLD_MILESTONE_ID := "first_coffee_sold"

const BONUS_PENDING_PLAYERS_KEY := "coffee_first_coffee_sold_bonus_pending_players"
const CLEANUP_TASK_KIND := "coffee_first_coffee_sold_bonus_coffee_shop"

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

	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.success()
	var ds: Dictionary = ds_val
	var sales_val = ds.get("sales", null)
	if not (sales_val is Array):
		return Result.success()
	var sales: Array = sales_val
	if sales.is_empty():
		return Result.success()

	var timeline_events := DinnertimeTimelineClass.ensure_state_timeline_events(state)

	var first_sale_index_by_seller := {}
	for sale_index in range(sales.size()):
		var s_val = sales[sale_index]
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var rp_val = s.get("route_purchases", null)
		if not (rp_val is Array):
			continue
		for p_val in Array(rp_val):
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			if str(p.get("kind", "")) != COFFEE_ID:
				continue
			var seller: int = int(p.get("seller", -1))
			if seller < 0 or seller >= state.players.size():
				continue
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
	for v in pending_players:
		var pid: int = int(v)
		if pid >= 0 and pid < state.players.size():
			bonus_set[pid] = true

	# 读取现有 Cleanup pending（可能来自冰箱选择）
	var existing: Array = []
	var ppa: Dictionary = {}
	if state.round_state.has("pending_phase_actions"):
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if not (ppa_val is Dictionary):
			return Result.failure("coffee:first_coffee_sold: pending_phase_actions 类型错误（期望 Dictionary）")
		ppa = ppa_val
	if ppa.has(PhaseDefsClass.PHASE_CLEANUP):
		var list_val = ppa.get(PhaseDefsClass.PHASE_CLEANUP, null)
		if not (list_val is Array):
			return Result.failure("coffee:first_coffee_sold: pending_phase_actions[Cleanup] 类型错误（期望 Array）")
		existing = list_val

	# tasks_by_player: pid -> Array[Dictionary]
	var tasks_by_player := {}
	for item_val in existing:
		if item_val is Dictionary:
			var d: Dictionary = item_val
			var pid: int = int(d.get("player_id", -1))
			if pid < 0 or pid >= state.players.size():
				continue
			if not tasks_by_player.has(pid):
				tasks_by_player[pid] = []
			(tasks_by_player[pid] as Array).append(d)
		elif item_val is int or item_val is float:
			# 兼容旧存档：Cleanup pending 列表为 [player_id(int)]（仅用于 fridge_keep）
			var pid2: int = int(item_val)
			if pid2 < 0 or pid2 >= state.players.size():
				continue
			if not tasks_by_player.has(pid2):
				tasks_by_player[pid2] = []
			(tasks_by_player[pid2] as Array).append({
				"kind": "fridge_keep",
				"player_id": pid2,
			})

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

	if state.round_state.has("pending_phase_actions"):
		var ppa_val2 = state.round_state.get("pending_phase_actions", null)
		if ppa_val2 == null:
			state.round_state["pending_phase_actions"] = {}
		elif not (ppa_val2 is Dictionary):
			return Result.failure("coffee:first_coffee_sold: pending_phase_actions 类型错误（期望 Dictionary）")
	else:
		state.round_state["pending_phase_actions"] = {}

	var ppa2: Dictionary = state.round_state["pending_phase_actions"]
	ppa2[PhaseDefsClass.PHASE_CLEANUP] = merged
	state.round_state["pending_phase_actions"] = ppa2

	# 将 current_player_index 对齐到第一位待处理玩家
	var first_task: Dictionary = merged[0]
	var first_pid: int = int(first_task.get("player_id", -1))
	for idx in range(state.turn_order.size()):
		if int(state.turn_order[idx]) == first_pid:
			state.current_player_index = idx
			break

	state.round_state.erase(BONUS_PENDING_PLAYERS_KEY)
	return Result.success()
