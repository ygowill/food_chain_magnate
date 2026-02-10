# Restaurant logo texture loading regression test
# Ensures restaurant logo piece textures load via MapSkin.
class_name RestaurantLogoTexturesLoadedTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")

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

	var placeholder: Texture2D = skin.get_piece_texture("__missing__")
	var missing: Array[String] = []
	for piece_id_val in MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS:
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
		"count": MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS.size(),
	}).with_warnings(read.warnings)

