# 模块12：乡村营销员（Rural Marketeers）
# - 巨型广告牌：4 槽位（N/E/S/W），每轮 Marketing 向 rural_area 添加 2 需求
# - Offramp：棋盘外放置（external_cells），与 airplane 同边互斥
class_name RuralMarketeersV2Test
extends RefCounted

const ModuleEntryClass = preload("res://modules/rural_marketeers/rules/entry.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_place_billboard_and_offramp(seed_val)
	if not r.ok:
		return r
	return Result.success()

static func _test_place_billboard_and_offramp(seed_val: int) -> Result:
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
		"rural_marketeers",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s: GameState = e.get_state()

	# 手动触发模块初始化（等价于 Restructuring BEFORE_ENTER）
	var entry = ModuleEntryClass.new()
	var init_r := entry._on_restructuring_before_enter(s)
	if not init_r.ok:
		return Result.failure("初始化 rural_area 失败: %s" % init_r.error)

	# 进入 Working/Marketing，并给予玩家 0 rural_marketeer
	_force_player0_ready_for_marketing(s)
	_take_to_active(s, 0, "rural_marketeer")

	# 放置巨型广告牌（side=N）
	var cmd1 := Command.create("place_giant_billboard", 0)
	cmd1.params = {
		"side": "N",
		"product": "burger",
	}
	var r1 := e.execute_command(cmd1)
	if not r1.ok:
		return Result.failure("放置巨型广告牌失败: %s" % r1.error)
	s = e.get_state()

	# 触发 Marketing 结算扩展：本轮应 +2 需求（且不受 cap 限制）
	var houses: Dictionary = s.map["houses"]
	var rural: Dictionary = houses["rural_area"]
	rural["demands"] = [
		{"product": "burger", "from_player": 0, "board_number": 0, "type": "x"},
		{"product": "burger", "from_player": 0, "board_number": 0, "type": "x"},
		{"product": "burger", "from_player": 0, "board_number": 0, "type": "x"},
	]
	houses["rural_area"] = rural
	s.map["houses"] = houses
	var r2 := entry._on_marketing_enter_extension(s, e.phase_manager)
	if not r2.ok:
		return Result.failure("Marketing 扩展失败: %s" % r2.error)
	houses = s.map["houses"]
	rural = houses["rural_area"]
	var demands: Array = rural["demands"]
	if demands.size() != 5:
		return Result.failure("rural_area.demands 应追加 2 条（cap 不生效），实际: %d" % demands.size())

	# 由于 milestone effect，玩家 0 应有 offramp pending
	if not s.round_state.has("rural_marketeers_offramp_pending") or not (s.round_state["rural_marketeers_offramp_pending"] is Dictionary):
		return Result.failure("缺少 round_state.rural_marketeers_offramp_pending")
	var pending: Dictionary = s.round_state["rural_marketeers_offramp_pending"]
	if not (pending.get(0, false) is bool) or not bool(pending.get(0, false)):
		return Result.failure("玩家 0 应有 offramp pending")

	# 伪造棋盘边缘道路，使 offramp 放置满足“连接到道路”
	_ensure_north_edge_has_outward_road(s, 0)

	var cmd2 := Command.create("place_highway_offramp", 0)
	cmd2.params = {
		"position": [0, 0],
	}
	var r3 := e.execute_command(cmd2)
	if not r3.ok:
		return Result.failure("放置 offramp 失败: %s" % r3.error)
	s = e.get_state()

	# 再尝试在同一边放置 airplane，应被模块 validator 拒绝
	var cmd3 := Command.create("initiate_marketing", 0)
	cmd3.params = {
		"employee_type": "brand_director",
		"board_number": 4,
		"product": "burger",
		"position": [0, 0],
		"duration": 1,
	}
	var r4 := e.execute_command(cmd3)
	if r4.ok:
		return Result.failure("同边已存在 offramp 时 airplane 应被拒绝")

	return Result.success()

static func _force_player0_ready_for_marketing(state: GameState) -> void:
	state.phase = "Working"
	state.sub_phase = "Marketing"
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["sub_phase_passed"] = {0: false, 1: false}

static func _take_to_active(state: GameState, player_id: int, employee_id: String) -> void:
	if not state.employee_pool.has(employee_id):
		state.employee_pool[employee_id] = 0
	state.employee_pool[employee_id] = int(state.employee_pool.get(employee_id, 0)) - 1
	state.players[player_id]["employees"].append(employee_id)

static func _ensure_north_edge_has_outward_road(state: GameState, tile_index: int) -> void:
	var grid_size: Vector2i = state.map["grid_size"]
	var x := tile_index * 5
	if x < 0 or x >= grid_size.x:
		return
	var cell: Dictionary = state.map["cells"][0][x]
	var segs: Array = cell.get("road_segments", [])
	segs.append({"dirs": ["N", "S"], "bridge": false})
	cell["road_segments"] = segs
	state.map["cells"][0][x] = cell
