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

	return Result.success()
