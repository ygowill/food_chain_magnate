extends RefCounted

const UtilsClass = preload("res://modules/new_milestones/rules/utils.gd")

const CM_PROVIDER_ID := "new_milestones:campaign_manager:pending_second_tile"
const CM_PENDING_KEY := "new_milestones_campaign_manager_pending"
const CM_USED_KEY := "new_milestones_campaign_manager_used_this_turn"

const MILESTONE_ID_CAMPAIGN_MANAGER := "first_campaign_manager_used"
const MILESTONE_ID_BRAND_MANAGER := "first_brand_manager_used"
const MILESTONE_ID_BRAND_DIRECTOR := "first_brand_director_used"

const BM_PROVIDER_ID := "new_milestones:brand_manager:pending_airplane_second_good"
const BM_PENDING_KEY := "new_milestones_brand_manager_airplane_pending"
const BM_USED_KEY := "new_milestones_brand_manager_airplane_used_this_turn"

const BD_PROVIDER_ID := "new_milestones:brand_director:radio_permanent_and_busy_forever"

func register(registrar) -> Result:
	var r = registrar.register_marketing_initiation_provider(CM_PROVIDER_ID, Callable(self, "_on_marketing_initiated_campaign_manager"), 120)
	if not r.ok:
		return r
	r = registrar.register_marketing_initiation_provider(BM_PROVIDER_ID, Callable(self, "_on_marketing_initiated_brand_manager"), 121)
	if not r.ok:
		return r
	r = registrar.register_marketing_initiation_provider(BD_PROVIDER_ID, Callable(self, "_on_marketing_initiated_brand_director"), 122)
	if not r.ok:
		return r
	return Result.success()

