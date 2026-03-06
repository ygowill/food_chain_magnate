# RoundState：order_of_business 读写工具（Fail Fast）
class_name RoundStateOrderOfBusiness
extends RefCounted

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func require_order_of_business(round_state: Dictionary, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if not round_state.has("order_of_business") or not (round_state["order_of_business"] is Dictionary):
		return Result.failure("%sround_state.order_of_business 缺失或类型错误（期望 Dictionary）" % prefix)
	return Result.success(round_state["order_of_business"])

static func require_finalized(order_of_business: Dictionary, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not order_of_business.has("finalized") or not (order_of_business["finalized"] is bool):
		return Result.failure("%sround_state.order_of_business.finalized 缺失或类型错误（期望 bool）" % prefix)
	return Result.success(bool(order_of_business["finalized"]))

static func require_picks(order_of_business: Dictionary, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not order_of_business.has("picks") or not (order_of_business["picks"] is Array):
		return Result.failure("%sround_state.order_of_business.picks 缺失或类型错误（期望 Array）" % prefix)
	return Result.success(order_of_business["picks"])

static func require_previous_turn_order(order_of_business: Dictionary, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not order_of_business.has("previous_turn_order") or not (order_of_business["previous_turn_order"] is Array):
		return Result.failure("%sround_state.order_of_business.previous_turn_order 缺失或类型错误（期望 Array）" % prefix)
	return Result.success(order_of_business["previous_turn_order"])
