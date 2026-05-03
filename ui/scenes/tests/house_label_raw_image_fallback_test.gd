class_name HouseLabelRawImageFallbackTest
extends RefCounted

const StructuresPassClass = preload("res://ui/scenes/game/map/drawer/passes/structures_pass.gd")

static func run() -> Result:
	var path := "user://house_label_raw_image_fallback_test.png"
	var img := Image.create(7, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var save_err := img.save_png(path)
	if save_err != OK:
		return Result.failure("无法写入测试 PNG: %s err=%d" % [path, int(save_err)])

	var tex: Texture2D = StructuresPassClass._load_raw_house_id_label_texture(path)
	if tex == null:
		return Result.failure("house label raw image fallback 返回 null")

	var loaded := tex.get_image()
	if loaded == null or loaded.is_empty():
		return Result.failure("house label raw image fallback 生成的 Texture2D 没有 Image 数据")
	if loaded.get_width() != 7 or loaded.get_height() != 5:
		return Result.failure("house label raw image fallback 尺寸错误: %dx%d" % [loaded.get_width(), loaded.get_height()])

	return Result.success()
