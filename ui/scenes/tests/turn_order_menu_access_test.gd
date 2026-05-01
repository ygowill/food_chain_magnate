class_name TurnOrderMenuAccessTest
extends RefCounted

const GamePanelModalsControllerClass = preload("res://ui/scenes/game/panel/modals_controller.gd")

static func run() -> Result:
	var controller = GamePanelModalsControllerClass.new(null, Callable())
	if not controller.has_method("has_menu_blocking_modal_ui"):
		return Result.failure("GamePanelModalsController 缺少 has_menu_blocking_modal_ui")

	var turn_order := Control.new()
	turn_order.visible = true
	controller.set("_turn_order_modal", turn_order)
	if not bool(controller.has_open_modal_ui()):
		_safe_free(turn_order)
		return Result.failure("顺位选择弹窗可见时 has_open_modal_ui 应为 true")
	if bool(controller.has_menu_blocking_modal_ui()):
		_safe_free(turn_order)
		return Result.failure("顺位选择弹窗不应阻止打开游戏菜单")

	var reserve := Control.new()
	reserve.visible = true
	controller.set("_reserve_card_modal", reserve)
	if not bool(controller.has_menu_blocking_modal_ui()):
		_safe_free(turn_order)
		_safe_free(reserve)
		return Result.failure("储备卡弹窗仍应阻止打开游戏菜单")

	_safe_free(turn_order)
	_safe_free(reserve)
	return Result.success({})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
