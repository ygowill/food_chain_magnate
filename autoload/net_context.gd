# 联机上下文（运行模式/房间信息/本地玩家信息）
extends Node

enum Mode {
	HOTSEAT = 0,
	ONLINE_CLIENT = 1,
	ONLINE_SERVER = 2,
}

const PROTOCOL_VERSION := 1

var mode: Mode = Mode.HOTSEAT
var local_player_id: int = -1

var server_url: String = ""
var room_state: Dictionary = {}
var player_profile: Dictionary = {}

func _ready() -> void:
	_ensure_default_profile()

func reset() -> void:
	mode = Mode.HOTSEAT
	local_player_id = -1
	server_url = ""
	room_state = {}
	_ensure_default_profile()

func _ensure_default_profile() -> void:
	if player_profile != null and not player_profile.is_empty():
		return
	var name := "玩家"
	var color_index := 0
	if Globals != null:
		if Globals.player_names is Array and not Globals.player_names.is_empty():
			name = str(Globals.player_names[0])
		if Globals.player_color_indices is Array and not Globals.player_color_indices.is_empty():
			color_index = int(Globals.player_color_indices[0])
	player_profile = {
		"name": name,
		"color_index": color_index,
	}

