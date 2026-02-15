# Restructuring UI regression test:
# Dropping cards back to reserve should work anywhere within the reserve scroll area.
# Covers issue_tracker #46.
class_name RestructuringReserveDropTargetTest
extends RefCounted

const HandAreaScene = preload("res://ui/components/hand_area/hand_area.tscn")

static func run() -> Result:
	var hand = HandAreaScene.instantiate()
	if hand == null or not is_instance_valid(hand):
		return Result.failure("无法实例化 HandAreaScene")

	if hand.has_method("_ready"):
		hand.call("_ready")

	var ha: HandArea = hand
	ha.set_display_mode("restructuring")

	if not is_instance_valid(ha.scroll_container):
		_safe_free(hand)
		return Result.failure("HandArea.scroll_container 未找到")

	# In restructuring, the scroll area should be a drop target for reserve.
	if not ha.scroll_container.is_in_group("employee_card_drop_target"):
		_safe_free(hand)
		return Result.failure("scroll_container 未加入 employee_card_drop_target")
	if not ha.scroll_container.is_in_group("hand_area_reserve_drop_target"):
		_safe_free(hand)
		return Result.failure("scroll_container 未加入 hand_area_reserve_drop_target")

	# Active container is hidden in restructuring and must not be a drop target.
	if is_instance_valid(ha.active_container) and ha.active_container.is_in_group("employee_card_drop_target"):
		_safe_free(hand)
		return Result.failure("active_container 在重组模式下不应是 drop target")

	# Reserve container remains a valid drop target.
	if not is_instance_valid(ha.reserve_container) or not ha.reserve_container.is_in_group("employee_card_drop_target"):
		_safe_free(hand)
		return Result.failure("reserve_container 应是 drop target")

	_safe_free(hand)
	return Result.success({})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
