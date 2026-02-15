# Restructuring UI regression test:
# Dropping cards back to reserve should work anywhere within the reserve section area.
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

	if not is_instance_valid(ha.reserve_section):
		_safe_free(hand)
		return Result.failure("HandArea.reserve_section 未找到")

	# In restructuring, reserve section should be a drop target for reserve.
	if not ha.reserve_section.is_in_group("employee_card_drop_target"):
		_safe_free(hand)
		return Result.failure("reserve_section 未加入 employee_card_drop_target")
	if not ha.reserve_section.is_in_group("hand_area_reserve_drop_target"):
		_safe_free(hand)
		return Result.failure("reserve_section 未加入 hand_area_reserve_drop_target")

	# Scroll container should not be treated as a reserve drop target, otherwise dropping on active may be misrouted.
	if is_instance_valid(ha.scroll_container) and ha.scroll_container.is_in_group("hand_area_reserve_drop_target"):
		_safe_free(hand)
		return Result.failure("scroll_container 不应加入 hand_area_reserve_drop_target（避免误判 active 区为 reserve）")

	# Active container should remain a valid drop target (dropping here moves back to active).
	if not is_instance_valid(ha.active_container) or not ha.active_container.is_in_group("employee_card_drop_target"):
		_safe_free(hand)
		return Result.failure("active_container 应是 drop target（重组模式）")

	# Reserve container remains a valid drop target.
	if not is_instance_valid(ha.reserve_container) or not ha.reserve_container.is_in_group("employee_card_drop_target"):
		_safe_free(hand)
		return Result.failure("reserve_container 应是 drop target")

	_safe_free(hand)
	return Result.success({})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
