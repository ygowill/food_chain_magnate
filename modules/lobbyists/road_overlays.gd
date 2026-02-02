# Lobbyists module: road overlays used by both rules/actions and UI rendering.
extends RefCounted

const MODULE_ID := "lobbyists"

const PENDING_ROADS_KEY := "lobbyists_pending_roads"
const ROADWORK_MARKERS_KEY := "lobbyists_roadworks_markers"

const ROAD_PIECES: Array[String] = ["lobbyists_road_straight", "lobbyists_road_long", "lobbyists_road_l"]

const ROAD_OVERLAYS := {
	"lobbyists_road_straight": {
		"segments": [
			{"offset": Vector2i(0, 0), "dirs": ["E", "W"]},
			{"offset": Vector2i(1, 0), "dirs": ["E", "W"]},
		],
		"arrows": [
			{"offset": Vector2i(0, 0), "dir": "W"},
			{"offset": Vector2i(1, 0), "dir": "E"},
		],
	},
	"lobbyists_road_long": {
		"segments": [
			{"offset": Vector2i(0, 0), "dirs": ["E", "W"]},
			{"offset": Vector2i(1, 0), "dirs": ["E", "W"]},
			{"offset": Vector2i(2, 0), "dirs": ["E", "W"]},
		],
		"arrows": [
			{"offset": Vector2i(0, 0), "dir": "W"},
			{"offset": Vector2i(2, 0), "dir": "E"},
		],
	},
	"lobbyists_road_l": {
		"segments": [
			{"offset": Vector2i(0, 0), "dirs": ["N", "S"]},
			{"offset": Vector2i(0, 1), "dirs": ["N", "E"]},
			{"offset": Vector2i(1, 1), "dirs": ["W", "E"]},
		],
		"arrows": [
			{"offset": Vector2i(0, 0), "dir": "N"},
			{"offset": Vector2i(1, 1), "dir": "E"},
		],
	},
}

