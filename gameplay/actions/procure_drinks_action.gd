# 饮料采购动作（GET_DRINKS 子阶段）
# 卡车司机/飞艇驾驶员从饮料源采购饮料到玩家库存
class_name ProcureDrinksAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

# 每个饮料源提供的饮料数量
const DRINKS_PER_SOURCE := 2

func _init() -> void:
	action_id = "procure_drinks"
	display_name = "采购饮料"
	description = "从饮料源采购饮料"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["GetDrinks"]

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	if not command.params.has("employee_type"):
		return Result.failure("缺少参数: employee_type")
	var employee_type_val = command.params["employee_type"]
	if not (employee_type_val is String):
		return Result.failure("employee_type 必须为字符串")
	var employee_type: String = employee_type_val
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")

	# 从 EmployeeRegistry 获取员工定义
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)

	# 检查该员工是否能采购饮料
	if not emp_def.can_procure():
		return Result.failure("该员工类型不能采购饮料: %s" % employee_type)

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 检查玩家是否拥有该类型的员工
	var player := state.get_player(command.actor)
	var active_count := EmployeeRulesClass.count_active_for_working(state, player, command.actor, employee_type)
	if active_count <= 0:
		return Result.failure("你没有激活的 %s" % employee_type)

	# 检查本子阶段该员工类型的采购次数
	var used_result := RoundStateCountersClass.get_player_key_count(
		state.round_state, "procurement_counts", command.actor, employee_type
	)
	if not used_result.ok:
		return used_result
	var used: int = used_result.value
	if used >= active_count:
		return Result.failure("所有 %s 本子阶段已采购完毕: %d/%d" % [employee_type, used, active_count])

	# 检查玩家是否有餐厅（采购需要从餐厅入口计算范围）
	var restaurant_ids := MapRuntimeClass.get_player_restaurants(state, command.actor)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	# 若提供了路线参数，则在 validate 阶段校验路线合法性与可拾取来源
	var plan_result := DrinksProcurementClass.resolve_procurement_plan(state, command, restaurant_ids, emp_def)
	if not plan_result.ok:
		return plan_result

	# 校验里程碑效果（Fail Fast）：procure_plus_one
	var bonus_check := DrinksProcurementClass.get_drinks_per_source_bonus_from_milestones(state, command.actor)
	if not bonus_check.ok:
		return bonus_check

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	if not command.params.has("employee_type"):
		return Result.failure("缺少参数: employee_type")
	var employee_type_val = command.params["employee_type"]
	if not (employee_type_val is String):
		return Result.failure("employee_type 必须为字符串")
	var employee_type: String = employee_type_val
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")
	var player_id: int = command.actor
	var warnings: Array[String] = []

	# 从 EmployeeRegistry 获取员工定义
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null or not emp_def.can_procure():
		return Result.failure("无法获取 %s 的采购信息" % employee_type)

	var restaurant_ids := MapRuntimeClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	var plan_result := DrinksProcurementClass.resolve_procurement_plan(state, command, restaurant_ids, emp_def)
	if not plan_result.ok:
		return plan_result

	# 使用员工：用于“first_cart_operator_used”等里程碑（要求首个 haul 也生效）
	var ms_use := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": employee_type})
	if not ms_use.ok:
		warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [employee_type, ms_use.error])

	var plan: Dictionary = plan_result.value
	if not plan.has("picked_sources") or not (plan["picked_sources"] is Array):
		return Result.failure("procurement_plan.picked_sources 缺失或类型错误")
	if not plan.has("route") or not (plan["route"] is Array):
		return Result.failure("procurement_plan.route 缺失或类型错误")
	if not plan.has("restaurant_id") or not (plan["restaurant_id"] is String):
		return Result.failure("procurement_plan.restaurant_id 缺失或类型错误")
	var restaurant_id: String = plan["restaurant_id"]
	if restaurant_id.is_empty():
		return Result.failure("procurement_plan.restaurant_id 不能为空")

	var picked_sources: Array = plan["picked_sources"]
	var route: Array = plan["route"]

	var bonus_read := DrinksProcurementClass.get_drinks_per_source_bonus_from_milestones(state, player_id)
	if not bonus_read.ok:
		return bonus_read
	var delta_read := DrinksProcurementClass.get_drinks_per_source_delta_for_employee_from_milestones(state, player_id, employee_type)
	if not delta_read.ok:
		return delta_read
	var drinks_per_source := DRINKS_PER_SOURCE + int(bonus_read.value) + int(delta_read.value)

	# 为路线经过的饮料源添加饮料到库存（同一来源在一次采购中只记一次）
	var total_drinks: Dictionary = {}
	for source in picked_sources:
		if not (source is Dictionary):
			return Result.failure("picked_source 必须为字典: %s" % str(source))
		var src: Dictionary = source
		if not src.has("type") or not (src["type"] is String):
			return Result.failure("picked_source.type 缺失或为空: %s" % str(source))
		var drink_type: String = src["type"]
		if drink_type.is_empty():
			return Result.failure("picked_source.type 缺失或为空: %s" % str(source))
		var current := 0
		if total_drinks.has(drink_type):
			var cur_val = total_drinks[drink_type]
			if not (cur_val is int):
				return Result.failure("total_drinks[%s] 类型错误（期望 int）" % drink_type)
			current = cur_val
		total_drinks[drink_type] = current + drinks_per_source

	# 添加饮料到玩家库存
	for drink_type in total_drinks:
		var amount: int = total_drinks[drink_type]
		var add_result := StateUpdater.add_inventory(state, player_id, drink_type, amount)
		if not add_result.ok:
			return add_result

	# 增加采购计数
	var inc_result := RoundStateCountersClass.increment_player_key_count(
		state.round_state, "procurement_counts", player_id, employee_type, 1
	)
	if not inc_result.ok:
		return inc_result

	return Result.success({
		"employee_type": employee_type,
		"player_id": player_id,
		"restaurant_id": restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"sources_count": picked_sources.size(),
		"drinks_procured": total_drinks,
		"picked_sources": picked_sources
	}).with_warnings(warnings)

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	assert(command.params.has("employee_type"), "procure_drinks 缺少参数: employee_type")
	assert(command.params["employee_type"] is String, "procure_drinks employee_type 必须为字符串")
	var employee_type: String = command.params["employee_type"]
	assert(not employee_type.is_empty(), "procure_drinks employee_type 不能为空")

	events.append({
		"type": EventBus.EventType.DRINKS_PROCURED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type
		}
	})

	return events
