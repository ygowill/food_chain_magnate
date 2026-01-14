# UI 图标/贴图缓存（基于 MapSkin）
# 复用 modules/*/content/visuals/*.json 的 VisualCatalog，
# 用于 UI 中按启用模块获取 product_icons / marketing_visuals 贴图。
class_name UiSkinCache
extends RefCounted

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MapSkinClass = preload("res://ui/visual/map_skin.gd")

static var _skins: Dictionary = {} # key -> MapSkin

static func get_skin_for_modules(base_dir: String, modules: Array[String], desired_cell_size_px: int = 40) -> MapSkin:
	var mods: Array[String] = []
	if modules is Array and not modules.is_empty():
		mods = Array(modules, TYPE_STRING, "", null)
	mods.sort()

	var key := "%s|%s|%d" % [str(base_dir), str(mods), int(desired_cell_size_px)]
	var cached = _skins.get(key, null)
	if cached != null and cached is MapSkin:
		return cached

	var read := MapSkinBuilderClass.build_for_modules(str(base_dir), mods, int(desired_cell_size_px))
	var skin: MapSkin = null
	if read.ok and read.value != null and read.value is MapSkin:
		skin = read.value
	else:
		push_error("UiSkinCache: MapSkin 构建失败，将使用占位皮肤: %s" % str(read.error))
		skin = MapSkinClass.new()
		skin.cell_size_px = maxi(1, int(desired_cell_size_px))
		skin._init_placeholders()

	_skins[key] = skin
	return skin

