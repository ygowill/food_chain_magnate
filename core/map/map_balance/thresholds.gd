class_name MapBalanceThresholds
extends RefCounted

const REQUIRED_DRINK_TYPES := ["beer", "lemonade", "soda"]

const _REPORT_THRESHOLDS := {
	2: {
		"total_starting_houses": {"min": 4, "max": 6},
		"starting_houses_in_neighborhood": {"max": 2, "max_ratio": 0.28},
		"starting_houses_on_road_system": {"max": 3, "max_ratio": 0.65},
		"total_drink_locations": {"min": 5, "max": 7},
		"drink_type_min": 1,
		"drink_locations_on_road_system": {"max": 3},
		"neighborhood_count": {"min": 10, "max": 12},
		"neighborhood_total_space_medium_min": 5,
		"neighborhood_empty_space_medium_min": 5,
		"road_system_count": {"min": 2, "max": 99},
		"road_system_route_medium_min": 3,
	},
	3: {
		"total_starting_houses": {"min": 6, "max": 7},
		"starting_houses_in_neighborhood": {"max": 2, "max_ratio": 0.21},
		"starting_houses_on_road_system": {"max": 4, "max_ratio": 0.71},
		"total_drink_locations": {"min": 7, "max": 9},
		"drink_type_min": 2,
		"drink_locations_on_road_system": {"max": 5},
		"neighborhood_count": {"min": 12, "max": 14},
		"neighborhood_total_space_medium_min": 9,
		"neighborhood_empty_space_medium_min": 5,
		"road_system_count": {"min": 2, "max": 3},
		"road_system_route_medium_min": 5,
	},
	4: {
		"total_starting_houses": {"min": 8, "max": 9},
		"starting_houses_in_neighborhood": {"max": 2, "max_ratio": 0.16},
		"starting_houses_on_road_system": {"max": 6, "max_ratio": 0.70},
		"total_drink_locations": {"min": 9, "max": 11},
		"drink_type_min": 3,
		"drink_locations_on_road_system": {"max": 7},
		"neighborhood_count": {"min": 15, "max": 17},
		"neighborhood_total_space_medium_min": 5,
		"neighborhood_empty_space_medium_min": 5,
		"road_system_count": {"min": 2, "max": 3},
		"road_system_route_medium_min": 5,
	},
	5: {
		"total_starting_houses": {"min": 11, "max": 11},
		"starting_houses_in_neighborhood": {"max": 3, "max_ratio": 0.20},
		"starting_houses_on_road_system": {"max": 7, "max_ratio": 0.70},
		"total_drink_locations": {"min": 13, "max": 13},
		"drink_type_min": 4,
		"drink_locations_on_road_system": {"max": 8},
		"neighborhood_count": {"min": 19, "max": 20},
		"neighborhood_total_space_medium_min": 5,
		"neighborhood_empty_space_medium_min": 5,
		"road_system_count": {"min": 2, "max": 3},
		"road_system_route_medium_min": 5,
	},
}

static func for_player_count(player_count: int) -> Result:
	if not _REPORT_THRESHOLDS.has(player_count):
		return Result.failure("MapBalanceThresholds: 暂无玩家数 %d 的报告阈值" % player_count)
	var thresholds: Dictionary = Dictionary(_REPORT_THRESHOLDS[player_count]).duplicate(true)
	thresholds["player_count"] = player_count
	thresholds["required_drink_types"] = REQUIRED_DRINK_TYPES.duplicate()
	return Result.success(thresholds)

static func supported_player_counts() -> Array[int]:
	var out: Array[int] = []
	for k in _REPORT_THRESHOLDS.keys():
		out.append(int(k))
	out.sort()
	return out
