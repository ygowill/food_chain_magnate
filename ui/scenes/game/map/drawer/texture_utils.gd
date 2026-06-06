# MapCanvasDrawer：纹理绘制辅助方法下沉
extends RefCounted

const PREFILTER_MINIFICATION_RATIO := 1.5
const PREFILTER_CACHE_LIMIT := 256

static var _prefilter_cache: Dictionary = {}

static func clear_prefilter_cache() -> void:
	_prefilter_cache.clear()

static func draw_texture_aspect_fit(
	canvas,
	texture: Texture2D,
	rect: Rect2,
	modulate: Color = Color(1, 1, 1, 1),
	v_align: String = "center"
) -> void:
	if texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return

	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	if v_align == "top":
		pos.y = rect.position.y
	elif v_align == "bottom":
		pos.y = rect.position.y + rect.size.y - size.y

	canvas.draw_texture_rect(texture, Rect2(pos, size), false, modulate)

static func draw_texture_aspect_fit_prefiltered(
	canvas,
	texture: Texture2D,
	rect: Rect2,
	modulate: Color = Color(1, 1, 1, 1),
	v_align: String = "center"
) -> void:
	if texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return

	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	if v_align == "top":
		pos.y = rect.position.y
	elif v_align == "bottom":
		pos.y = rect.position.y + rect.size.y - size.y

	var target_size := Vector2i(
		maxi(1, int(round(size.x))),
		maxi(1, int(round(size.y)))
	)
	var draw_texture := get_lanczos_prefiltered_texture(texture, target_size)
	canvas.draw_texture_rect(draw_texture, Rect2(pos, size), false, modulate)

static func get_lanczos_prefiltered_texture(texture: Texture2D, target_size: Vector2i) -> Texture2D:
	if texture == null:
		return null
	var ts: Vector2 = texture.get_size()
	var src_size := Vector2i(maxi(1, int(round(ts.x))), maxi(1, int(round(ts.y))))
	var dst_size := Vector2i(maxi(1, int(target_size.x)), maxi(1, int(target_size.y)))
	var minify_ratio := maxf(
		float(src_size.x) / float(dst_size.x),
		float(src_size.y) / float(dst_size.y)
	)
	if minify_ratio < PREFILTER_MINIFICATION_RATIO:
		return texture
	if dst_size.x >= src_size.x and dst_size.y >= src_size.y:
		return texture

	var key := "%d:%dx%d" % [int(texture.get_instance_id()), dst_size.x, dst_size.y]
	var cached = _prefilter_cache.get(key, null)
	if cached is Texture2D:
		return cached

	var src_img := texture.get_image()
	if src_img == null or src_img.is_empty():
		return texture
	var out := src_img.get_region(Rect2i(Vector2i.ZERO, src_size))
	if out == null or out.is_empty():
		return texture
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	out.resize(dst_size.x, dst_size.y, Image.INTERPOLATE_LANCZOS)

	var filtered := ImageTexture.create_from_image(out)
	if filtered == null:
		return texture
	if _prefilter_cache.size() >= PREFILTER_CACHE_LIMIT:
		_prefilter_cache.clear()
	_prefilter_cache[key] = filtered
	return filtered

static func draw_texture_aspect_fit_rotated(
	canvas,
	texture: Texture2D,
	rect: Rect2,
	rotation_degrees: float,
	modulate: Color = Color(1, 1, 1, 1)
) -> void:
	if canvas == null or texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var effective_size := Vector2(ts.y, ts.x)
	var scale := minf(rect.size.x / effective_size.x, rect.size.y / effective_size.y)
	var size := ts * scale
	var center := rect.position + rect.size * 0.5
	canvas.draw_set_transform(center, deg_to_rad(rotation_degrees), Vector2.ONE)
	canvas.draw_texture_rect(texture, Rect2(-size * 0.5, size), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func get_texture_aspect_fit_rect(texture: Texture2D, rect: Rect2, v_align: String = "center") -> Rect2:
	if texture == null:
		return Rect2()
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()

	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	if v_align == "top":
		pos.y = rect.position.y
	elif v_align == "bottom":
		pos.y = rect.position.y + rect.size.y - size.y

	return Rect2(pos, size)

static func get_texture_aspect_fill_rect(texture: Texture2D, rect: Rect2) -> Rect2:
	if texture == null:
		return Rect2()
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()

	var scale := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	return Rect2(pos, size)

static func draw_texture_rect_clipped_by_view_cells(
	canvas,
	texture: Texture2D,
	dst_rect: Rect2,
	view_cells: Array,
	cell_size: int,
	modulate: Color
) -> void:
	if canvas == null or texture == null:
		return
	if dst_rect.size.x <= 0.0 or dst_rect.size.y <= 0.0:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return

	var inv_w := 1.0 / dst_rect.size.x
	var inv_h := 1.0 / dst_rect.size.y

	for vpos_val in view_cells:
		if not (vpos_val is Vector2i):
			continue
		var vpos: Vector2i = vpos_val
		var cell_rect := Rect2(Vector2(vpos.x * cell_size, vpos.y * cell_size), Vector2(cell_size, cell_size))
		var clip := dst_rect.intersection(cell_rect)
		if clip.size.x <= 0.1 or clip.size.y <= 0.1:
			continue

		var u0 := (clip.position.x - dst_rect.position.x) * inv_w
		var v0 := (clip.position.y - dst_rect.position.y) * inv_h
		var u1 := (clip.position.x + clip.size.x - dst_rect.position.x) * inv_w
		var v1 := (clip.position.y + clip.size.y - dst_rect.position.y) * inv_h

		u0 = clampf(u0, 0.0, 1.0)
		v0 = clampf(v0, 0.0, 1.0)
		u1 = clampf(u1, 0.0, 1.0)
		v1 = clampf(v1, 0.0, 1.0)

		var src_pos := Vector2(u0 * ts.x, v0 * ts.y)
		var src_size := Vector2(maxf(0.0, (u1 - u0) * ts.x), maxf(0.0, (v1 - v0) * ts.y))
		if src_size.x <= 0.1 or src_size.y <= 0.1:
			continue
		canvas.draw_texture_rect_region(texture, clip, Rect2(src_pos, src_size), modulate)

static func draw_texture_aspect_fill(canvas, texture: Texture2D, rect: Rect2, modulate: Color = Color(1, 1, 1, 1)) -> void:
	if texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var dest_ratio := rect.size.x / rect.size.y
	var src_ratio := ts.x / ts.y

	var src_rect := Rect2(Vector2.ZERO, ts)
	if src_ratio > dest_ratio:
		var w := ts.y * dest_ratio
		src_rect.position.x = (ts.x - w) * 0.5
		src_rect.size.x = w
	else:
		var h := ts.x / dest_ratio
		src_rect.position.y = (ts.y - h) * 0.5
		src_rect.size.y = h

	canvas.draw_texture_rect_region(texture, rect, src_rect, modulate)
