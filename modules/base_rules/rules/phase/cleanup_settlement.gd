# Cleanup 结算（从 PhaseManager 抽离）
# 目标：聚合 Cleanup 阶段“库存清理 + 里程碑池清理”逻辑，便于测试与复用。
class_name CleanupSettlement
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY := "opening_soon_restaurants"

static func apply(state: GameState) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("CleanupSettlement: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("CleanupSettlement: state.players 类型错误（期望 Array）")
	if not ProductRegistryClass.is_loaded():
		return Result.failure("CleanupSettlement: ProductRegistry 未初始化")

	var warnings: Array[String] = []

	# M3 最小实现（对齐 docs/design.md）：
	# - 无冰箱：清空所有库存
	# - 有冰箱：仅对 food+drink 生效，且总量 <= 容量；若超出则需要玩家在 Cleanup 阶段选择保留哪些商品
	var inventory_discarded: Array[Dictionary] = []
	var needs_fridge_choice := {}  # player_id -> true

	for i in range(state.players.size()):
		var player_val = state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("CleanupSettlement: player[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val

		var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % i, "CleanupSettlement")
		if not milestones_read.ok:
			return milestones_read
		var milestones: Array = milestones_read.value
		var fridge_read := get_fridge_capacity_from_milestones(milestones)
		if not fridge_read.ok:
			return fridge_read
		var fridge: Dictionary = fridge_read.value
		var has_fridge: bool = bool(fridge.get("has_fridge", false))
		var fridge_cap: int = int(fridge.get("capacity", 0))

		var inventory_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % i, "CleanupSettlement")
		if not inventory_read.ok:
			return inventory_read
		var inventory: Dictionary = inventory_read.value

		# food+drink 总量（用于判断是否需要弹窗选择）
		var total_food_drink := 0
		for product_key in inventory.keys():
			var pid: String = str(product_key)
			if pid.is_empty():
				continue
			if not _is_food_or_drink(pid):
				continue
			total_food_drink += maxi(0, int(inventory.get(pid, 0)))

		var need_choice := has_fridge and total_food_drink > fridge_cap and fridge_cap > 0
		if need_choice:
			needs_fridge_choice[i] = true

		var discarded: Dictionary = {}
		for product in inventory.keys():
			var before: int = maxi(0, int(inventory.get(product, 0)))
			var after := before
			if not has_fridge:
				after = 0
			elif need_choice:
				# 需要玩家选择：先不改动库存，等待 choose_fridge_keep 动作落地
				after = before
			else:
				# 有冰箱且不需要选择：保留全部（总量未超 cap）
				after = before

			inventory[product] = after

			var delta := before - after
			if delta > 0:
				discarded[str(product)] = delta

		player["inventory"] = inventory
		state.players[i] = player

		inventory_discarded.append({
			"player_id": i,
			"has_fridge": has_fridge,
			"discarded": discarded
		})

		# 里程碑：首次丢弃（first_throw_away）依赖该事件触发点。
		if not discarded.is_empty():
			var ms := MilestoneSystemClass.process_event(state, "CleanupDiscard", {
				"player_id": i,
				"discarded": discarded,
			})
			if not ms.ok:
				warnings.append("里程碑触发失败(CleanupDiscard): 玩家 %d: %s" % [i, ms.error])
			else:
				warnings.append_array(ms.warnings)

	state.round_state["cleanup"] = {
		"inventory_discarded": inventory_discarded,
		"fridge_choice_pending": not needs_fridge_choice.is_empty(),
	}

	# 新店开业: 将所有“即将开业”的餐厅翻面至“欢迎光临”（加入正式 restaurants 列表，并移除 opening_soon 标记）。
	var open_r := _open_opening_soon_restaurants(state)
	if not open_r.ok:
		return open_r
	warnings.append_array(open_r.warnings)

	# 若需要玩家在 Cleanup 选择保留库存，则暂缓“里程碑池清理”，
	# 否则 CleanupDiscard 触发的里程碑可能发生在清理之后而残留在 pool 中。
	if not needs_fridge_choice.is_empty():
		# 按 turn_order 顺序依次弹窗（hotseat）
		var pending: Array[Dictionary] = []
		for pid_val in state.turn_order:
			var pid: int = int(pid_val)
			if needs_fridge_choice.has(pid):
				pending.append({
					"kind": "fridge_keep",
					"player_id": pid,
				})
		var set_pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
			state.round_state,
			DefsClass.PHASE_CLEANUP,
			pending,
			"CleanupSettlement"
		)
		if not set_pending.ok:
			return set_pending

		# 将 current_player_index 对齐到第一位待处理玩家，保证 UI/命令执行一致
		if not pending.is_empty():
			var first_task: Dictionary = pending[0]
			var first_pid: int = int(first_task.get("player_id", -1))
			for idx in range(state.turn_order.size()):
				if int(state.turn_order[idx]) == first_pid:
					state.current_player_index = idx
					break

		return Result.success().with_warnings(warnings)

	# 允许模块要求延迟“里程碑池清理”（例如：Cleanup 阶段仍有额外交互/选择）。
	# 约定：模块在 Cleanup primary 之前写入 round_state.cleanup_defer_milestone_cleanup=true，
	# 并在后续动作完成后调用 apply_cleanup_milestones。
	if state.round_state.has("cleanup_defer_milestone_cleanup"):
		var defer_val = state.round_state.get("cleanup_defer_milestone_cleanup", null)
		if not (defer_val is bool):
			return Result.failure("CleanupSettlement: round_state.cleanup_defer_milestone_cleanup 类型错误（期望 bool）")
		if bool(defer_val):
			return Result.success().with_warnings(warnings)

	var milestone_cleanup := apply_cleanup_milestones(state)
	if not milestone_cleanup.ok:
		return milestone_cleanup
	warnings.append_array(milestone_cleanup.warnings)
	return Result.success().with_warnings(warnings)

