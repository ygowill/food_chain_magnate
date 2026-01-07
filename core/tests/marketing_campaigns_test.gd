# 营销系统测试（M4 起步）
# 覆盖：发起营销（占用板件/忙碌营销员）与 Marketing 阶段需求生成/持续时间/释放。
class_name MarketingCampaignsTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	EmployeeRegistryClass.reset()
	MilestoneRegistryClass.reset()
	MarketingRegistryClass.reset()

	var r1 := _test_billboard_mailbox_and_expiry(player_count, seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_radio_and_airplane_ranges(player_count, seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_first_billboard_permanent_and_no_salary(player_count, seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_effect_registry_first_radio_demand_amount(player_count, seed_val)
	if not r4.ok:
		return r4

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"cases": 4,
	})

static func _test_billboard_mailbox_and_expiry(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state, player_count)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var map_result := _build_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)
	state.players[actor]["restaurants"] = ["rest_0"]

	# 准备员工（直接从池取卡，保持守恒）
	if int(state.employee_pool.get("marketer", 0)) <= 0:
		return Result.failure("员工池中没有 marketer")
	state.employee_pool["marketer"] = int(state.employee_pool.get("marketer", 0)) - 1
	state.players[actor]["employees"].append("marketer")

	if int(state.employee_pool.get("campaign_manager", 0)) <= 0:
		return Result.failure("员工池中没有 campaign_manager")
	state.employee_pool["campaign_manager"] = int(state.employee_pool.get("campaign_manager", 0)) - 1
	state.players[actor]["employees"].append("campaign_manager")

	# 固定到 Working / Marketing 子阶段
	state.phase = "Working"
	state.sub_phase = "Marketing"

	# 1) 2 人局：#12/#15/#16 被移除
	var invalid := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "marketer",
		"board_number": 12,
		"product": "burger",
		"duration": 1,
		"position": [1, 2],
	}))
	if invalid.ok:
		return Result.failure("2 人局使用移除的营销板件 #12 应失败")
	if str(invalid.error).find("移除") < 0:
		return Result.failure("移除原因应包含'移除'，实际: %s" % invalid.error)

	# 2) 右侧房屋预填到上限，Mailbox 不应再增加需求
	state = engine.get_state()
	var houses: Dictionary = state.map.get("houses", {})
	var right: Dictionary = houses.get("house_right", {})
	right["demands"] = [
		{"product": "pizza", "from_player": -1, "board_number": 0, "type": "seed"},
		{"product": "pizza", "from_player": -1, "board_number": 0, "type": "seed"},
		{"product": "pizza", "from_player": -1, "board_number": 0, "type": "seed"},
	]
	houses["house_right"] = right
	state.map["houses"] = houses

	var mailbox := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "campaign_manager",
		"board_number": 7,
		"product": "pizza",
		"duration": 1,
		"position": [3, 2],
	}))
	if not mailbox.ok:
		return Result.failure("发起 mailbox 营销失败: %s" % mailbox.error)

	var billboard := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "marketer",
		"board_number": 11,
		"product": "burger",
		"duration": 1,
		"position": [1, 2],
	}))
	if not billboard.ok:
		return Result.failure("发起 billboard 营销失败: %s" % billboard.error)

	state = engine.get_state()
	var busy: Array = state.players[actor].get("busy_marketers", [])
	if not busy.has("campaign_manager") or not busy.has("marketer"):
		return Result.failure("营销员应进入忙碌区，实际: %s" % str(busy))
	if state.players[actor].get("employees", []).has("campaign_manager") or state.players[actor].get("employees", []).has("marketer"):
		return Result.failure("营销员不应仍留在在岗 employees")

	# 3) 进入 Marketing 阶段：结算需求并使持续时间 -1（duration=1 => 到期）
	state.phase = "Payday"
	state.sub_phase = ""
	var cash := StateUpdaterClass.player_receive_from_bank(state, actor, 20)
	if not cash.ok:
		return Result.failure("发放测试现金失败: %s" % cash.error)
	var adv := engine.phase_manager.advance_phase(state)
	if not adv.ok:
		return Result.failure("推进到 Marketing 失败: %s" % adv.error)

	state = engine.get_state()

	# 3.1 billboard：左侧房屋应新增 1 个 burger 需求
	houses = state.map.get("houses", {})
	var left: Dictionary = houses.get("house_left", {})
	var left_demands: Array = left.get("demands", [])
	if left_demands.size() != 1:
		return Result.failure("billboard 后左侧房屋需求应为 1，实际: %d" % left_demands.size())
	var d0: Dictionary = left_demands[0]
	if str(d0.get("product", "")) != "burger":
		return Result.failure("需求产品应为 burger，实际: %s" % str(d0.get("product", null)))
	if int(d0.get("from_player", -1)) != actor:
		return Result.failure("需求来源玩家不匹配: %s" % str(d0.get("from_player", null)))
	if int(d0.get("board_number", 0)) != 11:
		return Result.failure("需求 board_number 不匹配: %s" % str(d0.get("board_number", null)))
	if str(d0.get("type", "")) != "billboard":
		return Result.failure("需求 type 不匹配: %s" % str(d0.get("type", null)))

	# 3.2 mailbox：右侧房屋需求已满，不应继续增加；左侧不应被影响
	right = houses.get("house_right", {})
	var right_demands: Array = right.get("demands", [])
	var demand_cap_normal = state.get_rule_int("demand_cap_normal")
	if right_demands.size() != demand_cap_normal:
		return Result.failure("mailbox 后右侧房屋需求应保持上限 %d，实际: %d" % [demand_cap_normal, right_demands.size()])

	# 3.3 到期：营销实例与放置应被移除，员工从忙碌区释放回待命区
	if not state.marketing_instances.is_empty():
		return Result.failure("duration=1 的营销应到期移除，但仍存在: %s" % str(state.marketing_instances))

	var placements: Dictionary = state.map.get("marketing_placements", {})
	if not placements.is_empty():
		return Result.failure("到期后 marketing_placements 应为空，实际: %s" % str(placements))

	var reserve: Array = state.players[actor].get("reserve_employees", [])
	busy = state.players[actor].get("busy_marketers", [])
	if busy.has("marketer") or busy.has("campaign_manager"):
		return Result.failure("到期后不应仍忙碌，busy=%s" % str(busy))
	if not reserve.has("marketer") or not reserve.has("campaign_manager"):
		return Result.failure("到期后员工应回到 reserve_employees，实际: %s" % str(reserve))

	var marketing_round: Dictionary = state.round_state.get("marketing", {})
	if marketing_round.is_empty():
		return Result.failure("Marketing 阶段应写入 round_state.marketing")

	return Result.success({
		"actor": actor,
		"left_demands": left_demands.size(),
		"right_demands": right_demands.size(),
	})

