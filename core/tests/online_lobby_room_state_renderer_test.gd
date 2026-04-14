class_name OnlineLobbyRoomStateRendererTest
extends RefCounted

const RendererClass = preload("res://ui/scenes/online/online_lobby_room_state_renderer.gd")

static func run() -> Result:
	var renderer = RendererClass.new()
	var base_room: Dictionary = {
		"room_code": "ABCD12",
		"status": "Lobby",
		"room_mode": "normal",
		"host_peer_id": 1,
		"host_seat_index": 0,
		"players": [{
			"seat_index": 0,
			"name": "房主",
			"color_index": 0,
			"connected": true,
			"forfeited": false,
			"peer_id": 1,
			"restaurant_logo_id": 2,
		}],
		"waiting_members": [],
		"spectators": [],
		"config": {
			"desired_player_count": 2,
			"seed_mode": "random",
			"seed": 123,
			"allow_spectators": true,
		},
	}

	var config_only_changed: Dictionary = base_room.duplicate(true)
	var config_only_cfg: Dictionary = Dictionary(config_only_changed.get("config", {}))
	config_only_cfg["seed"] = 999
	config_only_cfg["allow_spectators"] = false
	config_only_changed["config"] = config_only_cfg
	if renderer.has_visible_room_state_change(base_room, config_only_changed, 1):
		return Result.failure("仅配置细节变化时，不应触发房间成员区重建")

	var desired_changed: Dictionary = base_room.duplicate(true)
	var desired_cfg: Dictionary = Dictionary(desired_changed.get("config", {}))
	desired_cfg["desired_player_count"] = 3
	desired_changed["config"] = desired_cfg
	if not renderer.has_visible_room_state_change(base_room, desired_changed, 1):
		return Result.failure("desired_player_count 变化时应触发房间成员区重建")

	var player_name_changed: Dictionary = base_room.duplicate(true)
	var players: Array = Array(player_name_changed["players"])
	var first_player: Dictionary = Dictionary(players[0])
	first_player["name"] = "新房主"
	players[0] = first_player
	player_name_changed["players"] = players
	if not renderer.has_visible_room_state_change(base_room, player_name_changed, 1):
		return Result.failure("玩家显示名变化时应触发房间成员区重建")

	var resume_room: Dictionary = {
		"room_code": "RSM001",
		"status": "Lobby",
		"room_mode": "resume_archive",
		"host_peer_id": 1,
		"host_seat_index": 0,
		"players": [{
			"seat_index": 0,
			"name": "房主",
			"color_index": 0,
			"connected": true,
			"forfeited": false,
			"peer_id": 1,
			"restaurant_logo_id": -1,
		}],
		"waiting_members": [],
		"spectators": [],
		"config": {
			"desired_player_count": 2,
			"resume_summary": {
				"source_name": "resume_test.json",
				"round_number": 2,
				"phase": "Working",
				"current_index": 8,
				"current_player_id": 1,
			},
			"resume_player_summaries": [{
				"player_id": 0,
				"restaurant_logo_id": 3,
				"cash": 27,
				"restaurants_count": 1,
				"milestones_count": 2,
				"employee_counts": {"active": 5, "reserve": 1, "busy": 0},
				"employee_groups": {"active": [], "reserve": [], "busy": []},
			}],
		},
	}
	var resume_cash_changed: Dictionary = resume_room.duplicate(true)
	var resume_cfg: Dictionary = Dictionary(resume_cash_changed.get("config", {}))
	var resume_players: Array = Array(resume_cfg.get("resume_player_summaries", []))
	var resume_first_player: Dictionary = Dictionary(resume_players[0])
	resume_first_player["cash"] = 35
	resume_players[0] = resume_first_player
	resume_cfg["resume_player_summaries"] = resume_players
	resume_cash_changed["config"] = resume_cfg
	if not renderer.has_visible_room_state_change(resume_room, resume_cash_changed, 1):
		return Result.failure("恢复房玩家详情变化时应触发右侧信息重建")

	var four_player_summaries: Array = []
	var four_current_players: Array = []
	for player_id in range(4):
		four_player_summaries.append({
			"player_id": player_id,
			"restaurant_logo_id": player_id,
			"cash": 20 + player_id,
			"restaurants_count": 1 + (player_id % 2),
			"milestones_count": 2 + player_id,
			"employee_counts": {"active": 5 + player_id, "reserve": 1, "busy": 0},
			"employee_groups": {
				"active": [{"employee_id": "marketing_trainee", "name": "营销实习生", "count": 2 + player_id}],
				"reserve": [{"employee_id": "kitchen_trainee", "name": "后厨实习生", "count": 1}],
				"busy": [],
			},
		})
		four_current_players.append({
			"seat_index": player_id,
			"name": "玩家%d" % (player_id + 1),
			"connected": true,
			"forfeited": false,
		})

	var resume_panel = renderer._build_resume_players_panel(four_player_summaries, four_current_players)
	if resume_panel == null or not (resume_panel is PanelContainer):
		return Result.failure("恢复房玩家详情面板构建失败")
	if int(resume_panel.size_flags_vertical) != int(Control.SIZE_EXPAND_FILL):
		return Result.failure("恢复房玩家详情面板应纵向扩展填充，避免整页被撑高")
	var root := resume_panel.get_child(0)
	if root == null or not (root is VBoxContainer):
		return Result.failure("恢复房玩家详情面板根节点类型错误")
	if root.get_child_count() < 2:
		return Result.failure("恢复房玩家详情面板应包含固定标题和滚动列表")
	if not (root.get_child(0) is Label):
		return Result.failure("恢复房玩家详情面板首个子节点应为固定标题")
	var players_scroll := root.get_child(1)
	if players_scroll == null or not (players_scroll is ScrollContainer):
		return Result.failure("恢复房玩家详情面板应使用 ScrollContainer 承载玩家卡片列表")
	if int((players_scroll as ScrollContainer).horizontal_scroll_mode) != int(ScrollContainer.SCROLL_MODE_DISABLED):
		return Result.failure("恢复房玩家详情滚动区应禁用横向滚动")
	var players_list := players_scroll.get_node_or_null("PlayersList")
	if players_list == null or not (players_list is VBoxContainer):
		return Result.failure("恢复房玩家详情滚动区缺少 PlayersList")
	if players_list.get_child_count() != 4:
		return Result.failure("恢复房玩家详情滚动区应渲染 4 个玩家卡片，实际: %d" % players_list.get_child_count())

	return Result.success()
