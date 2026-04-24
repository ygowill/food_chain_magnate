extends "res://tools/manual_test_saves/builders/manual_test_save_map_support.gd"

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")

func get_registry() -> Dictionary:
	return {
		"marketing_phase_animation_review": Callable(self, "_build_marketing_phase_animation_review"),
	}

func _build_marketing_phase_animation_review(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, DefsClass.SUB_PHASE_MARKETING)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var map_check := _validate_review_map_has_real_tiles(state)
	if not map_check.ok:
		return map_check
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	_reset_sub_phase_passed(state)

	var employee_counts := {
		"brand_director": 1,
		"brand_manager": 1,
		"campaign_manager": 2,
	}
	for employee_type in employee_counts.keys():
		var ensure := _ensure_employee(state, actor, str(employee_type), false, int(employee_counts[employee_type]))
		if not ensure.ok:
			return ensure

	var commands := [
		{
			"label": "radio #1",
			"employee_type": "brand_director",
			"board_number": 1,
			"product": "soda",
			"duration": 3,
		},
		{
			"label": "airplane #4",
			"employee_type": "brand_manager",
			"board_number": 4,
			"product": "beer",
			"duration": 3,
		},
		{
			"label": "mailbox #7",
			"employee_type": "campaign_manager",
			"board_number": 7,
			"product": "pizza",
			"duration": 3,
		},
		{
			"label": "billboard #14",
			"employee_type": "campaign_manager",
			"board_number": 14,
			"product": "burger",
			"duration": 3,
		},
	]
	var chosen: Array = []
	for spec_val in commands:
		var spec: Dictionary = spec_val
		var find := _find_first_valid_marketing_with_affected_houses(
			engine,
			actor,
			str(spec.get("employee_type", "")),
			int(spec.get("board_number", 0)),
			str(spec.get("product", "")),
			int(spec.get("duration", 0))
		)
		if not find.ok:
			return find
		var cmd_info: Dictionary = find.value
		var params: Dictionary = cmd_info.get("params", {})
		var r := engine.execute_command(Command.create("initiate_marketing", actor, params))
		if not r.ok:
			return Result.failure("%s initiate_marketing failed: %s" % [str(spec.get("label", "")), r.error])
		chosen.append({
			"label": str(spec.get("label", "")),
			"params": params.duplicate(true),
			"affected_houses": cmd_info.get("affected_houses", []),
		})

	state = engine.get_state()
	var visible_before := _validate_visible_marketing_placements(state, {
		"1": "radio",
		"4": "airplane",
		"7": "mailbox",
		"14": "billboard",
	})
	if not visible_before.ok:
		return visible_before

	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	var cash := StateUpdater.player_receive_from_bank(state, actor, 40)
	if not cash.ok:
		return Result.failure("player_receive_from_bank failed: %s" % cash.error)
	var to_marketing := engine.phase_manager.advance_phase(state)
	if not to_marketing.ok:
		return Result.failure("advance to Marketing failed: %s" % to_marketing.error)

	state = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_MARKETING:
		return Result.failure("expected Marketing phase, got: %s/%s" % [str(state.phase), str(state.sub_phase)])
	var marketing_report_val = state.round_state.get("marketing", null)
	if not (marketing_report_val is Dictionary):
		return Result.failure("round_state.marketing missing after settlement")
	var marketing_report: Dictionary = marketing_report_val
	var events_val = marketing_report.get("timeline_events", [])
	if not (events_val is Array) or (events_val as Array).is_empty():
		return Result.failure("round_state.marketing.timeline_events is empty")
	var processed_check := _validate_processed_marketing_report(marketing_report)
	if not processed_check.ok:
		return processed_check
	var visible_after := _validate_visible_marketing_placements(state, {
		"1": "radio",
		"4": "airplane",
		"7": "mailbox",
		"14": "billboard",
	})
	if not visible_after.ok:
		return visible_after

	var pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state, DefsClass.PHASE_MARKETING, ["confirm_marketing"], "manual marketing review"
	)
	if not pending.ok:
		return pending

	return Result.success({
		"scenario": [
			"存档已冻结在 Marketing 阶段，并保留 confirm_marketing pending；图形界面载入后应启动营销结算动画，而不是立刻跳过。",
			"本场景使用项目真实随机板块地图（保留 tile_placements），避免极简测试地图在 UI 中缺少正常地图渲染上下文。",
			"本场景包含四种基础广告：radio #1、airplane #4、mailbox #7、billboard #14，结算顺序按 board_number 升序。",
			"四个广告均设置为 3 回合，结算后仍剩余 2 回合并保留在 map.marketing_placements 中，便于复核广告件本体渲染。",
			"自动选择的放置参数：%s" % str(chosen),
		],
	})