static func _test_radio_and_airplane_ranges(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state, player_count)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var map_result := _build_range_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)
	state.players[actor]["restaurants"] = ["rest_0"]

	# 准备员工：
	# - brand_director：可放置 radio（在池中，按守恒取用）
	# - brand_manager：可放置 airplane（在池中，按守恒取用）
	if int(state.employee_pool.get("brand_director", 0)) <= 0:
		return Result.failure("员工池中没有 brand_director")
	state.employee_pool["brand_director"] = int(state.employee_pool.get("brand_director", 0)) - 1
	state.players[actor]["employees"].append("brand_director")

	if int(state.employee_pool.get("brand_manager", 0)) <= 0:
		return Result.failure("员工池中没有 brand_manager")
	state.employee_pool["brand_manager"] = int(state.employee_pool.get("brand_manager", 0)) - 1
	state.players[actor]["employees"].append("brand_manager")

	# 固定到 Working / Marketing 子阶段
	state.phase = "Working"
	state.sub_phase = "Marketing"

	# 1) Radio（board #1）：放在 tile(0,0)，应影响 2x2 tiles 区域内的房屋
	var radio := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "brand_director",
		"board_number": 1,
		"product": "soda",
		"duration": 1,
		"position": [2, 2],
	}))
	if not radio.ok:
		return Result.failure("发起 radio 营销失败: %s" % radio.error)

	# 2) Airplane（board #4）：放在左边缘，落在 tile row=2，应影响该行所有 tiles 内的房屋
	var airplane := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "brand_manager",
		"board_number": 4,
		"product": "beer",
		"duration": 1,
		"position": [0, 11],
	}))
	if not airplane.ok:
		return Result.failure("发起 airplane 营销失败: %s" % airplane.error)

	# 3) 进入 Marketing 阶段结算
	state = engine.get_state()
	state.phase = "Payday"
	state.sub_phase = ""
	var cash := StateUpdaterClass.player_receive_from_bank(state, actor, 20)
	if not cash.ok:
		return Result.failure("发放测试现金失败: %s" % cash.error)
	var adv := engine.phase_manager.advance_phase(state)
	if not adv.ok:
		return Result.failure("推进到 Marketing 失败: %s" % adv.error)

	state = engine.get_state()

	var houses: Dictionary = state.map.get("houses", {})

	# 里程碑：首个电波广告 -> radio 每次放 2 个需求标记（docs/rules.md）
	# radio 影响 tiles (0,0)-(1,1)：h00/h10/h01/h11 应新增 2 个 soda；hout 不应被影响
	for hid in ["h00", "h10", "h01", "h11"]:
		var h: Dictionary = houses.get(hid, {})
		var demands: Array = h.get("demands", [])
		if demands.size() != 2:
			return Result.failure("radio 后 %s 需求应为 2，实际: %d" % [hid, demands.size()])
		for d in demands:
			if str(d.get("product", "")) != "soda":
				return Result.failure("radio 后 %s 需求产品应为 soda，实际: %s" % [hid, str(d.get("product", null))])

	var hout: Dictionary = houses.get("hout", {})
	if Array(hout.get("demands", [])).size() != 0:
		return Result.failure("radio 不应影响 hout（tile 2,0），实际: %s" % str(hout.get("demands", [])))

	# airplane 影响 tile row=2：h20/h21/h22 应新增 beer；h00 不应被影响
	for hid in ["h20", "h21", "h22"]:
		var h: Dictionary = houses.get(hid, {})
		var demands: Array = h.get("demands", [])
		if demands.size() != 1:
			return Result.failure("airplane 后 %s 需求应为 1，实际: %d" % [hid, demands.size()])
		if str(demands[0].get("product", "")) != "beer":
			return Result.failure("airplane 后 %s 需求产品应为 beer，实际: %s" % [hid, str(demands[0].get("product", null))])

	var h00: Dictionary = houses.get("h00", {})
	if Array(h00.get("demands", [])).size() != 2:
		return Result.failure("h00 不应被 airplane 影响（仍应只有 radio 的 2 个需求）")

	return Result.success({
		"actor": actor,
	})

