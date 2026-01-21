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
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("无法获取 GameState")

	state.map = _build_empty_map_with_drink_source(Vector2i(3, 3), Vector2i(0, 0))

	var scene := FakeScene.new()
	scene.game_engine = engine

	var map_canvas := FakeMapCanvas.new()
	var controller := GameMapInteractionControllerClass.new(scene, map_canvas, null)

	# airplane(#4) footprint is 1x2; anchor at (0,0) would cover the drink_source at (0,0).
	controller.on_marketing_map_selection_requested("airplane", "brand_manager", 4, 0)

	var set := {}
	for v in map_canvas.highlighted:
		set[v] = true

	# Airplane selectable points are outside the map (issue_tracker #38). For left edge anchors the clickable
	# positions are on x=-1. Anchor (0,0) would overlap drink_source -> should be excluded.
	if set.has(Vector2i(-1, 0)):
		return Result.failure("highlights should exclude anchors that cover drink_source (found outside (-1,0))")
	if not set.has(Vector2i(-1, 1)):
		return Result.failure("expected at least one valid outside anchor (e.g. (-1,1))")

	return Result.success({})

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
