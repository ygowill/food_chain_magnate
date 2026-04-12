extends RefCounted

const LeftPanelScene: PackedScene = preload("res://ui/components/left_panel/left_panel.tscn")

static func run() -> Result:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 0

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if LeftPanelScene == null:
		return Result.failure("LeftPanelScene preload 失败")

	var panel = LeftPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 LeftPanel 失败")
	tree.root.add_child(panel)
	await tree.process_frame

	var state := _build_state()
	panel.call("set_game_state", state)
	panel.call("set_current_player", 0)
	panel.call("set_view_player", 0)

	NetContext.room_state = {
		"players": [
			{"seat_index": 0, "connected": true, "forfeited": false},
			{"seat_index": 1, "connected": false, "forfeited": false},
		]
	}
	if NetClient != null:
		NetClient.room_state_updated.emit(Dictionary(NetContext.room_state).duplicate(true))
	await tree.process_frame

	var disconnected_card := _find_overview_card(panel, 1)
	if disconnected_card == null:
		_cleanup_panel(panel)
		return Result.failure("未找到 player_id=1 的概览卡")
	var employees_scroll = panel.get_node_or_null("MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll")
	if employees_scroll == null:
		_cleanup_panel(panel)
		return Result.failure("未找到 EmployeesScroll")
	if int(employees_scroll.get("vertical_scroll_mode")) != int(ScrollContainer.SCROLL_MODE_AUTO):
		_cleanup_panel(panel)
		return Result.failure("EmployeesScroll.vertical_scroll_mode 应为 AUTO，实际: %s" % str(employees_scroll.get("vertical_scroll_mode")))
	if str(disconnected_card.get_meta("status_kind", "")) != "disconnected":
		_cleanup_panel(panel)
		return Result.failure("掉线玩家概览卡状态错误: %s" % str(disconnected_card.get_meta("status_kind", null)))
	var disconnected_logo := disconnected_card.find_child("RestaurantLogo", true, false)
	var disconnected_badge = disconnected_logo.get_node_or_null("StatusBadge") if disconnected_logo != null else null
	if disconnected_badge == null or not bool(disconnected_badge.visible):
		_cleanup_panel(panel)
		return Result.failure("掉线玩家未显示状态徽章")

	state.players[1]["forfeited"] = true
	panel.call("set_game_state", state)
	panel.call("set_view_player", 1)
	await tree.process_frame

	var forfeited_card := _find_overview_card(panel, 1)
	if forfeited_card == null:
		_cleanup_panel(panel)
		return Result.failure("未找到 forfeited 玩家概览卡")
	if str(forfeited_card.get_meta("status_kind", "")) != "forfeited":
		_cleanup_panel(panel)
		return Result.failure("弃权玩家概览卡状态错误: %s" % str(forfeited_card.get_meta("status_kind", null)))

	var summary_icon = panel.get("restaurant_icon")
	if summary_icon == null or not is_instance_valid(summary_icon):
		_cleanup_panel(panel)
		return Result.failure("summary restaurant_icon 无效")
	if str(summary_icon.get_meta("status_kind", "")) != "forfeited":
		_cleanup_panel(panel)
		return Result.failure("摘要卡餐厅图标状态错误: %s" % str(summary_icon.get_meta("status_kind", null)))
	var summary_badge = summary_icon.get_node_or_null("StatusBadge")
	if summary_badge == null or not bool(summary_badge.visible):
		_cleanup_panel(panel)
		return Result.failure("摘要卡餐厅图标未显示弃权徽章")

	_cleanup_panel(panel)
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	return Result.success()

static func _build_state() -> GameState:
	var state := GameState.new()
	state.seed = 12345
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.players = [
		{
			"id": 0,
			"cash": 10,
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
			"cash": 12,
			"employees": ["ceo"],
			"reserve_employees": [],
			"busy_marketers": [],
			"inventory": {},
			"milestones": [],
			"restaurants": [],
			"forfeited": false,
		},
	]
	return state

static func _find_overview_card(panel, player_id: int) -> Control:
	if panel == null or not is_instance_valid(panel):
		return null
	var grid = panel.get("overview_grid")
	if grid == null or not is_instance_valid(grid):
		return null
	for child in grid.get_children():
		if not (child is Control):
			continue
		var card: Control = child
		if not card.has_meta("player_id"):
			continue
		if int(card.get_meta("player_id")) == player_id:
			return card
	return null

static func _cleanup_panel(panel: Node) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
