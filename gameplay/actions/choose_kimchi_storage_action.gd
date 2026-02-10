# Cleanup：泡菜冰柜储存选择
# - store=true：保留最多 10 个 kimchi，并清空其它库存
# - store=false：丢弃所有 kimchi（允许保留其它库存/进入冰箱选择）
class_name ChooseKimchiStorageAction
extends ActionExecutor

const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const PRODUCT_ID := "kimchi"
const PENDING_KIND_KIMCHI := "kimchi"
const PENDING_KIND_FRIDGE := "fridge"

func _init() -> void:
	action_id = "choose_kimchi_storage"
	display_name = "选择泡菜储存"
	description = "清理阶段：选择是否使用泡菜冰柜（储存泡菜则只能保留泡菜，最多 10）"
	allowed_phases = [DefsClass.PHASE_CLEANUP]
	requires_actor = true
	is_mandatory = false
	is_internal = true

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if str(state.phase) != DefsClass.PHASE_CLEANUP:
		return Result.failure("仅可在 Cleanup 阶段执行")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if state.turn_order.is_empty():
		return Result.failure("turn_order 为空")
	if command.actor != state.get_current_player_id():
		return Result.failure("不是你的回合")

	var kind_r := _get_cleanup_pending_kind(state)
	if not kind_r.ok:
		return kind_r
	var kind: String = str(kind_r.value)
	if kind != PENDING_KIND_KIMCHI:
		return Result.failure("当前不是泡菜储存选择（kind=%s）" % kind)

	var pending_r := _get_pending_cleanup_players(state)
	if not pending_r.ok:
		return pending_r
	var pending: Array[int] = pending_r.value
	if pending.is_empty():
		return Result.failure("当前没有待处理的泡菜储存选择")
	if int(pending[0]) != int(command.actor):
		return Result.failure("当前不是需要选择泡菜储存的玩家")

	var store_r := _require_bool_param(command, "store")
	if not store_r.ok:
		return store_r

	var player: Dictionary = state.players[command.actor]
	var inventory_val = player.get("inventory", null)
	if not (inventory_val is Dictionary):
		return Result.failure("player.inventory 类型错误（期望 Dictionary）")
	var inventory: Dictionary = inventory_val
	var available_r := _get_kimchi_available(state, command.actor, inventory)
	if not available_r.ok:
		return available_r
	var available: int = int(available_r.value)
	if available <= 0:
		return Result.failure("当前玩家没有泡菜，无需选择储存")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var warnings: Array[String] = []

	var store_r := _require_bool_param(command, "store")
	if not store_r.ok:
		return store_r
	var store: bool = bool(store_r.value)

	var player: Dictionary = state.players[command.actor]
	var inventory: Dictionary = player.get("inventory", {})

	var available_r := _get_kimchi_available(state, command.actor, inventory)
	if not available_r.ok:
		return available_r
	var before_kimchi: int = maxi(0, int(available_r.value))
	if before_kimchi <= 0:
		return Result.failure("内部错误：kimchi 可用数量为空")

	var discarded: Dictionary = {}
	if store:
		var kept_kimchi: int = clampi(before_kimchi, 0, 10)
		for k in inventory.keys():
			var pid: String = str(k)
			if pid.is_empty():
				continue
			if pid == PRODUCT_ID:
				continue
			var before: int = maxi(0, int(inventory.get(pid, 0)))
			inventory[pid] = 0
			if before > 0:
				discarded[pid] = before

		inventory[PRODUCT_ID] = kept_kimchi
		var delta_kimchi := before_kimchi - kept_kimchi
		if delta_kimchi > 0:
			discarded[PRODUCT_ID] = int(discarded.get(PRODUCT_ID, 0)) + delta_kimchi
	else:
		# 不存泡菜：丢弃全部泡菜（包含本回合计划产出的泡菜），其它商品保持不变（由 base 冰箱逻辑决定是否还需进一步选择）
		inventory[PRODUCT_ID] = 0
		discarded[PRODUCT_ID] = before_kimchi

	player["inventory"] = inventory
	state.players[command.actor] = player

	_merge_cleanup_inventory_discarded(state, command.actor, discarded)

	if not discarded.is_empty():
		var ms := MilestoneSystemClass.process_event(state, "CleanupDiscard", {
			"player_id": command.actor,
			"discarded": discarded,
		})
		if not ms.ok:
			warnings.append("里程碑触发失败(CleanupDiscard): 玩家 %d: %s" % [command.actor, ms.error])
		else:
			warnings.append_array(ms.warnings)

	# === pending 流转：先处理 kimchi 选择；结束后再进入 fridge 选择（若有） ===
	var pending_r := _get_pending_cleanup_players(state)
	if not pending_r.ok:
		return pending_r
	var pending: Array[int] = pending_r.value
	if pending.is_empty() or int(pending[0]) != int(command.actor):
		return Result.failure("内部错误：pending_phase_actions[Cleanup] 异常")
	pending.remove_at(0)

	var cleanup_val = state.round_state.get("cleanup", null)
	var cleanup: Dictionary = cleanup_val if cleanup_val is Dictionary else {}

	# 若选择存泡菜，则不再需要冰箱选择：从 fridge_pending_players 中移除
	if store:
		var fp_val = cleanup.get("fridge_pending_players", [])
		if fp_val is Array:
			var fp_any: Array = fp_val
			var fp: Array[int] = []
			for v in fp_any:
				fp.append(int(v))
			fp = fp.filter(func(pid: int) -> bool: return pid != int(command.actor))
			cleanup["fridge_pending_players"] = fp

	# kimchi pending 仍未结束：继续 kimchi 选择
	if not pending.is_empty():
		cleanup["pending_choice_kind"] = PENDING_KIND_KIMCHI
		state.round_state["cleanup"] = cleanup
		_set_pending_cleanup_players(state, pending)
		_set_current_player_to_pid(state, int(pending[0]))
		return Result.success().with_warnings(warnings)

	# kimchi 选择结束：转入 fridge 选择（若存在）
	var fridge_pending: Array[int] = []
	var fp2_val = cleanup.get("fridge_pending_players", [])
	if fp2_val is Array:
		for v in fp2_val:
			fridge_pending.append(int(v))

	if not fridge_pending.is_empty():
		cleanup["pending_choice_kind"] = PENDING_KIND_FRIDGE
		if cleanup.has("fridge_choice_pending"):
			cleanup["fridge_choice_pending"] = true
		state.round_state["cleanup"] = cleanup
		_set_pending_cleanup_players(state, fridge_pending)
		_set_current_player_to_pid(state, int(fridge_pending[0]))
		return Result.success().with_warnings(warnings)

	# 全部 pending 完成：解除阻塞并执行里程碑池清理
	cleanup["pending_choice_kind"] = ""
	if cleanup.has("fridge_choice_pending"):
		cleanup["fridge_choice_pending"] = false
	state.round_state["cleanup"] = cleanup
	_set_pending_cleanup_players(state, [] as Array[int])
	if state.round_state.has("cleanup_defer_milestone_cleanup"):
		state.round_state.erase("cleanup_defer_milestone_cleanup")

	var milestone_cleanup := CleanupSettlementClass.apply_cleanup_milestones(state)
	if not milestone_cleanup.ok:
		return milestone_cleanup
	warnings.append_array(milestone_cleanup.warnings)
	return Result.success().with_warnings(warnings)

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if old_state == null or new_state == null or command == null:
		return out
	if not ProductRegistryClass.is_loaded():
		return out

	var actor := int(command.actor)
	if actor < 0 or actor >= new_state.players.size():
		return out

	var old_p_val = old_state.players[actor]
	var new_p_val = new_state.players[actor]
	if not (old_p_val is Dictionary) or not (new_p_val is Dictionary):
		return out
	var old_p: Dictionary = old_p_val
	var new_p: Dictionary = new_p_val

	var old_inv_val = old_p.get("inventory", null)
	var new_inv_val = new_p.get("inventory", null)
	if not (old_inv_val is Dictionary) or not (new_inv_val is Dictionary):
		return out
	var old_inv: Dictionary = old_inv_val
	var new_inv: Dictionary = new_inv_val

	var discarded: Dictionary = {}
	for k in old_inv.keys():
		var pid: String = str(k)
		if pid.is_empty():
			continue
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val == null or not (def_val is ProductDef):
			continue
		var def: ProductDef = def_val
		if not (def.has_tag("food") or def.has_tag("drink")):
			continue

		var before: int = maxi(0, int(old_inv.get(pid, 0)))
		var after: int = maxi(0, int(new_inv.get(pid, 0)))
		var delta := before - after
		if delta > 0:
			discarded[pid] = delta

	if discarded.is_empty():
		return out

	# 是否拥有冰箱：仅用于 UI 展示（复用 base 逻辑）
	var has_fridge := false
	var ms_val = new_p.get("milestones", [])
	if ms_val is Array:
		var fridge_r := CleanupSettlementClass.get_fridge_capacity_from_milestones(ms_val)
		if fridge_r.ok:
			var fridge: Dictionary = fridge_r.value
			has_fridge = bool(fridge.get("has_fridge", false))

	out.append({
		"type": EventBus.EventType.FOOD_DISCARDED,
		"data": {
			"round": int(new_state.round_number),
			"player_id": actor,
			"has_fridge": has_fridge,
			"discarded": discarded,
		}
	})
	return out

