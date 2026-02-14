# Placement overlays：取消按钮在压平动作流中不应清空 ActionPanel 上下文
# 覆盖回归：放置/选点模式点击“取消”后，动作面板不应变空白。
class_name PlacementOverlayCancelResetsTest
extends RefCounted

const RestaurantPlacementOverlayClass = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.gd")
const HousePlacementOverlayClass = preload("res://ui/components/house_placement/house_placement_overlay.gd")
const PiecePlacementOverlayClass = preload("res://ui/components/piece_placement/piece_placement_overlay.gd")

static func run() -> Result:
	var r1 := _case_restaurant()
	if not r1.ok:
		return r1
	var r2 := _case_house()
	if not r2.ok:
		return r2
	var r3 := _case_piece()
	if not r3.ok:
		return r3
	return Result.success({})

static func _case_restaurant() -> Result:
	var ov = RestaurantPlacementOverlayClass.new()
	ov.visible = true
	ov.set_mode("place_restaurant")
	ov.set_selected_rotation(90)
	ov.set_selected_position(Vector2i(1, 2))

	if not _assert_spec_does_not_clear_on_cancel(ov):
		_safe_free(ov)
		return Result.failure("restaurant: spec 缺少 clear_on_cancel=false")
	if not ov.can_confirm():
		_safe_free(ov)
		return Result.failure("restaurant: 预期 can_confirm=true（测试前置条件失败）")

	ov.request_cancel()

	if not ov.visible:
		_safe_free(ov)
		return Result.failure("restaurant: request_cancel 不应隐藏 overlay（否则 ActionPanel 上下文会被清空）")
	if ov.can_confirm():
		_safe_free(ov)
		return Result.failure("restaurant: request_cancel 后 can_confirm 应为 false（位置应被重置）")
	if ov.get_selected_position() != Vector2i(-1, -1):
		_safe_free(ov)
		return Result.failure("restaurant: request_cancel 后 position 未重置: %s" % str(ov.get_selected_position()))
	if ov.get_selected_rotation() != 0:
		_safe_free(ov)
		return Result.failure("restaurant: request_cancel 后 rotation 未重置: %s" % str(ov.get_selected_rotation()))

	_safe_free(ov)
	return Result.success({})

static func _case_house() -> Result:
	var ov = HousePlacementOverlayClass.new()
	ov.visible = true
	ov.set_mode("place_house")
	ov.set_selected_house_number(1)
	ov.set_selected_rotation(90)
	ov.set_selected_position(Vector2i(1, 2))

	if not _assert_spec_does_not_clear_on_cancel(ov):
		_safe_free(ov)
		return Result.failure("house: spec 缺少 clear_on_cancel=false")
	if not ov.can_confirm():
		_safe_free(ov)
		return Result.failure("house: 预期 can_confirm=true（测试前置条件失败）")

	ov.request_cancel()

	if not ov.visible:
		_safe_free(ov)
		return Result.failure("house: request_cancel 不应隐藏 overlay（否则 ActionPanel 上下文会被清空）")
	if ov.can_confirm():
		_safe_free(ov)
		return Result.failure("house: request_cancel 后 can_confirm 应为 false（选点应被重置）")
	if ov.get_selected_rotation() != 0:
		_safe_free(ov)
		return Result.failure("house: request_cancel 后 rotation 未重置: %s" % str(ov.get_selected_rotation()))
	if ov.get_selected_house_number() != -1:
		_safe_free(ov)
		return Result.failure("house: request_cancel 后 house_number 未重置: %s" % str(ov.get_selected_house_number()))

	_safe_free(ov)
	return Result.success({})

static func _case_piece() -> Result:
	var ov = PiecePlacementOverlayClass.new()
	ov.visible = true
	ov.set_mode("place_lobbyists_road")
	ov.set_available_pieces(["lobbyists_road"])
	ov.set_selected_rotation(90)
	ov.set_selected_position(Vector2i(1, 2))

	if not _assert_spec_does_not_clear_on_cancel(ov):
		_safe_free(ov)
		return Result.failure("piece: spec 缺少 clear_on_cancel=false")
	if not ov.can_confirm():
		_safe_free(ov)
		return Result.failure("piece: 预期 can_confirm=true（测试前置条件失败）")

	ov.request_cancel()

	if not ov.visible:
		_safe_free(ov)
		return Result.failure("piece: request_cancel 不应隐藏 overlay（否则 ActionPanel 上下文会被清空）")
	if ov.can_confirm():
		_safe_free(ov)
		return Result.failure("piece: request_cancel 后 can_confirm 应为 false（选点应被重置）")
	if ov.get_selected_position() != Vector2i(-1, -1):
		_safe_free(ov)
		return Result.failure("piece: request_cancel 后 position 未重置: %s" % str(ov.get_selected_position()))
	if ov.get_selected_rotation() != 0:
		_safe_free(ov)
		return Result.failure("piece: request_cancel 后 rotation 未重置: %s" % str(ov.get_selected_rotation()))

	_safe_free(ov)
	return Result.success({})

static func _assert_spec_does_not_clear_on_cancel(overlay: Object) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	if not overlay.has_method("get_action_panel_context_spec"):
		return false
	var spec_val = overlay.call("get_action_panel_context_spec")
	if not (spec_val is Dictionary):
		return false
	var spec: Dictionary = spec_val
	return not bool(spec.get("clear_on_cancel", true))

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()

