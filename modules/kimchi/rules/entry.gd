extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const ProductRegistry = preload("res://core/data/product_registry.gd")

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
	# 说明：面条是 fallback 规则，不应在 base 可成交时被优先。
	var total := 0
	for k in base_required.keys():
		total += int(base_required.get(k, 0))
	if total > 0 and ProductRegistry.has("noodles"):
		out.append({
			"id": "%s:kimchi_plus_noodles" % MODULE_ID,
			"rank": 80,
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

func _on_cleanup_enter_after_primary(state: GameState, _phase_manager) -> Result:
	if state == null:
		return Result.failure("%s: cleanup: state 为空" % MODULE_ID)
	if not (state.players is Array):
		return Result.failure("%s: cleanup: state.players 类型错误（期望 Array）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: cleanup: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)

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
			continue

		var inv_val = player.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("%s: cleanup: players[%d].inventory 类型错误（期望 Dictionary）" % [MODULE_ID, pid])
		var inv: Dictionary = inv_val
		inv[PRODUCT_ID] = int(inv.get(PRODUCT_ID, 0)) + count
		player["inventory"] = inv
		state.players[pid] = player
		produced.append({"player_id": pid, "count": count})

	# 2) 储存规则（确定性实现）：
	# - 若玩家在 cleanup 后 inventory 中存在 kimchi，则其他所有产品均丢弃（不可与 kimchi 同存）
	# - kimchi 最多保留 10
	# 注意：这是无“玩家选择”的确定性版本；若未来引入选择，将改为显式动作。
	var stored: Array[Dictionary] = []
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

		var new_inv := {}
		for k in inv2.keys():
			new_inv[str(k)] = 0
		new_inv[PRODUCT_ID] = clampi(kimchi_count, 0, 10)
		player2["inventory"] = new_inv
		state.players[pid] = player2
		stored.append({"player_id": pid, "kimchi_kept": int(new_inv[PRODUCT_ID])})

	state.round_state["kimchi"] = {
		"produced": produced,
		"stored": stored,
	}

	return Result.success()
