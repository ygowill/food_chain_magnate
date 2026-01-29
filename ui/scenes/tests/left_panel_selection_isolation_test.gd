# LeftPanel：玩家选择仅影响左侧展示，不应作为全局“view_player”控制入口。
# 回归：避免选择左侧玩家导致 ActionPanel 可用动作变化。
extends RefCounted

const LeftPanelClass = preload("res://ui/components/left_panel/left_panel.gd")

static func run() -> Result:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

	var panel = LeftPanelClass.new()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 LeftPanel 失败")

	# 左侧面板只做信息展示：不应向外暴露“切换全局玩家视角”的信号入口。
	if panel.has_signal("player_selected"):
		if is_instance_valid(panel):
			panel.free()
		return Result.failure("LeftPanel 不应暴露 player_selected 信号（应仅做信息展示）")

	# 最小 GameState：只需要 players 数量用于 view_player 校验。
	var state := GameState.new()
	state.players = [{}, {}]
	state.turn_order = [0, 1]
	state.current_player_index = 0

	panel._game_state = state
	panel.set_current_player(0)
	panel.set_view_player(1)

	if panel._resolve_view_player_id() != 1:
		if is_instance_valid(panel):
			panel.free()
		return Result.failure("LeftPanel view_player 未正确切换到 1")

	if is_instance_valid(panel):
		panel.free()
	return Result.success()

