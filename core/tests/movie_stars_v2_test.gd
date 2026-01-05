# 模块15：电影明星（Movie Stars）
# - waitress.train_to 由模块注入 movie_star_b/c/d
# - OrderOfBusiness：拥有在岗 movie_star_* 的玩家优先选择顺序（B>C>D），剩余玩家按空槽数排序
# - Dinnertime：movie_star_* 作为更高优先级 tie-breaker（B>C>D）
class_name MovieStarsV2Test
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")
const ModuleEntryClass = preload("res://modules/movie_stars/rules/entry.gd")

const EFFECT_B := "movie_stars:dinnertime:tiebreaker:movie_star_b"
const EFFECT_C := "movie_stars:dinnertime:tiebreaker:movie_star_c"
const EFFECT_D := "movie_stars:dinnertime:tiebreaker:movie_star_d"

static func run(player_count: int = 3, seed_val: int = 12345) -> Result:
	if player_count != 3:
		return Result.failure("本测试固定为 3 人局（实际: %d）" % player_count)

	var r1 := _test_waitress_train_to_patched(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_order_of_business_priority(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_tiebreak_effect_registered(seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_train_exclusive(seed_val)
	if not r4.ok:
		return r4

	return Result.success()

static func _test_waitress_train_to_patched(seed_val: int) -> Result:
	# 1) 未启用 movie_stars：waitress.train_to 不应包含 movie_star
	var e0 := GameEngine.new()
	var init0 := e0.initialize(3, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var w0 = EmployeeRegistryClass.get_def("waitress")
	if w0 == null:
		return Result.failure("缺少 waitress 定义")
	for sid in ["movie_star_b", "movie_star_c", "movie_star_d"]:
		if (w0.train_to as Array).has(sid):
			return Result.failure("未启用 movie_stars 时 waitress.train_to 不应包含 %s" % sid)

	# 2) 启用 movie_stars：waitress.train_to 应包含 movie_star
	var e1 := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"movie_stars",
	]
	var init1 := e1.initialize(3, seed_val, enabled_modules)
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)
	var w1 = EmployeeRegistryClass.get_def("waitress")
	if w1 == null:
		return Result.failure("缺少 waitress 定义（启用 movie_stars 后）")
	for sid2 in ["movie_star_b", "movie_star_c", "movie_star_d"]:
		if not (w1.train_to as Array).has(sid2):
			return Result.failure("启用 movie_stars 后 waitress.train_to 应包含 %s，实际: %s" % [sid2, str(w1.train_to)])
		if EmployeeRegistryClass.get_def(sid2) == null:
			return Result.failure("启用 movie_stars 后应存在 %s 定义" % sid2)

	return Result.success()

static func _test_order_of_business_priority(seed_val: int) -> Result:
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
		"movie_stars",
	]
	var init := engine.initialize(3, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1, 2]

	# 构造：
	# - P2 有 movie_star_b，空槽最少，但应排第一
	# - P0 有 movie_star_c，空槽最多，但应排第二（明星排序优先于空槽）
	# - P1 无明星，排在最后
	state.players[2]["employees"].append("movie_star_b")
	state.players[0]["employees"].append("movie_star_c")
	state.players[2]["company_structure"]["ceo_slots"] = 1
	state.players[0]["company_structure"]["ceo_slots"] = 9
	state.players[1]["company_structure"]["ceo_slots"] = 3

	WorkingFlowClass.start_order_of_business(state)
	state.phase = "OrderOfBusiness"
	var entry = ModuleEntryClass.new()
	var hook_r := entry._on_order_of_business_after_enter(state)
	if not hook_r.ok:
		return hook_r

	var selection: Array = state.selection_order
	var expected := [2, 0, 1]
	if selection != expected:
		return Result.failure("selection_order 不匹配: %s != %s" % [str(selection), str(expected)])

	return Result.success()

static func _test_tiebreak_effect_registered(seed_val: int) -> Result:
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
		"movie_stars",
	]
	var init := engine.initialize(3, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var effect_registry = engine.phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("EffectRegistry 未设置")
	var ctx_b := {"score": 0}
	var rb: Result = effect_registry.invoke(EFFECT_B, [engine.get_state(), 0, ctx_b])
	if not rb.ok:
		return rb
	var ctx_c := {"score": 0}
	var rc: Result = effect_registry.invoke(EFFECT_C, [engine.get_state(), 0, ctx_c])
	if not rc.ok:
		return rc
	var ctx_d := {"score": 0}
	var rd: Result = effect_registry.invoke(EFFECT_D, [engine.get_state(), 0, ctx_d])
	if not rd.ok:
		return rd
	if int(ctx_b.get("score", 0)) <= int(ctx_c.get("score", 0)) or int(ctx_c.get("score", 0)) <= int(ctx_d.get("score", 0)):
		return Result.failure("movie_star tiebreak 应满足 B>C>D，实际: B=%s C=%s D=%s" % [str(ctx_b.get("score", null)), str(ctx_c.get("score", null)), str(ctx_d.get("score", null))])
	if int(ctx_d.get("score", 0)) < 1000:
		return Result.failure("movie_star_d tiebreak 应提供大幅加成，实际: %s" % str(ctx_d.get("score", null)))

	return Result.success()

static func _test_train_exclusive(seed_val: int) -> Result:
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
		"movie_stars",
	]
	var init := engine.initialize(3, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()

	# 玩家0 已拥有 movie_star_b（待命），则培训到 movie_star_c 应被拒绝
	state.players[0]["reserve_employees"].append("movie_star_b")
	var entry = ModuleEntryClass.new()
	var cmd := Command.create("train", 0)
	cmd.params = {"to_employee": "movie_star_c"}
	var r: Result = entry._validate_train_movie_star_exclusive(state, cmd)
	if r.ok:
		return Result.failure("已拥有电影明星时不应允许再培训电影明星")
	return Result.success()