static func _test_first_billboard_permanent_and_no_salary(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state, player_count)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var map_result := _build_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)
	state.players[actor]["restaurants"] = ["rest_0"]

	# 准备员工（从池取卡，保持守恒）：
	# - marketer：发起 billboard（触发 first_billboard）
	# - campaign_manager：里程碑后发起 mailbox（应永久），且其薪资应被豁免
	if int(state.employee_pool.get("marketer", 0)) <= 0:
		return Result.failure("员工池中没有 marketer")
	state.employee_pool["marketer"] = int(state.employee_pool.get("marketer", 0)) - 1
	state.players[actor]["employees"].append("marketer")

	if int(state.employee_pool.get("campaign_manager", 0)) <= 0:
		return Result.failure("员工池中没有 campaign_manager")
	state.employee_pool["campaign_manager"] = int(state.employee_pool.get("campaign_manager", 0)) - 1
	state.players[actor]["employees"].append("campaign_manager")

	state.phase = "Working"
	state.sub_phase = "Marketing"

	var paid_before := EmployeeRulesClass.count_paid_employees(state.players[actor])
	if paid_before != 1:
		return Result.failure("获得 first_billboard 前应支付 1 名员工薪资（campaign_manager），实际: %d" % paid_before)

	var billboard := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "marketer",
		"board_number": 11,
		"product": "burger",
		"duration": 1,
		"position": [1, 2],
	}))
	if not billboard.ok:
		return Result.failure("发起 billboard 营销失败: %s" % billboard.error)

	state = engine.get_state()
	var milestones: Array = state.players[actor].get("milestones", [])
	if not milestones.has("first_billboard"):
		return Result.failure("应获得 first_billboard 里程碑，但未发现: %s" % str(milestones))

	var paid_after := EmployeeRulesClass.count_paid_employees(state.players[actor])
	if paid_after != 0:
		return Result.failure("获得 first_billboard 后 campaign_manager 应免薪，paid_employee_count 应为 0，实际: %d" % paid_after)

	# 里程碑后发起的营销应永久（remaining_duration=-1）
	var mailbox := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "campaign_manager",
		"board_number": 7,
		"product": "pizza",
		"duration": 1,
		"position": [3, 2],
	}))
	if not mailbox.ok:
		return Result.failure("发起 mailbox 营销失败: %s" % mailbox.error)

	state = engine.get_state()
	var found_permanent := false
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			return Result.failure("marketing_instances 元素类型错误（期望 Dictionary）")
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", 0)) != 7:
			continue
		if int(inst.get("remaining_duration", 0)) != -1:
			return Result.failure("first_billboard 后 mailbox 应为永久 remaining_duration=-1，实际: %s" % str(inst.get("remaining_duration", null)))
		found_permanent = true
	if not found_permanent:
		return Result.failure("未找到 board_number=7 的 mailbox 营销实例")

	var placements: Dictionary = state.map.get("marketing_placements", {})
	if not (placements is Dictionary) or not placements.has("7"):
		return Result.failure("marketing_placements 缺少 #7")
	var p7: Dictionary = placements.get("7", {})
	if int(p7.get("remaining_duration", 0)) != -1:
		return Result.failure("marketing_placements#7.remaining_duration 应为 -1，实际: %s" % str(p7.get("remaining_duration", null)))

	# 结算营销：billboard(duration=1) 应到期移除；mailbox(permanent) 不应到期
	var pm := PhaseManagerClass.new()
	pm.set_effect_registry(EffectRegistryClass.new())
	var settle := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if not settle.ok:
		return Result.failure("MarketingSettlement 失败: %s" % settle.error)

	if state.marketing_instances.size() != 1:
		return Result.failure("结算后应仅剩 1 个营销实例（mailbox permanent），实际: %d" % state.marketing_instances.size())
	var remain: Dictionary = state.marketing_instances[0]
	if int(remain.get("board_number", 0)) != 7:
		return Result.failure("结算后剩余营销实例应为 board_number=7，实际: %s" % str(remain.get("board_number", null)))
	if int(remain.get("remaining_duration", 0)) != -1:
		return Result.failure("结算后剩余营销实例 remaining_duration 应为 -1，实际: %s" % str(remain.get("remaining_duration", null)))

	placements = state.map.get("marketing_placements", {})
	if placements.size() != 1 or not placements.has("7"):
		return Result.failure("结算后 marketing_placements 应仅包含 #7，实际: %s" % str(placements.keys()))

	var busy: Array = state.players[actor].get("busy_marketers", [])
	var reserve: Array = state.players[actor].get("reserve_employees", [])
	if busy.has("marketer"):
		return Result.failure("billboard 到期后 marketer 不应仍忙碌，busy=%s" % str(busy))
	if not busy.has("campaign_manager"):
		return Result.failure("mailbox 永久后 campaign_manager 应保持忙碌，busy=%s" % str(busy))
	if not reserve.has("marketer"):
		return Result.failure("billboard 到期后 marketer 应回到 reserve_employees，reserve=%s" % str(reserve))
	if reserve.has("campaign_manager"):
		return Result.failure("mailbox 永久后 campaign_manager 不应回到 reserve_employees，reserve=%s" % str(reserve))

	return Result.success({
		"actor": actor,
		"paid_before": paid_before,
		"paid_after": paid_after,
	})

