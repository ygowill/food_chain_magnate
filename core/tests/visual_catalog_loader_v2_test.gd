# 模块系统 V2：VisualCatalogLoader（UI 可选视觉目录）
class_name VisualCatalogLoaderV2Test
extends RefCounted

const VisualCatalogLoaderClass = preload("res://core/modules/v2/visual_catalog_loader.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var base_dir := "res://core/tests/fixtures/modules_v2_visuals_valid"

	var empty_read := VisualCatalogLoaderClass.load_for_modules(base_dir, ["gamma"])
	if not empty_read.ok:
		return Result.failure("gamma 视觉加载失败: %s" % empty_read.error)
	var empty_catalog = empty_read.value
	if empty_catalog == null:
		return Result.failure("gamma catalog 为空")
	if not (empty_catalog.piece_visuals is Dictionary) or not empty_catalog.piece_visuals.is_empty():
		return Result.failure("gamma 不应包含任何 piece_visuals: %s" % str(empty_catalog.piece_visuals))

	var read := VisualCatalogLoaderClass.load_for_modules(base_dir, ["alpha", "beta"])
	if not read.ok:
		return Result.failure("visuals 加载失败: %s" % read.error)
	var catalog = read.value
	if catalog == null:
		return Result.failure("catalog 为空")

	var house_val = catalog.piece_visuals.get("house", null)
	if not (house_val is Dictionary):
		return Result.failure("piece_visuals.house 缺失或类型错误: %s" % str(house_val))
	var house: Dictionary = house_val
	if str(house.get("texture", "")) != "res://modules/beta/assets/map/pieces/house.png":
		return Result.failure("piece_visuals.house.texture 覆盖失败: %s" % str(house.get("texture", "")))
	var offset_val = house.get("offset_px", null)
	if not (offset_val is Vector2i) or Vector2i(offset_val) != Vector2i(3, 4):
		return Result.failure("piece_visuals.house.offset_px 解析失败: %s" % str(offset_val))

	var has_override_warning := false
	for w in read.warnings:
		if w.contains("visual 覆盖: house") and w.contains("alpha -> beta"):
			has_override_warning = true
			break
	if not has_override_warning:
		return Result.failure("应产生覆盖 warning，但未发现: %s" % str(read.warnings))

	return Result.success()

