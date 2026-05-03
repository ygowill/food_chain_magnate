class_name MapSkinRawImageFallbackTest
extends RefCounted

const MapSkinClass = preload("res://ui/visual/map_skin.gd")

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

	return Result.success({"warnings": warnings.size()}).with_warnings(warnings)
