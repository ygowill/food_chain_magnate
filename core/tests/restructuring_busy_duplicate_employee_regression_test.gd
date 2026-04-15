# 回归：进入重组阶段时，同类型“在岗 + 忙碌”员工不能丢失在岗实例。
class_name RestructuringBusyDuplicateEmployeeRegressionTest
extends RefCounted

const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const PhaseAndMapRulesClass = preload("res://modules/base_rules/rules/phase_and_map.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	var initial_cash_read := InvariantsClass.compute_total_cash(state)
	if not initial_cash_read.ok:
		return initial_cash_read
	var initial_total_cash: int = int(initial_cash_read.value)

	var initial_totals_read := InvariantsClass.compute_employee_totals(state)
	if not initial_totals_read.ok:
		return initial_totals_read
	var initial_employee_totals: Dictionary = initial_totals_read.value

	var take_active := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_active.ok:
		return take_active
	var add_active := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", false)
	if not add_active.ok:
		return add_active

	var take_busy := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_busy.ok:
		return take_busy
	StateUpdaterClass.append_to_array(state.players[0], "busy_marketers", "marketing_trainee")

	var player_before := state.get_player(0)
	if _count_in_array(Array(player_before.get("employees", [])), "marketing_trainee") != 1:
		return Result.failure("测试前置失败：在岗区应有 1 张 marketing_trainee")
	if _count_in_array(Array(player_before.get("busy_marketers", [])), "marketing_trainee") != 1:
		return Result.failure("测试前置失败：忙碌区应有 1 张 marketing_trainee")

	state.round_number = 9
	state.round_state = {"prev_phase": "Cleanup"}

	var rules := PhaseAndMapRulesClass.new()
	var enter_r := rules._on_restructuring_before_enter(state)
	if not enter_r.ok:
		return Result.failure("进入重组阶段失败: %s" % enter_r.error)

	var player_after := state.get_player(0)
	var active_after: Array = player_after.get("employees", [])
	var reserve_after: Array = player_after.get("reserve_employees", [])
	var busy_after: Array = player_after.get("busy_marketers", [])

	if active_after.size() != 1 or str(active_after[0]) != "ceo":
		return Result.failure("进入重组后在岗区应仅剩 CEO，实际: %s" % str(active_after))
	if _count_in_array(reserve_after, "marketing_trainee") != 1:
		return Result.failure("进入重组后待命区应新增 1 张 marketing_trainee，实际: %s" % str(reserve_after))
	if _count_in_array(busy_after, "marketing_trainee") != 1:
		return Result.failure("进入重组后忙碌区应仍保留 1 张 marketing_trainee，实际: %s" % str(busy_after))

	var inv := InvariantsClass.check_invariants(state, initial_total_cash, initial_employee_totals)
	if not inv.ok:
		return Result.failure("员工守恒校验失败: %s" % inv.error)

	return Result.success({
		"player_count": player_count,
		"seed": seed,
		"reserve_marketing_trainee": _count_in_array(reserve_after, "marketing_trainee"),
		"busy_marketing_trainee": _count_in_array(busy_after, "marketing_trainee"),
	})

static func _count_in_array(items: Array, employee_id: String) -> int:
	var count := 0
	for item in items:
		if item is String and str(item) == employee_id:
			count += 1
	return count
