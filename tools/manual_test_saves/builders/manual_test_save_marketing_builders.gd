extends "res://tools/manual_test_saves/builders/manual_test_save_map_support.gd"

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

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

	_apply_marketing_animation_review_map(state, actor)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	_reset_sub_phase_passed(state)

	var employees := ["brand_director", "brand_manager", "campaign_manager", "marketing_trainee"]
	for employee_type in employees:
		var ensure := _ensure_employee(state, actor, employee_type, false, 1)
		if not ensure.ok:
			return ensure

	var commands := [
		{
			"label": "radio #1",
			"params": {
				"employee_type": "brand_director",
				"board_number": 1,
				"product": "soda",
				"duration": 2,
				"position": [2, 4],
			},
		},
		{
			"label": "airplane #4",
			"params": {
				"employee_type": "brand_manager",
				"board_number": 4,
				"product": "beer",
				"duration": 1,
				"position": [0, 10],
			},
		},
		{
			"label": "mailbox #7",
			"params": {
				"employee_type": "campaign_manager",
				"board_number": 7,
				"product": "pizza",
				"duration": 1,
				"position": [4, 2],
			},
		},
		{
			"label": "billboard #11",
			"params": {
				"employee_type": "marketing_trainee",
				"board_number": 11,
				"product": "burger",
				"duration": 2,
				"position": [0, 2],
			},
		},
	]
	for spec_val in commands:
		var spec: Dictionary = spec_val
		var params: Dictionary = spec.get("params", {})
		var r := engine.execute_command(Command.create("initiate_marketing", actor, params))
		if not r.ok:
			return Result.failure("%s initiate_marketing failed: %s" % [str(spec.get("label", "")), r.error])

	state = engine.get_state()
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

	var pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state, DefsClass.PHASE_MARKETING, ["confirm_marketing"], "manual marketing review"
	)
	if not pending.ok:
		return pending

	return Result.success({
		"scenario": [
			"存档已冻结在 Marketing 阶段，并保留 confirm_marketing pending；图形界面载入后应启动营销结算动画，而不是立刻跳过。",
			"本场景包含四种基础广告：radio #1、airplane #4、mailbox #7、billboard #11，结算顺序按 board_number 升序。",
			"右侧房屋在结算前已预填到普通需求上限，用于复核 mailbox/封顶反馈；其他房屋用于复核飞行动画、范围高亮和持续时间变化。",
		],
	})

func _apply_marketing_animation_review_map(state: GameState, owner: int) -> void:
	var grid_size := Vector2i(15, 15)
	var tile_grid_size := Vector2i(3, 3)
	var cells := _build_empty_cells(grid_size)

	for y in range(grid_size.y):
		var dirs: Array = []
		if y > 0:
			dirs.append("N")
		if y < grid_size.y - 1:
			dirs.append("S")
		_set_road_segment(cells, Vector2i(3, y), dirs)

	var left_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	var right_cells: Array[Vector2i] = [
		Vector2i(4, 0), Vector2i(5, 0),
		Vector2i(4, 1), Vector2i(5, 1),
	]
	_set_house(cells, "house_left", 1, left_cells)
	_set_house(cells, "house_right_capped", 2, right_cells)
	_set_house_1x1(cells, "radio_mid", 3, Vector2i(8, 5))
	_set_house_1x1(cells, "airplane_west", 4, Vector2i(0, 10))
	_set_house_1x1(cells, "airplane_mid", 5, Vector2i(5, 10))
	_set_house_1x1(cells, "airplane_east", 6, Vector2i(10, 10))
	_set_house_1x1(cells, "radio_outside", 7, Vector2i(12, 0))

	var rest_0_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 5), Vector2i(1, 5),
	]
	var rest_1_cells: Array[Vector2i] = [
		Vector2i(12, 13), Vector2i(13, 13),
		Vector2i(12, 14), Vector2i(13, 14),
	]
	_set_restaurant(cells, "rest_0", owner, rest_0_cells)
	if state.players.size() > 1:
		_set_restaurant(cells, "rest_1", 1, rest_1_cells)

	var cap := state.get_rule_int("demand_cap_normal")
	if cap <= 0:
		cap = 3
	var capped_demands: Array = []
	for _i in range(cap):
		capped_demands.append({
			"product": "pizza",
			"from_player": -1,
			"board_number": 0,
			"type": "seed",
		})

	var restaurants := {
		"rest_0": {
			"restaurant_id": "rest_0",
			"owner": owner,
			"anchor_pos": Vector2i(0, 4),
			"entrance_pos": Vector2i(2, 4),
			"cells": rest_0_cells,
		},
	}
	if state.players.size() > 1:
		restaurants["rest_1"] = {
			"restaurant_id": "rest_1",
			"owner": 1,
			"anchor_pos": Vector2i(12, 13),
			"entrance_pos": Vector2i(12, 13),
			"cells": rest_1_cells,
		}

	state.map = {
		"map_origin": Vector2i.ZERO,
		"grid_size": grid_size,
		"tile_grid_size": tile_grid_size,
		"cells": cells,
		"houses": {
			"house_left": {"house_id": "house_left", "house_number": 1, "anchor_pos": Vector2i(0, 0), "cells": left_cells, "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"house_right_capped": {"house_id": "house_right_capped", "house_number": 2, "anchor_pos": Vector2i(4, 0), "cells": right_cells, "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": capped_demands},
			"radio_mid": {"house_id": "radio_mid", "house_number": 3, "anchor_pos": Vector2i(8, 5), "cells": [Vector2i(8, 5)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"airplane_west": {"house_id": "airplane_west", "house_number": 4, "anchor_pos": Vector2i(0, 10), "cells": [Vector2i(0, 10)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"airplane_mid": {"house_id": "airplane_mid", "house_number": 5, "anchor_pos": Vector2i(5, 10), "cells": [Vector2i(5, 10)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"airplane_east": {"house_id": "airplane_east", "house_number": 6, "anchor_pos": Vector2i(10, 10), "cells": [Vector2i(10, 10)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"radio_outside": {"house_id": "radio_outside", "house_number": 7, "anchor_pos": Vector2i(12, 0), "cells": [Vector2i(12, 0)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
		},
		"restaurants": restaurants,
		"drink_sources": [],
		"next_house_number": 8,
		"next_restaurant_id": 2,
		"boundary_index": _build_boundary_index(tile_grid_size),
		"marketing_placements": {},
		"coffee_shops": {},
		"next_coffee_shop_id": 1,
	}

	state.players[owner]["restaurants"] = ["rest_0"]
	if state.players.size() > 1:
		state.players[1]["restaurants"] = ["rest_1"]
	_invalidate_road_graph(state)
