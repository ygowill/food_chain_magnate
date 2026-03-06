# Cleanup：冰箱保留选择（food+drink 总量容量）
class_name ChooseFridgeKeepAction
extends ActionExecutor

const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

const PENDING_TASK_KIND := "fridge_keep"

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

	var pending_r := _get_pending_cleanup_tasks(state)
	if not pending_r.ok:
		return pending_r
	var pending: Array[Dictionary] = pending_r.value
	if pending.is_empty():
		return Result.failure("当前没有待处理的冰箱选择")
	var first: Dictionary = pending[0]
	if str(first.get("kind", "")) != PENDING_TASK_KIND:
		return Result.failure("当前待处理动作不是冰箱保留选择")
	if int(first.get("player_id", -1)) != int(command.actor):
		return Result.failure("当前不是需要选择冰箱保留的玩家")

	# 兼容：Cleanup 阶段可能存在多种 pending（例如 kimchi 储存选择）
	# 若存在 kind 标记，则 choose_fridge_keep 仅在 kind=fridge 时可执行。
	var cleanup_val = Dictionary(state.round_state).get("cleanup", null)
	if cleanup_val is Dictionary:
		var cleanup: Dictionary = cleanup_val
		if cleanup.has("pending_choice_kind"):
			var kind_val = cleanup.get("pending_choice_kind", "")
			if not (kind_val is String):
				return Result.failure("round_state.cleanup.pending_choice_kind 类型错误（期望 String）")
			var kind: String = str(kind_val)
			if not kind.is_empty() and kind != "fridge":
				return Result.failure("当前不是冰箱保留选择（kind=%s）" % kind)

	var player_read := PlayerStateAccessClass.require_player(state, command.actor, action_id)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % command.actor, action_id)
	if not inventory_read.ok:
		return inventory_read
	var inventory: Dictionary = inventory_read.value

	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % command.actor, action_id)
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value
	var fridge_r := CleanupSettlementClass.get_fridge_capacity_from_milestones(milestones)
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

	var player_read := PlayerStateAccessClass.require_player(state, command.actor, action_id)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % command.actor, action_id)
	if not inventory_read.ok:
		return inventory_read
	var inventory: Dictionary = inventory_read.value

	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % command.actor, action_id)
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value
	var fridge_r := CleanupSettlementClass.get_fridge_capacity_from_milestones(milestones)
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

	var pending_r := _get_pending_cleanup_tasks(state)
	if not pending_r.ok:
		return pending_r
	var pending: Array[Dictionary] = pending_r.value
	if pending.is_empty():
		return Result.failure("内部错误：pending_phase_actions[Cleanup] 缺失")
	var first: Dictionary = pending[0]
	if str(first.get("kind", "")) != PENDING_TASK_KIND:
		return Result.failure("内部错误：pending[0] 不是 fridge_keep")
	if int(first.get("player_id", -1)) != int(command.actor):
		return Result.failure("内部错误：当前玩家不是 pending[0]")

	pending.remove_at(0)
	_set_pending_cleanup_tasks(state, pending)

	if not _has_pending_cleanup_task_kind(pending, PENDING_TASK_KIND):
		var cleanup_val = Dictionary(state.round_state).get("cleanup", null)
		if cleanup_val is Dictionary:
			var cleanup: Dictionary = cleanup_val
			if cleanup.has("fridge_choice_pending"):
				cleanup["fridge_choice_pending"] = false
			if cleanup.has("pending_choice_kind"):
				cleanup["pending_choice_kind"] = ""
			state.round_state["cleanup"] = cleanup

		if state.round_state.has("cleanup_defer_milestone_cleanup"):
			state.round_state.erase("cleanup_defer_milestone_cleanup")

		var milestone_cleanup := CleanupSettlementClass.apply_cleanup_milestones(state)
		if not milestone_cleanup.ok:
			return milestone_cleanup
		warnings.append_array(milestone_cleanup.warnings)

	if pending.is_empty():
		return Result.success().with_warnings(warnings)

	var next_pid: int = int(Dictionary(pending[0]).get("player_id", -1))
	for idx in range(state.turn_order.size()):
		if int(state.turn_order[idx]) == next_pid:
			state.current_player_index = idx
			break

	return Result.success().with_warnings(warnings)

func _generate_specific_events(_old_state: GameState, _new_state: GameState, _command: Command) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _new_state == null or _command == null:
		return out
	if _old_state == null:
		return out
	if not ProductRegistryClass.is_loaded():
		return out

	var actor := int(_command.actor)
	if actor < 0 or actor >= _new_state.players.size():
		return out
	if actor >= _old_state.players.size():
		return out

	var old_p_val = _old_state.players[actor]
	var new_p_val = _new_state.players[actor]
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
		if not _is_food_or_drink(pid):
			continue
		var before: int = maxi(0, int(old_inv.get(pid, 0)))
		var after: int = maxi(0, int(new_inv.get(pid, 0)))
		var delta := before - after
		if delta > 0:
			discarded[pid] = delta

	if discarded.is_empty():
		return out

	out.append({
		"type": EventBus.EventType.FOOD_DISCARDED,
		"data": {
			"round": int(_new_state.round_number),
			"player_id": actor,
			"has_fridge": true,
			"discarded": discarded,
		}
	})

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
	if def.has_tag("no_storage"):
		return false
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

static func _has_pending_cleanup_task_kind(tasks: Array, kind: String) -> bool:
	if kind.is_empty():
		return false
	for v in tasks:
		if v is Dictionary and str(Dictionary(v).get("kind", "")) == kind:
			return true
	return false

static func _get_pending_cleanup_tasks(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has("pending_phase_actions"):
		return Result.success([] as Array[Dictionary])
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(DefsClass.PHASE_CLEANUP):
		return Result.success([] as Array[Dictionary])
	var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return Result.failure("pending_phase_actions[Cleanup] 类型错误（期望 Array）")
	var list: Array = list_val

	var out: Array[Dictionary] = []
	for i in range(list.size()):
		var v = list[i]
		if v is Dictionary:
			var d: Dictionary = v
			var kind_val = d.get("kind", null)
			var pid_val = d.get("player_id", null)
			if not (kind_val is String):
				return Result.failure("pending_phase_actions[Cleanup][%d].kind 类型错误（期望 String）" % i)
			var kind: String = str(kind_val)
			if kind.is_empty():
				return Result.failure("pending_phase_actions[Cleanup][%d].kind 不能为空" % i)
			if not (pid_val is int or pid_val is float):
				return Result.failure("pending_phase_actions[Cleanup][%d].player_id 类型错误（期望 int/float）" % i)
			out.append({
				"kind": kind,
				"player_id": int(pid_val),
			})
			continue

		# 兼容旧存档：Cleanup pending 列表为 [player_id(int)]（仅用于 fridge_keep）
		if v is int or v is float:
			out.append({
				"kind": PENDING_TASK_KIND,
				"player_id": int(v),
			})
			continue
		return Result.failure("pending_phase_actions[Cleanup][%d] 类型错误（期望 Dictionary/int/float）" % i)

	return Result.success(out)

static func _set_pending_cleanup_tasks(state: GameState, pending: Array[Dictionary]) -> void:
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
		var prev_val = item.get("discarded", {})
		var prev: Dictionary = prev_val if prev_val is Dictionary else {}
		for k in discarded.keys():
			var pid: String = str(k)
			var add_amt: int = int(discarded.get(k, 0))
			if add_amt <= 0 or pid.is_empty():
				continue
			prev[pid] = int(prev.get(pid, 0)) + add_amt
		item["discarded"] = prev
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
