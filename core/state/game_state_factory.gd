# GameState 初始状态构建（Fail Fast）
# 负责：从 GameConfig + RandomManager 构建“新游戏”的初始 GameState。
class_name GameStateFactory
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const PoolBuilderClass = preload("res://core/modules/v2/pool_builder.gd")
const GameConstantsClass = preload("res://core/engine/game_constants.gd")

static func apply_initial_state(
	state,
	player_count: int,
	rng_seed: int,
	rng_manager,
	config
) -> Result:
	if player_count < GameConstantsClass.MIN_PLAYERS or player_count > GameConstantsClass.MAX_PLAYERS:
		return Result.failure("玩家数量超出范围: %d" % player_count)
	if rng_manager == null or not rng_manager.has_method("shuffle"):
		return Result.failure("必须提供可用的 RandomManager（用于确定性初始化 turn_order）")
	if config == null:
		return Result.failure("必须提供 GameConfig（禁止使用硬编码默认值）")

	var cfg = config

	state.seed = rng_seed
	state.round_number = 0
	state.phase = "Setup"
	state.sub_phase = ""
	state.current_player_index = 0
	state.selection_order.clear()

	state.bank = {
		"total": player_count * int(cfg.bank_default_per_player),
		"broke_count": 0,
		"ceo_slots_after_first_break": -1,
		"reserve_added_total": 0,
		"removed_total": 0
	}

	state.rules = {
		"base_unit_price": int(cfg.rule_base_unit_price),
		"salary_cost": int(cfg.rule_salary_cost),
		"waitress_tips": int(cfg.rule_waitress_tips),
		"cfo_bonus_percent": int(cfg.rule_cfo_bonus_percent),
		"demand_cap_normal": int(cfg.rule_demand_cap_normal),
		"demand_cap_with_garden": int(cfg.rule_demand_cap_with_garden),
		"fridge_capacity_per_product": int(cfg.rule_fridge_capacity_per_product),
	}
	var one_x_map: Dictionary = cfg.rule_one_x_employee_copies_by_player_count
	var pc_key := str(player_count)
	if not one_x_map.has(pc_key):
		return Result.failure("GameConfig.rules.one_x_employee_copies_by_player_count 缺少 key: %s" % pc_key)
	var one_x_val = one_x_map.get(pc_key, null)
	if not (one_x_val is int):
		return Result.failure("GameConfig.rules.one_x_employee_copies_by_player_count.%s 类型错误（期望 int）" % pc_key)
	state.rules["one_x_employee_copies"] = int(one_x_val)

	state.players.clear()
	for i in range(player_count):
		state.players.append(_create_player_from_config(i, cfg))

	state.turn_order.clear()
	for i in range(player_count):
		state.turn_order.append(i)
	rng_manager.shuffle(state.turn_order)
	# 规则：初始餐厅放置从“顺序轨最后一位”开始逆序进行。
	state.current_player_index = state.turn_order.size() - 1

	var employees: Dictionary = {}
	for emp_id in EmployeeRegistryClass.get_all_ids():
		var def = EmployeeRegistryClass.get_def(emp_id)
		if def == null:
			return Result.failure("初始 Pools 构建失败：未知员工定义: %s" % emp_id)
		employees[emp_id] = def

	var employee_pool_read := PoolBuilderClass.build_employee_pool(player_count, state.rules, employees)
	if not employee_pool_read.ok:
		return Result.failure("构建 employee_pool 失败: %s" % employee_pool_read.error)
	state.employee_pool = employee_pool_read.value

	var milestones: Dictionary = {}
	for mid in MilestoneRegistryClass.get_all_ids():
		var def = MilestoneRegistryClass.get_def(mid)
		if def == null:
			return Result.failure("初始 Pools 构建失败：未知里程碑定义: %s" % mid)
		milestones[mid] = def

	var milestone_pool_read := PoolBuilderClass.build_milestone_pool(milestones)
	if not milestone_pool_read.ok:
		return Result.failure("构建 milestone_pool 失败: %s" % milestone_pool_read.error)
	state.milestone_pool = milestone_pool_read.value

	# MapRuntime 会在 GameEngine.initialize 时写入 baked map；这里只确保类型正确并清除运行时缓存。
	state.map = {}
	state._road_graph = null
	
	state.round_state = {
		"mandatory_actions_completed": {},
		"actions_this_round": [],
		"action_counts": {},
		"sub_phase_passed": {}
	}
	for i in range(player_count):
		state.round_state.mandatory_actions_completed[i] = []
		state.round_state.sub_phase_passed[i] = false

	state.marketing_instances.clear()

	return Result.success(state)

static func _create_player_from_config(id: int, cfg) -> Dictionary:
	var employees: Array = []
	employees.append_array(Array(cfg.player_starting_employees))

	# 起始库存：以 ProductDef.starting_inventory 为基础，再叠加 GameConfig.player_starting_inventory 的显式覆盖。
	var inventory: Dictionary = {}
	if ProductRegistryClass.is_loaded():
		for pid in ProductRegistryClass.get_all_ids():
			var def = ProductRegistryClass.get_def(pid)
			var v := 0
			if def != null and def.has_method("starting_inventory"):
				v = int(def.starting_inventory)
			inventory[pid] = v

	for k in cfg.player_starting_inventory.keys():
		var key: String = str(k)
		inventory[key] = int(cfg.player_starting_inventory.get(k, 0))

	return {
		"id": id,
		"cash": int(cfg.player_starting_cash),
		"employees": employees,
		"reserve_employees": [],
		"busy_marketers": [],
		"banned_employee_ids": [],
		"can_peek_all_reserve_cards": false,
		"multi_trainer_on_one": false,
		"ceo_cfo_ability_start_round": -1,
		"reserve_cards": cfg.build_reserve_cards(),
		"reserve_card_selected": int(cfg.player_reserve_card_selected),
		"reserve_card_revealed": false,
		"inventory": inventory,
		"restaurants": [],
		"milestones": [],
		"drive_thru_active": false,
		"company_structure": cfg.player_starting_company_structure.duplicate(true)
	}
