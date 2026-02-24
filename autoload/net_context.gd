# 联机上下文（运行模式/房间信息/本地玩家信息）
extends Node

enum Mode {
	HOTSEAT = 0,
	ONLINE_CLIENT = 1,
	ONLINE_SERVER = 2,
}

const PROTOCOL_VERSION := 1

const COMMAND_PRIVACY_SPECTATOR_VIEWER_PLAYER_ID := 999999

var mode: Mode = Mode.HOTSEAT
var local_player_id: int = -1

var server_url: String = ""
var connect_token: String = ""
var room_state: Dictionary = {}
var room_list: Array = []
var player_profile: Dictionary = {}

func _ready() -> void:
	_ensure_default_profile()

func get_command_privacy_viewer_player_id() -> int:
	# Hotseat/local：无需脱敏；联机 spectator：应视为“非本人”，避免 history/debug 误显示隐信息。
	if mode == Mode.ONLINE_CLIENT and local_player_id < 0:
		return COMMAND_PRIVACY_SPECTATOR_VIEWER_PLAYER_ID
	return local_player_id

func reset() -> void:
	mode = Mode.HOTSEAT
	local_player_id = -1
	server_url = ""
	connect_token = ""
	room_state = {}
	room_list = []
	_ensure_default_profile()

func _ensure_default_profile() -> void:
	var name := "玩家"
	var color_index := 0
	var restaurant_logo_id := -1
	if Globals != null:
		if Globals.player_names is Array and not Globals.player_names.is_empty():
			name = str(Globals.player_names[0])
		if Globals.player_color_indices is Array and not Globals.player_color_indices.is_empty():
			color_index = int(Globals.player_color_indices[0])
		if Globals.player_restaurant_logo_choices is Array and not Globals.player_restaurant_logo_choices.is_empty():
			restaurant_logo_id = int(Globals.player_restaurant_logo_choices[0])
	if player_profile != null and not player_profile.is_empty():
		if str(player_profile.get("name", "")).strip_edges().is_empty():
			player_profile["name"] = name
		if not player_profile.has("color_index"):
			player_profile["color_index"] = color_index
		if not player_profile.has("restaurant_logo_id"):
			player_profile["restaurant_logo_id"] = restaurant_logo_id
		return
	player_profile = {
		"name": name,
		"color_index": color_index,
		"restaurant_logo_id": restaurant_logo_id,
	}
