class_name MapSkinRawImageFallbackTest
extends RefCounted

const MapSkinClass = preload("res://ui/visual/map_skin.gd")
const TextureUtilsClass = preload("res://ui/scenes/game/map/drawer/texture_utils.gd")

static func run() -> Result:
	var path := "user://map_skin_raw_image_fallback_test.png"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.6, 1.0))
	var save_err := img.save_png(path)
	if save_err != OK:
		return Result.failure("无法写入测试 PNG: %s err=%d" % [path, int(save_err)])

	var skin = MapSkinClass.new()
	skin.cell_size_px = 8
	skin._init_placeholders()
	var placeholder: Texture2D = skin.get_product_icon_texture("__missing__")
	var warnings: Array[String] = []
	var tex: Texture2D = skin._load_texture_or_placeholder(path, "icon", warnings, "raw-fallback")
	if tex == null:
		return Result.failure("raw image fallback 返回 null")
	if tex == placeholder:
		return Result.failure("raw image fallback 仍返回占位贴图")

	var loaded := tex.get_image()
	if loaded == null or loaded.is_empty():
		return Result.failure("raw image fallback 生成的 Texture2D 没有 Image 数据")
	if loaded.get_width() != 4 or loaded.get_height() != 4:
		return Result.failure("raw image fallback 尺寸错误: %dx%d" % [loaded.get_width(), loaded.get_height()])

	var prefilter_r := _test_lanczos_prefilter_cache()
	if not prefilter_r.ok:
		return prefilter_r.with_warnings(warnings)

	return Result.success({"warnings": warnings.size()}).with_warnings(warnings)

static func _test_lanczos_prefilter_cache() -> Result:
	TextureUtilsClass.clear_prefilter_cache()

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var c := Color(0.05, 0.05, 0.05, 1.0) if ((x + y) % 2 == 0) else Color(0.95, 0.95, 0.95, 1.0)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	if tex == null:
		return Result.failure("prefilter 测试纹理创建失败")

	var filtered: Texture2D = TextureUtilsClass.get_lanczos_prefiltered_texture(tex, Vector2i(16, 16))
	if filtered == null:
		return Result.failure("prefilter 返回 null")
	if filtered == tex:
		return Result.failure("prefilter 未生成降采样纹理")
	var filtered_img := filtered.get_image()
	if filtered_img == null or filtered_img.is_empty():
		return Result.failure("prefilter 纹理缺少 Image 数据")
	if filtered_img.get_width() != 16 or filtered_img.get_height() != 16:
		return Result.failure("prefilter 尺寸错误: %dx%d" % [filtered_img.get_width(), filtered_img.get_height()])

	var cached: Texture2D = TextureUtilsClass.get_lanczos_prefiltered_texture(tex, Vector2i(16, 16))
	if cached != filtered:
		return Result.failure("prefilter 未命中缓存")

	var unchanged: Texture2D = TextureUtilsClass.get_lanczos_prefiltered_texture(tex, Vector2i(64, 64))
	if unchanged != tex:
		return Result.failure("prefilter 不应替换非降采样纹理")

	TextureUtilsClass.clear_prefilter_cache()
	return Result.success()
