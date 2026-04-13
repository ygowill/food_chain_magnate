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

	return Result.success()
