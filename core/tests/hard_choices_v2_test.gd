# 模块16：艰难抉择（Hard Choices）
class_name HardChoicesV2Test
extends RefCounted

const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_base_milestones_no_expire_by_default(seed_val)
	if not r.ok:
		return r
	r = _test_hard_choices_sets_expires_and_cleanup_removes(seed_val)
	if not r.ok:
		return r
	r = _test_round_number_does_not_count_setup(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _test_base_milestones_no_expire_by_default(seed_val: int) -> Result:
	var e := GameEngine.new()
	var init := e.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	for mid in ["first_burger_marketed", "first_pizza_marketed", "first_drink_marketed", "first_train", "first_hire_3"]:
		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null or not (def_val is MilestoneDefClass):
			return Result.failure("缺少里程碑定义: %s" % mid)
		var def: MilestoneDef = def_val
		if def.expires_at != null:
			return Result.failure("未启用 hard_choices 时 %s.expires_at 应为 null，实际: %s" % [mid, str(def.expires_at)])

	# round=2 cleanup：不应移除这些里程碑（因为不应过期）
	s.round_number = 2
	var before := s.milestone_pool.duplicate()
	var c := CleanupSettlementClass.apply(s)
	if not c.ok:
		return Result.failure("Cleanup 失败: %s" % c.error)
	for mid2 in ["first_burger_marketed", "first_pizza_marketed", "first_drink_marketed", "first_train"]:
		if not before.has(mid2):
			return Result.failure("测试前 milestone_pool 缺少: %s" % mid2)
		if not s.milestone_pool.has(mid2):
			return Result.failure("未启用 hard_choices 时，round2 cleanup 不应移除: %s" % mid2)

	return Result.success()

static func _test_hard_choices_sets_expires_and_cleanup_removes(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"hard_choices",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	var exp2 := ["first_burger_marketed", "first_pizza_marketed", "first_drink_marketed", "first_train"]
	for mid in exp2:
		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null or not (def_val is MilestoneDefClass):
			return Result.failure("缺少里程碑定义: %s" % mid)
		var def: MilestoneDef = def_val
		if def.expires_at == null or int(def.expires_at) != 2:
			return Result.failure("启用 hard_choices 后 %s.expires_at 应为 2，实际: %s" % [mid, str(def.expires_at)])

	var def3_val = MilestoneRegistryClass.get_def("first_hire_3")
	if def3_val == null or not (def3_val is MilestoneDefClass):
		return Result.failure("缺少里程碑定义: first_hire_3")
	var def3: MilestoneDef = def3_val
	if def3.expires_at == null or int(def3.expires_at) != 3:
		return Result.failure("启用 hard_choices 后 first_hire_3.expires_at 应为 3，实际: %s" % str(def3.expires_at))

	# round=2 cleanup：移除 exp2
	s.round_number = 2
	var c2 := CleanupSettlementClass.apply(s)
	if not c2.ok:
		return Result.failure("Cleanup(2) 失败: %s" % c2.error)
	for mid2 in exp2:
		if s.milestone_pool.has(mid2):
			return Result.failure("启用 hard_choices 后，round2 cleanup 应移除: %s" % mid2)

	# round=3 cleanup：移除 first_hire_3
	s.round_number = 3
	var c3 := CleanupSettlementClass.apply(s)
	if not c3.ok:
		return Result.failure("Cleanup(3) 失败: %s" % c3.error)
	if s.milestone_pool.has("first_hire_3"):
		return Result.failure("启用 hard_choices 后，round3 cleanup 应移除 first_hire_3")

	return Result.success()

static func _test_round_number_does_not_count_setup(seed_val: int) -> Result:
	# 验证：Setup（含起始餐厅放置）不应算作第 1 回合；
	# 回合数应在 Setup -> Restructuring 时从 0 增加到 1。
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"hard_choices",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var s: GameState = engine.get_state()
	if int(s.round_number) != 0 or str(s.phase) != DefsClass.PHASE_SETUP:
		return Result.failure("开局应处于 Setup 且 round=0，实际: phase=%s round=%d" % [str(s.phase), int(s.round_number)])

	var setup := TestPhaseUtilsClass.complete_setup(engine)
	if not setup.ok:
		return Result.failure("complete_setup 失败: %s" % setup.error)

	s = engine.get_state()
	if str(s.phase) == DefsClass.PHASE_SETUP or int(s.round_number) != 1:
		return Result.failure("完成 Setup 后应离开 Setup 且 round=1，实际: phase=%s round=%d" % [str(s.phase), int(s.round_number)])

	# 首回合可能会被 auto-advance 直接推进到 Working（见 AutoAdvanceTryStep：round1 跳过 Restructuring/OrderOfBusiness）。
	# 为了让本测试对齐真实流程，统一推进到 Working 作为“回合开始”的锚点。
	var to_working_r1 := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 80)
	if not to_working_r1.ok:
		return to_working_r1
	s = engine.get_state()
	if int(s.round_number) != 1 or str(s.phase) != DefsClass.PHASE_WORKING:
		return Result.failure("回合1 应处于 Working 且 round=1，实际: phase=%s round=%d" % [str(s.phase), int(s.round_number)])

	var exp2 := ["first_burger_marketed", "first_pizza_marketed", "first_drink_marketed", "first_train"]
	for mid in exp2:
		if not s.milestone_pool.has(mid):
			return Result.failure("round1 开始时 milestone_pool 缺少: %s" % mid)

	# 推进 1 个完整回合到 round2 Working：round2 时不应移除 exp2（应在 round2 cleanup 才移除）
	var done_w1 := TestPhaseUtilsClass.complete_working_phase(engine, 200)
	if not done_w1.ok:
		return done_w1
	var to_working_r2 := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 200)
	if not to_working_r2.ok:
		return to_working_r2

	s = engine.get_state()
	if int(s.round_number) != 2:
		return Result.failure("进入第 2 回合时 round_number 应为 2，实际: %d" % int(s.round_number))
	for mid2 in exp2:
		if not s.milestone_pool.has(mid2):
			return Result.failure("round2 开始时不应移除: %s（疑似回合计数/过期结算偏移）" % mid2)

	# 推进到 round3 Working：round2 cleanup 已发生，exp2 应被移除
	var done_w2 := TestPhaseUtilsClass.complete_working_phase(engine, 200)
	if not done_w2.ok:
		return done_w2
	var to_working_r3 := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 200)
	if not to_working_r3.ok:
		return to_working_r3

	s = engine.get_state()
	if int(s.round_number) != 3:
		return Result.failure("进入第 3 回合时 round_number 应为 3，实际: %d" % int(s.round_number))
	for mid3 in exp2:
		if s.milestone_pool.has(mid3):
			return Result.failure("round3 开始时应已移除: %s（应在 round2 cleanup 移除）" % mid3)

	return Result.success()
