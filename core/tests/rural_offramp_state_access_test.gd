# rural offramp 状态访问回归测试
class_name RuralOfframpStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/rural_marketeers/actions/place_highway_offramp_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_validate_fails_fast_on_missing_grid_size()
	if not r.ok:
		return r
	r = _test_validate_fails_fast_on_missing_tile_grid_size()
	if not r.ok:
		return r
	r = _test_validate_fails_fast_on_invalid_pending_flag_type()
	if not r.ok:
		return r
	r = _test_apply_external_piece_fails_fast_on_invalid_external_cells_type()
	if not r.ok:
		return r
	r = _test_get_offramp_connection_cells_fails_fast_on_invalid_offramp_array_type()
	if not r.ok:
		return r
	r = _test_get_offramp_connection_cells_fails_fast_on_missing_offramp_array()
	if not r.ok:
		return r
	r = _test_has_offramp_at_pos_fails_fast_on_missing_offramps()
	if not r.ok:
		return r
	r = _test_has_offramp_at_pos_fails_fast_on_malformed_entry()
	if not r.ok:
		return r
	r = _test_airplane_overlap_fails_fast_on_malformed_marketing_placement()
	if not r.ok:
		return r
	r = _test_airplane_overlap_fails_fast_on_malformed_airplane_placement()
	if not r.ok:
		return r
	return Result.success({"cases": 10})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.turn_order = [0]
	state.current_player_index = 0
	state.round_state = {
		"rural_marketeers_offramp_pending": {
			0: true,
		}
	}
	state.map = {
		"grid_size": Vector2i(5, 5),
		"tile_grid_size": Vector2i(1, 1),
		"external_cells": {},
		"rural_marketeers_offramps": [],
	}
	return state

static func _make_command() -> Command:
	return Command.create("place_highway_offramp", 0, {
		"position": [0, 0],
	})

static func _test_validate_fails_fast_on_missing_grid_size() -> Result:
	var action := ActionClass.new()
	var state := _make_state()
	state.map.erase("grid_size")
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("缺失 grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.grid_size，实际: %s" % err)
	return Result.success()

static func _test_validate_fails_fast_on_missing_tile_grid_size() -> Result:
	var action := ActionClass.new()
	var state := _make_state()
	state.map.erase("tile_grid_size")
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("缺失 tile_grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.tile_grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.tile_grid_size，实际: %s" % err)
	return Result.success()

static func _test_validate_fails_fast_on_invalid_pending_flag_type() -> Result:
	var action := ActionClass.new()
	var state := _make_state()
	state.round_state["rural_marketeers_offramp_pending"] = {0: "bad"}
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("pending flag 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.rural_marketeers_offramp_pending[0]") < 0:
		return Result.failure("错误信息应包含 round_state.rural_marketeers_offramp_pending[0]，实际: %s" % err)
	return Result.success()

static func _test_apply_external_piece_fails_fast_on_invalid_external_cells_type() -> Result:
	var action := ActionClass.new()
	var state := _make_state()
	state.map["external_cells"] = []
	var result := action._apply_external_offramp_piece(state, 0, Vector2i(0, 0), "N")
	if result.ok:
		return Result.failure("external_cells 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.external_cells") < 0:
		return Result.failure("错误信息应包含 state.map.external_cells，实际: %s" % err)
	return Result.success()

static func _test_get_offramp_connection_cells_fails_fast_on_invalid_offramp_array_type() -> Result:
	var state := _make_state()
	state.map["rural_marketeers_offramps"] = {}
	var result := ActionClass.get_offramp_connection_cells(state)
	if result.ok:
		return Result.failure("offramps 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramps，实际: %s" % err)
	return Result.success()

static func _test_get_offramp_connection_cells_fails_fast_on_missing_offramp_array() -> Result:
	var state := _make_state()
	state.map.erase("rural_marketeers_offramps")
	var result := ActionClass.get_offramp_connection_cells(state)
	if result.ok:
		return Result.failure("缺失 offramps 时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramps，实际: %s" % err)
	return Result.success()

static func _test_has_offramp_at_pos_fails_fast_on_missing_offramps() -> Result:
	var state := _make_state()
	state.map.erase("rural_marketeers_offramps")
	var result := ActionClass.has_offramp_at_pos(state, Vector2i(0, 0))
	if result.ok:
		return Result.failure("缺失 offramps 时 has_offramp_at_pos 应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramps，实际: %s" % err)
	return Result.success()

static func _test_has_offramp_at_pos_fails_fast_on_malformed_entry() -> Result:
	var state := _make_state()
	state.map["rural_marketeers_offramps"] = [{}]
	var result := ActionClass.has_offramp_at_pos(state, Vector2i(0, 0))
	if result.ok:
		return Result.failure("offramp entry 缺失 pos 时 has_offramp_at_pos 应失败")
	var err := str(result.error)
	if err.find("rural_marketeers_offramps[0].pos") < 0:
		return Result.failure("错误信息应包含 rural_marketeers_offramps[0].pos，实际: %s" % err)
	return Result.success()

static func _test_airplane_overlap_fails_fast_on_malformed_marketing_placement() -> Result:
	var state := _make_state()
	state.map["marketing_placements"] = {
		500: [],
	}
	var result := ActionClass._has_airplane_overlap_at_connection_cell(state, Vector2i(0, 0), "N")
	if result.ok:
		return Result.failure("marketing_placements entry 类型错误时应失败")
	var err := str(result.error)
	if err.find("marketing_placements[500]") < 0:
		return Result.failure("错误信息应包含 marketing_placements[500]，实际: %s" % err)
	return Result.success()

static func _test_airplane_overlap_fails_fast_on_malformed_airplane_placement() -> Result:
	var state := _make_state()
	state.map["marketing_placements"] = {
		500: {
			"type": "airplane",
			"world_pos": Vector2i(0, 0),
			"footprint_size": Vector2i(2, 5),
		},
	}
	var result := ActionClass._has_airplane_overlap_at_connection_cell(state, Vector2i(0, 0), "N")
	if result.ok:
		return Result.failure("airplane placement 缺失 axis 时应失败")
	var err := str(result.error)
	if err.find("marketing_placements[500].axis") < 0:
		return Result.failure("错误信息应包含 marketing_placements[500].axis，实际: %s" % err)
	return Result.success()
