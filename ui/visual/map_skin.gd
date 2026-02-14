# 地图皮肤（UI）
# 负责：
# - 按启用模块加载 VisualCatalog（modules/*/content/visuals/*.json）
# - 尝试加载对应 Texture2D；缺失则使用占位贴图继续渲染（Q12=C）
class_name MapSkin
extends RefCounted

const PerfTraceClass = preload("res://core/debug/perf_trace.gd")

var cell_size_px: int = 40

var cell_textures: Dictionary = {}         # key -> Texture2D
var road_textures: Dictionary = {}         # key -> Texture2D
var piece_textures: Dictionary = {}        # piece_id -> Texture2D
var product_icon_textures: Dictionary = {} # product_id -> Texture2D
var marketing_textures: Dictionary = {}    # key -> Texture2D

var piece_offsets_px: Dictionary = {}      # piece_id -> Vector2i
var piece_scales: Dictionary = {}          # piece_id -> Vector2

var restaurant_logo_piece_ids: Array[String] = []

var _placeholders: Dictionary = {}         # kind -> Texture2D
var _logo_textures_transparent_bg: Dictionary = {} # piece_id -> Texture2D

func apply_visual_catalog(catalog, warnings: Array[String]) -> void:
	if catalog == null:
		return

	restaurant_logo_piece_ids = []
	var ids_val = catalog.restaurant_logo_piece_ids if catalog.has_method("get") else null
	if ids_val is Array:
		for v in Array(ids_val):
			if v is String:
				var s := str(v).strip_edges()
				if not s.is_empty():
					restaurant_logo_piece_ids.append(s)

	# cell_visuals
	var span_cell := PerfTraceClass.begin_span("skin:apply.cell_visuals")
	for k in catalog.cell_visuals.keys():
		var key: String = str(k)
		var entry_val = catalog.cell_visuals.get(k, null)
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var texture_path: String = str(entry.get("texture", ""))
		cell_textures[key] = _load_texture_or_placeholder(texture_path, "cell", warnings, "cell:%s" % key)
	PerfTraceClass.end_span(span_cell)

	# road_visuals
	var span_road := PerfTraceClass.begin_span("skin:apply.road_visuals")
	for k in catalog.road_visuals.keys():
		var key2: String = str(k)
		var entry_val2 = catalog.road_visuals.get(k, null)
		if not (entry_val2 is Dictionary):
			continue
		var entry2: Dictionary = entry_val2
		var texture_path2: String = str(entry2.get("texture", ""))
		road_textures[key2] = _load_texture_or_placeholder(texture_path2, "road", warnings, "road:%s" % key2)
	PerfTraceClass.end_span(span_road)

	# piece_visuals
	var span_piece := PerfTraceClass.begin_span("skin:apply.piece_visuals")
	for k in catalog.piece_visuals.keys():
		var piece_id: String = str(k)
		var entry_val3 = catalog.piece_visuals.get(k, null)
		if not (entry_val3 is Dictionary):
			continue
		var entry3: Dictionary = entry_val3
		var texture_path3: String = str(entry3.get("texture", ""))
		var base_tex := _load_texture_or_placeholder(texture_path3, "piece", warnings, "piece:%s" % piece_id)
		piece_textures[piece_id] = _maybe_make_transparent_logo_texture(piece_id, base_tex, warnings)
		var offset_val = entry3.get("offset_px", Vector2i.ZERO)
		if offset_val is Vector2i:
			piece_offsets_px[piece_id] = offset_val
		var scale_val = entry3.get("scale", Vector2.ONE)
		if scale_val is Vector2:
			piece_scales[piece_id] = scale_val
	PerfTraceClass.end_span(span_piece)

	# product_icons
	var span_icons := PerfTraceClass.begin_span("skin:apply.product_icons")
	for k in catalog.product_icons.keys():
		var product_id: String = str(k)
		var entry_val4 = catalog.product_icons.get(k, null)
		if not (entry_val4 is Dictionary):
			continue
		var entry4: Dictionary = entry_val4
		var texture_path4: String = str(entry4.get("texture", ""))
		product_icon_textures[product_id] = _load_texture_or_placeholder(texture_path4, "icon", warnings, "product:%s" % product_id)
	PerfTraceClass.end_span(span_icons)

	# marketing_visuals
	var span_marketing := PerfTraceClass.begin_span("skin:apply.marketing_visuals")
	for k in catalog.marketing_visuals.keys():
		var key3: String = str(k)
		var entry_val5 = catalog.marketing_visuals.get(k, null)
		if not (entry_val5 is Dictionary):
			continue
		var entry5: Dictionary = entry_val5
		var texture_path5: String = str(entry5.get("texture", ""))
		marketing_textures[key3] = _load_texture_or_placeholder(texture_path5, "marketing", warnings, "marketing:%s" % key3)
	PerfTraceClass.end_span(span_marketing)

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

func get_restaurant_logo_piece_ids() -> Array[String]:
	return restaurant_logo_piece_ids

func get_restaurant_logo_piece_id(logo_id: int) -> String:
	var lid := int(logo_id)
	if lid < 0 or lid >= restaurant_logo_piece_ids.size():
		return ""
	return str(restaurant_logo_piece_ids[lid]).strip_edges()

