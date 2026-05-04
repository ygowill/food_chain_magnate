class_name TutorialCampaignAssetsLoadedTest
extends RefCounted

const TutorialCampaignSceneClass = preload("res://ui/scenes/tutorial_campaign/tutorial_campaign.gd")
const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")

static func run() -> Result:
	var missing: Array[String] = []
	var reserve_paths: Array[String] = [
		"res://assets/images/reserve_cards/reserve_2.png",
		"res://assets/images/reserve_cards/reserve_3.png",
		"res://assets/images/reserve_cards/reserve_4.png",
	]
	for path in reserve_paths:
		_assert_tutorial_texture(path, missing)

	var read: Result = MapSkinBuilderClass.build_for_modules("res://modules", ["base_tiles"], 40)
	if not read.ok:
		return Result.failure("MapSkinBuilder.build_for_modules 失败: %s" % read.error).with_warnings(read.warnings)
	var skin = read.value
	if skin == null or not skin.has_method("get_road_texture"):
		return Result.failure("MapSkinBuilder 返回值类型错误（期望 MapSkin）: %s" % str(skin)).with_warnings(read.warnings)

	var placeholder: Texture2D = skin.get_road_texture("__missing__")
	var road_keys: Array[String] = ["straight", "corner", "tee", "cross", "road_bridge"]
	for key in road_keys:
		var tex: Texture2D = skin.get_road_texture(key)
		if tex == null:
			missing.append("road:%s(null)" % key)
		elif tex == placeholder:
			missing.append("road:%s(placeholder)" % key)
		elif tex.get_size().x <= 0.0 or tex.get_size().y <= 0.0:
			missing.append("road:%s(empty)" % key)

	if not missing.is_empty():
		return Result.failure("教学页素材缺失或仍为占位: %s" % ", ".join(missing)).with_warnings(read.warnings)
	return Result.success({"checked": reserve_paths.size() + road_keys.size()}).with_warnings(read.warnings)

static func _assert_tutorial_texture(path: String, missing: Array[String]) -> void:
	var tex: Texture2D = TutorialCampaignSceneClass._load_texture2d_from_path(path)
	if tex == null:
		missing.append("%s(null)" % path)
		return
	if tex.get_size().x <= 0.0 or tex.get_size().y <= 0.0:
		missing.append("%s(empty)" % path)
