# Marketing placement highlights regression test (no real rendering required)
# Covers issue_tracker #35: marketing pieces must not be placeable on top of drink_source cells,
# and "valid anchors" highlights should exclude such positions.
class_name MarketingHighlightsNoDrinkSourceTest
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")

class FakeMapCanvas extends RefCounted:
	var highlighted: Array[Vector2i] = []

	func clear_cell_highlights() -> void:
		highlighted.clear()

	func set_cell_highlights(cells: Array) -> void:
		highlighted.clear()
		for v in cells:
			if v is Vector2i:
				highlighted.append(v)

class FakeScene extends RefCounted:
	var game_engine = null

static func run() -> Result:
	var engine := GameEngineClass.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, engine)

	var state: GameState = engine.get_state()
	if state == null:
		return _finish(Result.failure("无法获取 GameState"), null, engine)

	state.map = _build_empty_map_with_drink_source(Vector2i(3, 3), Vector2i(0, 0))
	# Provide a road so non-edge marketing (e.g. radio) has at least one valid adjacent-to-road anchor.
	var cells: Array = state.map.get("cells", [])
	if cells is Array and cells.size() >= 1 and cells[0] is Array and (cells[0] as Array).size() >= 2:
		var road_cell: Dictionary = cells[0][1]
		road_cell["road_segments"] = [{"dirs": ["N", "S"], "bridge": false}]
		(cells[0] as Array)[1] = road_cell
		state.map["cells"] = cells

	var scene := FakeScene.new()
	scene.game_engine = engine

	var map_canvas := FakeMapCanvas.new()
	var controller := GameMapInteractionControllerClass.new(scene, map_canvas, null)

	# radio(#1) footprint is 1x1; anchor at (0,0) would cover the drink_source at (0,0) and must be excluded.
	controller.on_marketing_map_selection_requested("radio", "brand_director", 1, 0)

	var set := {}
	for v in map_canvas.highlighted:
		set[v] = true

	if set.has(Vector2i(0, 0)):
		return _finish(Result.failure("highlights should exclude anchors that cover drink_source (found (0,0))"), controller, engine)
	if not set.has(Vector2i(1, 1)):
		return _finish(Result.failure("expected at least one valid anchor (e.g. (1,1))"), controller, engine)

	return _finish(Result.success({}), controller, engine)

static func _finish(result: Result, controller, engine) -> Result:
	if controller != null and is_instance_valid(controller) and controller.has_method("dispose"):
		controller.dispose()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result

static func _build_empty_map_with_drink_source(grid_size: Vector2i, drink_pos: Vector2i) -> Dictionary:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false,
			})
		cells.append(row)

	# Add drink source in both list form (rules/UI) and cell field (rendering).
	var drink_sources := [{"world_pos": drink_pos, "type": "soda"}]
	var cell: Dictionary = cells[drink_pos.y][drink_pos.x]
	cell["drink_source"] = {"type": "soda"}
	cells[drink_pos.y][drink_pos.x] = cell

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"map_origin": Vector2i.ZERO,
		"cells": cells,
		"houses": {},
		"restaurants": {},
		"drink_sources": drink_sources,
		"boundary_index": {},
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"marketing_placements": {},
		"external_cells": {},
		"external_tile_placements": [],
	}
