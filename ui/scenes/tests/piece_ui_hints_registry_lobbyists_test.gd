class_name PieceUiHintsRegistryLobbyistsTest
extends RefCounted

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

	if not PieceUiHintsRegistry.is_loaded():
		return Result.failure("PieceUiHintsRegistry 未加载（ModuleUiMetadataBootstrap.apply 后应已配置）")

	var overlay := PieceUiHintsRegistry.get_road_overlay("lobbyists_road_straight")
	if overlay.is_empty():
		return Result.failure("road overlay 未注册: lobbyists_road_straight")
	var segments_val = overlay.get("segments", null)
	if not (segments_val is Array) or Array(segments_val).is_empty():
		return Result.failure("road overlay.segments 缺失或为空: lobbyists_road_straight")
	var arrows_val = overlay.get("arrows", null)
	if not (arrows_val is Array) or Array(arrows_val).is_empty():
		return Result.failure("road overlay.arrows 缺失或为空: lobbyists_road_straight")

	var park_kind := PieceUiHintsRegistry.get_kind("lobbyists_park_line")
	if park_kind != "park":
		return Result.failure("park kind 未注册或错误: lobbyists_park_line (%s)" % park_kind)
	var park_overlay := PieceUiHintsRegistry.get_road_overlay("lobbyists_park_line")
	if not park_overlay.is_empty():
		return Result.failure("park piece 不应注册 road overlay: lobbyists_park_line")

	return Result.success({
		"segments": Array(segments_val).size(),
		"arrows": Array(arrows_val).size(),
	})
