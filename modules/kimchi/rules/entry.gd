extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const ProductRegistry = preload("res://core/data/product_registry.gd")
const DemandVariantHelpersClass = preload("res://modules/dinnertime_demand_variant_helpers.gd")
const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

const MODULE_ID := "kimchi"
const PRODUCT_ID := "kimchi"
const KIMCHI_MASTER_ID := "kimchi_master"
const EXTRA_LUXURY_MANAGER_PATCH_ID := "extra_luxury_manager"

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

func register(registrar) -> Result:
	var r = registrar.register_dinnertime_demand_provider(
		"%s:demand_variants" % MODULE_ID,
		Callable(self, "_get_demand_variants"),
		90
	)
	if not r.ok:
		return r

	# 额外 +1 张奢侈品经理（多模块同时使用时只加一次）
	r = registrar.register_employee_pool_patch(EXTRA_LUXURY_MANAGER_PATCH_ID, "luxury_manager", 1)
	if not r.ok:
		return r

	# Cleanup：在 primary 之前先“暂存”已存在的 kimchi（kimchi freezer：不依赖 base 冰箱里程碑）
	# - 目的：避免无冰箱时 primary cleanup 清空库存导致 kimchi 丢失。
	r = registrar.register_extension_settlement(
		Phase.CLEANUP,
		Point.ENTER,
		Callable(self, "_on_cleanup_enter_before_primary"),
		50
	)
	if not r.ok:
		return r

	# 清理阶段生产 kimchi，并应用“kimchi 储存互斥”规则
	r = registrar.register_extension_settlement(
		Phase.CLEANUP,
		Point.ENTER,
		Callable(self, "_on_cleanup_enter_after_primary"),
		150
	)
	if not r.ok:
		return r

	return Result.success()

func _get_demand_variants(_state: GameState, _house_id: String, house: Dictionary, base_required: Dictionary) -> Array[Dictionary]:
	if base_required == null or not (base_required is Dictionary):
		return []
	if base_required.is_empty():
		return []
	if house == null or not (house is Dictionary):
		return []
	# coffee 不可被替代/叠加进 kimchi 套餐
	if base_required.has("coffee"):
		return []

	var out: Array[Dictionary] = []

	# 1) Kimchi + base demand（优先于 base）
	var req_base := base_required.duplicate(true)
	req_base[PRODUCT_ID] = int(req_base.get(PRODUCT_ID, 0)) + 1
	out.append({
		"id": "%s:kimchi_plus_base" % MODULE_ID,
		"rank": 10,
		"required": req_base,
	})

	# 2) Kimchi + noodles（仅当 base 无法成交时才会走到这里，所以 rank 必须在 base 之后、noodles 之前）
	# 说明：在多模块交互（Sushi/Kimchi/Noodles）中，优先级为：
	#  - Kimchi+Sushi > Kimchi+Base > Kimchi+Noodles > Sushi > Base > Noodles
	# 因此 Kimchi+Noodles 需要排在 Sushi 与 Base 之前，但仍低于 Kimchi+Base。
	var total := DemandVariantHelpersClass.sum_required_counts(base_required)
	if total > 0 and ProductRegistry.has("noodles"):
		out.append({
			"id": "%s:kimchi_plus_noodles" % MODULE_ID,
			"rank": 20,
			"required": {
				"noodles": total,
				PRODUCT_ID: 1,
			},
		})

	# 3) Kimchi + sushi（仅花园房屋，且 sushi 模块启用时存在）
	if bool(house.get("has_garden", false)) and total > 0 and ProductRegistry.has("sushi"):
		out.append({
			"id": "%s:kimchi_plus_sushi" % MODULE_ID,
			"rank": 5,
			"required": {
				"sushi": total,
				PRODUCT_ID: 1,
			},
		})

	return out

