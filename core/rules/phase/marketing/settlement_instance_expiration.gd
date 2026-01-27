# MarketingSettlement：营销实例到期处理（从 settlement_helpers_impl.gd 抽离）
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func expire_marketing_instance(state: GameState, inst: Dictionary) -> void:
	assert(inst.has("board_number") and (inst["board_number"] is int), "MarketingSettlementHelpers.expire_marketing_instance: 缺少/错误 board_number（期望 int）")
	assert(inst.has("owner") and (inst["owner"] is int), "MarketingSettlementHelpers.expire_marketing_instance: 缺少/错误 owner（期望 int）")
	assert(inst.has("employee_type") and (inst["employee_type"] is String), "MarketingSettlementHelpers.expire_marketing_instance: 缺少/错误 employee_type（期望 String）")
	var board_number: int = inst["board_number"]
	var owner: int = inst["owner"]
	var employee_type: String = inst["employee_type"]
	var link_id := ""
	if inst.has("link_id") and (inst["link_id"] is String):
		link_id = str(inst["link_id"])

	# 收回营销板件
	assert(state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary, "MarketingSettlementHelpers.expire_marketing_instance: state.map.marketing_placements 缺失或类型错误（期望 Dictionary）")
	state.map["marketing_placements"].erase(str(board_number))

	# 释放忙碌营销员：仅当该员工仍处于忙碌区（可能在 Payday 被解雇）
	assert(owner >= 0 and owner < state.players.size(), "MarketingSettlementHelpers.expire_marketing_instance: owner 越界: %d" % owner)
	assert(not employee_type.is_empty(), "MarketingSettlementHelpers.expire_marketing_instance: employee_type 不能为空")

	# 扩展点：某些营销员（例如品牌总监）可被标记为“永不释放”
	if inst.has("no_release"):
		var nr = inst.get("no_release", false)
		if nr is bool and bool(nr):
			return

	# 若该员工链接到多个营销实例（例如 campaign manager 的第二张板件），只在最后一个实例到期时释放。
	if not link_id.is_empty():
		for other_val in state.marketing_instances:
			if not (other_val is Dictionary):
				continue
			var other: Dictionary = other_val
			if int(other.get("board_number", -1)) == board_number:
				continue
			if not (other.get("link_id", "") is String):
				continue
			if str(other.get("link_id", "")) != link_id:
				continue
			var rem = other.get("remaining_duration", null)
			# rem==1：本轮也会到期，因此不应阻止释放
			if rem is int and int(rem) > 1:
				return
			if rem is int and int(rem) == -1:
				return

	var removed := StateUpdaterClass.remove_from_array(state.players[owner], "busy_marketers", employee_type)
	if removed:
		StateUpdaterClass.append_to_array(state.players[owner], "reserve_employees", employee_type)
