# Cleanup 结算（从 PhaseManager 抽离）
# 目标：聚合 Cleanup 阶段“库存清理 + 里程碑池清理”逻辑，便于测试与复用。
class_name CleanupSettlement
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

static func apply(state: GameState) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("CleanupSettlement: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("CleanupSettlement: state.players 类型错误（期望 Array）")

	# M3 最小实现（对齐 docs/design.md）：
	# - 无冰箱：清空所有库存
	# - 有冰箱：每种产品各自限幅到容量（简化策略，后续可升级为“总容量”分配）
	var inventory_discarded: Array[Dictionary] = []

	for i in range(state.players.size()):
		var player_val = state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("CleanupSettlement: player[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val

		var milestones_val = player.get("milestones", null)
		if not (milestones_val is Array):
			return Result.failure("CleanupSettlement: player[%d].milestones 类型错误（期望 Array）" % i)
		var milestones: Array = milestones_val
		var fridge_read := _get_fridge_capacity_from_milestones(milestones)
		if not fridge_read.ok:
			return fridge_read
		var fridge: Dictionary = fridge_read.value
		var has_fridge: bool = bool(fridge.get("has_fridge", false))
		var fridge_cap: int = int(fridge.get("capacity", 0))

		var inventory_val = player.get("inventory", null)
		if not (inventory_val is Dictionary):
			return Result.failure("CleanupSettlement: player[%d].inventory 类型错误（期望 Dictionary）" % i)
		var inventory: Dictionary = inventory_val

		var discarded: Dictionary = {}
		for product in inventory:
			var before: int = int(inventory.get(product, 0))
			var after := before
			if has_fridge:
				after = clampi(before, 0, fridge_cap)
			else:
				after = 0
			inventory[product] = after

			var delta := before - after
			if delta > 0:
				discarded[str(product)] = delta

		player["inventory"] = inventory
		# 清理阶段重置状态标志（对齐 docs/design.md 的 drive_thru_active）
		player["drive_thru_active"] = false
		state.players[i] = player

		inventory_discarded.append({
			"player_id": i,
			"has_fridge": has_fridge,
			"discarded": discarded
		})

	state.round_state["cleanup"] = {
		"inventory_discarded": inventory_discarded
	}

	var milestone_cleanup := _apply_cleanup_milestones(state)
	if not milestone_cleanup.ok:
		return milestone_cleanup

	return Result.success().with_warnings(milestone_cleanup.warnings)

static func _get_fridge_capacity_from_milestones(milestones: Array) -> Result:
	var has_fridge := false
	var capacity := 0

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("CleanupSettlement: player.milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("CleanupSettlement: player.milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("CleanupSettlement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("CleanupSettlement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("CleanupSettlement: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("CleanupSettlement: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "gain_fridge":
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("CleanupSettlement: %s" % v_read.error)
			has_fridge = true
			capacity = maxi(capacity, int(v_read.value))

	return Result.success({
		"has_fridge": has_fridge,
		"capacity": capacity,
	})

static func _apply_cleanup_milestones(state: GameState) -> Result:
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
	for k in claimed.keys():
		claimed_ids.append(str(k))
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

	var remove_set := {}
	for mid in claimed_ids:
		remove_set[mid] = true
	for mid in expired_ids:
		remove_set[mid] = true

	if remove_set.is_empty():
		return Result.success()

	var remaining: Array[String] = []
	var removed: Array[String] = []
	for mid in state.milestone_pool:
		var milestone_id := str(mid)
		if remove_set.has(milestone_id):
			removed.append(milestone_id)
		else:
			remaining.append(milestone_id)

	state.milestone_pool = remaining

	state.round_state["cleanup_milestones"] = {
		"removed": removed,
		"removed_claimed": claimed_ids,
		"removed_expired": expired_ids
	}

	return Result.success().with_warnings(warnings)

static func _parse_non_negative_int_value(value, path: String) -> Result:
	if value is int:
		if int(value) < 0:
			return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			var i: int = int(f)
			if i < 0:
				return Result.failure("%s 必须 >= 0，实际: %d" % [path, i])
			return Result.success(i)
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为非负整数" % path)