static func _get_kimchi_available(state: GameState, player_id: int, inventory: Dictionary) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var inv_before: int = 0
	if inventory != null and inventory is Dictionary:
		inv_before = maxi(0, int(inventory.get(PRODUCT_ID, 0)))

	var rs_val = Dictionary(state.round_state).get(PRODUCT_ID, null)
	if rs_val == null:
		return Result.success(inv_before)
	if not (rs_val is Dictionary):
		return Result.failure("round_state.kimchi 类型错误（期望 Dictionary）")
	var rs: Dictionary = rs_val

	# 优先使用 available_by_player（由 kimchi cleanup settlement 计算：包含“上回合存的 + 本回合计划产出”）
	var avail_val = rs.get("available_by_player", null)
	if avail_val is Dictionary:
		var avail: Dictionary = avail_val
		if avail.has(player_id):
			return Result.success(maxi(inv_before, int(avail.get(player_id, inv_before))))
		var key_s := str(player_id)
		if avail.has(key_s):
			return Result.success(maxi(inv_before, int(avail.get(key_s, inv_before))))

	# 兜底：carried_over_before_cleanup + planned_produced_by_player
	var carried_val = rs.get("carried_over_before_cleanup", null)
	var planned_val = rs.get("planned_produced_by_player", null)
	if carried_val is Dictionary and planned_val is Dictionary:
		var carried: Dictionary = carried_val
		var planned: Dictionary = planned_val
		var c := 0
		if carried.has(player_id):
			c = maxi(0, int(carried.get(player_id, 0)))
		elif carried.has(str(player_id)):
			c = maxi(0, int(carried.get(str(player_id), 0)))
		var p := 0
		if planned.has(player_id):
			p = maxi(0, int(planned.get(player_id, 0)))
		elif planned.has(str(player_id)):
			p = maxi(0, int(planned.get(str(player_id), 0)))
		return Result.success(maxi(inv_before, c + p))

	return Result.success(inv_before)