static func _test_effect_registry_first_radio_demand_amount(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state, player_count)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var map_result := _build_range_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)
	state.players[actor]["restaurants"] = ["rest_0"]

	# 准备员工：brand_director 可放置 radio（在池中，按守恒取用）
	if int(state.employee_pool.get("brand_director", 0)) <= 0:
		return Result.failure("员工池中没有 brand_director")
	state.employee_pool["brand_director"] = int(state.employee_pool.get("brand_director", 0)) - 1
	state.players[actor]["employees"].append("brand_director")

	# 固定到 Working / Marketing 子阶段
	state.phase = "Working"
	state.sub_phase = "Marketing"

	var radio := engine.execute_command(Command.create("initiate_marketing", actor, {
		"employee_type": "brand_director",
		"board_number": 1,
		"product": "soda",
		"duration": 1,
		"position": [2, 2],
	}))
	if not radio.ok:
		return Result.failure("发起 radio 营销失败: %s" % radio.error)

	state = engine.get_state()
	var milestones: Array = state.players[actor].get("milestones", [])
	if not milestones.has("first_radio"):
		return Result.failure("应获得 first_radio 里程碑，但未发现: %s" % str(milestones))

	var ms_def_val = MilestoneRegistryClass.get_def("first_radio")
	if ms_def_val == null:
		return Result.failure("无法获取 first_radio 里程碑定义")
	if not (ms_def_val is MilestoneDef):
		return Result.failure("first_radio 里程碑定义类型错误（期望 MilestoneDef）")
	var ms_def: MilestoneDef = ms_def_val
	if not ms_def.effect_ids.has("base_rules:marketing:demand_amount:first_radio"):
		return Result.failure("first_radio.effect_ids 缺少 base_rules:marketing:demand_amount:first_radio: %s" % str(ms_def.effect_ids))

	var effect_registry = EffectRegistryClass.new()
	var handler := FirstRadioDemandAmountHandler.new()
	var reg := effect_registry.register_effect(
		"base_rules:marketing:demand_amount:first_radio",
		Callable(handler, "apply"),
		"base_rules"
	)
	if not reg.ok:
		return Result.failure("注册测试 effect handler 失败: %s" % reg.error)

	var pm = PhaseManagerClass.new()
	pm.set_effect_registry(effect_registry)

	var settle := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if not settle.ok:
		return Result.failure("MarketingSettlement 失败: %s" % settle.error)

	var houses: Dictionary = state.map.get("houses", {})
	for hid in ["h00", "h10", "h01", "h11"]:
		var h: Dictionary = houses.get(hid, {})
		var demands: Array = h.get("demands", [])
		if demands.size() != 2:
			return Result.failure("EffectRegistry radio 后 %s 需求应为 2，实际: %d" % [hid, demands.size()])
		for d in demands:
			if str(d.get("product", "")) != "soda":
				return Result.failure("EffectRegistry radio 后 %s 需求产品应为 soda，实际: %s" % [hid, str(d.get("product", null))])

	var hout: Dictionary = houses.get("hout", {})
	if Array(hout.get("demands", [])).size() != 0:
		return Result.failure("EffectRegistry radio 不应影响 hout（tile 2,0），实际: %s" % str(hout.get("demands", [])))

	return Result.success({
		"actor": actor,
	})