static func _open_opening_soon_restaurants(state: GameState) -> Result:
	if state == null:
		return Result.failure("CleanupSettlement: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("CleanupSettlement: state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("CleanupSettlement: state.map 类型错误（期望 Dictionary）")
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("CleanupSettlement: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("CleanupSettlement: state.players 类型错误（期望 Array）")

	var pending_val = state.round_state.get(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY, null)
	if pending_val == null:
		return Result.success()
	if not (pending_val is Array):
		return Result.failure("CleanupSettlement: round_state.%s 类型错误（期望 Array）" % ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY)
	var pending: Array = pending_val
	if pending.is_empty():
		return Result.success()

	var warnings: Array[String] = []
	var restaurants: Dictionary = state.map["restaurants"]

	for i in range(pending.size()):
		var entry_val = pending[i]
		if not (entry_val is Dictionary):
			return Result.failure("CleanupSettlement: opening_soon_restaurants[%d] 类型错误（期望 Dictionary）" % i)
		var entry: Dictionary = entry_val

		var rid := str(entry.get("restaurant_id", "")).strip_edges()
		if rid.is_empty():
			return Result.failure("CleanupSettlement: opening_soon_restaurants[%d].restaurant_id 为空" % i)
		var owner := int(entry.get("owner", -1))
		if owner < 0 or owner >= state.players.size():
			return Result.failure("CleanupSettlement: opening_soon_restaurants[%s].owner 越界: %d" % [rid, owner])
		var anchor_val = entry.get("anchor_pos", null)
		var entrance_val = entry.get("entrance_pos", null)
		var cells_val = entry.get("cells", null)
		if not (anchor_val is Vector2i):
			return Result.failure("CleanupSettlement: opening_soon_restaurants[%s].anchor_pos 类型错误（期望 Vector2i）" % rid)
		if not (entrance_val is Vector2i):
			return Result.failure("CleanupSettlement: opening_soon_restaurants[%s].entrance_pos 类型错误（期望 Vector2i）" % rid)
		if not (cells_val is Array):
			return Result.failure("CleanupSettlement: opening_soon_restaurants[%s].cells 类型错误（期望 Array）" % rid)
		var anchor_pos: Vector2i = anchor_val
		var entrance_pos: Vector2i = entrance_val
		var cells_any: Array = cells_val
		var cells: Array[Vector2i] = []
		for j in range(cells_any.size()):
			var c = cells_any[j]
			if not (c is Vector2i):
				return Result.failure("CleanupSettlement: opening_soon_restaurants[%s].cells[%d] 类型错误（期望 Vector2i）" % [rid, j])
			cells.append(c)

		var rotation := int(entry.get("rotation", 0))

		if restaurants.has(rid):
			# 容错：已开业则跳过（避免重复加入导致玩家 restaurants 重复）
			continue

		restaurants[rid] = {
			"restaurant_id": rid,
			"owner": owner,
			"anchor_pos": anchor_pos,
			"entrance_pos": entrance_pos,
			"cells": cells,
			"rotation": rotation,
		}

		# 玩家餐厅列表
		var p_val = state.players[owner]
		if not (p_val is Dictionary):
			return Result.failure("CleanupSettlement: players[%d] 类型错误（期望 Dictionary）" % owner)
		var player: Dictionary = p_val
		if not player.has("restaurants") or not (player["restaurants"] is Array):
			return Result.failure("CleanupSettlement: players[%d].restaurants 缺失或类型错误（期望 Array）" % owner)
		var plist: Array = player["restaurants"]
		if not plist.has(rid):
			plist.append(rid)
		player["restaurants"] = plist
		state.players[owner] = player

		# 清理 structure 上的 opening_soon 标志（翻面至“欢迎光临”）
		for cpos in cells:
			var idx: Vector2i = CoordsClass.world_to_index(state, cpos)
			var cell: Dictionary = state.map.cells[idx.y][idx.x]
			var s_val = cell.get("structure", null)
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			if str(s.get("piece_id", "")) != "restaurant":
				continue
			if str(s.get("restaurant_id", "")) != rid:
				continue
			if s.has("opening_soon"):
				s.erase("opening_soon")
			cell["structure"] = s
			state.map.cells[idx.y][idx.x] = cell

	state.map["restaurants"] = restaurants
	state.round_state.erase(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY)
	return Result.success().with_warnings(warnings)

static func get_fridge_capacity_from_milestones(milestones: Array) -> Result:
	var best_read := MilestoneEffectQueriesClass.max_non_negative_int_value(
		milestones,
		"gain_fridge",
		"CleanupSettlement: ",
		"player.milestones"
	)
	if not best_read.ok:
		return best_read
	if not (best_read.value is Dictionary):
		return Result.failure("CleanupSettlement: 内部错误（max_non_negative_int_value 返回值类型错误）")
	var best: Dictionary = best_read.value
	return Result.success({
		"has_fridge": bool(best.get("found", false)),
		"capacity": int(best.get("value", 0)),
	})

static func apply_cleanup_milestones(state: GameState) -> Result:
	# 对齐 docs/design.md：同回合获得的里程碑类型在 Cleanup 统一从 supply 移除；
	# 同时移除已过期的里程碑（expires_at）。
	var warnings: Array[String] = []

	if not (state.milestone_pool is Array):
		return Result.failure("CleanupSettlement: state.milestone_pool 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("CleanupSettlement: state.round_state 类型错误（期望 Dictionary）")

	var claimed_val = state.round_state.get("milestones_claimed", {})
	if not (claimed_val is Dictionary):
		return Result.failure("CleanupSettlement: round_state.milestones_claimed 类型错误（期望 Dictionary）")
	var claimed: Dictionary = claimed_val

	var claimed_ids: Array[String] = []
	var claimed_remove_counts := {}  # milestone_id -> copies to remove
	for k in claimed.keys():
		var mid := str(k)
		if mid.is_empty():
			continue
		claimed_ids.append(mid)
		var list_val = claimed.get(k, [])
		if list_val is Array:
			claimed_remove_counts[mid] = maxi(1, Array(list_val).size())
		else:
			# 容错：结构异常时按 1 份处理（避免阻塞回合推进）
			claimed_remove_counts[mid] = 1
	claimed_ids.sort()

	var expired_ids: Array[String] = []
	for mid in state.milestone_pool:
		var milestone_id := str(mid)
		var def = MilestoneRegistryClass.get_def(milestone_id)
		if def == null:
			return Result.failure("CleanupSettlement: 里程碑未定义: %s" % milestone_id)
		if def.expires_at != null and int(state.round_number) >= int(def.expires_at):
			expired_ids.append(milestone_id)
	expired_ids.sort()

	if claimed_remove_counts.is_empty() and expired_ids.is_empty():
		return Result.success()

	var expired_set := {}
	for mid in expired_ids:
		expired_set[mid] = true

	var remaining: Array[String] = []
	var removed: Array[String] = []
	var removed_claimed_counts := {}  # milestone_id -> removed copies
	for mid in state.milestone_pool:
		var milestone_id := str(mid)
		if expired_set.has(milestone_id):
			removed.append(milestone_id)
			continue
		if claimed_remove_counts.has(milestone_id):
			var left: int = int(claimed_remove_counts.get(milestone_id, 0))
			if left > 0:
				removed.append(milestone_id)
				claimed_remove_counts[milestone_id] = left - 1
				removed_claimed_counts[milestone_id] = int(removed_claimed_counts.get(milestone_id, 0)) + 1
				continue
		remaining.append(milestone_id)

	state.milestone_pool = remaining

	state.round_state["cleanup_milestones"] = {
		"removed": removed,
		"removed_claimed": claimed_ids,
		"removed_claimed_counts": removed_claimed_counts,
		"removed_expired": expired_ids
	}

	return Result.success().with_warnings(warnings)

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
