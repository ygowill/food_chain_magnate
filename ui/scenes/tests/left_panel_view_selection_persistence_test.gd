extends RefCounted

const LeftPanelScene: PackedScene = preload("res://ui/components/left_panel/left_panel.tscn")

static func run() -> Result:
	var prev_mode = NetContext.mode if NetContext != null else 0
	var prev_local_player_id := int(NetContext.local_player_id) if NetContext != null else -1

	if NetContext != null:
		NetContext.mode = NetContext.Mode.HOTSEAT
		NetContext.local_player_id = -1

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return await _finish(Result.failure("SceneTree.root 不可用"), null, prev_mode, prev_local_player_id)
	if LeftPanelScene == null:
		return await _finish(Result.failure("LeftPanelScene preload 失败"), null, prev_mode, prev_local_player_id)

	var panel = LeftPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return await _finish(Result.failure("实例化 LeftPanel 失败"), null, prev_mode, prev_local_player_id)
	tree.root.add_child(panel)
	await tree.process_frame

	var state1 := _build_state(10, 20)
	panel.call("set_display_context", state1, 0, 0)
	await tree.process_frame
	panel.call("set_view_player", 1)
	await tree.process_frame

	if int(panel.call("_resolve_view_player_id")) != 1:
		return await _finish(Result.failure("手动切换后 LeftPanel 应查看玩家 1"), panel, prev_mode, prev_local_player_id)

	var state2 := _build_state(11, 21)
	panel.call("set_display_context", state2, 1, 1)
	await tree.process_frame

	if int(panel.call("_resolve_view_player_id")) != 1:
		return await _finish(Result.failure("时间线/回放刷新后 LeftPanel 选择不应被重置"), panel, prev_mode, prev_local_player_id)

	var player_name_label = panel.get("player_name_label")
	if player_name_label == null or not is_instance_valid(player_name_label):
		return await _finish(Result.failure("未找到 player_name_label"), panel, prev_mode, prev_local_player_id)
	var player_name_text := str(player_name_label.text).replace(" ", "")
	if player_name_text.find("玩家2") == -1:
		return await _finish(Result.failure("刷新后摘要仍应显示玩家2，实际=%s" % str(player_name_label.text)), panel, prev_mode, prev_local_player_id)

	return await _finish(Result.success({}), panel, prev_mode, prev_local_player_id)

static func _build_state(cash0: int, cash1: int) -> GameState:
	var state := GameState.new()
	state.players = [
		{
			"id": 0,
			"cash": int(cash0),
			"employees": ["ceo"],
			"reserve_employees": [],
			"busy_marketers": [],
			"inventory": {},
			"milestones": [],
			"restaurants": [],
			"forfeited": false,
		},
		{
			"id": 1,
			"cash": int(cash1),
			"employees": ["ceo"],
			"reserve_employees": [],
			"busy_marketers": [],
			"inventory": {},
			"milestones": [],
			"restaurants": [],
			"forfeited": false,
		},
	]
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.rules["salary_cost"] = 5
	return state

static func _finish(result: Result, panel: Node, prev_mode, prev_local_player_id: int) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		var tree_val = Engine.get_main_loop()
		if tree_val is SceneTree:
			await (tree_val as SceneTree).process_frame
	if NetContext != null:
		NetContext.mode = prev_mode
		NetContext.local_player_id = prev_local_player_id
	return result
