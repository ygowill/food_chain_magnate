# 地图皮肤（UI）
# 负责：
# - 按启用模块加载 VisualCatalog（modules/*/content/visuals/*.json）
# - 尝试加载对应 Texture2D；缺失则使用占位贴图继续渲染（Q12=C）
class_name MapSkin
extends RefCounted

var cell_size_px: int = 40

var cell_textures: Dictionary = {}         # key -> Texture2D
var road_textures: Dictionary = {}         # key -> Texture2D
var piece_textures: Dictionary = {}        # piece_id -> Texture2D
var product_icon_textures: Dictionary = {} # product_id -> Texture2D
var marketing_textures: Dictionary = {}    # key -> Texture2D

var piece_offsets_px: Dictionary = {}      # piece_id -> Vector2i
var piece_scales: Dictionary = {}          # piece_id -> Vector2

var _placeholders: Dictionary = {}         # kind -> Texture2D

func apply_visual_catalog(catalog, warnings: Array[String]) -> void:
	if catalog == null:
		return

	# cell_visuals
	for k in catalog.cell_visuals.keys():
		var key: String = str(k)
		var entry_val = catalog.cell_visuals.get(k, null)
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var texture_path: String = str(entry.get("texture", ""))
		cell_textures[key] = _load_texture_or_placeholder(texture_path, "cell", warnings, "cell:%s" % key)

	# road_visuals
	for k in catalog.road_visuals.keys():
		var key2: String = str(k)
		var entry_val2 = catalog.road_visuals.get(k, null)
		if not (entry_val2 is Dictionary):
			continue
		var entry2: Dictionary = entry_val2
		var texture_path2: String = str(entry2.get("texture", ""))
		road_textures[key2] = _load_texture_or_placeholder(texture_path2, "road", warnings, "road:%s" % key2)

	# piece_visuals
	for k in catalog.piece_visuals.keys():
		var piece_id: String = str(k)
		var entry_val3 = catalog.piece_visuals.get(k, null)
		if not (entry_val3 is Dictionary):
			continue
		var entry3: Dictionary = entry_val3
		var texture_path3: String = str(entry3.get("texture", ""))
		piece_textures[piece_id] = _load_texture_or_placeholder(texture_path3, "piece", warnings, "piece:%s" % piece_id)
		var offset_val = entry3.get("offset_px", Vector2i.ZERO)
		if offset_val is Vector2i:
			piece_offsets_px[piece_id] = offset_val
		var scale_val = entry3.get("scale", Vector2.ONE)
		if scale_val is Vector2:
			piece_scales[piece_id] = scale_val

	# product_icons
	for k in catalog.product_icons.keys():
		var product_id: String = str(k)
		var entry_val4 = catalog.product_icons.get(k, null)
		if not (entry_val4 is Dictionary):
			continue
		var entry4: Dictionary = entry_val4
		var texture_path4: String = str(entry4.get("texture", ""))
		product_icon_textures[product_id] = _load_texture_or_placeholder(texture_path4, "icon", warnings, "product:%s" % product_id)

	# marketing_visuals
	for k in catalog.marketing_visuals.keys():
		var key3: String = str(k)
		var entry_val5 = catalog.marketing_visuals.get(k, null)
		if not (entry_val5 is Dictionary):
			continue
		var entry5: Dictionary = entry_val5
		var texture_path5: String = str(entry5.get("texture", ""))
		marketing_textures[key3] = _load_texture_or_placeholder(texture_path5, "marketing", warnings, "marketing:%s" % key3)

func get_cell_texture(key: String) -> Texture2D:
	if cell_textures.has(key):
		return cell_textures[key]
	return _get_placeholder("cell")

func get_ground_texture() -> Texture2D:
	if cell_textures.has("ground"):
		return cell_textures["ground"]
	return _get_placeholder("cell")

func get_blocked_overlay_texture() -> Texture2D:
	if cell_textures.has("blocked"):
		return cell_textures["blocked"]
	return _get_placeholder("blocked")

func get_road_texture(key: String) -> Texture2D:
	if road_textures.has(key):
		return road_textures[key]
	return _get_placeholder("road")

func get_piece_texture(piece_id: String) -> Texture2D:
	if piece_textures.has(piece_id):
		return piece_textures[piece_id]
	return _get_placeholder("piece")

func get_piece_offset_px(piece_id: String) -> Vector2i:
	var val = piece_offsets_px.get(piece_id, Vector2i.ZERO)
	return val if (val is Vector2i) else Vector2i.ZERO

func get_piece_scale(piece_id: String) -> Vector2:
	var val = piece_scales.get(piece_id, Vector2.ONE)
	return val if (val is Vector2) else Vector2.ONE

func get_product_icon_texture(product_id: String) -> Texture2D:
	if product_icon_textures.has(product_id):
		return product_icon_textures[product_id]
	return _get_placeholder("icon")

func get_marketing_texture(key: String) -> Texture2D:
	if marketing_textures.has(key):
		return marketing_textures[key]
	return _get_placeholder("marketing")

func _init_placeholders() -> void:
	_placeholders.clear()
	_placeholders["cell"] = _make_checker_texture(Vector2i(cell_size_px, cell_size_px), Color(0.18, 0.2, 0.22), Color(0.14, 0.16, 0.18))
	_placeholders["blocked"] = _make_checker_texture(Vector2i(cell_size_px, cell_size_px), Color(0.35, 0.15, 0.15), Color(0.25, 0.1, 0.1))
	_placeholders["road"] = _make_checker_texture(Vector2i(cell_size_px, cell_size_px), Color(0.45, 0.45, 0.45), Color(0.35, 0.35, 0.35))
	_placeholders["piece"] = _make_checker_texture(Vector2i(cell_size_px * 2, cell_size_px * 2), Color(0.25, 0.35, 0.6), Color(0.18, 0.26, 0.45))
	_placeholders["icon"] = _make_checker_texture(Vector2i(int(cell_size_px * 0.6), int(cell_size_px * 0.6)), Color(0.7, 0.6, 0.2), Color(0.55, 0.45, 0.15))
	_placeholders["marketing"] = _make_checker_texture(Vector2i(cell_size_px, cell_size_px), Color(0.75, 0.55, 0.15), Color(0.6, 0.42, 0.1))

func _get_placeholder(kind: String) -> Texture2D:
	var val = _placeholders.get(kind, null)
	if val is Texture2D:
		return val
	return _placeholders.get("cell")

func _load_texture_or_placeholder(path: String, kind: String, warnings: Array[String], label: String) -> Texture2D:
	if path.is_empty():
		return _get_placeholder(kind)
	if not ResourceLoader.exists(path):
		warnings.append("MapSkin: 贴图不存在，使用占位: %s (%s)" % [label, path])
		return _get_placeholder(kind)
	var res = load(path)
	if res is Texture2D:
		return res
	warnings.append("MapSkin: 贴图类型错误，使用占位: %s (%s)" % [label, path])
	return _get_placeholder(kind)

static func _make_checker_texture(size: Vector2i, a: Color, b: Color, cell: int = 6) -> Texture2D:
	var w: int = max(size.x, 1)
	var h: int = max(size.y, 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var use_a := ((x / cell) + (y / cell)) % 2 == 0
			img.set_pixel(x, y, a if use_a else b)
	return ImageTexture.create_from_image(img)
