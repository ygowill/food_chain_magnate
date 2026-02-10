# Restaurant logo texture loading regression test
# Ensures restaurant logo piece textures load via MapSkin.
class_name RestaurantLogoTexturesLoadedTest
extends RefCounted

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")

const _EXPECTED_LOGO_PIECE_IDS := [
	"restaurant_logo_fried_geese_donkey",
	"restaurant_logo_gluttony_inc_burgers",
	"restaurant_logo_golden_duck_diner",
	"restaurant_logo_santa_maria_pizza",
	"restaurant_logo_xango_blues_bar",
	"restaurant_logo_sixth_chain",
]

static func run() -> Result:
	var base_dir := "res://modules"
	var modules: Array[String] = [
		"base_pieces",
	]

	var read: Result = MapSkinBuilderClass.build_for_modules(base_dir, modules, 40)
	if not read.ok:
		return Result.failure("MapSkinBuilder.build_for_modules 失败: %s" % read.error).with_warnings(read.warnings)
	var skin = read.value
	if skin == null or not skin.has_method("get_piece_texture"):
		return Result.failure("MapSkinBuilder 返回值类型错误（期望 MapSkin）: %s" % str(skin)).with_warnings(read.warnings)

	if not skin.has_method("get_restaurant_logo_piece_ids"):
		return Result.failure("MapSkin 缺少 get_restaurant_logo_piece_ids").with_warnings(read.warnings)
	var logo_ids = skin.get_restaurant_logo_piece_ids()
	if not (logo_ids is Array) or (logo_ids as Array).is_empty():
		return Result.failure("缺少 restaurant_logo_piece_ids（无法加载餐厅 Logo 列表）").with_warnings(read.warnings)
	var actual: Array[String] = []
	for v in (logo_ids as Array):
		actual.append(str(v))
	if str(actual) != str(_EXPECTED_LOGO_PIECE_IDS):
		return Result.failure("restaurant_logo_piece_ids 顺序或内容变化（可能影响存档兼容）: %s" % str(actual)).with_warnings(read.warnings)

	var placeholder: Texture2D = skin.get_piece_texture("__missing__")
	var missing: Array[String] = []
	for piece_id_val in (logo_ids as Array):
		var piece_id := str(piece_id_val).strip_edges()
		if piece_id.is_empty():
			continue
		var tex: Texture2D = skin.get_piece_texture(piece_id)
		if tex == null:
			missing.append("%s(null)" % piece_id)
		elif tex == placeholder:
			missing.append("%s(placeholder)" % piece_id)

	if not missing.is_empty():
		return Result.failure("餐厅 Logo 贴图仍为占位或缺失: %s" % ", ".join(missing)).with_warnings(read.warnings)

	return Result.success({
		"count": (logo_ids as Array).size(),
	}).with_warnings(read.warnings)