func _validate_review_map_has_real_tiles(state: GameState) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.map is Dictionary):
		return Result.failure("state.map is not Dictionary")
	var map: Dictionary = state.map
	var tile_placements_val = map.get("tile_placements", null)
	if not (tile_placements_val is Array) or (tile_placements_val as Array).is_empty():
		return Result.failure("manual marketing review requires a real baked map with tile_placements")
	var cells_val = map.get("cells", null)
	if not (cells_val is Array) or (cells_val as Array).is_empty():
		return Result.failure("manual marketing review map.cells missing or empty")
	var houses_val = map.get("houses", null)
	if not (houses_val is Dictionary) or (houses_val as Dictionary).is_empty():
		return Result.failure("manual marketing review map.houses missing or empty")
	var restaurants_val = map.get("restaurants", null)
	if not (restaurants_val is Dictionary) or (restaurants_val as Dictionary).is_empty():
		return Result.failure("manual marketing review map.restaurants missing or empty")
	return Result.success()

func _find_first_valid_marketing_with_affected_houses(
	engine: GameEngine,
	actor: int,
	employee_type: String,
	board_number: int,
	product: String,
	duration: int
) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	var ex := engine.action_registry.get_executor("initiate_marketing")
	if ex == null:
		return Result.failure("cannot find executor: initiate_marketing")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	var valid_candidates := 0
	var empty_affected_candidates := 0
	var fallback_attempts := 0
	var last_fallback_error := ""
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var params := {
					"employee_type": employee_type,
					"board_number": board_number,
					"product": product,
					"duration": duration,
					"position": [x, y],
					"rotation": int(rot),
				}
				var cmd := Command.create("initiate_marketing", actor, params)
				var vr := ex.validate(state, cmd)
				if not vr.ok:
					continue
				valid_candidates += 1
				var affected_read := _get_candidate_affected_houses(engine, state, board_number, cmd)
				if not affected_read.ok:
					continue
				var affected: Array = affected_read.value
				if affected.is_empty():
					empty_affected_candidates += 1
					fallback_attempts += 1
					var prepared := _try_make_billboard_candidate_affect_review_house(engine, state, board_number, cmd, ex)
					if not prepared.ok:
						last_fallback_error = prepared.error
						continue
					var prepared_value: Dictionary = prepared.value
					var prepared_affected: Array = prepared_value.get("affected_houses", [])
					if prepared_affected.is_empty():
						continue
					return Result.success({
						"action_id": "initiate_marketing",
						"actor": actor,
						"params": cmd.params.duplicate(true),
						"affected_houses": prepared_affected.duplicate(true),
						"added_house": prepared_value.get("added_house", {}),
					})
				return Result.success({
					"action_id": "initiate_marketing",
					"actor": actor,
					"params": cmd.params.duplicate(true),
					"affected_houses": affected.duplicate(true),
				})

	return Result.failure(
		"no valid initiate_marketing placement with affected houses found (board=%d product=%s valid=%d empty_affected=%d fallback_attempts=%d last_fallback=%s)" % [
			board_number,
			product,
			valid_candidates,
			empty_affected_candidates,
			fallback_attempts,
			last_fallback_error,
		]
	)

