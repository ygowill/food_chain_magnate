# 培训动作（M3 起步）
# 将"待命"员工培训为更高级的职位。
class_name TrainAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const TrainCompanyValidationClass = preload("res://gameplay/actions/train/train_company_validation.gd")
const TrainEmployeeUsageClass = preload("res://gameplay/actions/train/train_employee_usage.gd")
const TrainEmployeeLocksClass = preload("res://gameplay/actions/train/train_employee_locks.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func _compute_train_steps_within_limit(from_employee: String, to_employee: String, max_steps: int) -> int:
	# 规则：培训必须沿 employee_def.train_to 的路径逐步进行。
	# - 返回最短步数（1..max_steps），找不到则返回 -1。
	if from_employee.is_empty() or to_employee.is_empty():
		return -1
	if from_employee == to_employee:
		return -1
	if max_steps <= 0:
		return -1
	if not EmployeeRegistryClass.is_loaded():
		return -1

	var visited := {}
	visited[from_employee] = 0
	var queue: Array[String] = [from_employee]
	var qi := 0

	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		var dist := int(visited.get(cur, 0))
		if dist >= max_steps:
			continue

		var def_val = EmployeeRegistryClass.get_def(cur)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val

		for nxt_val in def.train_to:
			var nxt := str(nxt_val)
			if nxt.is_empty():
				continue
			if visited.has(nxt):
				continue
			var ndist := dist + 1
			if ndist > max_steps:
				continue
			if nxt == to_employee:
				return ndist
			visited[nxt] = ndist
			queue.append(nxt)

	return -1

func _init() -> void:
	action_id = "train"
	display_name = "培训"
	description = "将待命员工培训为更高级职位"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_TRAIN]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, player_id))
	var limit := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
	var used := EmployeeRulesClass.get_action_count(state, player_id, action_id)

	if limit <= 0:
		return pending_total > 0
	if used >= limit:
		return false
	if pending_total > 0:
		return true

	var player := state.get_player(player_id)
	var reserve_val = player.get("reserve_employees", [])
	if reserve_val is Array:
		var reserve: Array = reserve_val
		if not reserve.is_empty():
			return true

	var can_train_from_active := bool(player.get("train_from_active_same_color", false))
	if can_train_from_active:
		var active_val = player.get("employees", [])
		if active_val is Array:
			var active: Array = active_val
			if not active.is_empty():
				return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var from_result := require_string_param(command, "from_employee")
	if not from_result.ok:
		return from_result
	var to_result := require_string_param(command, "to_employee")
	if not to_result.ok:
		return to_result
	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	# 检查训练次数
	var player := state.get_player(command.actor)
	# 禁用员工（ban_card）：不能再获得/培训该员工
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		var banned: Array = banned_val
		if banned.find(to_employee) >= 0:
			return Result.failure("该员工已被禁用，不能培训: %s" % to_employee)

	var limit := EmployeeRulesClass.get_train_limit_for_working(state, command.actor)
	if limit <= 0:
		return Result.failure("没有可用的培训员")
	var used := EmployeeRulesClass.get_action_count(state, command.actor, action_id)

	# 仅允许培训“待命”员工
	var reserve_read := TrainEmployeeLocksClass._require_player_string_array(player, "reserve_employees", "train: player.reserve_employees")
	if not reserve_read.ok:
		return reserve_read
	var reserve: Array = reserve_read.value
	var pending_total := EmployeeRulesClass.get_immediate_train_pending_total(state, command.actor)
	var pending_count := EmployeeRulesClass.get_immediate_train_pending_count(state, command.actor, from_employee)
	var has_reserve := reserve.find(from_employee) >= 0
	var has_pending := pending_count > 0
	var has_active := EmployeeRulesClass.count_active(player, from_employee) > 0
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))

	# 若存在“缺货预支”待培训员工，则必须优先清账（避免占用培训次数导致无法离开 Train 子阶段）
	if pending_total > 0 and not has_pending:
		return Result.failure("存在缺货预支待培训员工，必须先在 Train 子阶段完成培训")

	if not has_reserve and not has_pending and not has_active:
		return Result.failure("待命区不存在员工: %s" % from_employee)
	if has_active and not has_reserve and not has_pending and not can_train_from_active:
		return Result.failure("该员工在岗，且未启用“在岗同色培训”能力: %s" % from_employee)

	# 培训路径 + 多步培训（coach/guru）：
	# - 默认 max_steps 为 1；coach=2、guru=3
	# - max_steps 会随本子阶段已消耗的 trainer slots 下降（例如 coach 用掉 1 slot 后，本次最多只能 1 步）
	var max_steps_one := EmployeeRulesClass.get_max_train_steps_for_single_employee_for_working(state, command.actor)
	var steps_required := _compute_train_steps_within_limit(from_employee, to_employee, maxi(1, max_steps_one))
	if steps_required <= 0:
		return Result.failure("无法按培训路径培训: %s -> %s（本次最多 %d 步）" % [from_employee, to_employee, maxi(1, max_steps_one)])
	if used + steps_required > limit:
		return Result.failure("本子阶段培训次数不足: %d/%d（需要 %d）" % [used, limit, steps_required])

	var multi_val = player.get("multi_trainer_on_one", false)
	if not (multi_val is bool):
		return Result.failure("train: player.multi_trainer_on_one 类型错误（期望 bool）")
	var multi: bool = bool(multi_val)
	var lock_check := TrainEmployeeLocksClass.plan_training(
		state, command.actor, from_employee, steps_required, multi, reserve, false
	)
	if not lock_check.ok:
		return lock_check

	# 目标职位必须有卡可用（当前仅检查最终职位堆）
	var available: int = state.employee_pool.get(to_employee, 0)
	if available <= 0:
		return Result.failure("员工池中没有 %s" % to_employee)

	# 公司结构校验（唯一员工约束等）- 校验培训后的目标员工
	var validator = CompanyStructureValidatorClass.new()
	var to_reserve := true
	if can_train_from_active and has_active and not has_reserve and not has_pending:
		# FIRST LEMONADE SOLD：在岗同色培训时，若旧员工未被使用，则新员工可立刻在岗
		var from_used := TrainEmployeeUsageClass._is_employee_used_before_training(state, command.actor, from_employee)
		to_reserve = from_used

		# 同色限制：不允许颜色变化
		var color_ok := TrainCompanyValidationClass._is_same_role_color(from_employee, to_employee)
		if not color_ok.ok:
			return color_ok
		if not bool(color_ok.value):
			return Result.failure("在岗培训不允许改变颜色: %s -> %s" % [from_employee, to_employee])

		if not to_reserve:
			var cap_check := TrainCompanyValidationClass._validate_company_structure_replacing_active(state, command.actor, from_employee, to_employee)
			if not cap_check.ok:
				return cap_check

	var validation: Result = validator.validate(state, command.actor, {
		"employee_id": to_employee,
		"to_reserve": to_reserve
	})
	if not validation.ok:
		return validation

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var from_result := require_string_param(command, "from_employee")
	if not from_result.ok:
		return from_result
	var to_result := require_string_param(command, "to_employee")
	if not to_result.ok:
		return to_result
	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("train: player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var steps_required := _compute_train_steps_within_limit(from_employee, to_employee, 50)
	if steps_required <= 0:
		return Result.failure("train: 无法按培训路径培训: %s -> %s" % [from_employee, to_employee])

	var train_events_read := _read_train_events(state)
	if not train_events_read.ok:
		return train_events_read
	var train_events: Array = train_events_read.value

	var multi_val = player.get("multi_trainer_on_one", false)
	if not (multi_val is bool):
		return Result.failure("train: player.multi_trainer_on_one 类型错误（期望 bool）")
	var multi: bool = bool(multi_val)

	var reserve_read := TrainEmployeeLocksClass._require_player_string_array(player, "reserve_employees", "train: player.reserve_employees")
	if not reserve_read.ok:
		return reserve_read
	var reserve: Array = reserve_read.value

	var use_pending := EmployeeRulesClass.get_immediate_train_pending_count(state, player_id, from_employee) > 0
	var has_reserve := reserve.find(from_employee) >= 0
	var has_active := EmployeeRulesClass.count_active(player, from_employee) > 0
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))

	var lock_plan_read := TrainEmployeeLocksClass.plan_training(
		state, player_id, from_employee, steps_required, multi, reserve, true
	)
	if not lock_plan_read.ok:
		return lock_plan_read
	var lock_plan: Dictionary = lock_plan_read.value

	# 记录并消耗“培训员 slots”（用于 coach/guru 多步培训约束 + “同一名员工必须由同一名培训员继续培训”）
	var alloc := EmployeeRulesClass.allocate_train_slots_for_working(
		state,
		player_id,
		steps_required,
		str(lock_plan.get("trainer_id", "")),
		int(lock_plan.get("instance_idx", 0))
	)
	if not alloc.ok:
		return alloc
	var alloc_info: Dictionary = alloc.value if (alloc.value is Dictionary) else {}
	var trainer_id := str(alloc_info.get("trainer_id", "")).strip_edges()
	var trainer_instance_idx := int(alloc_info.get("instance_idx", -1))

	var from_used_before := TrainEmployeeUsageClass._is_employee_used_before_training(state, player_id, from_employee)
	var target_to_reserve := true
	if can_train_from_active and has_active and not has_reserve and not use_pending:
		target_to_reserve = from_used_before

	if use_pending:
		var consumed := EmployeeRulesClass.consume_immediate_train_pending(state, player_id, from_employee)
		if not consumed:
			return Result.failure("缺货预支待清账员工不存在: %s" % from_employee)
	else:
		# 优先从待命区移除；否则允许从在岗移除（FIRST LEMONADE SOLD）
		var removed := StateUpdater.remove_from_array(state.players[player_id], "reserve_employees", from_employee)
		if not removed:
			if can_train_from_active:
				removed = StateUpdater.remove_from_array(state.players[player_id], "employees", from_employee)
		if not removed:
			return Result.failure("待命区/在岗区不存在员工: %s" % from_employee)

		# 原卡回供应区（简化：假设培训会归还原卡）
		StateUpdater.return_to_pool(state, from_employee, 1)

	# 取出目标员工
	var take_result := StateUpdater.take_from_pool(state, to_employee, 1)
	if not take_result.ok:
		return take_result

	# 培训后的员工：默认进待命；FIRST LEMONADE SOLD 且旧员工未使用时可直接在岗
	var add_result := StateUpdater.add_employee(state, player_id, to_employee, target_to_reserve)
	if not add_result.ok:
		return add_result

	# 同步“培训锁 token”：培训成功后，将 token 从 from_employee 移动到 to_employee，并在需要时锁定到具体培训员实例。
	var lock_apply := TrainEmployeeLocksClass.apply_move_token_and_lock(
		state, player_id, from_employee, to_employee, lock_plan, multi, reserve
	)
	if not lock_apply.ok:
		return lock_apply

	for _i in range(steps_required):
		EmployeeRulesClass.increment_action_count(state, player_id, action_id)

	# 记录训练事件（供模块在 Train 子阶段注入“训练后可选动作窗口”等逻辑使用）
	train_events.append({
		"player_id": player_id,
		"from_employee": from_employee,
		"to_employee": to_employee,
		"from_pending": use_pending,
		"steps": steps_required,
		"trainer_id": trainer_id,
		"trainer_instance_idx": trainer_instance_idx,
	})
	state.round_state["train_events"] = train_events

	var ms := MilestoneSystemClass.process_event(state, "Train", {"player_id": player_id})

	# 使用员工：按“培训次数/容量”推导哪些培训员必然被使用，并对每次推导出的使用调用一次 UseEmployee。
	var warnings: Array[String] = []
	var inferred_use := TrainEmployeeUsageClass.apply_inferred_use_employee_train(state, player_id)
	if not inferred_use.ok:
		return inferred_use
	warnings.append_array(inferred_use.warnings)

	var result := Result.success({
		"player_id": player_id,
		"from_employee": from_employee,
		"to_employee": to_employee,
		"from_pending": use_pending
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(Train): %s" % ms.error)
	result.with_warnings(warnings)
	return result

static func _read_train_events(state: GameState) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	var te_val = state.round_state.get("train_events", null)
	if te_val == null:
		return Result.success([])
	if not (te_val is Array):
		return Result.failure("train: round_state.train_events 类型错误（期望 Array）")
	return Result.success(Array(te_val).duplicate(true))

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var from_result := require_string_param(command, "from_employee")
	assert(from_result.ok, "train 缺少/错误参数: from_employee")
	var to_result := require_string_param(command, "to_employee")
	assert(to_result.ok, "train 缺少/错误参数: to_employee")

	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	# 优先从 new_state.round_state.train_events 中读取本次训练的细节（trainer/steps）。
	var old_train_events: Array = []
	if old_state != null and (old_state.round_state is Dictionary):
		var old_val = Dictionary(old_state.round_state).get("train_events", null)
		if old_val is Array:
			old_train_events = Array(old_val)

	var new_train_events: Array = []
	if new_state != null and (new_state.round_state is Dictionary):
		var new_val = Dictionary(new_state.round_state).get("train_events", null)
		if new_val is Array:
			new_train_events = Array(new_val)

	var start := old_train_events.size()
	for i in range(start, new_train_events.size()):
		var item_val = new_train_events[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("player_id", -1)) != command.actor:
			continue
		if str(item.get("from_employee", "")) != from_employee:
			continue
		if str(item.get("to_employee", "")) != to_employee:
			continue

		events.append({
			"type": EventBus.EventType.EMPLOYEE_TRAINED,
			"data": {
				"player_id": command.actor,
				"from_employee": from_employee,
				"to_employee": to_employee,
				"from_pending": bool(item.get("from_pending", false)),
				"steps": maxi(1, int(item.get("steps", 1))),
				"trainer_id": str(item.get("trainer_id", "")).strip_edges(),
				"trainer_instance_idx": int(item.get("trainer_instance_idx", -1)),
			}
		})
		return events

	# 兜底：旧状态/异常情况下仍发射基础事件（不阻断日志）。
	var from_pending := EmployeeRulesClass.get_immediate_train_pending_count(old_state, command.actor, from_employee) > 0
	var steps := _compute_train_steps_within_limit(from_employee, to_employee, 50)
	events.append({
		"type": EventBus.EventType.EMPLOYEE_TRAINED,
		"data": {
			"player_id": command.actor,
			"from_employee": from_employee,
			"to_employee": to_employee,
			"from_pending": from_pending,
			"steps": maxi(1, steps),
		}
	})
	return events
