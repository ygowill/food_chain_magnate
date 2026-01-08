extends RefCounted

const UtilsClass = preload("res://modules/new_milestones/rules/utils.gd")

const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

const Phase = PhaseDefsClass.Phase

const CM_PENDING_KEY := "new_milestones_campaign_manager_pending"
const CM_USED_KEY := "new_milestones_campaign_manager_used_this_turn"
const BM_PENDING_KEY := "new_milestones_brand_manager_airplane_pending"
const BM_USED_KEY := "new_milestones_brand_manager_airplane_used_this_turn"
const PIZZA_PENDING_KEY := "new_milestones_pizza_radios_pending"

const MILESTONE_ID_BURGER_SOLD := "first_burger_sold"
const MILESTONE_ID_PIZZA_SOLD := "first_pizza_sold"

func register(registrar) -> Result:
	# 晚餐结算后：按售卖记录触发 ProductSold 事件，并处理“首个卖出汉堡” CEO 卡槽修正
	var r = registrar.register_extension_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_after_dinnertime_primary"), 150)
	if not r.ok:
		return r

	# 不能存到下一回合：离开 Working/Marketing 子阶段时清空 pending
	r = registrar.register_working_sub_phase_hook("Marketing", PhaseManagerClass.HookType.AFTER_EXIT, Callable(self, "_on_working_marketing_after_exit"), 120)
	if not r.ok:
		return r

	return Result.success()

func _on_working_marketing_after_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("new_milestones: after_exit: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones: after_exit: state.round_state 类型错误（期望 Dictionary）")
	if state.round_state.has(CM_PENDING_KEY):
		state.round_state.erase(CM_PENDING_KEY)
	if state.round_state.has(CM_USED_KEY):
		state.round_state.erase(CM_USED_KEY)
	if state.round_state.has(BM_PENDING_KEY):
		state.round_state.erase(BM_PENDING_KEY)
	if state.round_state.has(BM_USED_KEY):
		state.round_state.erase(BM_USED_KEY)
	return Result.success()

