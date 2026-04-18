# 饮料采购动作（GET_DRINKS 子阶段）
# 卡车司机/飞艇驾驶员从饮料源采购饮料到玩家库存
class_name ProcureDrinksAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

# 每个饮料源提供的饮料数量
const DRINKS_PER_SOURCE := 2

func _init() -> void:
	action_id = "procure_drinks"
	display_name = "采购饮料"
	description = "从饮料源采购饮料"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_GET_DRINKS]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return false

	var providers_read := EmployeeRulesClass.try_get_drinks_procurers_for_working(state, player_id)
	if not providers_read.ok:
		return false
	for provider_val in providers_read.value:
		if not (provider_val is Dictionary):
			continue
		if int(Dictionary(provider_val).get("remaining", 0)) > 0:
			return true
	return false

func _build_preview_state_with_use_employee(state: GameState, player_id: int, employee_type: String) -> GameState:
	if state == null or employee_type.is_empty():
		return state

	var preview_state := state.duplicate_state()
	var preview_warnings: Array[String] = []
	EmployeeUsageHelperClass.append_use_employee_warning(preview_warnings, preview_state, player_id, employee_type)
	return preview_state

func _read_optional_staff_id(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if not command.params.has("staff_id"):
		return Result.success(-1)
	var staff_id_result := require_int_param(command, "staff_id")
	if not staff_id_result.ok:
		return staff_id_result
	var staff_id := int(staff_id_result.value)
	if staff_id <= 0:
		return Result.failure("staff_id 必须 > 0，实际: %d" % staff_id)
	return Result.success(staff_id)

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	if not command.params.has("employee_type"):
		return Result.failure("缺少参数: employee_type", Result.ErrorCode.MISSING_PARAMS)
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

	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)
	var provider_read := EmployeeRulesClass.try_resolve_drinks_procurer(
		state,
		command.actor,
		employee_type,
		requested_staff_id
	)
	if not provider_read.ok:
		return provider_read

	# 检查玩家是否有餐厅（采购需要从餐厅入口计算范围）
	var restaurant_ids := StructuresClass.get_player_restaurants(state, command.actor)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	# 特殊：跑腿伙计（直接获得 1 瓶指定饮料，不走路线/饮料源拾取）
	if employee_type == "errand_boy":
		var drink_type_r := require_string_param(command, "drink_type")
		if not drink_type_r.ok:
			return drink_type_r
		var drink_type: String = str(drink_type_r.value).strip_edges()
		if drink_type.is_empty():
			return Result.failure("drink_type 不能为空")

		# 跑腿伙计直接“获得饮料”，不要求地图上存在对应饮料源；但仍需是已注册的饮品类型。
		if not ProductRegistryClass.is_loaded():
			return Result.failure("ProductRegistry 未初始化，无法校验 drink_type")
		if not ProductRegistryClass.is_drink(drink_type):
			return Result.failure("未知或非饮品的 drink_type: %s" % drink_type)

		return Result.success()

	# 其它采购员工：必须由玩家手动选点生成路线后才能执行（不允许系统自动选路）
	if not command.params.has("route"):
		return Result.failure("缺少参数: route（请先在地图上选择进货点生成路线）", Result.ErrorCode.MISSING_PARAMS)
	if not command.params.has("selected_sources"):
		return Result.failure("缺少参数: selected_sources（请先选择饮料点）", Result.ErrorCode.MISSING_PARAMS)

	var preview_state := _build_preview_state_with_use_employee(state, command.actor, employee_type)

	# 校验路线合法性与可拾取来源
	var plan_result := DrinksProcurementClass.resolve_procurement_plan(preview_state, command, restaurant_ids, emp_def)
	if not plan_result.ok:
		return plan_result

	# 校验里程碑效果（Fail Fast）：procure_plus_one
	var bonus_check := DrinksProcurementClass.get_drinks_per_source_bonus_from_milestones(preview_state, command.actor)
	if not bonus_check.ok:
		return bonus_check

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	if not command.params.has("employee_type"):
		return Result.failure("缺少参数: employee_type", Result.ErrorCode.MISSING_PARAMS)
	var employee_type_val = command.params["employee_type"]
	if not (employee_type_val is String):
		return Result.failure("employee_type 必须为字符串")
	var employee_type: String = employee_type_val
	if employee_type.is_empty():
		return Result.failure("employee_type 不能为空")
	var player_id: int = command.actor
	var warnings: Array[String] = []
	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)
	var provider_read := EmployeeRulesClass.try_resolve_drinks_procurer(
		state,
		player_id,
		employee_type,
		requested_staff_id
	)
	if not provider_read.ok:
		return provider_read
	var provider: Dictionary = provider_read.value
	var procurer_staff_id := int(provider.get("staff_id", -1))
	var procurer_employee_type := str(provider.get("employee_type", employee_type)).strip_edges()
	if procurer_staff_id <= 0 or procurer_employee_type.is_empty():
		return Result.failure("procure_drinks: 采购员工解析结果无效: %s" % str(provider))

	# 从 EmployeeRegistry 获取员工定义
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null or not emp_def.can_procure():
		return Result.failure("无法获取 %s 的采购信息" % employee_type)

	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	# 使用员工：用于“first_cart_operator_used”等里程碑（要求首个 haul 也生效）
	EmployeeUsageHelperClass.append_use_employee_warning(warnings, state, player_id, procurer_employee_type)

	# 特殊：跑腿伙计（直接获得 1 瓶指定饮料）
	if employee_type == "errand_boy":
		var drink_type_r := require_string_param(command, "drink_type")
		if not drink_type_r.ok:
			return drink_type_r
		var drink_type: String = str(drink_type_r.value).strip_edges()
		if drink_type.is_empty():
			return Result.failure("drink_type 不能为空")

		# 防御：避免绕过 validate 直接执行时写入非法产品 id。
		if not ProductRegistryClass.is_loaded():
			return Result.failure("ProductRegistry 未初始化，无法校验 drink_type")
		if not ProductRegistryClass.is_drink(drink_type):
			return Result.failure("未知或非饮品的 drink_type: %s" % drink_type)

		var add_result := StateUpdater.add_inventory(state, player_id, drink_type, 1)
		if not add_result.ok:
			return add_result

		var inc_result := RoundStateCountersClass.increment_player_key_count(
			state.round_state, "procurement_counts", player_id, employee_type, 1
		)
		if not inc_result.ok:
			return inc_result
		var use_staff := StaffStateClass.increment_staff_track_usage(state, procurer_staff_id, action_id, 1)
		if not use_staff.ok:
			return use_staff

		return Result.success({
			"employee_type": employee_type,
			"staff_id": procurer_staff_id,
			"procurer_staff_id": procurer_staff_id,
			"procurer_employee_type": procurer_employee_type,
			"player_id": player_id,
			"drink_type": drink_type,
			"drinks_procured": {drink_type: 1},
		}).with_warnings(warnings)

	var plan_result := DrinksProcurementClass.resolve_procurement_plan(state, command, restaurant_ids, emp_def)
	if not plan_result.ok:
		return plan_result

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
	var use_staff := StaffStateClass.increment_staff_track_usage(state, procurer_staff_id, action_id, 1)
	if not use_staff.ok:
		return use_staff

	return Result.success({
		"employee_type": employee_type,
		"staff_id": procurer_staff_id,
		"procurer_staff_id": procurer_staff_id,
		"procurer_employee_type": procurer_employee_type,
		"player_id": player_id,
		"restaurant_id": restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"sources_count": picked_sources.size(),
		"drinks_procured": total_drinks,
		"picked_sources": picked_sources
	}).with_warnings(warnings)

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var employee_type_r := require_string_param(command, "employee_type")
	if not employee_type_r.ok:
		return events
	var employee_type: String = str(employee_type_r.value).strip_edges()
	if employee_type.is_empty():
		return events
	var procurer_staff_id := -1

	var data := {
		"player_id": command.actor,
		"employee_type": employee_type
	}
	var provider_read := EmployeeRulesClass.try_resolve_drinks_procurer(
		_old_state,
		command.actor,
		employee_type,
		int(command.params.get("staff_id", -1))
	)
	if provider_read.ok and provider_read.value is Dictionary:
		procurer_staff_id = int(Dictionary(provider_read.value).get("staff_id", -1))
	if procurer_staff_id > 0:
		data["staff_id"] = procurer_staff_id

	var drinks_procured: Dictionary = {}
	if employee_type == "errand_boy":
		var drink_type_val = command.params.get("drink_type", null)
		if drink_type_val is String and not str(drink_type_val).strip_edges().is_empty():
			drinks_procured[str(drink_type_val).strip_edges()] = 1
	else:
		var emp_def = EmployeeRegistryClass.get_def(employee_type)
		var restaurant_ids := StructuresClass.get_player_restaurants(_old_state, command.actor)
		if emp_def != null and (emp_def is EmployeeDef) and not restaurant_ids.is_empty():
			var preview_state := _build_preview_state_with_use_employee(_old_state, command.actor, employee_type)
			var plan_r := DrinksProcurementClass.resolve_procurement_plan(preview_state, command, restaurant_ids, emp_def)
			if plan_r.ok and plan_r.value is Dictionary:
				var plan: Dictionary = plan_r.value
				var rest_id := str(plan.get("restaurant_id", "")).strip_edges()
				if not rest_id.is_empty():
					data["restaurant_id"] = rest_id

				# issue_tracker #48: include chosen drink sources for log readability (route A: start restaurant + sources).
				var picked_val = plan.get("picked_sources", null)
				if picked_val is Array:
					var picked_sources_out: Array[Dictionary] = []
					for src_val in Array(picked_val):
						if not (src_val is Dictionary):
							continue
						var src: Dictionary = src_val
						var drink_type := str(src.get("type", "")).strip_edges()
						var pos_out: Array = []
						var wp_val = src.get("world_pos", null)
						if wp_val is Vector2i:
							var wp: Vector2i = wp_val
							pos_out = [wp.x, wp.y]
						elif wp_val is Array:
							pos_out = Array(wp_val)

						var item := {}
						if not drink_type.is_empty():
							item["type"] = drink_type
						if not pos_out.is_empty():
							item["world_pos"] = pos_out
						if not item.is_empty():
							picked_sources_out.append(item)
					if not picked_sources_out.is_empty():
						data["picked_sources"] = picked_sources_out

				var selected_val = command.params.get("selected_sources", null)
				if selected_val is Array and not Array(selected_val).is_empty():
					data["selected_sources"] = Array(selected_val)

				var picked_sources_val = plan.get("picked_sources", null)
				if picked_sources_val is Array:
					var bonus_read := DrinksProcurementClass.get_drinks_per_source_bonus_from_milestones(preview_state, command.actor)
					var delta_read := DrinksProcurementClass.get_drinks_per_source_delta_for_employee_from_milestones(preview_state, command.actor, employee_type)
					if bonus_read.ok and delta_read.ok:
						var drinks_per_source := DRINKS_PER_SOURCE + int(bonus_read.value) + int(delta_read.value)
						for src_val in picked_sources_val:
							if not (src_val is Dictionary):
								continue
							var src: Dictionary = src_val
							var drink_type := str(src.get("type", "")).strip_edges()
							if drink_type.is_empty():
								continue
							drinks_procured[drink_type] = int(drinks_procured.get(drink_type, 0)) + drinks_per_source

	if not drinks_procured.is_empty():
		data["drinks_procured"] = drinks_procured

	events.append({
		"type": EventBus.EventType.DRINKS_PROCURED,
		"data": data
	})

	return events
