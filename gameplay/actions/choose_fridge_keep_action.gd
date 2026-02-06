# Cleanup：冰箱保留选择（food+drink 总量容量）
class_name ChooseFridgeKeepAction
extends ActionExecutor

const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

func _init() -> void:
	action_id = "choose_fridge_keep"
	display_name = "选择冰箱保留"
	description = "清理阶段：选择保留在冰箱中的食物/饮料（总量不超过容量）"
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
	if not ProductRegistryClass.is_loaded():
		return Result.failure("ProductRegistry 未初始化")

	var pending_r := _get_pending_cleanup_players(state)
	if not pending_r.ok:
		return pending_r
	var pending: Array[int] = pending_r.value
	if pending.is_empty():
		return Result.failure("当前没有待处理的冰箱选择")
	if int(pending[0]) != int(command.actor):
		return Result.failure("当前不是需要选择冰箱保留的玩家")

	var player: Dictionary = state.players[command.actor]
	var inventory_val = player.get("inventory", null)
	if not (inventory_val is Dictionary):
		return Result.failure("player.inventory 类型错误（期望 Dictionary）")
	var inventory: Dictionary = inventory_val

	var ms_val = player.get("milestones", null)
	if not (ms_val is Array):
		return Result.failure("player.milestones 类型错误（期望 Array）")
	var fridge_r := CleanupSettlementClass.get_fridge_capacity_from_milestones(ms_val)
	if not fridge_r.ok:
		return fridge_r
	var fridge: Dictionary = fridge_r.value
	if not bool(fridge.get("has_fridge", false)):
		return Result.failure("当前玩家没有冰箱")
	var cap: int = int(fridge.get("capacity", 0))
	if cap <= 0:
		return Result.failure("冰箱容量无效: %d" % cap)

	var total_food_drink := _get_total_food_drink(inventory)
	if total_food_drink <= cap:
		return Result.failure("当前库存总量未超出冰箱容量，无需选择")

	var keep_r := _parse_keep_param(command, inventory)
	if not keep_r.ok:
		return keep_r
	var keep: Dictionary = keep_r.value

	var keep_total := 0
	for v in keep.values():
		keep_total += int(v)
	if keep_total > cap:
		return Result.failure("保留总量超出冰箱容量: keep=%d cap=%d" % [keep_total, cap])

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var warnings: Array[String] = []

	var player: Dictionary = state.players[command.actor]
	var inventory: Dictionary = player.get("inventory", {})

	var ms_val = player.get("milestones", [])
	var fridge_r := CleanupSettlementClass.get_fridge_capacity_from_milestones(ms_val)
	if not fridge_r.ok:
		return fridge_r
	var fridge: Dictionary = fridge_r.value
	var cap: int = int(fridge.get("capacity", 0))

	var keep_r := _parse_keep_param(command, inventory)
	if not keep_r.ok:
		return keep_r
	var keep: Dictionary = keep_r.value

	var discarded: Dictionary = {}
	for product_key in inventory.keys():
		var pid: String = str(product_key)
		if pid.is_empty():
			continue
		if not _is_food_or_drink(pid):
			continue

		var before: int = maxi(0, int(inventory.get(pid, 0)))
		var after := 0
		if keep.has(pid):
			after = int(keep.get(pid, 0))
		inventory[pid] = after

		var delta := before - after
		if delta > 0:
			discarded[pid] = delta

	player["inventory"] = inventory
	state.players[command.actor] = player

	_upsert_cleanup_inventory_discarded(state, command.actor, discarded, true)

	if not discarded.is_empty():
		var ms := MilestoneSystemClass.process_event(state, "CleanupDiscard", {
			"player_id": command.actor,
			"discarded": discarded,
		})
		if not ms.ok:
			warnings.append("里程碑触发失败(CleanupDiscard): 玩家 %d: %s" % [command.actor, ms.error])
		else:
			warnings.append_array(ms.warnings)

	var pending_r := _get_pending_cleanup_players(state)
	if not pending_r.ok:
		return pending_r
	var pending: Array[int] = pending_r.value
	if pending.is_empty():
		return Result.failure("内部错误：pending_phase_actions[Cleanup] 缺失")
	if int(pending[0]) != int(command.actor):
		return Result.failure("内部错误：当前玩家不是 pending[0]")

	pending.remove_at(0)
	_set_pending_cleanup_players(state, pending)

	if pending.is_empty():
		var cleanup_val = Dictionary(state.round_state).get("cleanup", null)
		if cleanup_val is Dictionary:
			var cleanup: Dictionary = cleanup_val
			if cleanup.has("fridge_choice_pending"):
				cleanup["fridge_choice_pending"] = false
				state.round_state["cleanup"] = cleanup

		var milestone_cleanup := CleanupSettlementClass.apply_cleanup_milestones(state)
		if not milestone_cleanup.ok:
			return milestone_cleanup
		warnings.append_array(milestone_cleanup.warnings)
		return Result.success().with_warnings(warnings)

	var next_pid: int = int(pending[0])
	for idx in range(state.turn_order.size()):
		if int(state.turn_order[idx]) == next_pid:
			state.current_player_index = idx
			break

	return Result.success().with_warnings(warnings)

