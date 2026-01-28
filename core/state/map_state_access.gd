class_name MapStateAccess
extends RefCounted

const KEY_MARKETING_PLACEMENTS := "marketing_placements"
const KEY_RESTAURANTS := "restaurants"
const KEY_HOUSES := "houses"

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func require_map(state: GameState, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if state == null:
		return Result.failure("%sstate 为空" % prefix)
	if not (state.map is Dictionary):
		return Result.failure("%sstate.map 类型错误（期望 Dictionary）" % prefix)
	return Result.success(state.map)

static func require_marketing_placements(state: GameState, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	var map_read := require_map(state, prefix_label)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	if not map.has(KEY_MARKETING_PLACEMENTS) or not (map[KEY_MARKETING_PLACEMENTS] is Dictionary):
		return Result.failure("%sstate.map.%s 缺失或类型错误（期望 Dictionary）" % [prefix, KEY_MARKETING_PLACEMENTS])
	return Result.success(map[KEY_MARKETING_PLACEMENTS])

static func require_restaurants(state: GameState, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	var map_read := require_map(state, prefix_label)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	if not map.has(KEY_RESTAURANTS) or not (map[KEY_RESTAURANTS] is Dictionary):
		return Result.failure("%sstate.map.%s 缺失或类型错误（期望 Dictionary）" % [prefix, KEY_RESTAURANTS])
	return Result.success(map[KEY_RESTAURANTS])

static func require_houses(state: GameState, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	var map_read := require_map(state, prefix_label)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value

	if not map.has(KEY_HOUSES) or not (map[KEY_HOUSES] is Dictionary):
		return Result.failure("%sstate.map.%s 缺失或类型错误（期望 Dictionary）" % [prefix, KEY_HOUSES])
	return Result.success(map[KEY_HOUSES])