static func _force_turn_order(state: GameState, player_count: int) -> void:
	state.turn_order.clear()
	for i in range(player_count):
		state.turn_order.append(i)
	state.current_player_index = 0

static func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false
			})
		cells.append(row)
	return cells

static func _set_road(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true
		}

static func _build_test_map(owner: int) -> Result:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	# 垂直道路（x=2），用于分割街区并提供邻路放置
	_set_road(cells, Vector2i(2, 0), ["S"])
	_set_road(cells, Vector2i(2, 1), ["N", "S"])
	_set_road(cells, Vector2i(2, 2), ["N", "S"])
	_set_road(cells, Vector2i(2, 3), ["N", "S"])
	_set_road(cells, Vector2i(2, 4), ["N"])

	# 左侧房屋（用于 billboard）
	var left_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	_set_house(cells, "house_left", 1, left_cells)

	# 右侧房屋（用于 mailbox）
	var right_cells: Array[Vector2i] = [
		Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(3, 1), Vector2i(4, 1),
	]
	_set_house(cells, "house_right", 2, right_cells)

	var houses := {
		"house_left": {
			"house_id": "house_left",
			"house_number": 1,
			"anchor_pos": Vector2i(0, 0),
			"cells": left_cells,
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		},
		"house_right": {
			"house_id": "house_right",
			"house_number": 2,
			"anchor_pos": Vector2i(3, 0),
			"cells": right_cells,
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		},
	}

	var restaurants := {
		"rest_0": {
			"restaurant_id": "rest_0",
			"owner": owner,
			"anchor_pos": Vector2i(0, 4),
			"entrance_pos": Vector2i(1, 4),
		}
	}

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": houses,
		"restaurants": restaurants,
		"drink_sources": [],
		"next_house_number": 3,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	})

