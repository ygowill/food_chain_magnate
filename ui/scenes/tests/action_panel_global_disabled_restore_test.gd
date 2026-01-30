# ActionPanel：从“全局禁用”恢复时应重算按钮 enabled 状态（联机回合交接不会卡死）
class_name ActionPanelGlobalDisabledRestoreTest
extends RefCounted

const ActionPanelClass = preload("res://ui/components/action_panel/action_panel.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")

static func run() -> Result:
	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345)
	if not init_r.ok:
		return Result.failure("GameEngine.initialize 失败: %s" % init_r.error)
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var panel = ActionPanelClass.new()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 ActionPanel 失败")

	# 不挂载到场景树：手动注入 items_container，确保 refresh() 能构建按钮。
	var items := VBoxContainer.new()
	panel.add_child(items)
	panel.set("items_container", items)

	panel.set_game_state(state)
	var buttons_val = panel.get("_action_buttons")
	if not (buttons_val is Dictionary):
		_safe_free(panel)
		return Result.failure("_action_buttons 类型错误（期望 Dictionary）")
	var buttons: Dictionary = buttons_val
	if buttons.is_empty():
		_safe_free(panel)
		return Result.failure("ActionPanel 未构建任何按钮")
	if not _any_button_enabled(buttons):
		_safe_free(panel)
		return Result.failure("初始状态应至少有一个按钮 enabled")

	panel.set_globally_disabled("联机：等待其他玩家操作")
	buttons_val = panel.get("_action_buttons")
	buttons = buttons_val if (buttons_val is Dictionary) else {}
	if _any_button_enabled(buttons):
		_safe_free(panel)
		return Result.failure("全局禁用后按钮应全部 disabled")

	panel.set_globally_disabled("")
	buttons_val = panel.get("_action_buttons")
	buttons = buttons_val if (buttons_val is Dictionary) else {}
	if not _any_button_enabled(buttons):
		_safe_free(panel)
		return Result.failure("解除全局禁用后应恢复按钮 enabled（避免联机回合交接卡死）")

	_safe_free(panel)
	return Result.success()

static func _any_button_enabled(buttons: Dictionary) -> bool:
	for btn_val in buttons.values():
		if not is_instance_valid(btn_val):
			continue
		if btn_val is Button:
			var btn: Button = btn_val
			if not btn.disabled:
				return true
	return false

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()

