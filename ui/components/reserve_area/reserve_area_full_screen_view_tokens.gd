# ReserveAreaFullScreenView token helpers (moved out to keep the view script small).
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map_canvas_drawer_structures_pass.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")


# === 通用 token（贴图 + badge）===
class IconToken extends PanelContainer:
	var texture: Texture2D = null
	var badge_text: String = ""

	var _tex_rect: TextureRect
	var _badge_label: Label

	func _ready() -> void:
		_build_ui()
		_update_ui()

	func _build_ui() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(80, 80)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.97, 0.94, 0.86, 0.95)
		style.border_color = Color(0.73, 0.23, 0.18, 0.35)
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		add_theme_stylebox_override("panel", style)

		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(container)
		container.set_anchors_preset(Control.PRESET_FULL_RECT)

		_tex_rect = TextureRect.new()
		_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tex_rect.offset_left = 10
		_tex_rect.offset_top = 10
		_tex_rect.offset_right = -10
		_tex_rect.offset_bottom = -10
		container.add_child(_tex_rect)

		_badge_label = Label.new()
		_badge_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(12) if Globals != null else 12)
		_badge_label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
		_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_badge_label.offset_left = 8
		_badge_label.offset_top = 6
		_badge_label.offset_right = -8
		_badge_label.offset_bottom = -6
		container.add_child(_badge_label)

	func _update_ui() -> void:
		if _tex_rect != null:
			_tex_rect.texture = texture
		if _badge_label != null:
			_badge_label.text = badge_text


# === 房屋编号 token（按地图真实风格绘制：house_with_garden）===
class HouseWithGardenNumberToken extends Control:
	var house_number: int = -1

	var _skin = null
	var _cell_size: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size * 3))
		var t := str(house_number) if house_number > 0 else ""
		tooltip_text = "房屋 %s" % t if not t.is_empty() else "房屋"
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size * 3))
		queue_redraw()

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		# 该 token 内部使用“局部网格”（world==view），以复用 MapCanvasDrawer 的绘制逻辑。
		return world_pos

	func _draw() -> void:
		if _skin == null:
			return
		# MapCanvasDrawerStructuresPass.draw_house_and_garden 依赖 canvas._skin / canvas._world_to_view()
		self._skin = _skin
		var info := {
			"piece_id": "house_with_garden",
			"rotation": 0,
			"house_id": str(house_number) if house_number > 0 else "",
			"min": Vector2i(0, 0),
			"max": Vector2i(1, 2), # 2x3（house 2x2 + garden 2x1）
		}
		StructuresPassClass.draw_house_and_garden(self, _cell_size, Vector2i.ZERO, info, 1.0)


# === 花园 token（按地图风格绘制 2x1 花园扩展 + 数量角标）===
class GardenExtensionToken extends Control:
	var count: int = 0

	var _skin = null
	var _cell_size: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size))
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		custom_minimum_size = Vector2(float(_cell_size * 2), float(_cell_size))
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, custom_minimum_size)
		var bg := Color("#22C55E")
		bg.a = 0.30
		draw_rect(rect, bg, true)

		if _skin != null:
			var tex: Texture2D = _skin.get_piece_texture("garden_large")
			var pad := maxf(2.0, float(_cell_size) * 0.10)
			var inner := rect.grow(-pad)
			MapCanvasDrawerClass._draw_texture_aspect_fit(self, tex, inner, Color(1, 1, 1, 0.9), "center")

		if count > 0:
			# 复用营销板件的编号角标样式（白底圆 + 黑字），用于展示剩余数量。
			MapCanvasDrawerClass._draw_marketing_board_number_badge(self, rect, int(count), _cell_size, 1.0)


# === 营销板件 token（复用 MapCanvasDrawer 的绘制风格）===
class MarketingBoardToken extends Control:
	var board_number: int = 0
	var marketing_type: String = ""
	var footprint_size: Vector2i = Vector2i.ONE

	var _skin = null
	var _cell_size: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_update_min_size()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		_update_min_size()
		queue_redraw()

	func _update_min_size() -> void:
		var size := Vector2(maxi(1, footprint_size.x) * _cell_size, maxi(1, footprint_size.y) * _cell_size)
		custom_minimum_size = size

	func _draw() -> void:
		if _skin == null:
			return
		var placement := {
			"type": marketing_type,
			"board_number": board_number,
			"footprint_size": footprint_size,
			"rotation": 0,
		}
		# MapCanvasDrawer._draw_marketing_placement 依赖 canvas._skin
		self._skin = _skin
		MapCanvasDrawerClass._draw_marketing_placement(self, _cell_size, placement, 1.0, Rect2(Vector2.ZERO, custom_minimum_size))