static func _require_bool_param(command: Command, key: String) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if not command.params.has(key):
		return Result.failure("缺少参数: %s" % key, Result.ErrorCode.MISSING_PARAMS)
	var value = command.params[key]
	if not (value is bool):
		return Result.failure("%s 必须为 bool" % key)
	return Result.success(bool(value))

static func _get_cleanup_pending_kind(state: GameState) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var cleanup_val = Dictionary(state.round_state).get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return Result.failure("round_state.cleanup 类型错误（期望 Dictionary）")
	var cleanup: Dictionary = cleanup_val
	var kind_val = cleanup.get("pending_choice_kind", "")
	if not (kind_val is String):
		return Result.failure("round_state.cleanup.pending_choice_kind 类型错误（期望 String）")
	var kind: String = str(kind_val)
	return Result.success(kind)

static func _get_pending_cleanup_players(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has("pending_phase_actions"):
		return Result.success([] as Array[int])
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(DefsClass.PHASE_CLEANUP):
		return Result.success([] as Array[int])
	var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return Result.failure("pending_phase_actions[Cleanup] 类型错误（期望 Array）")
	var list: Array = list_val
	var out: Array[int] = []
	for v in list:
		out.append(int(v))
	return Result.success(out)

static func _set_pending_cleanup_players(state: GameState, pending: Array[int]) -> void:
	if state == null or not (state.round_state is Dictionary):
		return
	if not state.round_state.has("pending_phase_actions"):
		state.round_state["pending_phase_actions"] = {}
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return
	var ppa: Dictionary = ppa_val
	if pending.is_empty():
		ppa.erase(DefsClass.PHASE_CLEANUP)
	else:
		ppa[DefsClass.PHASE_CLEANUP] = pending
	state.round_state["pending_phase_actions"] = ppa

static func _set_current_player_to_pid(state: GameState, pid: int) -> void:
	if state == null:
		return
	for idx in range(state.turn_order.size()):
		if int(state.turn_order[idx]) == int(pid):
			state.current_player_index = idx
			break

static func _merge_cleanup_inventory_discarded(state: GameState, player_id: int, discarded_delta: Dictionary) -> void:
	if state == null or not (state.round_state is Dictionary):
		return
	if discarded_delta == null or not (discarded_delta is Dictionary) or discarded_delta.is_empty():
		return

	var cleanup_val = state.round_state.get("cleanup", null)
	var cleanup: Dictionary = cleanup_val if cleanup_val is Dictionary else {}
	var inv_val = cleanup.get("inventory_discarded", null)
	var inv: Array = inv_val if inv_val is Array else []

	for idx in range(inv.size()):
		var item_val = inv[idx]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("player_id", -1)) != int(player_id):
			continue
		var prev_val = item.get("discarded", {})
		var prev: Dictionary = prev_val if prev_val is Dictionary else {}
		for k in discarded_delta.keys():
			var pid: String = str(k)
			var add_amt: int = int(discarded_delta.get(k, 0))
			if add_amt <= 0 or pid.is_empty():
				continue
			prev[pid] = int(prev.get(pid, 0)) + add_amt
		item["discarded"] = prev
		inv[idx] = item
		cleanup["inventory_discarded"] = inv
		state.round_state["cleanup"] = cleanup
		return

	# 兜底：理论上 primary cleanup 已为每个玩家写入 inventory_discarded；若缺失则补写。
	inv.append({
		"player_id": int(player_id),
		"has_fridge": false,
		"discarded": discarded_delta.duplicate(true),
	})
	cleanup["inventory_discarded"] = inv
	state.round_state["cleanup"] = cleanup
