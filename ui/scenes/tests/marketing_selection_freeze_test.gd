# Marketing placement preview should lock after click selection.
# Covers issue_tracker #43.
class_name MarketingSelectionFreezeTest
extends RefCounted

const GameMapInteractionControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")

class FakeMapCanvas extends RefCounted:
	var preview_calls: int = 0
	var clear_preview_calls: int = 0

	func set_structure_preview(cells: Array, ok: bool, preview_info: Dictionary = {}) -> void:
		preview_calls += 1

	func clear_structure_preview() -> void:
		clear_preview_calls += 1

class FakeOverlayController extends RefCounted:
	var preview_calls: int = 0
	var hide_calls: int = 0

	func preview_marketing_range(anchor: Vector2i, rotation: int, marketing_type: String, extra: Dictionary = {}) -> void:
		preview_calls += 1

	func hide_marketing_range_overlay() -> void:
		hide_calls += 1

static func run() -> Result:
	var map_canvas := FakeMapCanvas.new()
	var overlay := FakeOverlayController.new()
	var controller := GameMapInteractionControllerClass.new(null, map_canvas, overlay)

	controller.begin_selection("marketing", {
		"marketing_type": "radio",
		"employee_type": "brand_director",
		"board_number": 1,
		"rotation": 0,
	})

	# Provide a minimal valid-anchors set so the preview code runs.
	controller._marketing_valid_anchors[Vector2i(0, 0)] = true
	controller._marketing_valid_anchors[Vector2i(1, 0)] = true

	controller._on_map_cell_hovered(Vector2i(0, 0))
	if map_canvas.preview_calls <= 0:
		return Result.failure("expected hover to call set_structure_preview at least once")
	if overlay.preview_calls <= 0:
		return Result.failure("expected hover to call preview_marketing_range at least once")

	# Click locks selection and prevents further hover updates.
	controller._on_map_cell_selected(Vector2i(0, 0))
	var selected_val = controller._payload.get("selected_target", null)
	if not (selected_val is Vector2i) or Vector2i(selected_val) != Vector2i(0, 0):
		return Result.failure("expected _payload.selected_target to be set after click")

	var preview_calls_after_click := map_canvas.preview_calls
	var range_calls_after_click := overlay.preview_calls
	var clear_calls_after_click := map_canvas.clear_preview_calls

	controller._on_map_cell_hovered(Vector2i(1, 0))
	controller._on_map_cell_hovered(Vector2i(-1, -1))
	if map_canvas.preview_calls != preview_calls_after_click:
		return Result.failure("hover should not move preview after selection is locked")
	if overlay.preview_calls != range_calls_after_click:
		return Result.failure("hover should not update range after selection is locked")
	if map_canvas.clear_preview_calls != clear_calls_after_click:
		return Result.failure("hover(-1,-1) should not clear preview after selection is locked")

	# Clicking another valid point should allow changing selection and update preview again.
	controller._on_map_cell_selected(Vector2i(1, 0))
	var selected_val2 = controller._payload.get("selected_target", null)
	if not (selected_val2 is Vector2i) or Vector2i(selected_val2) != Vector2i(1, 0):
		return Result.failure("expected _payload.selected_target to update on second click")
	if map_canvas.preview_calls <= preview_calls_after_click:
		return Result.failure("expected clicking a new target to refresh the preview")
	if overlay.preview_calls <= range_calls_after_click:
		return Result.failure("expected clicking a new target to refresh the range overlay")

	return Result.success({})