func _try_make_billboard_candidate_affect_review_house(
	engine: GameEngine,
	state: GameState,
	board_number: int,
	cmd: Command,
	ex
) -> Result:
	var board_spec_read := MarketingRulesClass.require_board_spec(state, board_number)
	if not board_spec_read.ok:
		return board_spec_read
	var board_spec: Dictionary = board_spec_read.value
	if str(board_spec.get("marketing_type", "")) != "billboard":
		return Result.failure("not a billboard candidate")

	var original_map: Dictionary = state.map.duplicate(true)
	var added_house_read := _add_adjacent_review_house_for_billboard(state, board_spec, cmd)
	if not added_house_read.ok:
		state.map = original_map
		_invalidate_road_graph(state)
		return added_house_read

	var vr = ex.validate(state, cmd)
	if not vr.ok:
		state.map = original_map
		_invalidate_road_graph(state)
		return vr

	var affected_read := _get_candidate_affected_houses(engine, state, board_number, cmd)
	if not affected_read.ok:
		state.map = original_map
		_invalidate_road_graph(state)
		return affected_read
	var affected: Array = affected_read.value
	if affected.is_empty():
		state.map = original_map
		_invalidate_road_graph(state)
		return Result.failure("added billboard review house was not affected")

	return Result.success({
		"added_house": added_house_read.value,
		"affected_houses": affected.duplicate(true),
	})

func _add_adjacent_review_house_for_billboard(state: GameState, board_spec: Dictionary, cmd: Command) -> Result:
	var world_pos_read := _read_command_position(cmd)
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value
	var rotation := int(cmd.params.get("rotation", 0))
	var base_size: Vector2i = board_spec.get("footprint_size", Vector2i.ONE)
	var size_read := MarketingRulesClass.get_rotated_footprint_size(base_size, rotation)
	if not size_read.ok:
		return size_read
	var footprint: Array[Vector2i] = MarketingRulesClass.build_footprint_cells(world_pos, size_read.value)
	var pos_read := _find_empty_adjacent_cell_for_review_house(state, footprint)
	if not pos_read.ok:
		return pos_read
	return _add_review_house_1x1(state, pos_read.value)

func _find_empty_adjacent_cell_for_review_house(state: GameState, footprint: Array[Vector2i]) -> Result:
	var footprint_set := {}
	for cell_pos in footprint:
		footprint_set[cell_pos] = true
	for cell_pos in footprint:
		for dir in MapUtils.DIRECTIONS:
			var n := MapUtils.get_neighbor_pos(cell_pos, dir)
			if footprint_set.has(n):
				continue
			if _is_empty_base_cell_for_review_house(state, n):
				return Result.success(n)
	return Result.failure("no empty adjacent cell for billboard review house")

