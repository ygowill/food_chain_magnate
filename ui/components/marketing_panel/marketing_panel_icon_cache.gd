# MarketingPanel skin + icon cache helper
extends RefCounted

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

var _visual_modules: Array[String] = []
var _skin = null
var _product_icon_cache: Dictionary = {} # key -> Texture2D
var _marketing_type_icon_cache: Dictionary = {} # key -> Texture2D

func set_visual_modules(modules: Array[String]) -> void:
	_visual_modules = Array(modules, TYPE_STRING, "", null)
	_skin = null
	_product_icon_cache.clear()
	_marketing_type_icon_cache.clear()

func get_marketing_texture(type_id: String) -> Texture2D:
	_ensure_skin()
	if _skin == null or not _skin.has_method("get_marketing_texture"):
		return null
	return _skin.get_marketing_texture(str(type_id))

func get_product_icon_texture(product_id: String) -> Texture2D:
	_ensure_skin()
	if _skin == null or not _skin.has_method("get_product_icon_texture"):
		return null
	var pid := str(product_id)
	if pid == "cola":
		pid = "soda"
	return _skin.get_product_icon_texture(pid)

func get_product_icon_texture_scaled(product_id: String, target_size: Vector2i) -> Texture2D:
	var pid := str(product_id)
	if pid.is_empty():
		return null

	var key := "%s@%dx%d" % [pid, int(target_size.x), int(target_size.y)]
	if _product_icon_cache.has(key):
		var cached = _product_icon_cache.get(key, null)
		return cached if cached is Texture2D else null

	var base_tex := get_product_icon_texture(pid)
	var scaled := _scale_texture_to_square(base_tex, target_size)
	_product_icon_cache[key] = scaled
	return scaled

func get_marketing_icon_texture(type_id: String, target_size: Vector2i) -> Texture2D:
	var type_key := str(type_id)
	if type_key.is_empty():
		type_key = "default"

	var key := "%s@%dx%d" % [type_key, int(target_size.x), int(target_size.y)]
	if _marketing_type_icon_cache.has(key):
		var cached = _marketing_type_icon_cache.get(key, null)
		return cached if cached is Texture2D else null

	_ensure_skin()
	if _skin == null or not _skin.has_method("get_marketing_texture"):
		return null

	var base_tex = _skin.get_marketing_texture(type_key)
	var scaled := _scale_texture_to_square(base_tex, target_size)
	_marketing_type_icon_cache[key] = scaled
	return scaled

func _ensure_skin() -> void:
	if _skin != null:
		return

	var base_dir := ModulesBaseDirClass.get_base_dir()

	var mods := _visual_modules
	if mods.is_empty() and Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)

	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _scale_texture_to_square(tex: Texture2D, target_size: Vector2i) -> Texture2D:
	if tex == null:
		return null

	var tw := maxi(1, int(target_size.x))
	var th := maxi(1, int(target_size.y))

	var src_size: Vector2i = tex.get_size()
	var sw := int(src_size.x)
	var sh := int(src_size.y)
	if sw <= 0 or sh <= 0:
		return tex

	# 只做缩小；避免小图被放大后发糊。
	if sw <= tw and sh <= th:
		return tex

	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex

	if img.is_compressed():
		# 修改像素前需解压，否则 resize 会失败。
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var scale := minf(float(tw) / float(sw), float(th) / float(sh))
	var new_w := maxi(1, int(round(float(sw) * scale)))
	var new_h := maxi(1, int(round(float(sh) * scale)))

	img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	var out := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var dst := Vector2i(int((tw - new_w) / 2), int((th - new_h) / 2))
	out.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(new_w, new_h)), dst)

	return ImageTexture.create_from_image(out)

func _scale_texture_to_square_cover(tex: Texture2D, target_size: Vector2i) -> Texture2D:
	if tex == null:
		return null

	var tw := maxi(1, int(target_size.x))
	var th := maxi(1, int(target_size.y))

	var src_size: Vector2i = tex.get_size()
	var sw := int(src_size.x)
	var sh := int(src_size.y)
	if sw <= 0 or sh <= 0:
		return tex

	# 只做缩小；避免把小图放大后发糊（TextureRect 会在必要时自行放大）。
	if sw <= tw and sh <= th:
		return tex

	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex

	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	# Cover：按较大的缩放比放大到至少覆盖目标尺寸，再居中裁切。
	var scale := maxf(float(tw) / float(sw), float(th) / float(sh))
	var new_w := maxi(tw, int(ceil(float(sw) * scale)))
	var new_h := maxi(th, int(ceil(float(sh) * scale)))

	img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	var x0 := maxi(0, int((new_w - tw) / 2))
	var y0 := maxi(0, int((new_h - th) / 2))
	var out := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(Vector2i(x0, y0), Vector2i(tw, th)), Vector2i.ZERO)
	return ImageTexture.create_from_image(out)
