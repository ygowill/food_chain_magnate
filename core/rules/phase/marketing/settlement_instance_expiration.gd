# MarketingSettlement：营销实例到期处理（从 settlement_helpers_impl.gd 抽离）
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func expire_marketing_instance(state: GameState, inst: Dictionary) -> Result:
	if state == null:
		return Result.failure("MarketingSettlement: state 为空")
	if inst == null:
		return Result.failure("MarketingSettlement: inst 为空")
	if not (state.map is Dictionary):
		return Result.failure("MarketingSettlement: state.map 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("MarketingSettlement: state.players 类型错误（期望 Array）")

	if not inst.has("board_number") or not (inst["board_number"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.board_number 缺失或类型错误（期望 int）")
	if not inst.has("owner") or not (inst["owner"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.owner 缺失或类型错误（期望 int）")
	if not inst.has("employee_type") or not (inst["employee_type"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.employee_type 缺失或类型错误（期望 String）")

	var board_number: int = int(inst["board_number"])
	var owner: int = int(inst["owner"])
	var employee_type: String = str(inst["employee_type"])
	var link_id := ""
	if inst.has("link_id") and (inst["link_id"] is String):
		link_id = str(inst["link_id"])

	# 收回营销板件
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("MarketingSettlement: state.map.marketing_placements 缺失或类型错误（期望 Dictionary）")
	var placements: Dictionary = state.map["marketing_placements"]
	placements.erase(str(board_number))
	state.map["marketing_placements"] = placements

	# 释放忙碌营销员：仅当该员工仍处于忙碌区（可能在 Payday 被解雇）
	if owner < 0 or owner >= state.players.size():
		return Result.failure("MarketingSettlement: owner 越界: %d" % owner)
	if employee_type.is_empty():
		return Result.failure("MarketingSettlement: employee_type 不能为空")

	# 扩展点：某些营销员（例如品牌总监）可被标记为“永不释放”
	if inst.has("no_release"):
		var nr = inst.get("no_release", false)
		if nr is bool and bool(nr):
			return Result.success()

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
				return Result.success()
			if rem is int and int(rem) == -1:
				return Result.success()

	var player_read := PlayerStateAccessClass.require_player(state, owner, "MarketingSettlement")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value

	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player[%d]" % owner, "MarketingSettlement")
	if not busy_read.ok:
		return busy_read
	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player[%d]" % owner, "MarketingSettlement")
	if not reserve_read.ok:
		return reserve_read

	var removed := StateUpdaterClass.remove_from_array(player, "busy_marketers", employee_type)
	if removed:
		StateUpdaterClass.append_to_array(player, "reserve_employees", employee_type)
		state.players[owner] = player

	return Result.success()