# === 通用 piece token：按 PieceRegistry footprint 1:1 预览 + 数量角标 ===
class PieceFootprintToken extends Control:
	var piece_id: String = ""
	var count: int = 0

	var _skin = null
	var _cell_size: int = 40
	var _size_cells: Vector2i = Vector2i.ONE
	var _cell_offsets: Array[Vector2i] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_recompute_footprint()
		_update_min_size()
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		_update_min_size()
		queue_redraw()

	func _recompute_footprint() -> void:
		_size_cells = Vector2i.ONE
		_cell_offsets.clear()
		if piece_id.is_empty():
			return
		if not PieceRegistryClass.is_loaded():
			return
		var def_val = PieceRegistryClass.get_def(piece_id) if PieceRegistryClass.has(piece_id) else null
		if not (def_val is PieceDef):
			return
		var def: PieceDef = def_val
		var cells: Array[Vector2i] = MapUtilsClass.get_footprint_cells(def.footprint_mask, def.anchor, Vector2i.ZERO, 0)
		var bounds: Dictionary = MapUtilsClass.get_footprint_bounds(cells)
		var size_val = bounds.get("size", Vector2i.ONE)
		var min_val = bounds.get("min", Vector2i.ZERO)
		var min_pos: Vector2i = min_val if min_val is Vector2i else Vector2i.ZERO
		if size_val is Vector2i:
			var s: Vector2i = size_val
			if s.x > 0 and s.y > 0:
				_size_cells = s
		for c in cells:
			_cell_offsets.append(c - min_pos)

	func _update_min_size() -> void:
		custom_minimum_size = Vector2(float(maxi(1, _size_cells.x) * _cell_size), float(maxi(1, _size_cells.y) * _cell_size))

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, custom_minimum_size)
		var bg := Color(0.97, 0.94, 0.86, 0.95)
		draw_rect(rect, bg, true)
		draw_rect(rect, Color(0.73, 0.23, 0.18, 0.35), false, 1.0)

		# Footprint outline (supports non-rect shapes).
		for off in _cell_offsets:
			var cell_rect := Rect2(Vector2(off.x * _cell_size, off.y * _cell_size), Vector2(_cell_size, _cell_size))
			draw_rect(cell_rect, Color(1, 1, 1, 0.06), true)
			draw_rect(cell_rect, Color(1, 1, 1, 0.12), false, 1.0)

		if _skin != null and not piece_id.is_empty():
			var tex: Texture2D = _skin.get_piece_texture(piece_id)
			var offset_px: Vector2i = _skin.get_piece_offset_px(piece_id)
			var scale: Vector2 = _skin.get_piece_scale(piece_id)
			if tex != null and tex.get_size() != Vector2.ZERO and _size_cells.x > 0 and _size_cells.y > 0:
				var pos_px := Vector2(float(offset_px.x), float(offset_px.y))
				var size_px := Vector2(float(_size_cells.x * _cell_size), float(_size_cells.y * _cell_size)) * scale
				var full := Rect2(pos_px, size_px)
				var mod := Color(1, 1, 1, 0.85)
				var src_cell := tex.get_size() / Vector2(float(_size_cells.x), float(_size_cells.y))
				var dst_cell := Vector2(float(_cell_size), float(_cell_size)) * scale
				if _cell_offsets.size() >= _size_cells.x * _size_cells.y:
					draw_texture_rect(tex, full, false, mod)
				else:
					for off2 in _cell_offsets:
						var dst := Rect2(pos_px + Vector2(float(off2.x * _cell_size), float(off2.y * _cell_size)) * scale, dst_cell)
						var src := Rect2(Vector2(float(off2.x) * src_cell.x, float(off2.y) * src_cell.y), src_cell)
						draw_texture_rect_region(tex, dst, src, mod)

		if count > 0:
			_draw_count_badge(rect, count)

	func _draw_count_badge(rect: Rect2, c: int) -> void:
		var text := "×%d" % int(c)
		var pad := maxf(2.0, float(_cell_size) * 0.06)
		var font: Font = ThemeDB.fallback_font
		var font_size := maxi(10, int(round(float(_cell_size) * 0.32)))
		var est_char_w := float(font_size) * 0.6
		var w := maxf(float(font_size), est_char_w * float(text.length()) + pad * 2.0)
		var h := float(font_size) + pad * 2.0
		var box := Rect2(Vector2(rect.size.x - w - pad, pad), Vector2(w, h))
		draw_rect(box, Color(0, 0, 0, 0.55), true)
		var baseline := Vector2(box.position.x, box.position.y + box.size.y * 0.5 + float(font_size) * 0.35)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, Color(1, 1, 1, 0.95))
