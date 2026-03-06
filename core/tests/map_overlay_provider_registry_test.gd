# 模块系统 V2：MapOverlayProviderRegistry（模块私有 map_data -> 通用 overlay 指令）
class_name MapOverlayProviderRegistryTest
extends RefCounted

const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"lobbyists",
	])
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var ui_metadata_apply := ModuleUiMetadataBootstrapClass.apply(engine)
	if not ui_metadata_apply.ok:
		return Result.failure("UI metadata 装配失败: %s" % ui_metadata_apply.error)

	if not MapOverlayProviderRegistryClass.is_loaded():
		return Result.failure("MapOverlayProviderRegistry 未加载（ModuleUiMetadataBootstrap.apply 后应已配置）")

	# 构造带 lobbyists 私有 key 的 map_data（不依赖模块逻辑），通过 provider 生成通用 overlay 指令。
	var map_data := {
		"lobbyists_pending_roads": [
			{
				"segments_by_pos": {
					"2,3": [{"dirs": ["N", "E"]}],
					"2,4": [{"dirs": ["S"]}],
				},
			},
			{
				"segments_by_pos": {
					"2,3": [{"dirs": ["W"]}],
				},
			},
		],
		"lobbyists_roadworks_markers": {
			"2,3": true,
			"9,9": true,
		},
	}

	var pending_dirs: Dictionary = MapOverlayProviderRegistryClass.get_pending_road_connection_dirs(map_data)
	if pending_dirs.is_empty():
		return Result.failure("pending_road_connection_dirs 为空（期望 provider 输出）")

	var p23 := Vector2i(2, 3)
	var d23_val = pending_dirs.get(p23, null)
	if not (d23_val is Dictionary):
		return Result.failure("pending_road_connection_dirs[%s] 类型错误（期望 Dictionary）" % str(p23))
	var d23: Dictionary = d23_val
	for d in ["N", "E", "W"]:
		if not d23.has(d):
			return Result.failure("pending_road_connection_dirs[%s] 缺少 dir: %s" % [str(p23), str(d)])

	var p24 := Vector2i(2, 4)
	var d24_val = pending_dirs.get(p24, null)
	if not (d24_val is Dictionary):
		return Result.failure("pending_road_connection_dirs[%s] 类型错误（期望 Dictionary）" % str(p24))
	var d24: Dictionary = d24_val
	if not d24.has("S"):
		return Result.failure("pending_road_connection_dirs[%s] 缺少 dir: S" % str(p24))

	var markers: Array[Vector2i] = MapOverlayProviderRegistryClass.get_roadworks_marker_world_positions(map_data)
	if markers.is_empty():
		return Result.failure("roadworks_marker_world_positions 为空（期望 provider 输出）")
	var marker_set := {}
	for p in markers:
		if p is Vector2i:
			marker_set[p] = true
	if not marker_set.has(Vector2i(2, 3)):
		return Result.failure("markers 缺少位置: (2,3)")
	if not marker_set.has(Vector2i(9, 9)):
		return Result.failure("markers 缺少位置: (9,9)")

	return Result.success({
		"pending_cells": pending_dirs.size(),
		"marker_count": marker_set.size(),
	})