func _after_dinnertime_primary(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("new_milestones:dinnertime: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("new_milestones:dinnertime: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("new_milestones:dinnertime: state.players 类型错误（期望 Array）")

	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.success()
	var ds: Dictionary = ds_val
	var sales_val = ds.get("sales", null)
	if not (sales_val is Array):
		return Result.success()
	var sales: Array = sales_val
	if sales.is_empty():
		return Result.success()

	for s_val in sales:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var owner_val = s.get("winner_owner", null)
		if not (owner_val is int):
			continue
		var owner: int = int(owner_val)
		if owner < 0 or owner >= state.players.size():
			return Result.failure("new_milestones:dinnertime: winner_owner 越界: %d" % owner)
		var req_val = s.get("required", null)
		if not (req_val is Dictionary):
			continue
		var required: Dictionary = req_val
		for product_id_val in required.keys():
			if not (product_id_val is String):
				continue
			var product_id: String = str(product_id_val)
			if product_id.is_empty():
				continue
			var r2 := MilestoneSystemClass.process_event(state, "ProductSold", {
				"player_id": owner,
				"product": product_id,
			})
			if not r2.ok:
				return r2

	# FIRST PIZZA SOLD：本回合前 3 个“买披萨”的房屋，卖家需放置 2 回合 radio(pizza)（玩家选择落点；若无空间则跳过该房屋）
	var pizza_awarded := false
	if state.round_state.has("milestones_auto_awarded"):
		var log_val = state.round_state.get("milestones_auto_awarded", null)
		if log_val is Array:
			for e_val in Array(log_val):
				if e_val is Dictionary and str(Dictionary(e_val).get("milestone_id", "")) == MILESTONE_ID_PIZZA_SOLD:
					pizza_awarded = true
					break
	if pizza_awarded:
		var pending_list: Array = []
		var used_radio_boards := {}
		if state.map is Dictionary and state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary:
			for k in Dictionary(state.map["marketing_placements"]).keys():
				if k is String:
					used_radio_boards[str(k)] = true
		for inst_val in state.marketing_instances:
			if inst_val is Dictionary:
				var bn = Dictionary(inst_val).get("board_number", null)
				if bn is int:
					used_radio_boards[str(int(bn))] = true

		var pizza_count := 0
		for s_val in sales:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			if pizza_count >= 3:
				break
			var req_val = s.get("required", null)
			if not (req_val is Dictionary):
				continue
			var required: Dictionary = req_val
			if not required.has("pizza"):
				continue

			var owner_val = s.get("winner_owner", null)
			if not (owner_val is int):
				continue
			var seller: int = int(owner_val)

			var house_id_val = s.get("house_id", null)
			if not (house_id_val is String):
				continue
			var house_id: String = str(house_id_val)
			if house_id.is_empty():
				continue
			if not (state.map is Dictionary and state.map.has("houses") and state.map["houses"] is Dictionary):
				return Result.failure("new_milestones:pizza: state.map.houses 缺失或类型错误")
			var houses: Dictionary = state.map["houses"]
			if not houses.has(house_id):
				return Result.failure("new_milestones:pizza: houses 缺少 house_id: %s" % house_id)
			var house_val = houses[house_id]
			if not (house_val is Dictionary):
				return Result.failure("new_milestones:pizza: houses[%s] 类型错误（期望 Dictionary）" % house_id)
			var house: Dictionary = house_val
			if not house.has("anchor_pos") or not (house["anchor_pos"] is Vector2i):
				return Result.failure("new_milestones:pizza: houses[%s].anchor_pos 缺失或类型错误（期望 Vector2i）" % house_id)
			var anchor: Vector2i = house["anchor_pos"]

			var board_number := _pick_available_radio_board_number(used_radio_boards)
			if board_number <= 0:
				break

			var tile_pos: Vector2i = MapUtils.world_to_tile(anchor).board_pos
			var tile_min := Vector2i(tile_pos.x * MapUtils.TILE_SIZE, tile_pos.y * MapUtils.TILE_SIZE)
			var tile_max := tile_min + Vector2i(MapUtils.TILE_SIZE - 1, MapUtils.TILE_SIZE - 1)

			# “if there is room”：至少存在 1 个合法放置点才进入待处理列表
			if not _has_any_legal_radio_position_in_tile(state, tile_min, tile_max):
				used_radio_boards[str(board_number)] = true
				continue

			pending_list.append({
				"seller": seller,
				"house_id": house_id,
				"house_number": s.get("house_number", -1),
				"tile_min": tile_min,
				"tile_max": tile_max,
				"board_number": board_number,
				"product": "pizza",
				"duration": 2,
			})
			used_radio_boards[str(board_number)] = true
			pizza_count += 1

		if not pending_list.is_empty():
			state.round_state[PIZZA_PENDING_KEY] = pending_list
			if not state.round_state.has("pending_phase_actions"):
				state.round_state["pending_phase_actions"] = {}
			var ppa_val = state.round_state.get("pending_phase_actions", null)
			if not (ppa_val is Dictionary):
				return Result.failure("new_milestones:pizza: round_state.pending_phase_actions 类型错误（期望 Dictionary）")
			var ppa: Dictionary = ppa_val
			ppa["Dinnertime"] = pending_list.duplicate(true)
			state.round_state["pending_phase_actions"] = ppa

	# “FIRST BURGER SOLD”：从此 CEO 卡槽固定至少 4（不受储备卡影响）
	for player_id in range(state.players.size()):
		if not UtilsClass.player_has_milestone(state, player_id, MILESTONE_ID_BURGER_SOLD):
			continue
		var p_val = state.players[player_id]
		if not (p_val is Dictionary):
			return Result.failure("new_milestones:dinnertime: player 类型错误（期望 Dictionary）: %d" % player_id)
		var p: Dictionary = p_val
		var cs_val = p.get("company_structure", null)
		if not (cs_val is Dictionary):
			return Result.failure("new_milestones:dinnertime: player[%d].company_structure 类型错误（期望 Dictionary）" % player_id)
		var cs: Dictionary = cs_val
		if not cs.has("ceo_slots"):
			return Result.failure("new_milestones:dinnertime: player[%d].company_structure.ceo_slots 缺失" % player_id)
		var slots_val = cs.get("ceo_slots", null)
		var current := 0
		if slots_val is int:
			current = int(slots_val)
		elif slots_val is float:
			var f: float = float(slots_val)
			if f != floor(f):
				return Result.failure("new_milestones:dinnertime: player[%d].company_structure.ceo_slots 必须为整数，实际: %s" % [player_id, str(slots_val)])
			current = int(f)
		else:
			return Result.failure("new_milestones:dinnertime: player[%d].company_structure.ceo_slots 类型错误（期望 int/float）" % player_id)
		if current < 4:
			cs["ceo_slots"] = 4
			p["company_structure"] = cs
			state.players[player_id] = p

	return Result.success()

func _pick_available_radio_board_number(used_board_numbers: Dictionary) -> int:
	# base_marketing：radio #1-#3
	for bn in [1, 2, 3]:
		if not used_board_numbers.has(str(bn)):
			var def = MarketingRegistryClass.get_def(bn)
			if def != null and str(def.type) == "radio":
				return bn
	return -1

func _has_any_legal_radio_position_in_tile(state: GameState, tile_min: Vector2i, tile_max: Vector2i) -> bool:
	for y in range(tile_min.y, tile_max.y + 1):
		for x in range(tile_min.x, tile_max.x + 1):
			var pos := Vector2i(x, y)
			if _is_legal_radio_position(state, pos):
				return true
	return false

func _is_legal_radio_position(state: GameState, world_pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	if not MapRuntimeClass.is_world_pos_in_grid(state, world_pos):
		return false

	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return false
	var placements: Dictionary = state.map["marketing_placements"]
	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return false
		var p: Dictionary = p_val
		if not p.has("world_pos") or not (p["world_pos"] is Vector2i):
			return false
		if p["world_pos"] == world_pos:
			return false

	var cell := MapRuntimeClass.get_cell(state, world_pos)
	if cell.is_empty():
		return false
	if not cell.has("structure") or not (cell["structure"] is Dictionary):
		return false
	if not Dictionary(cell["structure"]).is_empty():
		return false
	if not cell.has("blocked") or not (cell["blocked"] is bool):
		return false
	if bool(cell["blocked"]):
		return false
	if not cell.has("road_segments") or not (cell["road_segments"] is Array):
		return false
	if not Array(cell["road_segments"]).is_empty():
		return false

	var adjacent_roads_result := RangeUtilsClass.get_adjacent_road_cells(state, world_pos)
	if not adjacent_roads_result.ok:
		return false
	var adjacent_roads: Array = adjacent_roads_result.value
	return not adjacent_roads.is_empty()

