extends RefCounted

const UtilsClass = preload("res://modules/new_milestones/rules/utils.gd")

const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const DinnertimeTimelineClass = preload("res://core/rules/dinnertime_timeline.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MarketingPlacementQueryClass = preload("res://core/map/marketing_placement_query.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

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

	var ds_read := _require_dinnertime_report(state)
	if not ds_read.ok:
		return ds_read
	var ds: Dictionary = ds_read.value
	var sales_read := _require_sales_report(ds)
	if not sales_read.ok:
		return sales_read
	var sales: Array = sales_read.value
	if sales.is_empty():
		return Result.success()

	var timeline_events := DinnertimeTimelineClass.ensure_state_timeline_events(state)
	var sale_reports: Array[Dictionary] = []

	for sale_index in range(sales.size()):
		var sale_read := _require_sale_report(state, sale_index, sales[sale_index])
		if not sale_read.ok:
			return sale_read
		var s: Dictionary = sale_read.value
		sale_reports.append(s)
		var owner_val = s.get("winner_owner", null)
		var owner: int = int(owner_val)
		var required: Dictionary = s.get("required", {})
		for product_id_val in required.keys():
			var product_id: String = str(product_id_val)
			var r2 := MilestoneSystemClass.process_event(state, "ProductSold", {
				"player_id": owner,
				"product": product_id,
			})
			if not r2.ok:
				return r2
			var v = r2.value
			if v is Dictionary:
				var claimed_val = Dictionary(v).get("claimed", [])
				if claimed_val is Array:
					for mid_val in Array(claimed_val):
						if not (mid_val is String):
							continue
						var mid := str(mid_val).strip_edges()
						if mid.is_empty():
							continue
						DinnertimeTimelineClass.append_sale_milestone(timeline_events, sale_index, owner, mid)

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
		var placements_read := MapStateAccessClass.require_marketing_placements(state, "new_milestones:pizza")
		if not placements_read.ok:
			return placements_read
		var placements: Dictionary = placements_read.value
		for k in placements.keys():
			if not (k is String):
				return Result.failure("new_milestones:pizza: marketing_placements key 类型错误（期望 String）: %s" % str(k))
			var placement_key := str(k).strip_edges()
			if placement_key.is_empty():
				return Result.failure("new_milestones:pizza: marketing_placements key 不能为空")
			used_radio_boards[placement_key] = true
		for inst_val in state.marketing_instances:
			if not (inst_val is Dictionary):
				return Result.failure("new_milestones:pizza: marketing_instances 元素类型错误（期望 Dictionary）")
			var bn = Dictionary(inst_val).get("board_number", null)
			if not (bn is int):
				return Result.failure("new_milestones:pizza: marketing_instances.board_number 缺失或类型错误（期望 int）")
			used_radio_boards[str(int(bn))] = true

		var pizza_count := 0
		for sale_index in range(sale_reports.size()):
			var s: Dictionary = sale_reports[sale_index]
			if pizza_count >= 3:
				break
			var required: Dictionary = s.get("required", {})
			if not required.has("pizza"):
				continue

			var seller: int = int(s.get("winner_owner", -1))

			var house_id_val = s.get("house_id", null)
			if not (house_id_val is String):
				return Result.failure("new_milestones:pizza: sales[%d].house_id 缺失或类型错误（期望 String）" % sale_index)
			var house_id: String = str(house_id_val)
			if house_id.is_empty():
				return Result.failure("new_milestones:pizza: sales[%d].house_id 不能为空" % sale_index)
			var house_number_read := _parse_int_value(s.get("house_number", null), "new_milestones:pizza: sales[%d].house_number" % sale_index)
			if not house_number_read.ok:
				return house_number_read
			var houses_read := MapStateAccessClass.require_houses(state, "new_milestones:pizza")
			if not houses_read.ok:
				return houses_read
			var houses: Dictionary = houses_read.value
			if not houses.has(house_id):
				return Result.failure("new_milestones:pizza: houses 缺少 house_id: %s" % house_id)
			var house_val = houses[house_id]
			if not (house_val is Dictionary):
				return Result.failure("new_milestones:pizza: houses[%s] 类型错误（期望 Dictionary）" % house_id)
			var house: Dictionary = house_val
			if not house.has("anchor_pos") or not (house["anchor_pos"] is Vector2i):
				return Result.failure("new_milestones:pizza: houses[%s].anchor_pos 缺失或类型错误（期望 Vector2i）" % house_id)
			var anchor: Vector2i = house["anchor_pos"]

			var board_number := _pick_available_radio_board_number(state, used_radio_boards)
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
				"house_number": int(house_number_read.value),
				"tile_min": tile_min,
				"tile_max": tile_max,
				"board_number": board_number,
				"product": "pizza",
				"duration": 2,
			})
			used_radio_boards[str(board_number)] = true
			pizza_count += 1

		if not pending_list.is_empty():
			var pending_phase_actions_set := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
				state.round_state,
				"Dinnertime",
				pending_list.duplicate(true),
				"new_milestones:pizza"
			)
			if not pending_phase_actions_set.ok:
				return pending_phase_actions_set
			state.round_state[PIZZA_PENDING_KEY] = pending_list

	# “FIRST BURGER SOLD”：从此 CEO 卡槽固定至少 4（不受储备卡影响）
	for player_id in range(state.players.size()):
		if not StateUpdater.player_has_milestone(state, player_id, MILESTONE_ID_BURGER_SOLD):
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

