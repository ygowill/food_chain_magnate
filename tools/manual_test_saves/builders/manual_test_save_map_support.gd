extends "res://tools/manual_test_saves/builders/manual_test_save_builder_support.gd"

func _invalidate_road_graph(state: GameState) -> void:
	var rg_cache_script = load("res://core/map/map_runtime/road_graph_cache.gd")
	if rg_cache_script == null:
		return
	rg_cache_script.invalidate_road_graph(state)

func _mark_all_players_passed_for_working(state: GameState) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state is not Dictionary")
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed
	return Result.success()

func _build_empty_cells(grid_size: Vector2i) -> Array:
	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		tile_size = 1
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			var tile_origin := Vector2i(int(x / tile_size) * tile_size, int(y / tile_size) * tile_size)
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"drink_source": null,
				"tile_origin": tile_origin,
				"blocked": false
			})
		cells.append(row)
	return cells

func _build_boundary_index(tile_grid_size: Vector2i) -> Dictionary:
	var horizontal_boundaries := []
	var vertical_boundaries := []
	for i in range(1, tile_grid_size.y):
		horizontal_boundaries.append(i * MapUtils.TILE_SIZE)
	for i in range(1, tile_grid_size.x):
		vertical_boundaries.append(i * MapUtils.TILE_SIZE)
	return {
		"horizontal": horizontal_boundaries,
		"vertical": vertical_boundaries,
		"tile_size": MapUtils.TILE_SIZE,
	}

func _set_road_segment(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

func _infer_parent_anchor(footprint: Array[Vector2i]) -> Vector2i:
	if footprint == null or footprint.is_empty():
		return Vector2i.ZERO
	var minp := footprint[0]
	for p in footprint:
		minp.x = min(minp.x, p.x)
		minp.y = min(minp.y, p.y)
	return minp

func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	var anchor := _infer_parent_anchor(footprint)
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"owner": -1,
			"anchor_cell": p == anchor,
			"parent_anchor": anchor,
			"rotation": 0,
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true
		}

func _set_house_with_garden(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	var anchor := _infer_parent_anchor(footprint)
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house_with_garden",
			"owner": -1,
			"anchor_cell": p == anchor,
			"parent_anchor": anchor,
			"rotation": 0,
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": true,
			"dynamic": true
		}

func _set_house_1x1(cells: Array, house_id: String, house_number: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "house",
		"owner": -1,
		"anchor_cell": true,
		"parent_anchor": pos,
		"rotation": 0,
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true
	}

func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	var anchor := _infer_parent_anchor(footprint)
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"anchor_cell": p == anchor,
			"parent_anchor": anchor,
			"rotation": 0,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

func _apply_test_map_single_sale(state: GameState) -> void:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 3), dirs)

	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)
	_set_house_1x1(cells, "h0", 1, Vector2i(3, 2))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h0": {
				"house_id": "h0",
				"house_number": 1,
				"anchor_pos": Vector2i(3, 2),
				"cells": [Vector2i(3, 2)],
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			}
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(1, 3),
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	_invalidate_road_graph(state)

