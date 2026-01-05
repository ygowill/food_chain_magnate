extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

const PlaceGiantBillboardActionClass = preload("res://modules/rural_marketeers/actions/place_giant_billboard_action.gd")
const PlaceHighwayOfframpActionClass = preload("res://modules/rural_marketeers/actions/place_highway_offramp_action.gd")

const Phase = PhaseDefsClass.Phase
const WorkingSubPhase = PhaseDefsClass.WorkingSubPhase
const HookType = PhaseManagerClass.HookType

const MODULE_ID := "rural_marketeers"
const RURAL_HOUSE_ID := "rural_area"
const RURAL_HOUSE_NUMBER := "zzzz_rural_area"
const OFFRAMP_SUPPLY_TOTAL := 3
const OFFRAMP_PENDING_KEY := "rural_marketeers_offramp_pending"
const OFFRAMP_SUPPLY_KEY := "rural_marketeers_offramp_supply_remaining"

const BILLBOARD_SIDES: Array[String] = ["N", "E", "S", "W"]
const BILLBOARD_BOARD_NUMBER_BY_SIDE := {
	"N": 5000,
	"E": 5001,
	"S": 5002,
	"W": 5003,
}

func register(registrar) -> Result:
	var r = registrar.register_employee_patch("marketer", {"add_train_to": ["rural_marketeer"]})
	if not r.ok:
		return r

	r = registrar.register_milestone_effect("rural_marketeers:grant_offramp_placement", Callable(self, "_milestone_effect_grant_offramp_placement"))
	if not r.ok:
		return r

	# 初始化：确保 rural_area 与 offramp supply 存在
	r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"), 0)
	if not r.ok:
		return r

	# 乡村地区需求：在 Marketing 阶段按轮次添加（巨型广告牌每轮 +2）
	r = registrar.register_extension_settlement(Phase.MARKETING, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_marketing_enter_extension"), 200)
	if not r.ok:
		return r

	# 晚餐前：将 rural_area 的“入口 road cells”更新为当前 offramp 的入口道路
	r = registrar.register_extension_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_dinnertime_enter_before_primary"), 0)
	if not r.ok:
		return r

	# 必须立即放置 offramp（不允许带着 pending 离开 Marketing 子阶段）
	r = registrar.register_sub_phase_hook(WorkingSubPhase.MARKETING, HookType.BEFORE_EXIT, Callable(self, "_on_working_marketing_before_exit"), 0)
	if not r.ok:
		return r

	# 模块动作
	r = registrar.register_action_executor(PlaceGiantBillboardActionClass.new())
	if not r.ok:
		return r
	r = registrar.register_action_executor(PlaceHighwayOfframpActionClass.new())
	if not r.ok:
		return r

	# 飞机与 offramp 互斥（仅在启用本模块时生效）
	r = registrar.register_action_validator("initiate_marketing", "%s:airplane_offramp_conflict" % MODULE_ID, Callable(self, "_validate_airplane_offramp_conflict"), 10)
	if not r.ok:
		return r

	return Result.success()

func _on_restructuring_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("%s: state.map.houses 缺失或类型错误（期望 Dictionary）" % MODULE_ID)
	var houses: Dictionary = state.map["houses"]

	if not houses.has(RURAL_HOUSE_ID):
		houses[RURAL_HOUSE_ID] = {
			"house_id": RURAL_HOUSE_ID,
			"house_number": RURAL_HOUSE_NUMBER,
			"has_garden": false,
			"no_demand_cap": true,
			"cells": [],
			"demands": [],
			"giant_billboards": {},
		}
	else:
		var h_val = houses[RURAL_HOUSE_ID]
		if not (h_val is Dictionary):
			return Result.failure("%s: houses[%s] 类型错误（期望 Dictionary）" % [MODULE_ID, RURAL_HOUSE_ID])
		var house: Dictionary = h_val
		house["house_id"] = RURAL_HOUSE_ID
		house["house_number"] = RURAL_HOUSE_NUMBER
		house["no_demand_cap"] = true
		if not house.has("has_garden"):
			house["has_garden"] = false
		if not house.has("cells"):
			house["cells"] = []
		if not house.has("demands"):
			house["demands"] = []
		if not house.has("giant_billboards"):
			house["giant_billboards"] = {}
		houses[RURAL_HOUSE_ID] = house

	state.map["houses"] = houses

	if not state.map.has(OFFRAMP_SUPPLY_KEY):
		state.map[OFFRAMP_SUPPLY_KEY] = OFFRAMP_SUPPLY_TOTAL
	else:
		var v = state.map.get(OFFRAMP_SUPPLY_KEY, null)
		if not (v is int):
			return Result.failure("%s: state.map.%s 类型错误（期望 int）" % [MODULE_ID, OFFRAMP_SUPPLY_KEY])
		if int(v) < 0:
			return Result.failure("%s: state.map.%s 不能为负数: %d" % [MODULE_ID, OFFRAMP_SUPPLY_KEY, int(v)])

	return Result.success()

func _on_marketing_enter_extension(state: GameState, phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("%s: state.map.houses 缺失或类型错误（期望 Dictionary）" % MODULE_ID)
	var houses: Dictionary = state.map["houses"]
	if not houses.has(RURAL_HOUSE_ID) or not (houses[RURAL_HOUSE_ID] is Dictionary):
		return Result.failure("%s: 缺少 rural_area（模块未正确初始化）" % MODULE_ID)
	var rural: Dictionary = houses[RURAL_HOUSE_ID]

	if not rural.has("demands") or not (rural["demands"] is Array):
		return Result.failure("%s: rural_area.demands 缺失或类型错误（期望 Array）" % MODULE_ID)
	var demands: Array = rural["demands"]

	var boards_val = rural.get("giant_billboards", null)
	if boards_val == null:
		return Result.success()
	if not (boards_val is Dictionary):
		return Result.failure("%s: rural_area.giant_billboards 类型错误（期望 Dictionary）" % MODULE_ID)
	var boards: Dictionary = boards_val
	if boards.is_empty():
		return Result.success()

	var rounds := 1
	if phase_manager != null and phase_manager.has_method("get_marketing_rounds"):
		var mr = phase_manager.get_marketing_rounds(state)
		if mr is Result:
			var rr: Result = mr
			if not rr.ok:
				return rr
			rounds = int(rr.value)
	if rounds <= 0:
		return Result.failure("%s: marketing_rounds 非法: %d" % [MODULE_ID, rounds])

	var total_added := 0
	for side in BILLBOARD_SIDES:
		if not boards.has(side):
			continue
		var b_val = boards[side]
		if not (b_val is Dictionary):
			return Result.failure("%s: rural_area.giant_billboards[%s] 类型错误（期望 Dictionary）" % [MODULE_ID, side])
		var b: Dictionary = b_val
		var product_val = b.get("product", null)
		if not (product_val is String):
			return Result.failure("%s: giant_billboards[%s].product 类型错误（期望 String）" % [MODULE_ID, side])
		var product: String = str(product_val)
		if product.is_empty():
			return Result.failure("%s: giant_billboards[%s].product 不能为空" % [MODULE_ID, side])
		if not ProductRegistryClass.has(product):
			return Result.failure("%s: giant_billboards[%s].product 未知: %s" % [MODULE_ID, side, product])

		var owner_val = b.get("owner", null)
		if not (owner_val is int):
			return Result.failure("%s: giant_billboards[%s].owner 类型错误（期望 int）" % [MODULE_ID, side])
		var owner: int = int(owner_val)

		var board_number_val = b.get("board_number", null)
		if not (board_number_val is int):
			return Result.failure("%s: giant_billboards[%s].board_number 类型错误（期望 int）" % [MODULE_ID, side])
		var board_number: int = int(board_number_val)

		for _i in range(rounds * 2):
			demands.append({
				"product": product,
				"from_player": owner,
				"board_number": board_number,
				"type": "giant_billboard"
			})
			total_added += 1

	rural["demands"] = demands
	houses[RURAL_HOUSE_ID] = rural
	state.map["houses"] = houses

	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has("rural_marketeers"):
		state.round_state["rural_marketeers"] = {}
	var rs_val = state.round_state["rural_marketeers"]
	if not (rs_val is Dictionary):
		return Result.failure("%s: round_state.rural_marketeers 类型错误（期望 Dictionary）" % MODULE_ID)
	var rs: Dictionary = rs_val
	rs["demands_added"] = int(rs.get("demands_added", 0)) + total_added
	state.round_state["rural_marketeers"] = rs

	return Result.success()

func _on_dinnertime_enter_before_primary(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("%s: state.map.houses 缺失或类型错误（期望 Dictionary）" % MODULE_ID)
	var houses: Dictionary = state.map["houses"]
	if not houses.has(RURAL_HOUSE_ID) or not (houses[RURAL_HOUSE_ID] is Dictionary):
		return Result.failure("%s: 缺少 rural_area（模块未正确初始化）" % MODULE_ID)
	var rural: Dictionary = houses[RURAL_HOUSE_ID]

	var entry_cells_read := PlaceHighwayOfframpActionClass.get_offramp_connection_cells(state)
	if not entry_cells_read.ok:
		return entry_cells_read
	var entry_cells_any: Array = entry_cells_read.value
	var entry_cells: Array[Vector2i] = []
	for i in range(entry_cells_any.size()):
		var p = entry_cells_any[i]
		if not (p is Vector2i):
			return Result.failure("%s: offramp_entry_cells[%d] 类型错误（期望 Vector2i）" % [MODULE_ID, i])
		entry_cells.append(p)

	rural["cells"] = entry_cells
	houses[RURAL_HOUSE_ID] = rural
	state.map["houses"] = houses
	return Result.success()

func _on_working_marketing_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has(OFFRAMP_PENDING_KEY):
		return Result.success()
	var pending_val = state.round_state[OFFRAMP_PENDING_KEY]
	if not (pending_val is Dictionary):
		return Result.failure("%s: round_state.%s 类型错误（期望 Dictionary）" % [MODULE_ID, OFFRAMP_PENDING_KEY])
	var pending: Dictionary = pending_val

	var blockers: Array[int] = []
	for pid in pending.keys():
		if not (pid is int):
			continue
		var v = pending.get(pid, false)
		if v is bool and bool(v):
			blockers.append(int(pid))
	if blockers.is_empty():
		return Result.success()

	blockers.sort()
	return Result.failure("必须先放置高速公路出口（offramp），否则不能离开 Marketing 子阶段: %s" % str(blockers))

func _milestone_effect_grant_offramp_placement(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)

	if not state.map.has(OFFRAMP_SUPPLY_KEY) or not (state.map[OFFRAMP_SUPPLY_KEY] is int):
		return Result.failure("%s: state.map.%s 缺失或类型错误（期望 int）" % [MODULE_ID, OFFRAMP_SUPPLY_KEY])
	var remaining: int = int(state.map[OFFRAMP_SUPPLY_KEY])
	if remaining <= 0:
		return Result.success().with_warning("高速公路出口已耗尽，无法放置 offramp")

	state.map[OFFRAMP_SUPPLY_KEY] = remaining - 1

	if not state.round_state.has(OFFRAMP_PENDING_KEY):
		state.round_state[OFFRAMP_PENDING_KEY] = {}
	var pending_val = state.round_state[OFFRAMP_PENDING_KEY]
	if not (pending_val is Dictionary):
		return Result.failure("%s: round_state.%s 类型错误（期望 Dictionary）" % [MODULE_ID, OFFRAMP_PENDING_KEY])
	var pending: Dictionary = pending_val
	pending[player_id] = true
	state.round_state[OFFRAMP_PENDING_KEY] = pending

	return Result.success()

func _validate_airplane_offramp_conflict(state: GameState, command: Command) -> Result:
	# 仅对 airplane 生效：同一边缘格子不能与 offramp 冲突。
	if state == null or command == null:
		return Result.success()
	if not (state.map is Dictionary):
		return Result.success()

	if not (command.params is Dictionary):
		return Result.success()
	if not command.params.has("board_number"):
		return Result.success()
	var board_number_read := _parse_int_value(command.params.get("board_number", null), "board_number")
	if not board_number_read.ok:
		return board_number_read
	var board_number: int = int(board_number_read.value)
	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.success()
	var t: String = str(def.type)
	if t != "airplane":
		return Result.success()

	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("%s: state.map.grid_size 缺失或类型错误" % MODULE_ID)
	var grid_size: Vector2i = state.map["grid_size"]
	if not state.map.has("tile_grid_size") or not (state.map["tile_grid_size"] is Vector2i):
		return Result.failure("%s: state.map.tile_grid_size 缺失或类型错误" % MODULE_ID)
	var tile_grid_size: Vector2i = state.map["tile_grid_size"]

	if not command.params.has("position"):
		return Result.success()
	var pos_val = command.params.get("position", null)
	if not (pos_val is Array) or (pos_val as Array).size() != 2:
		return Result.failure("%s: initiate_marketing.position 格式错误（期望 [x,y]）" % MODULE_ID)
	var arr: Array = pos_val
	var x_read := _parse_int_value(arr[0], "position[0]")
	if not x_read.ok:
		return x_read
	var y_read := _parse_int_value(arr[1], "position[1]")
	if not y_read.ok:
		return y_read
	var world_pos := Vector2i(int(x_read.value), int(y_read.value))
	if PlaceHighwayOfframpActionClass.has_offramp_at_pos(state, world_pos):
		return Result.failure("飞机不能放置在已有高速公路出口的格子: %s" % str(world_pos))

	return Result.success()

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)