func get_restaurant_logo_texture_by_id(logo_id: int) -> Texture2D:
	var pid := get_restaurant_logo_piece_id(int(logo_id))
	if pid.is_empty():
		return _get_placeholder("piece")
	return get_piece_texture(pid)

func dispose() -> void:
	cell_textures.clear()
	road_textures.clear()
	piece_textures.clear()
	product_icon_textures.clear()
	marketing_textures.clear()
	piece_offsets_px.clear()
	piece_scales.clear()
	restaurant_logo_piece_ids.clear()
	_logo_textures_transparent_bg.clear()
	_placeholders.clear()

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

	# ResourceLoader.exists() may return false for raw assets that haven't been imported yet
	# (i.e., the `*.import` sidecar isn't generated). If the file exists on disk, still try
	# to load it and let Godot import on demand.
	var exists := ResourceLoader.exists(path)
	if not exists and path.begins_with("res://") and FileAccess.file_exists(path):
		exists = true

	if not exists:
		PerfTraceClass.counter_add("skin:texture_missing", 1)
		warnings.append("MapSkin: 贴图不存在，使用占位: %s (%s)" % [label, path])
		return _get_placeholder(kind)
	PerfTraceClass.counter_add("skin:texture_load_attempt", 1)
	var res = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
	if res is Texture2D:
		PerfTraceClass.counter_add("skin:texture_load_ok", 1)
		return res
	PerfTraceClass.counter_add("skin:texture_load_bad_type", 1)
	warnings.append("MapSkin: 贴图类型错误，使用占位: %s (%s)" % [label, path])
	return _get_placeholder(kind)

func _maybe_make_transparent_logo_texture(piece_id: String, base_tex: Texture2D, warnings: Array[String]) -> Texture2D:
	if base_tex == null:
		return base_tex
	var id := str(piece_id)
	if not id.begins_with("restaurant_logo_"):
		return base_tex
	# restaurant logos 贴图已在 assets 中预处理为透明底；无需运行时像素级去背景（issue_tracker #72）。
	return base_tex

func _convert_texture_edge_bg_to_transparent(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null

	var img := tex.get_image()
	if img == null:
		return null
	if img.is_empty():
		return null

	var w := img.get_width()
	var h := img.get_height()
	if w <= 1 or h <= 1:
		return null

	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var bg := _average_corner_color(img)
	var threshold := 0.18

	var visited := PackedByteArray()
	visited.resize(w * h)

	var queue: Array[int] = []
	var head := 0

	for x in range(w):
		_try_enqueue_bg(img, visited, queue, w, h, x, 0, bg, threshold)
		_try_enqueue_bg(img, visited, queue, w, h, x, h - 1, bg, threshold)
	for y in range(1, h - 1):
		_try_enqueue_bg(img, visited, queue, w, h, 0, y, bg, threshold)
		_try_enqueue_bg(img, visited, queue, w, h, w - 1, y, bg, threshold)

	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var x := idx % w
		var y := int(idx / w)

		if x > 0:
			_try_enqueue_bg(img, visited, queue, w, h, x - 1, y, bg, threshold)
		if x + 1 < w:
			_try_enqueue_bg(img, visited, queue, w, h, x + 1, y, bg, threshold)
		if y > 0:
			_try_enqueue_bg(img, visited, queue, w, h, x, y - 1, bg, threshold)
		if y + 1 < h:
			_try_enqueue_bg(img, visited, queue, w, h, x, y + 1, bg, threshold)

	for idx in queue:
		var x := int(idx) % w
		var y := int(int(idx) / w)
		var c := img.get_pixel(x, y)
		c.a = 0.0
		img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)

func _try_enqueue_bg(img: Image, visited: PackedByteArray, queue: Array[int], w: int, h: int, x: int, y: int, bg: Color, threshold: float) -> void:
	if x < 0 or x >= w or y < 0 or y >= h:
		return
	var idx := y * w + x
	if idx < 0 or idx >= visited.size():
		return
	if visited[idx] != 0:
		return

	var c := img.get_pixel(x, y)
	if c.a <= 0.001:
		visited[idx] = 1
		queue.append(idx)
		return

	var diff := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
	if diff <= threshold:
		visited[idx] = 1
		queue.append(idx)

func _average_corner_color(img: Image) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return Color(1, 1, 1, 1)
	var c1 := img.get_pixel(0, 0)
	var c2 := img.get_pixel(w - 1, 0)
	var c3 := img.get_pixel(0, h - 1)
	var c4 := img.get_pixel(w - 1, h - 1)
	var c := Color(
		(c1.r + c2.r + c3.r + c4.r) * 0.25,
		(c1.g + c2.g + c3.g + c4.g) * 0.25,
		(c1.b + c2.b + c3.b + c4.b) * 0.25,
		(c1.a + c2.a + c3.a + c4.a) * 0.25
	)
	return c

static func _make_checker_texture(size: Vector2i, a: Color, b: Color, cell: int = 6) -> Texture2D:
	var w: int = max(size.x, 1)
	var h: int = max(size.y, 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var use_a := ((x / cell) + (y / cell)) % 2 == 0
			img.set_pixel(x, y, a if use_a else b)
	return ImageTexture.create_from_image(img)
