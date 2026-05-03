class_name MapSnapshotApartmentUiHintsTest
extends RefCounted

const MapDefClass = preload("res://core/map/map_def.gd")
const MapBakeClass = preload("res://core/map/map_baker/bake.gd")
const BakedMapClass = preload("res://core/map/map_runtime/baked_map.gd")
const MapSnapshotRendererClass = preload("res://server/map_snapshot_renderer.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var result := _run_with_engine(engine, seed_val)
	engine.dispose()
	return result

static func _run_with_engine(engine: GameEngine, seed_val: int) -> Result:
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"new_districts",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	var map_def := MapDefClass.create_fixed("snapshot_apartment_ui_hints_test_map", [
		{"tile_id": "tile_x", "board_pos": Vector2i(0, 0), "rotation": 0},
	])
	var bake := MapBakeClass.bake(map_def, engine.game_data.tiles, engine.game_data.pieces)
	if not bake.ok:
		return Result.failure("地图烘焙失败: %s" % bake.error)
	var apply := BakedMapClass.apply_baked_map(state, bake.value)
	if not apply.ok:
		return Result.failure("写入地图失败: %s" % apply.error)

	ModuleUiMetadataBootstrapClass.reset()
	if not PieceUiHintsRegistryClass.get_hints("apartment").is_empty():
		return Result.failure("测试前 apartment hints 应为空")

	var render := MapSnapshotRendererClass.render_state_png(state, {
		"cell_px": 32,
		"max_image_dimension": 512,
	})
	if not render.ok:
		return Result.failure("MapSnapshotRenderer.render_state_png 失败: %s" % render.error)

	var hints := PieceUiHintsRegistryClass.get_hints("apartment")
	if str(hints.get("structure_style", "")).strip_edges() != "house_id":
		return Result.failure("截图 renderer 未装配 apartment house_id 渲染提示: %s" % str(hints))

	var value: Dictionary = render.value if (render.value is Dictionary) else {}
	var png_bytes: PackedByteArray = value.get("png_bytes", PackedByteArray())
	if png_bytes.is_empty():
		return Result.failure("截图 renderer 未生成 PNG bytes")

	return Result.success({"bytes": png_bytes.size()})
