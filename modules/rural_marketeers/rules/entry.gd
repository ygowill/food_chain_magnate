extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const ParseHelpers = preload("res://core/state/serialization/parse_helpers.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const RoundStatePlayerBoolFlagsClass = preload("res://core/utils/round_state_player_bool_flags.gd")

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

const PLACEMENT_CONFLICT_PROVIDER_ID := "%s:placement_conflicts" % MODULE_ID
const CONFLICT_ID_OFFRAMP_CONNECTION := "%s:offramp_connection" % MODULE_ID
const STATE_SCHEMA_ID_OFFRAMP_PENDING := "rural_marketeers:round_state_int_keys:rural_marketeers_offramp_pending"

func register(registrar) -> Result:
	var steps: Array[Callable] = [
		Callable(registrar, "register_employee_patch").bind("marketing_trainee", {"add_train_to": ["rural_marketeer"]}),
		Callable(registrar, "register_milestone_effect").bind("rural_marketeers:grant_offramp_placement", Callable(self, "_milestone_effect_grant_offramp_placement")),
		Callable(registrar, "register_milestone_effect_ui_text").bind("rural_marketeers:grant_offramp_placement", "获得一次高速出口（offramp）放置机会（需本回合放置）", 100),
		# 初始化：确保 rural_area 与 offramp supply 存在
		Callable(registrar, "register_phase_hook").bind(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"), 0),
		# 乡村地区需求：在 Marketing 阶段按轮次添加（巨型广告牌每轮 +2）
		Callable(registrar, "register_extension_settlement").bind(Phase.MARKETING, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_marketing_enter_extension"), 200),
		# 晚餐前：将 rural_area 的“入口 road cells”更新为当前 offramp 的入口道路
		Callable(registrar, "register_extension_settlement").bind(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_dinnertime_enter_before_primary"), 0),
		# 必须立即放置 offramp（不允许带着 pending 离开 Marketing 子阶段）
		Callable(registrar, "register_sub_phase_hook").bind(WorkingSubPhase.MARKETING, HookType.BEFORE_EXIT, Callable(self, "_on_working_marketing_before_exit"), 0),
		# 模块动作
		Callable(registrar, "register_action_executor").bind(PlaceGiantBillboardActionClass.new()),
		Callable(registrar, "register_action_executor").bind(PlaceHighwayOfframpActionClass.new()),
		# UI：地图渲染提示（避免 core UI 写死 piece_id 分支）。
		Callable(registrar, "register_piece_ui_hint").bind(
			"highway_offramp",
			{
				"structure_style": "opaque_rotated_piece",
				"rotation_offset_deg": 270,
				"bg_color": Color("#4c8078"),
				"blocks_roads_under": true,
			},
			100
		),
		# 飞机与 offramp 互斥（仅在启用本模块时生效）
		Callable(registrar, "register_action_validator").bind("initiate_marketing", "%s:airplane_offramp_conflict" % MODULE_ID, Callable(self, "_validate_airplane_offramp_conflict"), 10),
		# 对外暴露“占用/冲突查询”：其他模块不应直接读取本模块的 state.map 字段结构。
		Callable(registrar, "register_placement_conflict_provider").bind(PLACEMENT_CONFLICT_PROVIDER_ID, Callable(self, "_get_placement_conflicts_at_world_pos"), 100),
		# round_state.<player_id(int) -> ...> 字典：读档后需要把 "0"/"1" 转回 0/1
		Callable(registrar, "register_round_state_int_key_dict_schema").bind(STATE_SCHEMA_ID_OFFRAMP_PENDING, [OFFRAMP_PENDING_KEY], 100),
	]
	for step in steps:
		var r: Result = step.call()
		if not r.ok:
			return r
	return Result.success()

func _get_placement_conflicts_at_world_pos(state: GameState, world_pos: Vector2i, _ctx: Dictionary) -> Result:
	var offramps_read := MapStateAccessClass.require_optional_array_field_or_empty(
		state,
		"rural_marketeers_offramps",
		"%s: placement_conflicts" % MODULE_ID
	)
	if not offramps_read.ok:
		return offramps_read
	var offramps: Array = offramps_read.value
	for i in range(offramps.size()):
		var o_val = offramps[i]
		if not (o_val is Dictionary):
			return Result.failure("%s: placement_conflicts: offramps[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, i])
		var o: Dictionary = o_val
		var p = o.get("pos", null)
		if not (p is Vector2i):
			return Result.failure("%s: placement_conflicts: offramps[%d].pos 类型错误（期望 Vector2i）" % [MODULE_ID, i])
		if p == world_pos:
			return Result.success([CONFLICT_ID_OFFRAMP_CONNECTION])

	return Result.success([])

func _on_restructuring_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	var houses_read := MapStateAccessClass.require_houses(state, MODULE_ID)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value

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

	var supply_read := MapStateAccessClass.require_optional_int_field_or_default(
		state,
		OFFRAMP_SUPPLY_KEY,
		OFFRAMP_SUPPLY_TOTAL,
		MODULE_ID
	)
	if not supply_read.ok:
		return supply_read
	var supply_remaining: int = int(supply_read.value)
	if supply_remaining < 0:
		return Result.failure("%s: state.map.%s 不能为负数: %d" % [MODULE_ID, OFFRAMP_SUPPLY_KEY, supply_remaining])
	state.map[OFFRAMP_SUPPLY_KEY] = supply_remaining

	return Result.success()

func _on_marketing_enter_extension(state: GameState, phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	var houses_read := MapStateAccessClass.require_houses(state, MODULE_ID)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
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

	var warnings: Array[String] = []
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
		var product_read := MarketingRulesClass.require_marketable_product(product)
		if not product_read.ok:
			return Result.failure("%s: giant_billboards[%s].product 非法: %s" % [MODULE_ID, side, product_read.error])

		var owner_val = b.get("owner", null)
		if not (owner_val is int):
			return Result.failure("%s: giant_billboards[%s].owner 类型错误（期望 int）" % [MODULE_ID, side])
		var owner: int = int(owner_val)

		var board_number_val = b.get("board_number", null)
		if not (board_number_val is int):
			return Result.failure("%s: giant_billboards[%s].board_number 类型错误（期望 int）" % [MODULE_ID, side])
		var board_number: int = int(board_number_val)

		for _round_index in range(rounds):
			# 每轮 Marketing：每个巨型广告牌对同一商品进行两次营销。
			for _i in range(2):
				demands.append({
					"product": product,
					"from_player": owner,
					"board_number": board_number,
					"type": "giant_billboard"
				})
				total_added += 1

			# 里程碑联动：对齐 core/rules/phase/marketing_settlement.gd 的 DemandMarked 语义。
			var ms := MilestoneSystemClass.process_event(state, "DemandMarked", {
				"player_id": owner,
				"product": product,
			})
			if not ms.ok:
				warnings.append("里程碑触发失败(DemandMarked)：%s" % ms.error)

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

	var result := Result.success()
	if not warnings.is_empty():
		result.with_warnings(warnings)
	return result

func _on_dinnertime_enter_before_primary(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	var houses_read := MapStateAccessClass.require_houses(state, MODULE_ID)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
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
	var pending_players_read := RoundStatePlayerBoolFlagsClass.list_true_players(
		state.round_state,
		[OFFRAMP_PENDING_KEY],
		state.players.size(),
		MODULE_ID
	)
	if not pending_players_read.ok:
		return pending_players_read
	var blockers: Array = pending_players_read.value
	if blockers.is_empty():
		return Result.success()

	return Result.failure("必须先放置高速公路出口（offramp），否则不能离开 Marketing 子阶段: %s" % str(blockers))

func _milestone_effect_grant_offramp_placement(state: GameState, player_id: int, _milestone_id: String, _effect: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)

	var supply_read := MapStateAccessClass.require_int_field(state, OFFRAMP_SUPPLY_KEY, MODULE_ID)
	if not supply_read.ok:
		return supply_read
	var remaining: int = int(supply_read.value)
	if remaining <= 0:
		return Result.success().with_warning("高速公路出口已耗尽，无法放置 offramp")

	state.map[OFFRAMP_SUPPLY_KEY] = remaining - 1

	var mark_pending := RoundStatePlayerBoolFlagsClass.set_player_flag(
		state.round_state,
		[OFFRAMP_PENDING_KEY],
		player_id,
		true,
		MODULE_ID
	)
	if not mark_pending.ok:
		return mark_pending

	return Result.success()

func _validate_airplane_offramp_conflict(state: GameState, command: Command) -> Result:
	# 仅对 airplane 生效：不能与 offramp 的连接格在同一边的占用段重叠（segment overlap）。
	if state == null or command == null:
		return Result.success()
	if not (state.map is Dictionary):
		return Result.success()

	if not (command.params is Dictionary):
		return Result.success()
	if not command.params.has("board_number"):
		return Result.success()
	var board_number_read := ParseHelpers.parse_int(command.params.get("board_number", null), "board_number")
	if not board_number_read.ok:
		return board_number_read
	var board_number: int = int(board_number_read.value)
	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.success()
	var t: String = str(def.type)
	if t != "airplane":
		return Result.success()

	var grid_size_read := MapStateAccessClass.require_grid_size(state, MODULE_ID)
	if not grid_size_read.ok:
		return grid_size_read
	var tile_grid_size_read := MapStateAccessClass.require_tile_grid_size(state, MODULE_ID)
	if not tile_grid_size_read.ok:
		return tile_grid_size_read

	if not command.params.has("position"):
		return Result.success()
	var pos_val = command.params.get("position", null)
	if not (pos_val is Array) or (pos_val as Array).size() != 2:
		return Result.failure("%s: initiate_marketing.position 格式错误（期望 [x,y]）" % MODULE_ID)
	var arr: Array = pos_val
	var x_read := ParseHelpers.parse_int(arr[0], "position[0]")
	if not x_read.ok:
		return x_read
	var y_read := ParseHelpers.parse_int(arr[1], "position[1]")
	if not y_read.ok:
		return y_read
	var world_pos := Vector2i(int(x_read.value), int(y_read.value))

	# Determine airplane axis & segment range.
	var footprint_size := Vector2i.ONE
	if def is MarketingDef:
		footprint_size = (def as MarketingDef).footprint_size
	elif def != null and def.has_method("get"):
		var fs = def.get("footprint_size")
		if fs is Vector2i:
			footprint_size = fs

	var axis := ""
	if command.params.has("axis"):
		axis = str(command.params.get("axis", "")).strip_edges()
	if axis != "row" and axis != "col":
		axis = _infer_airplane_axis_for_overlap(state, world_pos, footprint_size)
	if axis != "row" and axis != "col":
		# Let core validation fail for missing/invalid axis.
		return Result.success()

	var seg_read := PlaceHighwayOfframpActionClass.compute_airplane_segment(state, world_pos, footprint_size, axis)
	if not seg_read.ok:
		return seg_read
	var seg: Dictionary = seg_read.value
	var seg_side := str(seg.get("side", "")).strip_edges()
	if seg_side.is_empty():
		return Result.success()
	var start := int(seg.get("start", 0))
	var end := int(seg.get("end", -1))

	# Check overlap against existing offramps.
	var offramps_read := MapStateAccessClass.require_optional_array_field_or_empty(state, "rural_marketeers_offramps", MODULE_ID)
	if not offramps_read.ok:
		return offramps_read
	var offramps: Array = offramps_read.value
	for i in range(offramps.size()):
		var o_val = offramps[i]
		if not (o_val is Dictionary):
			continue
		var o: Dictionary = o_val
		var off_pos_val = o.get("pos", null)
		if not (off_pos_val is Vector2i):
			continue
		var pos: Vector2i = off_pos_val
		var off_side := str(o.get("side", "")).strip_edges()
		if off_side.is_empty():
			off_side = _infer_edge_side(state, pos)
		if off_side != seg_side:
			continue
		var coord := pos.x if (seg_side == "N" or seg_side == "S") else pos.y
		if coord >= start and coord <= end:
			return Result.failure("飞机不能与已有高速公路出口重叠: side=%s pos=%s" % [seg_side, str(pos)])

	return Result.success()

func _infer_edge_side(state: GameState, pos: Vector2i) -> String:
	if state == null:
		return ""
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	if pos.y == minp.y:
		return "N"
	if pos.y == maxp.y:
		return "S"
	if pos.x == minp.x:
		return "W"
	if pos.x == maxp.x:
		return "E"
	return ""

func _infer_airplane_axis_for_overlap(state: GameState, world_pos: Vector2i, footprint_size: Vector2i) -> String:
	# Copy semantics from gameplay/actions/initiate_marketing/apply.gd, with thickness-aware edge relaxation.
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var thickness := mini(int(footprint_size.x), int(footprint_size.y))
	thickness = maxi(1, thickness)
	var left := world_pos.x
	var right := world_pos.x + 0
	var top := world_pos.y
	var bottom := world_pos.y + 0

	# Left/right edges -> row; allow the inner column when thickness=2.
	if left == minp.x or right == maxp.x or left == (maxp.x - (thickness - 1)) or right == (maxp.x - (thickness - 1)):
		return "row"
	# Top/bottom edges -> col; allow the inner row when thickness=2.
	if top == minp.y or bottom == maxp.y or top == (maxp.y - (thickness - 1)) or bottom == (maxp.y - (thickness - 1)):
		return "col"
	return ""