func _on_cleanup_enter_before_primary(state: GameState, _phase_manager) -> Result:
	if state == null:
		return Result.failure("%s: cleanup(before): state 为空" % MODULE_ID)
	if not (state.players is Array):
		return Result.failure("%s: cleanup(before): state.players 类型错误（期望 Array）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: cleanup(before): state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)

	var carried_over: Dictionary = {}  # player_id(int) -> kimchi_count(int)
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("%s: cleanup(before): players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var player: Dictionary = p_val

		var inv_val = player.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("%s: cleanup(before): players[%d].inventory 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var inv: Dictionary = inv_val

		var count: int = maxi(0, int(inv.get(PRODUCT_ID, 0)))
		if count <= 0:
			continue

		carried_over[pid] = count
		# 置零以防 primary cleanup 将其当作普通 food 丢弃。
		inv[PRODUCT_ID] = 0
		player["inventory"] = inv
		state.players[pid] = player

	if carried_over.is_empty():
		return Result.success()

	if state.round_state.has(PRODUCT_ID) and not (state.round_state[PRODUCT_ID] is Dictionary):
		return Result.failure("%s: cleanup(before): round_state.kimchi 类型错误（期望 Dictionary）" % MODULE_ID)
	var rs: Dictionary = state.round_state.get(PRODUCT_ID, {})
	rs["carried_over_before_cleanup"] = carried_over
	state.round_state[PRODUCT_ID] = rs

	return Result.success()

func _on_cleanup_enter_after_primary(state: GameState, _phase_manager) -> Result:
	if state == null:
		return Result.failure("%s: cleanup: state 为空" % MODULE_ID)
	if not (state.players is Array):
		return Result.failure("%s: cleanup: state.players 类型错误（期望 Array）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: cleanup: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)

	var warnings: Array[String] = []

	# 0) 恢复：primary 前暂存的 kimchi（避免无冰箱时丢失）
	var carried_over_by_player: Dictionary = {}
	var rs_before_val = state.round_state.get(PRODUCT_ID, {})
	if rs_before_val != null:
		if not (rs_before_val is Dictionary):
			return Result.failure("%s: cleanup: round_state.kimchi 类型错误（期望 Dictionary）" % MODULE_ID)
		var rs_before: Dictionary = rs_before_val
		var co_val = rs_before.get("carried_over_before_cleanup", {})
		if co_val != null:
			if not (co_val is Dictionary):
				return Result.failure("%s: cleanup: round_state.kimchi.carried_over_before_cleanup 类型错误（期望 Dictionary）" % MODULE_ID)
			carried_over_by_player = co_val

	# 1) 生产：每个在岗 kimchi_master 生产 1 个 kimchi（自动保存）
	var produced: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("%s: cleanup: players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var player: Dictionary = p_val

		var employees_val = player.get("employees", null)
		if not (employees_val is Array):
			return Result.failure("%s: cleanup: players[%d].employees 类型错误（期望 Array）" % [MODULE_ID, pid])
		var employees: Array = employees_val

		var count := 0
		for i in range(employees.size()):
			var e_val = employees[i]
			if not (e_val is String):
				return Result.failure("%s: cleanup: players[%d].employees[%d] 类型错误（期望 String）" % [MODULE_ID, pid, i])
			if str(e_val) == KIMCHI_MASTER_ID:
				count += 1

		if count <= 0:
			count = 0

		var inv_val = player.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("%s: cleanup: players[%d].inventory 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var inv: Dictionary = inv_val

		var carried_over := 0
		if carried_over_by_player.has(pid):
			carried_over = maxi(0, int(carried_over_by_player.get(pid, 0)))

		var total := maxi(0, int(inv.get(PRODUCT_ID, 0))) + carried_over + count
		if total > 0:
			inv[PRODUCT_ID] = total
		elif inv.has(PRODUCT_ID):
			inv[PRODUCT_ID] = 0

		player["inventory"] = inv
		state.players[pid] = player
		if count > 0:
			produced.append({"player_id": pid, "count": count})

	# 2) 储存规则（确定性实现）：
	# - 若玩家在 cleanup 后 inventory 中存在 kimchi，则其他所有产品均丢弃（不可与 kimchi 同存）
	# - kimchi 最多保留 10
	# 注意：这是无“玩家选择”的确定性版本；若未来引入选择，将改为显式动作。
	var stored: Array[Dictionary] = []
	var pending_cleanup_players: Array[int] = []
	if state.round_state.has("pending_phase_actions"):
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if not (ppa_val is Dictionary):
			return Result.failure("%s: cleanup: pending_phase_actions 类型错误（期望 Dictionary）" % MODULE_ID)
		var ppa: Dictionary = ppa_val
		if ppa.has(PhaseDefsClass.PHASE_CLEANUP):
			var list_val = ppa.get(PhaseDefsClass.PHASE_CLEANUP, null)
			if not (list_val is Array):
				return Result.failure("%s: cleanup: pending_phase_actions[Cleanup] 类型错误（期望 Array）" % MODULE_ID)
			for v in list_val:
				pending_cleanup_players.append(int(v))

	var removed_from_pending: Dictionary = {}  # pid -> true
	for pid in range(state.players.size()):
		var p_val2 = state.players[pid]
		var player2: Dictionary = p_val2
		var inv_val2 = player2.get("inventory", null)
		if not (inv_val2 is Dictionary):
			return Result.failure("%s: cleanup: players[%d].inventory 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var inv2: Dictionary = inv_val2

		var kimchi_count: int = int(inv2.get(PRODUCT_ID, 0))
		if kimchi_count <= 0:
			continue

		var kept_kimchi: int = clampi(kimchi_count, 0, 10)

		# 计算因“kimchi freezer 互斥 + clamp”导致的丢弃，并同步写入 round_state.cleanup.inventory_discarded。
		var discarded_due_to_kimchi: Dictionary = {}
		for k in inv2.keys():
			var pid_key := str(k)
			if pid_key.is_empty():
				continue
			var before: int = maxi(0, int(inv2.get(k, 0)))
			var after := 0
			if pid_key == PRODUCT_ID:
				after = kept_kimchi
			var delta := before - after
			if delta > 0:
				discarded_due_to_kimchi[pid_key] = delta

		if not discarded_due_to_kimchi.is_empty():
			var cleanup_val = state.round_state.get("cleanup", null)
			if not (cleanup_val is Dictionary):
				return Result.failure("%s: cleanup: round_state.cleanup 类型错误（期望 Dictionary）" % MODULE_ID)
			var cleanup: Dictionary = cleanup_val
			var inv_disc_val = cleanup.get("inventory_discarded", null)
			if not (inv_disc_val is Array):
				return Result.failure("%s: cleanup: round_state.cleanup.inventory_discarded 类型错误（期望 Array）" % MODULE_ID)
			var inv_disc: Array = inv_disc_val

			var had_primary_discard := false
			var updated := false
			for idx in range(inv_disc.size()):
				var item_val = inv_disc[idx]
				if not (item_val is Dictionary):
					continue
				var item: Dictionary = item_val
				if int(item.get("player_id", -1)) != pid:
					continue
				var prev_val = item.get("discarded", {})
				if not (prev_val is Dictionary):
					return Result.failure("%s: cleanup: inventory_discarded[%d].discarded 类型错误（期望 Dictionary）" % [MODULE_ID, idx])
				var prev: Dictionary = prev_val
				had_primary_discard = not prev.is_empty()

				for dk in discarded_due_to_kimchi.keys():
					var key: String = str(dk)
					var add_amt: int = int(discarded_due_to_kimchi.get(dk, 0))
					if add_amt <= 0:
						continue
					prev[key] = int(prev.get(key, 0)) + add_amt
				item["discarded"] = prev
				inv_disc[idx] = item
				updated = true
				break
			if not updated:
				# 兜底：理论上 primary cleanup 已为每个玩家写入 inventory_discarded；若缺失则补写。
				inv_disc.append({
					"player_id": pid,
					"has_fridge": true,
					"discarded": discarded_due_to_kimchi.duplicate(true),
				})
				updated = true

			cleanup["inventory_discarded"] = inv_disc
			state.round_state["cleanup"] = cleanup

			# 只在 primary 未触发过 CleanupDiscard 时触发一次（避免同一玩家同一 Cleanup 重复触发）。
			if not had_primary_discard:
				var ms := MilestoneSystemClass.process_event(state, "CleanupDiscard", {
					"player_id": pid,
					"discarded": discarded_due_to_kimchi,
				})
				if not ms.ok:
					warnings.append("里程碑触发失败(CleanupDiscard): 玩家 %d: %s" % [pid, ms.error])
				else:
					warnings.append_array(ms.warnings)

		var new_inv := {}
		for k in inv2.keys():
			new_inv[str(k)] = 0
		new_inv[PRODUCT_ID] = kept_kimchi
		player2["inventory"] = new_inv
		state.players[pid] = player2
		stored.append({"player_id": pid, "kimchi_kept": int(new_inv[PRODUCT_ID])})

		# 若进入了冰箱选择 pending，则 kimchi 互斥结算后不再需要选择，直接解除阻塞。
		if pending_cleanup_players.has(pid):
			removed_from_pending[pid] = true

	if not removed_from_pending.is_empty():
		var new_pending: Array[int] = []
		for pid_val in pending_cleanup_players:
			var pid2: int = int(pid_val)
			if removed_from_pending.has(pid2):
				continue
			new_pending.append(pid2)

		var ppa2: Dictionary = state.round_state.get("pending_phase_actions", {})
		if not (ppa2 is Dictionary):
			return Result.failure("%s: cleanup: pending_phase_actions 类型错误（期望 Dictionary）" % MODULE_ID)
		if new_pending.is_empty():
			ppa2.erase(PhaseDefsClass.PHASE_CLEANUP)
		else:
			ppa2[PhaseDefsClass.PHASE_CLEANUP] = new_pending
		state.round_state["pending_phase_actions"] = ppa2

		# 同步 cleanup.fridge_choice_pending，并在 pending 清空时补跑 apply_cleanup_milestones（对齐 choose_fridge_keep 行为）。
		var cleanup_val2 = state.round_state.get("cleanup", null)
		if cleanup_val2 is Dictionary:
			var cleanup2: Dictionary = cleanup_val2
			if cleanup2.has("fridge_choice_pending"):
				cleanup2["fridge_choice_pending"] = not new_pending.is_empty()
				state.round_state["cleanup"] = cleanup2

		if new_pending.is_empty():
			var milestone_cleanup := CleanupSettlementClass.apply_cleanup_milestones(state)
			if not milestone_cleanup.ok:
				return milestone_cleanup
			warnings.append_array(milestone_cleanup.warnings)
		else:
			var next_pid: int = int(new_pending[0])
			for idx2 in range(state.turn_order.size()):
				if int(state.turn_order[idx2]) == next_pid:
					state.current_player_index = idx2
					break

	state.round_state["kimchi"] = {
		"produced": produced,
		"stored": stored,
		"carried_over": carried_over_by_player.duplicate(true),
	}

	return Result.success().with_warnings(warnings)