func _on_marketing_initiated_campaign_manager(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:campaign_manager: state 为空")
	if command == null:
		return Result.failure("new_milestones:campaign_manager: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("new_milestones:campaign_manager: marketing_instance 类型错误（期望 Dictionary）")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:campaign_manager: state.round_state 类型错误（期望 Dictionary）")

	var employee_type_val = null
	if command.params is Dictionary and command.params.has("employee_type"):
		employee_type_val = command.params.get("employee_type", null)
	if not (employee_type_val is String):
		return Result.failure("new_milestones:campaign_manager: 缺少/错误参数 employee_type（期望 String）")
	var employee_type: String = str(employee_type_val)
	if employee_type.is_empty():
		return Result.failure("new_milestones:campaign_manager: employee_type 不能为空")
	if employee_type != "campaign_manager":
		return Result.success()

	# 只允许在“获得该里程碑的同一回合”使用一次
	if not UtilsClass.was_milestone_awarded_this_turn(state, int(command.actor), MILESTONE_ID_CAMPAIGN_MANAGER):
		return Result.success()

	if not marketing_instance.has("type") or not (marketing_instance["type"] is String):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.type 缺失或类型错误（期望 String）")
	var mk_type: String = str(marketing_instance["type"])
	if mk_type != "billboard" and mk_type != "mailbox":
		return Result.success()

	if not state.round_state.has(CM_USED_KEY):
		state.round_state[CM_USED_KEY] = {}
	var used_val = state.round_state.get(CM_USED_KEY, null)
	if not (used_val is Dictionary):
		return Result.failure("new_milestones:campaign_manager: round_state.%s 类型错误（期望 Dictionary）" % CM_USED_KEY)
	var used: Dictionary = used_val
	if used.has(command.actor):
		return Result.success()

	if not state.round_state.has(CM_PENDING_KEY):
		state.round_state[CM_PENDING_KEY] = {}
	var pending_val = state.round_state.get(CM_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("new_milestones:campaign_manager: round_state.%s 类型错误（期望 Dictionary）" % CM_PENDING_KEY)
	var pending: Dictionary = pending_val
	if pending.has(command.actor):
		return Result.success()

	var board_number_val = marketing_instance.get("board_number", null)
	if not (board_number_val is int):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.board_number 缺失或类型错误（期望 int）")
	var board_number: int = int(board_number_val)
	var product_val = marketing_instance.get("product", null)
	if not (product_val is String):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.product 缺失或类型错误（期望 String）")
	var product: String = str(product_val)
	var duration_val = marketing_instance.get("remaining_duration", null)
	if not (duration_val is int):
		return Result.failure("new_milestones:campaign_manager: marketing_instance.remaining_duration 缺失或类型错误（期望 int）")
	var duration: int = int(duration_val)

	var link_id := "new_milestones:campaign_manager:%d:%d:%d" % [state.round_number, int(command.actor), board_number]
	marketing_instance["link_id"] = link_id

	pending[int(command.actor)] = {
		"link_id": link_id,
		"employee_type": employee_type,
		"type": mk_type,
		"product": product,
		"remaining_duration": duration,
		"primary_board_number": board_number,
	}
	state.round_state[CM_PENDING_KEY] = pending
	used[int(command.actor)] = true
	state.round_state[CM_USED_KEY] = used
	return Result.success()

func _on_marketing_initiated_brand_manager(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:brand_manager: state 为空")
	if command == null:
		return Result.failure("new_milestones:brand_manager: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("new_milestones:brand_manager: marketing_instance 类型错误（期望 Dictionary）")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:brand_manager: state.round_state 类型错误（期望 Dictionary）")

	# 只允许在“获得该里程碑的同一回合”使用一次
	if not UtilsClass.was_milestone_awarded_this_turn(state, int(command.actor), MILESTONE_ID_BRAND_MANAGER):
		return Result.success()

	var employee_type_val = null
	if command.params is Dictionary and command.params.has("employee_type"):
		employee_type_val = command.params.get("employee_type", null)
	if not (employee_type_val is String):
		return Result.failure("new_milestones:brand_manager: 缺少/错误参数 employee_type（期望 String）")
	var employee_type: String = str(employee_type_val)
	if employee_type.is_empty():
		return Result.failure("new_milestones:brand_manager: employee_type 不能为空")
	if employee_type != "brand_manager":
		return Result.success()

	if not marketing_instance.has("type") or not (marketing_instance["type"] is String):
		return Result.failure("new_milestones:brand_manager: marketing_instance.type 缺失或类型错误（期望 String）")
	var mk_type: String = str(marketing_instance["type"])
	if mk_type != "airplane":
		return Result.success()

	if not state.round_state.has(BM_USED_KEY):
		state.round_state[BM_USED_KEY] = {}
	var used_val = state.round_state.get(BM_USED_KEY, null)
	if not (used_val is Dictionary):
		return Result.failure("new_milestones:brand_manager: round_state.%s 类型错误（期望 Dictionary）" % BM_USED_KEY)
	var used: Dictionary = used_val
	if used.has(command.actor):
		return Result.success()

	if not state.round_state.has(BM_PENDING_KEY):
		state.round_state[BM_PENDING_KEY] = {}
	var pending_val = state.round_state.get(BM_PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("new_milestones:brand_manager: round_state.%s 类型错误（期望 Dictionary）" % BM_PENDING_KEY)
	var pending: Dictionary = pending_val
	if pending.has(command.actor):
		return Result.success()

	var board_number_val = marketing_instance.get("board_number", null)
	if not (board_number_val is int):
		return Result.failure("new_milestones:brand_manager: marketing_instance.board_number 缺失或类型错误（期望 int）")
	var board_number: int = int(board_number_val)
	var product_val = marketing_instance.get("product", null)
	if not (product_val is String):
		return Result.failure("new_milestones:brand_manager: marketing_instance.product 缺失或类型错误（期望 String）")
	var product_a: String = str(product_val)
	if product_a.is_empty():
		return Result.failure("new_milestones:brand_manager: marketing_instance.product 不能为空")

	pending[int(command.actor)] = {
		"board_number": board_number,
		"product_a": product_a,
	}
	state.round_state[BM_PENDING_KEY] = pending
	used[int(command.actor)] = true
	state.round_state[BM_USED_KEY] = used
	return Result.success()

func _on_marketing_initiated_brand_director(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("new_milestones:brand_director: state 为空")
	if command == null:
		return Result.failure("new_milestones:brand_director: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("new_milestones:brand_director: marketing_instance 类型错误（期望 Dictionary）")

	# 里程碑获得后：玩家放置的 radio 永久（duration=-1）
	if UtilsClass.player_has_milestone(state, int(command.actor), MILESTONE_ID_BRAND_DIRECTOR):
		if str(marketing_instance.get("type", "")) == "radio":
			marketing_instance["remaining_duration"] = -1
			if state.map is Dictionary and state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary:
				var placements: Dictionary = state.map["marketing_placements"]
				var key := str(int(marketing_instance.get("board_number", -1)))
				if placements.has(key) and (placements[key] is Dictionary):
					var p: Dictionary = placements[key]
					p["remaining_duration"] = -1
					placements[key] = p
					state.map["marketing_placements"] = placements

	# 品牌总监：忙碌到游戏结束（即使本次不是 radio）
	if str(marketing_instance.get("employee_type", "")) == "brand_director":
		if UtilsClass.player_has_milestone(state, int(command.actor), MILESTONE_ID_BRAND_DIRECTOR):
			marketing_instance["no_release"] = true

	return Result.success()

