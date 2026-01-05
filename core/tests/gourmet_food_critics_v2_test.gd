# 模块13：美食评论家（Gourmet Food Critics）
class_name GourmetFoodCriticsV2Test
extends RefCounted

const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_registration_and_range(seed_val)
	if not r.ok:
		return r
	r = _test_global_limit_and_offramp_conflict(seed_val)
	if not r.ok:
		return r

	return Result.success()

static func _test_registration_and_range(seed_val: int) -> Result:
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
		"gourmet_food_critics",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	if not MarketingTypeRegistryClass.has_type("gourmet_guide"):
		return Result.failure("MarketingTypeRegistry 缺少 gourmet_guide（模块未注册）")
	if not MarketingTypeRegistryClass.requires_edge("gourmet_guide"):
		return Result.failure("gourmet_guide 应要求边缘放置（requires_edge=true）")

	var marketer = EmployeeRegistryClass.get_def("marketer")
	if marketer == null:
		return Result.failure("缺少员工定义: marketer")
	if not marketer.train_to.has("gourmet_food_critic"):
		return Result.failure("marketer.train_to 应包含 gourmet_food_critic（模块 patch 未生效）")

	# 构造最小 houses（不依赖结构格）：仅验证 range handler 选中 has_garden 的房屋
	if not (s.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	s.map["houses"] = {
		"h_garden": {"house_id": "h_garden", "house_number": 1, "has_garden": true, "demands": []},
		"h_plain": {"house_id": "h_plain", "house_number": 2, "has_garden": false, "demands": []},
		"rural_area": {"house_id": "rural_area", "house_number": "zzzz_rural_area", "has_garden": false, "demands": []},
	}

	var handler := MarketingTypeRegistryClass.get_range_handler("gourmet_guide")
	if not handler.is_valid():
		return Result.failure("gourmet_guide handler 无效")
	var rr = handler.call(s, {"type": "gourmet_guide"})
	if not (rr is Result):
		return Result.failure("gourmet_guide handler 返回值类型错误（期望 Result）")
	var rres: Result = rr
	if not rres.ok:
		return Result.failure("gourmet_guide handler 失败: %s" % rres.error)
	var affected: Array = rres.value
	if affected.size() != 1 or str(affected[0]) != "h_garden":
		return Result.failure("gourmet_guide 应仅影响有花园的房屋（期望 [h_garden]），实际: %s" % str(affected))

	return Result.success()

static func _test_global_limit_and_offramp_conflict(seed_val: int) -> Result:
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
		"gourmet_food_critics",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	# 伪造已存在的 3 个 gourmet_guide 实例，下一次放置应被拒绝（全局最多 3 个）
	s.marketing_instances = [
		{"type": "gourmet_guide", "board_number": 17},
		{"type": "gourmet_guide", "board_number": 18},
		{"type": "gourmet_guide", "board_number": 19},
	]

	var entry = load("res://modules/gourmet_food_critics/rules/entry.gd").new()

	var cmd := Command.create("initiate_marketing", 0)
	cmd.params = {
		"employee_type": "gourmet_food_critic",
		"board_number": 20,
		"product": "burger",
		"position": [0, 0],
		"duration": 1,
	}
	var r1: Result = entry._validate_initiate_marketing(s, cmd)
	if r1.ok:
		return Result.failure("超过全局 3 个 gourmet_guide 时应被拒绝")

	# 冲突：同格已有 offramp 时应拒绝（通过 state.map.rural_marketeers_offramps 检测）
	s.marketing_instances = []
	s.map["rural_marketeers_offramps"] = [{"pos": Vector2i(0, 0)}]
	var r2: Result = entry._validate_initiate_marketing(s, cmd)
	if r2.ok:
		return Result.failure("与 offramp 同格应被拒绝")

	# sanity：board_number=4（airplane）不应被该 validator 影响
	var cmd_air := Command.create("initiate_marketing", 0)
	cmd_air.params = {"board_number": 4, "position": [0, 0]}
	var r3: Result = entry._validate_initiate_marketing(s, cmd_air)
	if not r3.ok:
		return Result.failure("非 gourmet_guide 不应被该 validator 拒绝: %s" % r3.error)

	# sanity：MarketingRegistry 中 17–20 的 type 应为 gourmet_guide
	for bn in [17, 18, 19, 20]:
		var def = MarketingRegistryClass.get_def(bn)
		if def == null:
			return Result.failure("缺少营销板件定义: #%d" % bn)
		if str(def.type) != "gourmet_guide":
			return Result.failure("营销板件 #%d type 应为 gourmet_guide，实际: %s" % [bn, str(def.type)])

	return Result.success()

