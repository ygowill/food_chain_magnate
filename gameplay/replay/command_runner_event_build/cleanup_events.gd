# CommandRunnerEventBuild：Cleanup 事件拆分
# 用途：从 round_state.cleanup 中推导库存丢弃事件（日志/展示语义）。
extends RefCounted

static func build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cleanup_state == null:
		return out
	if not (cleanup_state.round_state is Dictionary):
		return out

	var cleanup_val = Dictionary(cleanup_state.round_state).get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return out
	var cleanup: Dictionary = cleanup_val
	var inv_val = cleanup.get("inventory_discarded", null)
	if not (inv_val is Array):
		return out
	var round := int(cleanup_state.round_number)

	for item_val in Array(inv_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var player_id := int(item.get("player_id", -1))
		if player_id < 0:
			continue

		var discarded_val = item.get("discarded", null)
		if not (discarded_val is Dictionary):
			continue
		var discarded: Dictionary = Dictionary(discarded_val).duplicate(true)
		if discarded.is_empty():
			continue

		out.append({
			"type": EventBus.EventType.FOOD_DISCARDED,
			"data": {
				"round": round,
				"player_id": player_id,
				"has_fridge": bool(item.get("has_fridge", false)),
				"discarded": discarded,
			}
		})

	return out
