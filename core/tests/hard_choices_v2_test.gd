# 模块16：艰难抉择（Hard Choices）
class_name HardChoicesV2Test
extends RefCounted

const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_base_milestones_no_expire_by_default(seed_val)
	if not r.ok:
		return r
	r = _test_hard_choices_sets_expires_and_cleanup_removes(seed_val)
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

