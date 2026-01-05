# 地图皮肤构建器（UI）
# - 负责加载 VisualCatalog（modules/*/content/visuals/*.json）
# - 构建 MapSkin（Texture2D 加载；缺失资源使用占位继续，Q12=C）
class_name MapSkinBuilder
extends RefCounted

const MapSkinClass = preload("res://ui/visual/map_skin.gd")
const VisualCatalogLoaderClass = preload("res://core/modules/v2/visual_catalog_loader.gd")

static func build_for_modules(base_dir: String, module_ids: Array[String], desired_cell_size_px: int = 40) -> Result:
	var skin = MapSkinClass.new()
	skin.cell_size_px = max(desired_cell_size_px, 1)
	skin._init_placeholders()

	var cat_read := VisualCatalogLoaderClass.load_for_modules(base_dir, module_ids)
	if not cat_read.ok:
		return Result.failure("MapSkinBuilder: 视觉目录加载失败: %s" % cat_read.error).with_warnings(cat_read.warnings)

	var catalog = cat_read.value
	if catalog == null:
		return Result.failure("MapSkinBuilder: VisualCatalog 为空").with_warnings(cat_read.warnings)

	var warnings: Array[String] = []
	warnings.append_array(cat_read.warnings)
	skin.apply_visual_catalog(catalog, warnings)

	return Result.success(skin).with_warnings(warnings)

