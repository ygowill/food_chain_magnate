# 重组阶段：公司结构超限惩罚规则 smoke test
# 规则：若超出公司结构可容纳上限，则除 CEO 外全部转为待命。
class_name RestructuringOverflowPenaltyTest
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 避免首轮 Restructuring 自动跳过：让离开 Setup 后进入 round=2
	engine.get_state().round_number = 1

	var adv1 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv1.ok:
		return Result.failure("推进到 Restructuring 失败: %s" % adv1.error)
	if engine.get_state().phase != "Restructuring":
		return Result.failure("期望进入 Restructuring，实际: %s" % engine.get_state().phase)

	# 构造超限：把 CEO 卡槽设为 1，并添加 2 名在岗员工
	var state := engine.get_state()
	if not (state.players[0] is Dictionary):
		return Result.failure("player[0] 类型错误（期望 Dictionary）")
	var p0: Dictionary = state.players[0]
	if not p0.has("company_structure") or not (p0["company_structure"] is Dictionary):
		return Result.failure("player[0].company_structure 缺失或类型错误")
	p0["company_structure"]["ceo_slots"] = 1
	state.players[0] = p0

	var take1 := StateUpdaterClass.take_from_pool(state, "recruiter", 1)
	if not take1.ok:
		return take1
	var add1 := StateUpdaterClass.add_employee(state, 0, "recruiter", false)
	if not add1.ok:
		return add1

	var take2 := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take2.ok:
		return take2
	var add2 := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add2.ok:
		return add2

	# Restructuring -> OrderOfBusiness：离开重组时应触发超限惩罚
	var safety := 0
	while engine.get_state().phase == "Restructuring":
		safety += 1
		if safety > player_count + 5:
			return Result.failure("提交 Restructuring 超出安全上限")
		var actor := engine.get_state().get_current_player_id()
		var submit := engine.execute_command(Command.create("submit_restructuring", actor, {}))
		if not submit.ok:
			return Result.failure("提交重组失败: %s" % submit.error)

	state = engine.get_state()
	if state.phase != "OrderOfBusiness":
		return Result.failure("期望进入 OrderOfBusiness，实际: %s" % state.phase)

	var p_after := state.get_player(0)
	var active: Array = p_after.get("employees", [])
	var reserve: Array = p_after.get("reserve_employees", [])

	if active.size() != 1 or str(active[0]) != "ceo":
		return Result.failure("超限惩罚后在岗应仅剩 CEO，实际: %s" % str(active))
	if not reserve.has("recruiter") or not reserve.has("trainer"):
		return Result.failure("超限惩罚后 recruiter/trainer 应在待命区，实际: %s" % str(reserve))

	return Result.success({
		"player_count": player_count,
		"seed": seed
	})
