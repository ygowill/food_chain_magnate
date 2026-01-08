extends RefCounted

const CashOps = preload("res://core/state/state_updater/cash.gd")
const InventoryOps = preload("res://core/state/state_updater/inventory.gd")

# === 批量更新 ===

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

		if not update.has("op") or not (update["op"] is String):
			return Result.failure("apply_batch: updates[%d].op 缺失或类型错误（期望 String）" % i)
		var op: String = update["op"]
		var result: Result = Result.failure("未初始化")

		match op:
			"transfer_cash":
				if not update.has("from_type") or not (update["from_type"] is String):
					return Result.failure("apply_batch: updates[%d].from_type 缺失或类型错误（期望 String）" % i)
				if not update.has("from_id") or not (update["from_id"] is int):
					return Result.failure("apply_batch: updates[%d].from_id 缺失或类型错误（期望 int）" % i)
				if not update.has("to_type") or not (update["to_type"] is String):
					return Result.failure("apply_batch: updates[%d].to_type 缺失或类型错误（期望 String）" % i)
				if not update.has("to_id") or not (update["to_id"] is int):
					return Result.failure("apply_batch: updates[%d].to_id 缺失或类型错误（期望 int）" % i)
				if not update.has("amount") or not (update["amount"] is int):
					return Result.failure("apply_batch: updates[%d].amount 缺失或类型错误（期望 int）" % i)
				result = CashOps.transfer_cash(
					state,
					update["from_type"],
					update["from_id"],
					update["to_type"],
					update["to_id"],
					update["amount"]
				)
			"add_inventory":
				if not update.has("player_id") or not (update["player_id"] is int):
					return Result.failure("apply_batch: updates[%d].player_id 缺失或类型错误（期望 int）" % i)
				if not update.has("food_type") or not (update["food_type"] is String):
					return Result.failure("apply_batch: updates[%d].food_type 缺失或类型错误（期望 String）" % i)
				if not update.has("amount") or not (update["amount"] is int):
					return Result.failure("apply_batch: updates[%d].amount 缺失或类型错误（期望 int）" % i)
				result = InventoryOps.add_inventory(
					state,
					update["player_id"],
					update["food_type"],
					update["amount"]
				)
			"remove_inventory":
				if not update.has("player_id") or not (update["player_id"] is int):
					return Result.failure("apply_batch: updates[%d].player_id 缺失或类型错误（期望 int）" % i)
				if not update.has("food_type") or not (update["food_type"] is String):
					return Result.failure("apply_batch: updates[%d].food_type 缺失或类型错误（期望 String）" % i)
				if not update.has("amount") or not (update["amount"] is int):
					return Result.failure("apply_batch: updates[%d].amount 缺失或类型错误（期望 int）" % i)
				result = InventoryOps.remove_inventory(
					state,
					update["player_id"],
					update["food_type"],
					update["amount"]
				)
			_:
				result = Result.failure("未知操作: %s" % op)

		results.append(result)
		if not result.ok:
			return result  # 遇到错误立即返回

	return Result.success(results)

