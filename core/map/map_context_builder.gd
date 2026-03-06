# 地图上下文构建器（纯数据）
# 用途：为 PlacementValidator 等纯逻辑校验构建稳定的 map_ctx 字典结构，避免在多个动作中重复拼装。
class_name MapContextBuilder
extends RefCounted

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func build_context_result(state: GameState, prefix_label: String = "MapContextBuilder.build_context") -> Result:
	var map_read := MapStateAccessClass.require_map(state, prefix_label)
	if not map_read.ok:
		return map_read
	var map: Dictionary = map_read.value
	var prefix := MapStateAccessClass._prefix(prefix_label)
	if not map.has("cells") or not (map["cells"] is Array):
		return Result.failure("%sstate.map.cells 缺失或类型错误（期望 Array）" % prefix)
	if not map.has("grid_size") or not (map["grid_size"] is Vector2i):
		return Result.failure("%sstate.map.grid_size 缺失或类型错误（期望 Vector2i）" % prefix)
	var houses_read := MapStateAccessClass.require_houses(state, prefix_label)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	var restaurants_read := MapStateAccessClass.require_restaurants(state, prefix_label)
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value
	var placements_read := MapStateAccessClass.require_marketing_placements(state, prefix_label)
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value

	return Result.success({
		"cells": map["cells"],
		"grid_size": map["grid_size"],
		"map_origin": CoordsClass.get_map_origin(state),
		"houses": houses,
		"restaurants": restaurants,
		"drink_sources": map.get("drink_sources", []),
		"marketing_placements": placements,
	})

static func build_context(state: GameState) -> Dictionary:
	var read := build_context_result(state)
	assert(read.ok, "MapContextBuilder.build_context: %s" % str(read.error))
	return read.value
