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
	var produced_next: Dictionary = {}  # player_id(int) -> produced_count(int)
	var pending_players: Array[int] = []
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("%s: cleanup(before): players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var player: Dictionary = p_val

		var employees_val = player.get("employees", null)
		if not (employees_val is Array):
			return Result.failure("%s: cleanup(before): players[%d].employees 类型错误（期望 Array）" % [MODULE_ID, pid])
		var employees: Array = employees_val
		var km_count := 0
		for i in range(employees.size()):
			var e_val = employees[i]
			if not (e_val is String):
				return Result.failure("%s: cleanup(before): players[%d].employees[%d] 类型错误（期望 String）" % [MODULE_ID, pid, i])
			if str(e_val) == KIMCHI_MASTER_ID:
				km_count += 1
		if km_count > 0:
			produced_next[pid] = km_count

		var inv_val = player.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("%s: cleanup(before): players[%d].inventory 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var inv: Dictionary = inv_val

		var count: int = maxi(0, int(inv.get(PRODUCT_ID, 0)))
		if count > 0:
			carried_over[pid] = count
			# 置零以防 primary cleanup 将其当作普通 food 丢弃。
			inv[PRODUCT_ID] = 0
			player["inventory"] = inv
			state.players[pid] = player

		# 若 cleanup 后将存在 kimchi（上回合存下来的或本次产出的），需要弹出“是否存泡菜”选择；
		# 同时要求 base cleanup 延迟里程碑池清理（避免选择导致的丢弃在清理后触发里程碑而残留在 pool 中）。
		if count + km_count > 0:
			pending_players.append(pid)

	if not pending_players.is_empty():
		state.round_state["cleanup_defer_milestone_cleanup"] = true

	if state.round_state.has(PRODUCT_ID) and not (state.round_state[PRODUCT_ID] is Dictionary):
		return Result.failure("%s: cleanup(before): round_state.kimchi 类型错误（期望 Dictionary）" % MODULE_ID)
	var rs: Dictionary = state.round_state.get(PRODUCT_ID, {})
	rs["carried_over_before_cleanup"] = carried_over
	rs["planned_produced_by_player"] = produced_next
	rs["pending_storage_players"] = pending_players
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

	# 2) 选择：若 cleanup 后存在 kimchi，则要求玩家选择是否存泡菜（存泡菜则其它库存不可保留）。
	# - kimchi 选择优先于冰箱选择（若存泡菜，则冰箱选择不再需要）。
	var fridge_pending_players: Array[int] = []
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
				fridge_pending_players.append(int(v))

	var pending_set := {}
	var rs_any = state.round_state.get(PRODUCT_ID, {})
	if rs_any is Dictionary:
		var rs2: Dictionary = rs_any
		var pending_val = rs2.get("pending_storage_players", [])
		if pending_val is Array:
			for v in pending_val:
				pending_set[int(v)] = true

	var kimchi_pending_players: Array[int] = []
	var order: Array[int] = []
	if state.turn_order is Array and not state.turn_order.is_empty():
		for v in state.turn_order:
			order.append(int(v))
	else:
		for pid2 in range(state.players.size()):
			order.append(pid2)

	for pid3 in order:
		if not pending_set.has(pid3):
			continue
		var p_val3 = state.players[pid3]
		if not (p_val3 is Dictionary):
			continue
		var p3: Dictionary = p_val3
		var inv3_val = p3.get("inventory", null)
		if not (inv3_val is Dictionary):
			continue
		var inv3: Dictionary = inv3_val
		if maxi(0, int(inv3.get(PRODUCT_ID, 0))) > 0:
			kimchi_pending_players.append(pid3)

	var cleanup_val = state.round_state.get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return Result.failure("%s: cleanup: round_state.cleanup 类型错误（期望 Dictionary）" % MODULE_ID)
	var cleanup: Dictionary = cleanup_val
	cleanup["kimchi_pending_players"] = kimchi_pending_players
	cleanup["fridge_pending_players"] = fridge_pending_players
	if cleanup.has("fridge_choice_pending"):
		cleanup["fridge_choice_pending"] = not fridge_pending_players.is_empty()

	# 设置 pending：kimchi 选择优先；若无 kimchi pending，则保持/进入 fridge pending。
	if not kimchi_pending_players.is_empty():
		cleanup["pending_choice_kind"] = "kimchi"
		state.round_state["cleanup"] = cleanup
		if not state.round_state.has("pending_phase_actions"):
			state.round_state["pending_phase_actions"] = {}
		var ppa2_val = state.round_state.get("pending_phase_actions", null)
		if not (ppa2_val is Dictionary):
			return Result.failure("%s: cleanup: pending_phase_actions 类型错误（期望 Dictionary）" % MODULE_ID)
		var ppa2: Dictionary = ppa2_val
		ppa2[PhaseDefsClass.PHASE_CLEANUP] = kimchi_pending_players
		state.round_state["pending_phase_actions"] = ppa2

		var next_pid: int = int(kimchi_pending_players[0])
		for idx2 in range(state.turn_order.size()):
			if int(state.turn_order[idx2]) == next_pid:
				state.current_player_index = idx2
				break
	elif not fridge_pending_players.is_empty():
		cleanup["pending_choice_kind"] = "fridge"
		state.round_state["cleanup"] = cleanup
	else:
		cleanup["pending_choice_kind"] = ""
		state.round_state["cleanup"] = cleanup

	state.round_state["kimchi"] = {
		"produced": produced,
		"carried_over": carried_over_by_player.duplicate(true),
		"pending_players": kimchi_pending_players,
	}

	return Result.success().with_warnings(warnings)
