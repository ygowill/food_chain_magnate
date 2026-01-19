# 地图上下文构建器（纯数据）
# 用途：为 PlacementValidator 等纯逻辑校验构建稳定的 map_ctx 字典结构，避免在多个动作中重复拼装。
class_name MapContextBuilder
extends RefCounted

const CoordsClass = preload("res://core/map/map_runtime/coords.gd")

static func build_context(state: GameState) -> Dictionary:
	assert(state != null, "MapContextBuilder.build_context: state 为空")
	assert(state.map is Dictionary, "MapContextBuilder.build_context: state.map 类型错误（期望 Dictionary）")

	return {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": CoordsClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}