func _is_empty_base_cell_for_review_house(state: GameState, world_pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	var coords_script = _get_coords_script()
	if coords_script == null:
		return false
	if not coords_script.is_world_pos_in_grid(state, world_pos):
		return false
	if _is_world_pos_occupied_by_existing_marketing(state, world_pos):
		return false
	var cells_val = state.map.get("cells", null)
	if not (cells_val is Array):
		return false
	var idx: Vector2i = coords_script.world_to_index(state, world_pos)
	var cells: Array = cells_val
	if idx.y < 0 or idx.y >= cells.size():
		return false
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return false
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return false
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return false
	var cell: Dictionary = cell_val
	if bool(cell.get("blocked", false)):
		return false
	var structure_val = cell.get("structure", {})
	if structure_val is Dictionary and not (structure_val as Dictionary).is_empty():
		return false
	elif not (structure_val is Dictionary):
		return false
	var roads_val = cell.get("road_segments", [])
	if roads_val is Array and not (roads_val as Array).is_empty():
		return false
	elif not (roads_val is Array):
		return false
	var drink_val = cell.get("drink_source", null)
	if drink_val != null:
		if drink_val is Dictionary and (drink_val as Dictionary).is_empty():
			pass
		else:
			return false
	return true

func _is_world_pos_occupied_by_existing_marketing(state: GameState, world_pos: Vector2i) -> bool:
	if state == null or not (state.map is Dictionary):
		return false
	var placements_val = state.map.get("marketing_placements", null)
	if not (placements_val is Dictionary):
		return false
	var placements: Dictionary = placements_val
	for key in placements.keys():
		var p_val = placements[key]
		if not (p_val is Dictionary):
			continue
		var placement: Dictionary = p_val
		if str(placement.get("type", "")) == "airplane":
			continue
		var wp_val = placement.get("world_pos", null)
		if not (wp_val is Vector2i):
			continue
		var footprint_size := Vector2i.ONE
		var footprint_val = placement.get("footprint_size", null)
		if footprint_val is Vector2i:
			footprint_size = Vector2i(footprint_val)
		elif footprint_val is Array:
			var footprint_arr: Array = footprint_val
			if footprint_arr.size() == 2:
				footprint_size = Vector2i(int(footprint_arr[0]), int(footprint_arr[1]))
		var rotation := int(placement.get("rotation", 0))
		var size_read := MarketingRulesClass.get_rotated_footprint_size(footprint_size, rotation)
		if not size_read.ok:
			continue
		var footprint: Array[Vector2i] = MarketingRulesClass.build_footprint_cells(wp_val, size_read.value)
		if footprint.has(world_pos):
			return true
	return false

func _add_review_house_1x1(state: GameState, world_pos: Vector2i) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map is invalid")
	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var idx: Vector2i = coords_script.world_to_index(state, world_pos)
	var cells_val = state.map.get("cells", null)
	if not (cells_val is Array):
		return Result.failure("state.map.cells missing")
	var cells: Array = cells_val
	if idx.y < 0 or idx.y >= cells.size():
		return Result.failure("review house y out of range: %s" % str(world_pos))
	var row_val = cells[idx.y]
	if not (row_val is Array):
		return Result.failure("state.map.cells row invalid: %d" % idx.y)
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return Result.failure("review house x out of range: %s" % str(world_pos))
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return Result.failure("state.map cell invalid: %s" % str(world_pos))
	var cell: Dictionary = cell_val
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return Result.failure("state.map.houses missing")
	var houses: Dictionary = houses_val
	var house_id := "manual_marketing_review_house"
	var suffix := 2
	while houses.has(house_id):
		house_id = "manual_marketing_review_house_%d" % suffix
		suffix += 1
	var house_number := int(state.map.get("next_house_number", houses.size() + 1))
	if house_number <= 0:
		house_number = houses.size() + 1

	var structure := {
		"piece_id": "house",
		"owner": -1,
		"anchor_cell": true,
		"parent_anchor": world_pos,
		"rotation": 0,
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true,
	}
	cell["structure"] = structure
	row[idx.x] = cell
	cells[idx.y] = row
	state.map["cells"] = cells

	houses[house_id] = {
		"house_id": house_id,
		"house_number": house_number,
		"anchor_pos": world_pos,
		"cells": [world_pos],
		"has_garden": false,
		"is_apartment": false,
		"printed": false,
		"owner": -1,
		"demands": [],
	}
	state.map["houses"] = houses
	state.map["next_house_number"] = house_number + 1
	_consume_review_house_number_from_supply(state, house_number)
	_invalidate_road_graph(state)
	return Result.success({
		"house_id": house_id,
		"house_number": house_number,
		"world_pos": world_pos,
	})

func _consume_review_house_number_from_supply(state: GameState, house_number: int) -> void:
	if state == null or not (state.map is Dictionary):
		return
	var supply_val = state.map.get("house_number_supply_remaining", null)
	if not (supply_val is Array):
		return
	var supply: Array = supply_val
	for i in range(supply.size() - 1, -1, -1):
		if int(supply[i]) == house_number:
			supply.remove_at(i)
	state.map["house_number_supply_remaining"] = supply

func _get_candidate_affected_houses(engine: GameEngine, state: GameState, board_number: int, cmd: Command) -> Result:
	var board_spec_read := MarketingRulesClass.require_board_spec(state, board_number)
	if not board_spec_read.ok:
		return board_spec_read
	var board_spec: Dictionary = board_spec_read.value
	var marketing_type := str(board_spec.get("marketing_type", ""))
	var world_pos_read := _read_command_position(cmd)
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value
	var rotation := int(cmd.params.get("rotation", 0))
	var axis := ""
	var tile_index := -1
	if marketing_type == "airplane":
		axis = _infer_airplane_axis_for_candidate(state, world_pos)
		tile_index = world_pos.y if axis == "row" else world_pos.x
	var inst := {
		"board_number": board_number,
		"type": marketing_type,
		"owner": int(cmd.actor),
		"employee_type": str(cmd.params.get("employee_type", "")),
		"product": str(cmd.params.get("product", "")),
		"world_pos": world_pos,
		"rotation": rotation,
		"footprint_size": board_spec.get("footprint_size", Vector2i.ONE),
		"remaining_duration": int(cmd.params.get("duration", 1)),
		"axis": axis,
		"tile_index": tile_index,
		"created_round": int(state.round_number),
	}
	var calculator = engine.phase_manager.get_marketing_range_calculator()
	if calculator == null:
		return Result.failure("marketing range calculator is null")
	return calculator.get_affected_house_ids(state, inst)

func _read_command_position(cmd: Command) -> Result:
	if cmd == null:
		return Result.failure("cmd is null")
	var pos_val = cmd.params.get("position", null)
	if pos_val is Vector2i:
		return Result.success(Vector2i(pos_val))
	if pos_val is Array:
		var arr: Array = pos_val
		if arr.size() == 2:
			return Result.success(Vector2i(int(arr[0]), int(arr[1])))
	return Result.failure("command.position invalid: %s" % str(pos_val))

func _infer_airplane_axis_for_candidate(state: GameState, pos: Vector2i) -> String:
	var coords_script = _get_coords_script()
	if coords_script == null:
		return "row"
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return "row"

func _validate_visible_marketing_placements(state: GameState, expected: Dictionary) -> Result:
	if state == null:
		return Result.failure("state is null")
	var placements_val = state.map.get("marketing_placements", null) if (state.map is Dictionary) else null
	if not (placements_val is Dictionary):
		return Result.failure("state.map.marketing_placements missing or invalid")
	var placements: Dictionary = placements_val
	for key in expected.keys():
		var board_key := str(key)
		if not placements.has(board_key):
			return Result.failure("marketing placement missing board #%s; visible ads would not render" % board_key)
		if not (placements[board_key] is Dictionary):
			return Result.failure("marketing placement #%s is not Dictionary" % board_key)
		var p: Dictionary = placements[board_key]
		var expected_type := str(expected.get(key, ""))
		if str(p.get("type", "")) != expected_type:
			return Result.failure("marketing placement #%s type mismatch: expected=%s actual=%s" % [board_key, expected_type, str(p.get("type", ""))])
		if int(p.get("remaining_duration", 0)) <= 0:
			return Result.failure("marketing placement #%s should remain visible after settlement, remaining_duration=%s" % [board_key, str(p.get("remaining_duration", null))])
	return Result.success()

func _validate_processed_marketing_report(marketing_report: Dictionary) -> Result:
	var processed_val = marketing_report.get("processed", null)
	if not (processed_val is Array):
		return Result.failure("round_state.marketing.processed missing or invalid")
	var processed: Array = processed_val
	var expected := {
		"1": "radio",
		"4": "airplane",
		"7": "mailbox",
		"14": "billboard",
	}
	for key in expected.keys():
		var found := false
		for item_val in processed:
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			if int(item.get("board_number", 0)) != int(key):
				continue
			found = true
			if str(item.get("type", "")) != str(expected[key]):
				return Result.failure("processed #%s type mismatch: %s" % [key, str(item.get("type", ""))])
			var affected_val = item.get("affected_houses", null)
			if not (affected_val is Array) or (affected_val as Array).is_empty():
				return Result.failure("processed #%s has no affected_houses" % key)
			break
		if not found:
			return Result.failure("round_state.marketing.processed missing board #%s" % key)
	return Result.success()
