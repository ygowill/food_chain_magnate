# airplane marketing outside-ring selection regression test (no real rendering required)
# Covers issue_tracker #38: airplane marketing selectable points should be outside the map ring and clicking them
# should map back to the correct inside anchor for command execution.
class_name AirplaneMarketingOutsideSelectionTest
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")

class FakeMapCanvas extends RefCounted:
	var highlighted: Array[Vector2i] = []

	func clear_cell_highlights() -> void:
		highlighted.clear()

	func set_cell_highlights(cells: Array) -> void:
		highlighted.clear()
		for v in cells:
			if v is Vector2i:
				highlighted.append(v)

	func clear_structure_preview() -> void:
		pass

	func set_structure_preview(_cells: Array, _valid: bool, _preview_info: Dictionary = {}) -> void:
		pass

class FakeScene extends RefCounted:
	var game_engine = null

class FakeMarketingPanel extends Control:
	var last_target: Vector2i = Vector2i(-999, -999)
	var last_axis: String = ""

	func set_selected_target(pos: Vector2i, axis: String = "") -> void:
		last_target = pos
		last_axis = axis

	func set_error(_msg: String) -> void:
		pass

static func run() -> Result:
	var engine := GameEngineClass.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, null, engine)

	var scene := FakeScene.new()
	scene.game_engine = engine

	var map_canvas := FakeMapCanvas.new()
	var controller := GameMapInteractionControllerClass.new(scene, map_canvas, null)

	var panel := FakeMarketingPanel.new()
	panel.visible = true
	controller.set_marketing_panel(panel)

	# Begin airplane selection. Highlights should be outside (e.g. x=-1 on left edge).
	controller.on_marketing_map_selection_requested("airplane", "brand_manager", 4, 0)

	var state: GameState = engine.get_state()
	if state == null or not (state.map is Dictionary):
		return _finish(Result.failure("expected non-null GameState with map"), panel, controller, engine)
	var map_origin: Vector2i = state.map.get("map_origin", Vector2i.ZERO)
	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var minp := -map_origin
	var maxp := Vector2i(grid_size.x - map_origin.x - 1, grid_size.y - map_origin.y - 1)

	var has_outside := false
	for v in map_canvas.highlighted:
		if v.x == minp.x - 1 or v.y == minp.y - 1 or v.x == maxp.x + 1 or v.y == maxp.y + 1:
			has_outside = true
			break
	if not has_outside:
		return _finish(Result.failure("expected at least one outside-ring highlight for airplane selection"), panel, controller, engine)

	# Pick a specific outside position and verify it maps back to an inside anchor (x>=0,y>=0).
	var pick := Vector2i(-1, 0)
	# Avoid corners (corner selection opens an axis dialog). Prefer a non-corner outside highlight if present.
	for v in map_canvas.highlighted:
		if not (v is Vector2i):
			continue
		if v == Vector2i(-1, -1):
			continue
		var map_val = controller.get("_marketing_outside_to_anchor")
		if map_val is Dictionary and (map_val as Dictionary).has(v):
			var inside_val = (map_val as Dictionary).get(v, null)
			if inside_val is Vector2i:
				var inside: Vector2i = inside_val
				# Non-corner: only one edge coordinate should be outside the base map edge.
				# Here we use a simple heuristic: prefer inside anchors not at (0,0).
				if inside != Vector2i(0, 0):
					pick = v
					break

	# Prefer a right/bottom outside selection if present (regression for issue_tracker #40).
	for v in map_canvas.highlighted:
		if not (v is Vector2i):
			continue
		if not (v.x == maxp.x + 1 or v.y == maxp.y + 1):
			continue
		var map_val2 = controller.get("_marketing_outside_to_anchor")
		if map_val2 is Dictionary and (map_val2 as Dictionary).has(v):
			var inside_val2 = (map_val2 as Dictionary).get(v, null)
			if inside_val2 is Vector2i:
				pick = v
				break

	controller.call("_on_map_cell_selected", pick)

	var mapped := panel.last_target
	if mapped.x < 0 or mapped.y < 0:
		return _finish(Result.failure("outside click %s should map to inside anchor, got %s" % [str(pick), str(mapped)]), panel, controller, engine)

	return _finish(Result.success({}), panel, controller, engine)

static func _finish(result: Result, panel, controller, engine) -> Result:
	_safe_free(panel)
	if controller != null and is_instance_valid(controller) and controller.has_method("dispose"):
		controller.dispose()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
