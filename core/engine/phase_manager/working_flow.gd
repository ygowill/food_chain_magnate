# PhaseManager：回合/工作阶段状态维护（非结算规则）
# 负责：进入新回合、OrderOfBusiness 初始化、Working 子阶段计数重置、公司容量约束等状态维护。
extends RefCounted

const CompanyStructureRulesClass = preload("res://core/rules/company_structure_rules.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func start_new_round(state: GameState) -> void:
	# 重建回合状态（避免残留旧回合的计数/完成记录）
	var mandatory := {}
	var passed := {}
	for i in range(state.players.size()):
		mandatory[i] = []
		passed[i] = false
	state.round_state = {
		"mandatory_actions_completed": mandatory,
		"actions_this_round": [],
		"action_counts": {},
		"sub_phase_passed": passed
	}

static func auto_activate_reserve_employees(state: GameState) -> Result:
	# 简化策略：进入重组阶段时将上一回合招募/训练得到的员工自动变为“在岗”。
	if state == null:
		return Result.failure("WorkingFlow.auto_activate_reserve_employees: state 为空")
	for i in range(state.players.size()):
		var player_val = state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("WorkingFlow.auto_activate_reserve_employees: players[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val

		var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "players[%d]" % i, "WorkingFlow.auto_activate_reserve_employees")
		if not reserve_read.ok:
			return reserve_read
		var reserve: Array = reserve_read.value
		if reserve.is_empty():
			continue

		var active_read := PlayerStateAccessClass.require_employees(player, "players[%d]" % i, "WorkingFlow.auto_activate_reserve_employees")
		if not active_read.ok:
			return active_read
		var active: Array = active_read.value
		active.append_array(reserve)
		player["employees"] = active
		player["reserve_employees"] = []
		var cap_r := _enforce_company_capacity(player)
		if not cap_r.ok:
			return cap_r
		state.players[i] = player
	return Result.success()

static func start_order_of_business(state: GameState) -> Result:
	if state == null:
		return Result.failure("WorkingFlow.start_order_of_business: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("WorkingFlow.start_order_of_business: state.round_state 类型错误（期望 Dictionary）")
	if not (state.turn_order is Array):
		return Result.failure("WorkingFlow.start_order_of_business: state.turn_order 类型错误（期望 Array[int]）")

	var previous_turn_order: Array[int] = []
	for i in range(state.turn_order.size()):
		var pid_read := IntValueParseHelpersClass.parse_int_value(state.turn_order[i], "WorkingFlow.start_order_of_business: turn_order[%d]" % i)
		if not pid_read.ok:
			return pid_read
		previous_turn_order.append(int(pid_read.value))

	var selection_read := _compute_order_of_business_selection(state, previous_turn_order)
	if not selection_read.ok:
		return selection_read
	var selection: Array[int] = selection_read.value
	state.selection_order = selection

	# OrderOfBusiness 阶段期间，用 turn_order 表示“选择顺序”，复用现有的 current_player_index / get_current_player_id 逻辑。
	state.turn_order = selection
	state.current_player_index = 0

	var picks: Array = []
	for _i in range(state.players.size()):
		picks.append(-1)

	state.round_state["order_of_business"] = {
		"previous_turn_order": previous_turn_order,
		"selection_order": selection,
		"picks": picks,
		"finalized": false
	}
	return Result.success()

static func reset_working_phase_state(state: GameState) -> void:
	# 进入 Working：重置子阶段动作计数并从顺序第一位开始
	state.current_player_index = 0
	reset_working_sub_phase_state(state)
	reset_sub_phase_passed(state)

static func reset_working_sub_phase_state(state: GameState) -> void:
	if state.round_state is Dictionary:
		state.round_state["action_counts"] = {}
		# Train 子阶段：记录“培训员 slot 使用情况”（用于 coach/guru 多步培训）也需随子阶段重置。
		state.round_state["train_slot_usage"] = {}
		state.round_state["train_slot_usage_instances"] = {}
		# Train 子阶段：记录“员工培训锁”（同一员工不可更换培训员继续培训，除非里程碑允许）。
		state.round_state["train_employee_locks"] = {}

static func reset_sub_phase_passed(state: GameState) -> void:
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	var passed := {}
	for i in range(state.players.size()):
		passed[i] = false
	state.round_state["sub_phase_passed"] = passed

static func compute_order_of_business_empty_slots(state: GameState, player: Dictionary) -> Result:
	return _compute_order_of_business_empty_slots(state, player)

static func _compute_order_of_business_selection(state: GameState, previous_turn_order: Array[int]) -> Result:
	var player_count := state.players.size()
	if previous_turn_order.size() != player_count:
		return Result.failure("WorkingFlow: turn_order 长度错误（期望 %d，实际 %d）" % [player_count, previous_turn_order.size()])

	var prev_index := {}
	for i in range(previous_turn_order.size()):
		var pid: int = int(previous_turn_order[i])
		if pid < 0 or pid >= player_count:
			return Result.failure("WorkingFlow: turn_order[%d] 玩家 id 越界: %d" % [i, pid])
		if prev_index.has(pid):
			return Result.failure("WorkingFlow: turn_order 重复玩家: %d" % pid)
		prev_index[pid] = i

	var entries: Array[Dictionary] = []
	for pid in range(player_count):
		if not prev_index.has(pid):
			return Result.failure("WorkingFlow: turn_order 缺少玩家: %d" % pid)
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("WorkingFlow: players[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		var slots_read := _compute_order_of_business_empty_slots(state, player)
		if not slots_read.ok:
			return slots_read
		entries.append({
			"pid": pid,
			"empty_slots": int(slots_read.value),
			"prev_index": int(prev_index[pid]),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_slots: int = int(a.get("empty_slots", 0))
		var b_slots: int = int(b.get("empty_slots", 0))
		if a_slots != b_slots:
			return a_slots > b_slots
		return int(a.get("prev_index", 0)) < int(b.get("prev_index", 0))
	)

	var ids: Array[int] = []
	for e in entries:
		ids.append(int(e.get("pid", -1)))
	return Result.success(ids)

static func _compute_order_of_business_empty_slots(state: GameState, player: Dictionary) -> Result:
	var empty_slots_read := CompanyStructureRulesClass.get_empty_slots(player)
	if not empty_slots_read.ok:
		return empty_slots_read
	var empty_slots: int = int(empty_slots_read.value)

	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player", "WorkingFlow")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value
	var bonus_read := _get_turnorder_empty_slots_bonus_from_milestones(milestones)
	if not bonus_read.ok:
		return bonus_read
	empty_slots += int(bonus_read.value)

	return Result.success(empty_slots)

static func _get_turnorder_empty_slots_bonus_from_milestones(milestones: Array) -> Result:
	var bonus_read := MilestoneEffectQueriesClass.sum_non_negative_int_values(
		milestones,
		"turnorder_empty_slots",
		"WorkingFlow: ",
		"milestones"
	)
	if not bonus_read.ok:
		return bonus_read
	return Result.success(int(bonus_read.value))

static func _enforce_company_capacity(player: Dictionary) -> Result:
	return CompanyStructureRulesClass.enforce_capacity(player)
