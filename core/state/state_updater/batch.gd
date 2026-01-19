extends RefCounted

const CashOps = preload("res://core/state/state_updater/cash.gd")
const InventoryOps = preload("res://core/state/state_updater/inventory.gd")

# === 批量更新 ===

static func _require_update_string(update: Dictionary, i: int, key: String) -> Result:
	if not update.has(key) or not (update[key] is String):
		return Result.failure("apply_batch: updates[%d].%s 缺失或类型错误（期望 String）" % [i, key])
	return Result.success(str(update[key]))

static func _require_update_int(update: Dictionary, i: int, key: String) -> Result:
	if not update.has(key) or not (update[key] is int):
		return Result.failure("apply_batch: updates[%d].%s 缺失或类型错误（期望 int）" % [i, key])
	return Result.success(int(update[key]))

# 批量应用更新
static func apply_batch(state: GameState, updates: Array[Dictionary]) -> Result:
	if state == null:
		return Result.failure("apply_batch: state 为空")
	if not (updates is Array):
		return Result.failure("apply_batch: updates 类型错误（期望 Array）")
	var results: Array[Result] = []

	for i in range(updates.size()):
		var update_val = updates[i]
		if not (update_val is Dictionary):
			return Result.failure("apply_batch: updates[%d] 类型错误（期望 Dictionary）" % i)
		var update: Dictionary = update_val

		var op_read := _require_update_string(update, i, "op")
		if not op_read.ok:
			return op_read
		var op: String = str(op_read.value)
		var result: Result = Result.failure("未初始化")

		match op:
			"transfer_cash":
				var from_type_read := _require_update_string(update, i, "from_type")
				if not from_type_read.ok:
					return from_type_read
				var from_id_read := _require_update_int(update, i, "from_id")
				if not from_id_read.ok:
					return from_id_read
				var to_type_read := _require_update_string(update, i, "to_type")
				if not to_type_read.ok:
					return to_type_read
				var to_id_read := _require_update_int(update, i, "to_id")
				if not to_id_read.ok:
					return to_id_read
				var amount_read := _require_update_int(update, i, "amount")
				if not amount_read.ok:
					return amount_read
				result = CashOps.transfer_cash(
					state,
					str(from_type_read.value),
					int(from_id_read.value),
					str(to_type_read.value),
					int(to_id_read.value),
					int(amount_read.value)
				)
			"add_inventory":
				var player_id_read := _require_update_int(update, i, "player_id")
				if not player_id_read.ok:
					return player_id_read
				var food_type_read := _require_update_string(update, i, "food_type")
				if not food_type_read.ok:
					return food_type_read
				var add_amount_read := _require_update_int(update, i, "amount")
				if not add_amount_read.ok:
					return add_amount_read
				result = InventoryOps.add_inventory(
					state,
					int(player_id_read.value),
					str(food_type_read.value),
					int(add_amount_read.value)
				)
			"remove_inventory":
				var player_id_read2 := _require_update_int(update, i, "player_id")
				if not player_id_read2.ok:
					return player_id_read2
				var food_type_read2 := _require_update_string(update, i, "food_type")
				if not food_type_read2.ok:
					return food_type_read2
				var remove_amount_read := _require_update_int(update, i, "amount")
				if not remove_amount_read.ok:
					return remove_amount_read
				result = InventoryOps.remove_inventory(
					state,
					int(player_id_read2.value),
					str(food_type_read2.value),
					int(remove_amount_read.value)
				)
			_:
				result = Result.failure("未知操作: %s" % op)

		results.append(result)
		if not result.ok:
			return result  # 遇到错误立即返回

	return Result.success(results)
