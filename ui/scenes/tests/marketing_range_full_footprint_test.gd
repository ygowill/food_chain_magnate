# MarketingRangeOverlay regression test (no real rendering required)
# Covers issue_tracker #27: affected houses should highlight their full footprint, not only the anchor cell.
class_name MarketingRangeFullFootprintTest
extends RefCounted

const GameOverlayMarketingRangeClass = preload("res://ui/scenes/game/game_overlay_marketing_range.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

class FakeMapCanvas extends RefCounted:
	var calls: Array[Dictionary] = []

	func set_piece_overlay(id: String, cells: Array[Vector2i], style: Dictionary) -> void:
		calls.append({
			"id": id,
			"cells": cells.duplicate(),
			"style": style.duplicate(true),
		})

	func clear_piece_overlay(id: String) -> void:
		calls.append({"clear": id})

class FakeScene extends RefCounted:
	var game_engine = null

class FakeCalculator extends RefCounted:
	func get_affected_house_ids(_state: GameState, _inst: Dictionary) -> Result:
		return Result.success(["h1"])

static func run() -> Result:
	var state := GameStateClass.new()
	state.map = {
		"houses": {
			"h1": {
				"anchor_pos": Vector2i(1, 1),
				"cells": [
					Vector2i(1, 1),
					Vector2i(2, 1),
					Vector2i(1, 2),
					Vector2i(2, 2),
				],
			},
		},
	}

	var engine := GameEngineClass.new()
	engine.state = state

	var scene := FakeScene.new()
	scene.game_engine = engine

	var map_canvas := FakeMapCanvas.new()
	var controller = GameOverlayMarketingRangeClass.new(scene, map_canvas)
	controller._calculator = FakeCalculator.new()

	controller.preview_marketing_range(Vector2i(0, 0), 0, "billboard")

	if map_canvas.calls.is_empty():
		return Result.failure("expected set_piece_overlay call")
	var call0: Dictionary = map_canvas.calls[0]
	var id := str(call0.get("id", ""))
	if id != "marketing_range":
		return Result.failure("overlay id=%s (expected marketing_range)" % id)

	var cells_val = call0.get("cells", null)
	if not (cells_val is Array):
		return Result.failure("cells type invalid: %s" % str(typeof(cells_val)))
	var cells: Array = cells_val
	if cells.size() != 4:
		return Result.failure("cells.size=%d (expected 4) cells=%s" % [cells.size(), str(cells)])

	var set := {}
	for v in cells:
		if v is Vector2i:
			set[v] = true
	for expected in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		if not set.has(expected):
			return Result.failure("missing cell %s in %s" % [str(expected), str(cells)])

	return Result.success({})