func _generate_specific_events(_old_state: GameState, _new_state: GameState, _command: Command) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _new_state == null or _command == null:
		return out
	if not (_new_state.round_state is Dictionary):
		return out

	var cleanup_val = Dictionary(_new_state.round_state).get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return out
	var cleanup: Dictionary = cleanup_val
	var inv_val = cleanup.get("inventory_discarded", null)
	if not (inv_val is Array):
		return out

	var actor := int(_command.actor)
	for item_val in Array(inv_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("player_id", -1)) != actor:
			continue

		var discarded_val = item.get("discarded", null)
		if not (discarded_val is Dictionary):
			return out
		var discarded: Dictionary = Dictionary(discarded_val).duplicate(true)
		if discarded.is_empty():
			return out

		out.append({
			"type": EventBus.EventType.FOOD_DISCARDED,
			"data": {
				"round": int(_new_state.round_number),
				"player_id": actor,
				"has_fridge": bool(item.get("has_fridge", true)),
				"discarded": discarded,
			}
		})
		break

	return out

static func _is_food_or_drink(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if not ProductRegistryClass.is_loaded():
		return false
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val == null or not (def_val is ProductDef):
		return false
	var def: ProductDef = def_val
	return def.has_tag("food") or def.has_tag("drink")

static func _get_total_food_drink(inventory: Dictionary) -> int:
	var total := 0
	for product_key in inventory.keys():
		var pid: String = str(product_key)
		if pid.is_empty():
			continue
		if not _is_food_or_drink(pid):
			continue
		total += maxi(0, int(inventory.get(pid, 0)))
	return total

static func _parse_keep_param(command: Command, inventory: Dictionary) -> Result:
	if command == null:
		return Result.failure("command 为空")
	var keep_val = command.params.get("keep", null)
	if not (keep_val is Dictionary):
		return Result.failure("keep 参数缺失或类型错误（期望 Dictionary）")
	var keep_in: Dictionary = keep_val

	var out: Dictionary = {}
	for k in keep_in.keys():
		if not (k is String):
			return Result.failure("keep key 类型错误（期望 String）")
		var pid: String = str(k).strip_edges()
		if pid.is_empty():
			return Result.failure("keep 不应包含空 product_id")
		if not _is_food_or_drink(pid):
			return Result.failure("keep 包含非 food/drink 产品: %s" % pid)

		var n_read := _parse_non_negative_int(keep_in[k], "keep.%s" % pid)
		if not n_read.ok:
			return n_read
		var n: int = int(n_read.value)

		var before: int = maxi(0, int(inventory.get(pid, 0)))
		if n > before:
			return Result.failure("keep.%s 超出库存：keep=%d inventory=%d" % [pid, n, before])
		out[pid] = n

	return Result.success(out)

static func _parse_non_negative_int(value, path: String) -> Result:
	if value is int:
		var i: int = int(value)
		if i < 0:
			return Result.failure("%s 必须 >= 0，实际: %d" % [path, i])
		return Result.success(i)
	if value is float:
		var f: float = float(value)
		if f == int(f):
			var i2: int = int(f)
			if i2 < 0:
				return Result.failure("%s 必须 >= 0，实际: %d" % [path, i2])
			return Result.success(i2)
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为非负整数" % path)

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

static func _upsert_cleanup_inventory_discarded(state: GameState, player_id: int, discarded: Dictionary, has_fridge: bool) -> void:
	if state == null or not (state.round_state is Dictionary):
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
		item["has_fridge"] = has_fridge
		item["discarded"] = discarded
		inv[idx] = item
		cleanup["inventory_discarded"] = inv
		state.round_state["cleanup"] = cleanup
		return

	inv.append({
		"player_id": player_id,
		"has_fridge": has_fridge,
		"discarded": discarded
	})
	cleanup["inventory_discarded"] = inv
	state.round_state["cleanup"] = cleanup
