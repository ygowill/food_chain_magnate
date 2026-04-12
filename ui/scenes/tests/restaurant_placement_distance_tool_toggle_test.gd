# restaurant placement：允许临时切换到距离工具，并可恢复放置模式
class_name RestaurantPlacementDistanceToolToggleTest
extends RefCounted

const GameMapInteractionControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")
const RestaurantPlacementOverlayClass = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.gd")

class FakeMapCanvas extends RefCounted:
	func clear_cell_highlights() -> void:
		pass

	func clear_move_restaurant_selected_restaurant() -> void:
		pass

	func clear_structure_preview() -> void:
		pass

	func clear_piece_overlay(_overlay_id: String) -> void:
		pass

	func set_piece_overlay(_overlay_id: String, _cells: Array, _style: Dictionary) -> void:
		pass

static func run() -> Result:
	var controller = null
	var overlay = null

	controller = GameMapInteractionControllerClass.new(null, FakeMapCanvas.new(), null)
	overlay = RestaurantPlacementOverlayClass.new()
	overlay.visible = true
	overlay.set_mode("place_restaurant")
	overlay.set_selected_rotation(90)
	overlay.set_selected_position(Vector2i(2, 3))
	controller.set_restaurant_placement_overlay(overlay)

	controller.begin_selection("restaurant_placement", {"action_id": "place_restaurant"})
	controller.toggle_distance_tool()

	if str(controller.get_mode()) != "distance_tool":
		return _finish(Result.failure("餐厅放置阶段应允许切换到距离工具，实际 mode=%s" % str(controller.get_mode())), controller, overlay)

	controller.toggle_distance_tool()

	if str(controller.get_mode()) != "restaurant_placement":
		return _finish(Result.failure("关闭距离工具后应恢复餐厅放置模式，实际 mode=%s" % str(controller.get_mode())), controller, overlay)

	var payload_val = controller.get("_payload")
	var payload: Dictionary = Dictionary(payload_val) if payload_val is Dictionary else {}
	if str(payload.get("action_id", "")).strip_edges() != "place_restaurant":
		return _finish(Result.failure("恢复放置模式后 action_id 丢失: %s" % str(payload)), controller, overlay)

	return _finish(Result.success({}), controller, overlay)

static func _finish(result: Result, controller, overlay) -> Result:
	if overlay != null and is_instance_valid(overlay):
		overlay.free()
	if controller != null and is_instance_valid(controller) and controller.has_method("dispose"):
		controller.dispose()
	return result