static func _set_house_1x1(cells: Array, house_id: String, house_number: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "house",
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true
	}

static func _build_range_test_map(owner: int) -> Result:
	var grid_size := Vector2i(15, 15) # 3x3 tiles
	var tile_grid_size := Vector2i(3, 3)
	var cells := _build_empty_cells(grid_size)

	# 给 radio 营销提供邻路放置点：在 (2,3) 放一段道路，使 (2,2) 具备邻路条件
	_set_road(cells, Vector2i(2, 3), ["N", "S"])

	# 放置若干 1x1 房屋（用于验证 radio/airplane 的范围边界）
	_set_house_1x1(cells, "h00", 1, Vector2i(0, 0))   # tile (0,0)
	_set_house_1x1(cells, "h10", 2, Vector2i(5, 0))   # tile (1,0)
	_set_house_1x1(cells, "h01", 3, Vector2i(0, 5))   # tile (0,1)
	_set_house_1x1(cells, "h11", 4, Vector2i(5, 5))   # tile (1,1)
	_set_house_1x1(cells, "hout", 5, Vector2i(10, 0)) # tile (2,0) - radio 不应影响

	_set_house_1x1(cells, "h20", 6, Vector2i(0, 10))  # tile (0,2) - airplane row=2 影响
	_set_house_1x1(cells, "h21", 7, Vector2i(5, 10))  # tile (1,2) - airplane row=2 影响
	_set_house_1x1(cells, "h22", 8, Vector2i(10, 10)) # tile (2,2) - airplane row=2 影响

	var houses := {}
	var defs := [
		{"id": "h00", "n": 1, "pos": Vector2i(0, 0)},
		{"id": "h10", "n": 2, "pos": Vector2i(5, 0)},
		{"id": "h01", "n": 3, "pos": Vector2i(0, 5)},
		{"id": "h11", "n": 4, "pos": Vector2i(5, 5)},
		{"id": "hout", "n": 5, "pos": Vector2i(10, 0)},
		{"id": "h20", "n": 6, "pos": Vector2i(0, 10)},
		{"id": "h21", "n": 7, "pos": Vector2i(5, 10)},
		{"id": "h22", "n": 8, "pos": Vector2i(10, 10)},
	]
	for d in defs:
		var hid := str(d.get("id", ""))
		var pos: Vector2i = d.get("pos", Vector2i.ZERO)
		houses[hid] = {
			"house_id": hid,
			"house_number": int(d.get("n", 0)),
			"anchor_pos": pos,
			"cells": [pos],
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		}

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": tile_grid_size,
		"cells": cells,
		"houses": houses,
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": owner,
				"anchor_pos": Vector2i(7, 14),
				"entrance_pos": Vector2i(7, 14),
			}
		},
		"drink_sources": [],
		"next_house_number": 9,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	})

class FirstRadioDemandAmountHandler:
	extends RefCounted

	func apply(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
		if not ctx.has("marketing_type") or not (ctx["marketing_type"] is String):
			return Result.failure("FirstRadioDemandAmountHandler: ctx.marketing_type 缺失或类型错误（期望 String）")
		if not ctx.has("demand_amount") or not (ctx["demand_amount"] is int):
			return Result.failure("FirstRadioDemandAmountHandler: ctx.demand_amount 缺失或类型错误（期望 int）")

		var marketing_type: String = str(ctx["marketing_type"])
		if marketing_type != "radio":
			return Result.success()

		var current: int = int(ctx["demand_amount"])
		ctx["demand_amount"] = maxi(current, 2)
		return Result.success()
