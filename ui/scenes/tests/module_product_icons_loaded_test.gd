# Module product icon loading regression test
# Ensures module-defined product icons (coffee/kimchi/noodles/sushi) load via MapSkin.
class_name ModuleProductIconsLoadedTest
extends RefCounted

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")

static func run() -> Result:
	var base_dir := "res://modules"
	var modules: Array[String] = [
		"base_products",
		"coffee",
		"kimchi",
		"noodles",
		"sushi",
	]

	var read: Result = MapSkinBuilderClass.build_for_modules(base_dir, modules, 40)
	if not read.ok:
		return Result.failure("MapSkinBuilder.build_for_modules 失败: %s" % read.error).with_warnings(read.warnings)
	var skin = read.value
	if skin == null or not skin.has_method("get_product_icon_texture"):
		return Result.failure("MapSkinBuilder 返回值类型错误（期望 MapSkin）: %s" % str(skin)).with_warnings(read.warnings)

	var placeholder: Texture2D = skin.get_product_icon_texture("__missing__")
	var missing: Array[String] = []
	_assert_loaded(skin, placeholder, "burger", missing)
	_assert_loaded(skin, placeholder, "sushi", missing)
	_assert_loaded(skin, placeholder, "noodles", missing)
	_assert_loaded(skin, placeholder, "kimchi", missing)
	_assert_loaded(skin, placeholder, "coffee", missing)

	if not missing.is_empty():
		return Result.failure("产品图标仍为占位或缺失: %s" % ", ".join(missing)).with_warnings(read.warnings)

	return Result.success({"ok": true}).with_warnings(read.warnings)

static func _assert_loaded(skin, placeholder: Texture2D, product_id: String, missing: Array[String]) -> void:
	var tex: Texture2D = null
	if skin != null and skin.has_method("get_product_icon_texture"):
		tex = skin.get_product_icon_texture(str(product_id))
	if tex == null:
		missing.append("%s(null)" % str(product_id))
		return
	if tex == placeholder:
		missing.append("%s(placeholder)" % str(product_id))