func _require_dinnertime_report(state: GameState) -> Result:
	if not state.round_state.has("dinnertime"):
		return Result.failure("new_milestones:dinnertime: round_state.dinnertime 缺失")
	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.failure("new_milestones:dinnertime: round_state.dinnertime 类型错误（期望 Dictionary）")
	return Result.success(ds_val)

func _require_sales_report(dinnertime_report: Dictionary) -> Result:
	if not dinnertime_report.has("sales"):
		return Result.failure("new_milestones:dinnertime: round_state.dinnertime.sales 缺失")
	var sales_val = dinnertime_report.get("sales", null)
	if not (sales_val is Array):
		return Result.failure("new_milestones:dinnertime: round_state.dinnertime.sales 类型错误（期望 Array）")
	return Result.success(sales_val)

func _require_sale_report(state: GameState, sale_index: int, sale_val) -> Result:
	var path := "new_milestones:dinnertime: sales[%d]" % sale_index
	if not (sale_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var sale: Dictionary = sale_val

	var owner_read := _parse_int_value(sale.get("winner_owner", null), "%s.winner_owner" % path)
	if not owner_read.ok:
		return owner_read
	var owner: int = int(owner_read.value)
	if owner < 0 or owner >= state.players.size():
		return Result.failure("%s.winner_owner 越界: %d" % [path, owner])

	var required_read := _require_required_products(sale.get("required", null), "%s.required" % path)
	if not required_read.ok:
		return required_read
	sale["winner_owner"] = owner
	sale["required"] = required_read.value
	return Result.success(sale)

func _require_required_products(required_val, path: String) -> Result:
	if not (required_val is Dictionary):
		return Result.failure("%s 缺失或类型错误（期望 Dictionary）" % path)
	var required: Dictionary = required_val
	if required.is_empty():
		return Result.failure("%s 不能为空" % path)
	for product_id_val in required.keys():
		if not (product_id_val is String):
			return Result.failure("%s key 类型错误（期望 String）: %s" % [path, str(product_id_val)])
		var product_id := str(product_id_val).strip_edges()
		if product_id.is_empty():
			return Result.failure("%s key 不能为空" % path)
		var amount_read := _parse_int_value(required.get(product_id_val, null), "%s[%s]" % [path, product_id])
		if not amount_read.ok:
			return amount_read
		var amount := int(amount_read.value)
		if amount <= 0:
			return Result.failure("%s[%s] 必须 > 0，实际: %d" % [path, product_id, amount])
	return Result.success(required)

func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 缺失或类型错误（期望 int）" % path)

func _pick_available_radio_board_number(state: GameState, used_board_numbers: Dictionary) -> int:
	# base_marketing：radio #1-#3
	for bn in [1, 2, 3]:
		if used_board_numbers.has(str(bn)):
			continue
		var board_spec_read := MarketingRulesClass.require_board_spec(state, bn)
		if not board_spec_read.ok:
			continue
		var board_spec: Dictionary = board_spec_read.value
		if str(board_spec.get("marketing_type", "")) == "radio":
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
	if not CoordsClass.is_world_pos_in_grid(state, world_pos):
		return false

	var occupied_read := MarketingPlacementQueryClass.has_any_at_world_pos(state, world_pos)
	if not occupied_read.ok:
		return false
	if bool(occupied_read.value):
		return false

	var cell := CellsClass.get_cell(state, world_pos)
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
