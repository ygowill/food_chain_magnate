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

	panel.set_game_state(state)
	var ids: Array[String] = []
	if panel.has_method("get_visible_action_ids"):
		ids = Array(panel.call("get_visible_action_ids"), TYPE_STRING, "", null)
	if ids.is_empty():
		_safe_free(panel)
		return Result.failure("ActionPanel 未计算出任何可见动作")
	if not _any_action_enabled(panel, ids):
		_safe_free(panel)
		return Result.failure("初始状态应至少有一个动作 enabled")

	panel.set_globally_disabled("联机：等待其他玩家操作")
	if _any_action_enabled(panel, ids):
		_safe_free(panel)
		return Result.failure("全局禁用后动作应全部 disabled")

	panel.set_globally_disabled("")
	if not _any_action_enabled(panel, ids):
		_safe_free(panel)
		return Result.failure("解除全局禁用后应恢复动作 enabled（避免联机回合交接卡死）")

	_safe_free(panel)
	return Result.success()

static func _any_action_enabled(panel: Object, action_ids: Array[String]) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	if not panel.has_method("get_action_enabled"):
		return false
	for aid in action_ids:
		if bool(panel.call("get_action_enabled", str(aid))):
			return true
	return false

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
