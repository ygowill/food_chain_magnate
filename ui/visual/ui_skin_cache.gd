# UI 图标/贴图缓存（基于 MapSkin）
# 复用 modules/*/content/visuals/*.json 的 VisualCatalog，
# 用于 UI 中按启用模块获取 product_icons / marketing_visuals 贴图。
class_name UiSkinCache
extends RefCounted

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MapSkinClass = preload("res://ui/visual/map_skin.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")

static var _skins: Dictionary = {} # key -> MapSkin

static func get_skin_for_modules(base_dir: String, modules: Array[String], desired_cell_size_px: int = 40) -> MapSkin:
	var mods: Array[String] = []
	if modules is Array and not modules.is_empty():
		mods = Array(modules, TYPE_STRING, "", null)
	# 保持 modules 顺序（模块计划顺序决定 visuals 覆盖优先级；排序会改变最终贴图）。

	var mods_key := ",".join(mods)
	var key := "%s|%s|%d" % [str(base_dir).strip_edges(), mods_key, int(desired_cell_size_px)]
	var cached = _skins.get(key, null)
	if cached != null and cached is MapSkin:
		return cached
	if PerfTraceClass.enabled():
		print("[StartupProfile] UiSkinCache MISS key=%s mods=%s cell=%d" % [key, str(mods), int(desired_cell_size_px)])

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
