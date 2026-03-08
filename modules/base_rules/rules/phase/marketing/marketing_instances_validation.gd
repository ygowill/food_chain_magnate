# MarketingSettlement：marketing_instances 校验与归一化（抽离自 MarketingSettlement.apply）
extends RefCounted

const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")

static func build_sorted_instances(state: GameState, placements: Dictionary) -> Result:
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")

	var instances: Array[Dictionary] = []
	var seen_board_numbers := {}

	for i in range(state.marketing_instances.size()):
		var inst_val = state.marketing_instances[i]
		if not (inst_val is Dictionary):
			return Result.failure("MarketingSettlement: marketing_instances[%d] 类型错误（期望 Dictionary）" % i)
		var inst: Dictionary = (inst_val as Dictionary).duplicate(true)

		if not inst.has("board_number") or not (inst["board_number"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 缺失或类型错误（期望 int）" % i)
		var board_number: int = inst["board_number"]
		if board_number <= 0:
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 必须 > 0" % i)
		var board_spec_read := MarketingRulesClass.require_board_spec(state, board_number)
		if not board_spec_read.ok:
			var err := str(board_spec_read.error)
			if err.find("已移除") >= 0:
				return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 在当前玩家数下已移除: #%d" % [i, board_number])
			return Result.failure("MarketingSettlement: marketing_instances[%d].board_number 未知: #%d" % [i, board_number])
		if seen_board_numbers.has(board_number):
			return Result.failure("MarketingSettlement: marketing_instances 出现重复 board_number: #%d" % board_number)
		seen_board_numbers[board_number] = true

		if not inst.has("type") or not (inst["type"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].type 缺失或类型错误（期望 String）" % i)
		var marketing_type: String = inst["type"]
		if marketing_type.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances[%d].type 不能为空" % i)

		if not inst.has("owner") or not (inst["owner"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].owner 缺失或类型错误（期望 int）" % i)
		var owner: int = inst["owner"]
		if owner < 0 or owner >= state.players.size():
			return Result.failure("MarketingSettlement: marketing_instances[%d].owner 越界: %d" % [i, owner])

		if not inst.has("employee_type") or not (inst["employee_type"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].employee_type 缺失或类型错误（期望 String）" % i)
		var employee_type: String = inst["employee_type"]
		if employee_type.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances[%d].employee_type 不能为空" % i)

		if not inst.has("product") or not (inst["product"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].product 缺失或类型错误（期望 String）" % i)
		var product: String = inst["product"]
		if product.is_empty():
			return Result.failure("MarketingSettlement: marketing_instances[%d].product 不能为空" % i)

		if not inst.has("world_pos") or not (inst["world_pos"] is Vector2i):
			return Result.failure("MarketingSettlement: marketing_instances[%d].world_pos 缺失或类型错误（期望 Vector2i）" % i)

		if not inst.has("remaining_duration") or not (inst["remaining_duration"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].remaining_duration 缺失或类型错误（期望 int）" % i)
		var remaining_duration: int = inst["remaining_duration"]
		if remaining_duration == 0 or remaining_duration < -1:
			return Result.failure("MarketingSettlement: marketing_instances[%d].remaining_duration 必须为 -1(永久) 或 > 0，实际: %d" % [i, remaining_duration])

		if not inst.has("axis") or not (inst["axis"] is String):
			return Result.failure("MarketingSettlement: marketing_instances[%d].axis 缺失或类型错误（期望 String）" % i)
		if not inst.has("tile_index") or not (inst["tile_index"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].tile_index 缺失或类型错误（期望 int）" % i)
		var axis: String = inst["axis"]
		var tile_index: int = inst["tile_index"]
		if marketing_type == "airplane":
			if axis != "row" and axis != "col":
				return Result.failure("MarketingSettlement: airplane marketing_instances[%d].axis 非法（期望 row/col）: %s" % [i, axis])
		else:
			if not axis.is_empty():
				return Result.failure("MarketingSettlement: 非 airplane 的 axis 必须为空，实际: %s" % axis)
			if tile_index != -1:
				return Result.failure("MarketingSettlement: 非 airplane 的 tile_index 必须为 -1，实际: %d" % tile_index)

		if not inst.has("created_round") or not (inst["created_round"] is int):
			return Result.failure("MarketingSettlement: marketing_instances[%d].created_round 缺失或类型错误（期望 int）" % i)

		var placement_key := str(board_number)
		if not placements.has(placement_key):
			return Result.failure("MarketingSettlement: marketing_placements 缺少 board_number: #%d" % board_number)
		if not (placements[placement_key] is Dictionary):
			return Result.failure("MarketingSettlement: marketing_placements[%s] 类型错误（期望 Dictionary）" % placement_key)

		instances.append(inst)

	instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["board_number"]) < int(b["board_number"])
	)

	return Result.success(instances)
