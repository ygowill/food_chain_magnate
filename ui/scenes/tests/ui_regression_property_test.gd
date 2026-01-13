# UI 回归属性测试（无需渲染）
# 覆盖 issue_tracker 中若干“可用静态属性断言”的修复点，避免回归后只能靠手动点。
class_name UiRegressionPropertyTest
extends RefCounted

const MapModeBarScene = preload("res://ui/components/map_mode_bar/map_mode_bar.tscn")
const PlayerInfoItemClass = preload("res://ui/components/player_panel/player_info_item.gd")

static func run() -> Result:
	var r1 := _test_map_mode_bar_mouse_filter()
	if not r1.ok:
		return r1

	var r2 := _test_player_info_item_mouse_filter()
	if not r2.ok:
		return r2

	return Result.success({
		"map_mode_bar_mouse_filter_ok": true,
		"player_info_item_mouse_filter_ok": true,
	})

static func _test_map_mode_bar_mouse_filter() -> Result:
	var bar = MapModeBarScene.instantiate()
	var expected := Control.MOUSE_FILTER_IGNORE
	var paths := [
		".",
		"TopSpacer",
		"Bar",
		"Bar/MarginContainer",
		"Bar/MarginContainer/VBoxContainer",
		"Bar/MarginContainer/VBoxContainer/TitleLabel",
		"Bar/MarginContainer/VBoxContainer/HintLabel",
	]

	for p in paths:
		var node = bar if p == "." else bar.get_node_or_null(p)
		if node == null or not is_instance_valid(node):
			var fail := Result.failure("MapModeBar 缺少节点: %s" % p)
			_safe_free(bar)
			return fail
		if not (node is Control):
			var fail2 := Result.failure("MapModeBar 节点类型错误（期望 Control）: %s" % p)
			_safe_free(bar)
			return fail2
		var c: Control = node
		if c.mouse_filter != expected:
			var fail3 := Result.failure("MapModeBar.%s mouse_filter=%d (期望 %d IGNORE)" % [p, c.mouse_filter, expected])
			_safe_free(bar)
			return fail3

	_safe_free(bar)
	return Result.success()

static func _test_player_info_item_mouse_filter() -> Result:
	var item = PlayerInfoItemClass.new()
	if item == null or not is_instance_valid(item):
		return Result.failure("无法创建 PlayerInfoItem")

	# 直接构建 UI（不依赖 SceneTree）
	if item.has_method("_build_ui"):
		item.call("_build_ui")
	else:
		return Result.failure("PlayerInfoItem 缺少 _build_ui()")

	var expected := Control.MOUSE_FILTER_IGNORE
	var nodes := [
		"HBoxContainer",
		"HBoxContainer/ColorRect",
		"HBoxContainer/NameLabel",
		"HBoxContainer/CashLabel",
		"HBoxContainer/EmployeeLabel",
		"HBoxContainer/RestaurantLabel",
	]

	for p in nodes:
		var node2 = item.get_node_or_null(p)
		if node2 == null or not is_instance_valid(node2):
			var fail := Result.failure("PlayerInfoItem 缺少节点: %s" % p)
			_safe_free(item)
			return fail
		if not (node2 is Control):
			var fail2 := Result.failure("PlayerInfoItem 节点类型错误（期望 Control）: %s" % p)
			_safe_free(item)
			return fail2
		var c2: Control = node2
		if c2.mouse_filter != expected:
			var fail3 := Result.failure("PlayerInfoItem.%s mouse_filter=%d (期望 %d IGNORE)" % [p, c2.mouse_filter, expected])
			_safe_free(item)
			return fail3

	_safe_free(item)
	return Result.success()

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