func _apply_test_map_dinnertime_sale_complex(state: GameState) -> void:
	# 注意：地图工具默认 TILE_SIZE=5（MapUtils.TILE_SIZE），因此 grid_size 必须可被 5 整除。
	# 同时 tile_route_utils 要求 grid_size/tile_grid_size 组成的 tile 为正方形。
	var grid_size := Vector2i(10, 10) # 2x2 tiles（tile=5）
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 3), dirs)

	var rest_0_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 5), Vector2i(1, 5),
	]
	_set_restaurant(cells, "rest_0", 0, rest_0_cells)

	var rest_1_cells: Array[Vector2i] = [
		Vector2i(3, 4), Vector2i(4, 4),
		Vector2i(3, 5), Vector2i(4, 5),
	]
	_set_restaurant(cells, "rest_1", 1, rest_1_cells)

	# h0: house_with_garden (3x2), touches the road line y=3 but does not overlap it.
	var h0_cells: Array[Vector2i] = [
		Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
		Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 2),
	]
	_set_house_with_garden(cells, "h0", 1, h0_cells)

	# h1/h2: normal houses (2x2)
	var h1_cells: Array[Vector2i] = [
		Vector2i(4, 1), Vector2i(5, 1),
		Vector2i(4, 2), Vector2i(5, 2),
	]
	_set_house(cells, "h1", 2, h1_cells)

	var h2_cells: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(1, 2), Vector2i(2, 2),
	]
	_set_house(cells, "h2", 3, h2_cells)

	var tile_grid_size := Vector2i(int(grid_size.x / int(MapUtils.TILE_SIZE)), int(grid_size.y / int(MapUtils.TILE_SIZE)))

	state.map = {
		"map_origin": Vector2i.ZERO,
		"grid_size": grid_size,
		"tile_grid_size": tile_grid_size,
		"cells": cells,
		"houses": {
			"h0": {"house_id": "h0", "house_number": 1, "anchor_pos": Vector2i(7, 1), "cells": h0_cells, "has_garden": true, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h1": {"house_id": "h1", "house_number": 2, "anchor_pos": Vector2i(4, 1), "cells": h1_cells, "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h2": {"house_id": "h2", "house_number": 3, "anchor_pos": Vector2i(1, 1), "cells": h2_cells, "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
		},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 4), "entrance_pos": Vector2i(0, 4), "cells": rest_0_cells},
			"rest_1": {"restaurant_id": "rest_1", "owner": 1, "anchor_pos": Vector2i(3, 4), "entrance_pos": Vector2i(3, 4), "cells": rest_1_cells},
		},
		"drink_sources": [],
		"next_house_number": 4,
		"next_restaurant_id": 2,
		"boundary_index": _build_boundary_index(tile_grid_size),
		"marketing_placements": {},
		# coffee module compatibility（route purchase provider requires coffee_shops to exist）
		"coffee_shops": {},
		"next_coffee_shop_id": 1,
	}

	state.players[0]["restaurants"] = ["rest_0"]
	if state.players.size() > 1:
		state.players[1]["restaurants"] = ["rest_1"]
	_invalidate_road_graph(state)

func _apply_test_map_pizza_sale(state: GameState) -> void:
	var grid_size := Vector2i(5, 5) # 1 tile
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)
	_set_house_1x1(cells, "h1", 1, Vector2i(2, 1))
	_set_house_1x1(cells, "h2", 2, Vector2i(3, 1))
	_set_house_1x1(cells, "h3", 3, Vector2i(4, 1))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h1": {"house_id": "h1", "house_number": 1, "anchor_pos": Vector2i(2, 1), "cells": [Vector2i(2, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h2": {"house_id": "h2", "house_number": 2, "anchor_pos": Vector2i(3, 1), "cells": [Vector2i(3, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h3": {"house_id": "h3", "house_number": 3, "anchor_pos": Vector2i(4, 1), "cells": [Vector2i(4, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
		},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 3), "entrance_pos": Vector2i(1, 2), "cells": rest_cells},
		},
		"drink_sources": [],
		"next_house_number": 4,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	_invalidate_road_graph(state)

func _apply_test_map_ketchup(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var left_house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	_set_house(cells, "house_left", 1, left_house_cells)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": left_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest0_cells,
			},
			"rest_1": {
				"restaurant_id": "rest_1",
				"owner": 1,
				"anchor_pos": Vector2i(8, 3),
				"entrance_pos": Vector2i(9, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	_invalidate_road_graph(state)

func _apply_test_map_new_restaurant_mailbox(state: GameState) -> void:
	# 10x5：用竖向道路 x=3 将地图分成左右两个 mailbox block，
	# 且确保 mailbox #5（3x2）可在 position=[0,2] 合法放置并邻接道路（x=3）。
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

	for y in range(grid_size.y):
		var dirs: Array = []
		if y > 0:
			dirs.append("N")
		if y < grid_size.y - 1:
			dirs.append("S")
		_set_road_segment(cells, Vector2i(3, y), dirs)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(8, 1), Vector2i(9, 1),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 0), "entrance_pos": Vector2i(0, 0), "cells": rest0_cells},
			"rest_1": {"restaurant_id": "rest_1", "owner": 1, "anchor_pos": Vector2i(8, 0), "entrance_pos": Vector2i(8, 0), "cells": rest1_cells},
		},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	_invalidate_road_graph(state)

func _build_billboard_map_for_demand_marked() -> Dictionary:
	var grid_size := Vector2i(3, 3)
	var cells: Array = _build_empty_cells(grid_size)

	cells[1][1]["structure"] = {
		"piece_id": "house",
		"owner": -1,
		"anchor_cell": true,
		"parent_anchor": Vector2i(1, 1),
		"rotation": 0,
		"house_id": "house_1",
		"house_number": 1,
		"has_garden": false,
		"dynamic": true
	}

	var houses := {
		"house_1": {
			"house_id": "house_1",
			"house_number": 1,
			"anchor_pos": Vector2i(1, 1),
			"cells": [Vector2i(1, 1)],
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		}
	}

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": houses,
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}
