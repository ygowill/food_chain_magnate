# ActionPanel：联机模式下始终以本地玩家为上下文（避免显示他人动作导致误导/无法继续）
extends RefCounted

const ActionPanelClass = preload("res://ui/components/action_panel/action_panel.gd")

static func run() -> Result:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

	# Online：set_current_player 应忽略传入的 current_player_id，固定到 local_player_id。
	if NetContext != null:
		NetContext.mode = NetContext.Mode.ONLINE_CLIENT
		NetContext.local_player_id = 1

	var panel = ActionPanelClass.new()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 ActionPanel 失败")

	panel.set_current_player(0)
	var pid := int(panel.get("_current_player_id"))
	if pid != 1:
		_safe_free(panel)
		return Result.failure("联机模式下 ActionPanel 应使用 local_player_id=1，但得到 %d" % pid)

	_safe_free(panel)

	# Hotseat：应按传入的 current_player_id 工作。
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

	var panel2 = ActionPanelClass.new()
	if panel2 == null or not is_instance_valid(panel2):
		return Result.failure("实例化 ActionPanel 失败（case2）")
	panel2.set_current_player(0)
	var pid2 := int(panel2.get("_current_player_id"))
	if pid2 != 0:
		_safe_free(panel2)
		return Result.failure("Hotseat 下 ActionPanel 应使用传入 player_id=0，但得到 %d" % pid2)

	_safe_free(panel2)
	return Result.success()

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()

