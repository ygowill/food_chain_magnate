# ReserveAreaFullScreenView token helpers (moved out to keep the view script small).
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map/drawer/passes/structures_pass.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const TilePreviewFactoryClass = preload("res://ui/components/reserve_area/tile_preview_factory.gd")


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


# === 地图板块 token（仅显示板块预览）===
class TileSupplyToken extends Control:
	var tile_id: String = ""
	var count: int = 0

	var _cell_size: int = 40
	var _preview = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_build_ui()
		_update_layout()
		_update_ui()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		_update_layout()
		_update_ui()

	func _build_ui() -> void:
		_preview = TilePreviewFactoryClass.create_preview()
		if _preview == null:
			var fallback := Label.new()
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_preview = fallback
		if _preview != null:
			_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_preview)

	func _update_layout() -> void:
		var preview_size := float(maxi(84, int(round(float(_cell_size) * 2.3))))
		custom_minimum_size = Vector2(preview_size, preview_size)
		if _preview != null:
			_preview.position = Vector2.ZERO
			_preview.custom_minimum_size = Vector2(preview_size, preview_size)
			_preview.size = Vector2(preview_size, preview_size)

	func _update_ui() -> void:
		var id_text := str(tile_id).strip_edges()
		if _preview != null and _preview.has_method("set_tile"):
			_preview.set_tile(id_text, 0)
		elif _preview is Label:
			var fallback_label: Label = _preview
			fallback_label.text = id_text if not id_text.is_empty() else "tile"
		if id_text.is_empty():
			tooltip_text = "地图板块"
		else:
			tooltip_text = "地图板块 %s x%d" % [id_text, maxi(0, int(count))]


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
		var bg := _get_garden_bg_color()
		bg.a = 1.0
		draw_rect(rect, bg, true)

		if _skin != null:
			var tex: Texture2D = _skin.get_piece_texture("garden_large")
			var pad := maxf(2.0, float(_cell_size) * 0.10)
			var inner := rect.grow(-pad)
			MapCanvasDrawerClass._draw_texture_aspect_fit(self, tex, inner, Color(1, 1, 1, 0.9), "center")

		if count > 0:
			# 复用营销板件的编号角标样式（白底圆 + 黑字），用于展示剩余数量。
			MapCanvasDrawerClass._draw_marketing_board_number_badge(self, rect, int(count), _cell_size, 1.0)

	func _get_garden_bg_color() -> Color:
		return StructuresPassClass.GARDEN_BG_COLOR


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
	var owner_logo_id: int = -1

	var _skin = null
	var _cell_size: int = 40
	var _size_cells: Vector2i = Vector2i.ONE
	var _anchor_cell: Vector2i = Vector2i.ZERO
	var _cell_offsets: Array[Vector2i] = []
	var _player_restaurant_logo_ids: Dictionary = {} # pseudo player_id -> logo_id
	var _structures_by_anchor: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_recompute_footprint()
		_update_min_size()
		queue_redraw()

	func set_skin(skin) -> void:
		_skin = skin
		_recompute_footprint()
		_update_min_size()
		queue_redraw()

	func set_cell_size(cell_size: int) -> void:
		_cell_size = maxi(1, int(cell_size))
		_update_min_size()
		queue_redraw()

	func _recompute_footprint() -> void:
		_size_cells = Vector2i.ONE
		_anchor_cell = Vector2i.ZERO
		_cell_offsets.clear()
		_cell_offsets.append(Vector2i.ZERO)
		if piece_id.is_empty():
			return
		if not PieceRegistryClass.is_loaded():
			_apply_texture_aspect_fallback()
			return
		var def_val = PieceRegistryClass.get_def(piece_id) if PieceRegistryClass.has(piece_id) else null
		if not (def_val is PieceDef):
			_apply_texture_aspect_fallback()
			return
		var def: PieceDef = def_val
		var cells: Array[Vector2i] = MapUtilsClass.get_footprint_cells(def.footprint_mask, def.anchor, Vector2i.ZERO, 0)
		if cells.is_empty():
			_apply_texture_aspect_fallback()
			return
		var bounds: Dictionary = MapUtilsClass.get_footprint_bounds(cells)
		var size_val = bounds.get("size", Vector2i.ONE)
		var min_val = bounds.get("min", Vector2i.ZERO)
		var min_pos: Vector2i = min_val if min_val is Vector2i else Vector2i.ZERO
		if size_val is Vector2i:
			var s: Vector2i = size_val
			if s.x > 0 and s.y > 0:
				_size_cells = s
		_anchor_cell = Vector2i.ZERO - min_pos
		_cell_offsets.clear()
		for c in cells:
			_cell_offsets.append(c - min_pos)
		if _cell_offsets.is_empty():
			_cell_offsets.append(Vector2i.ZERO)

	func _apply_texture_aspect_fallback() -> void:
		var tex: Texture2D = _resolve_texture_for_draw()
		if tex == null:
			return
		var tex_size := tex.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return

		var ratio := tex_size.x / tex_size.y
		_size_cells = Vector2i.ONE
		if ratio >= 1.35:
			_size_cells = Vector2i(clampi(int(round(ratio)), 1, 4), 1)
		elif ratio <= 0.74:
			_size_cells = Vector2i(1, clampi(int(round(1.0 / ratio)), 1, 4))

		_anchor_cell = Vector2i.ZERO
		_cell_offsets.clear()
		for y in range(_size_cells.y):
			for x in range(_size_cells.x):
				_cell_offsets.append(Vector2i(x, y))
		if _cell_offsets.is_empty():
			_cell_offsets.append(Vector2i.ZERO)

	func _update_min_size() -> void:
		custom_minimum_size = Vector2(float(maxi(1, _size_cells.x) * _cell_size), float(maxi(1, _size_cells.y) * _cell_size))

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		return world_pos

	func _is_valid_world_pos(world_pos: Vector2i) -> bool:
		return world_pos.x >= 0 and world_pos.x < _size_cells.x and world_pos.y >= 0 and world_pos.y < _size_cells.y

	func _get_restaurant_logo_piece_ids() -> Array:
		if _skin == null or not _skin.has_method("get_restaurant_logo_piece_ids"):
			return []
		var ids_val = _skin.get_restaurant_logo_piece_ids()
		if ids_val is Array:
			return ids_val
		return []

	func _draw_piece_with_map_style() -> void:
		if _skin == null:
			return
		var pid := str(piece_id).strip_edges()
		if pid.is_empty():
			return

		var owner := -1
		_player_restaurant_logo_ids.clear()
		if owner_logo_id >= 0:
			owner = 0
			_player_restaurant_logo_ids[owner] = owner_logo_id

		var info := {
			"piece_id": pid,
			"rotation": 0,
			"owner": owner,
			"min": Vector2i.ZERO,
			"max": _size_cells - Vector2i.ONE,
			"cells": _cell_offsets.duplicate(),
		}
		_structures_by_anchor.clear()
		_structures_by_anchor[_anchor_cell] = info
		StructuresPassClass.draw_structures(self, _cell_size, _get_restaurant_logo_piece_ids())

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, custom_minimum_size)
		if _skin != null and not str(piece_id).strip_edges().is_empty():
			_draw_piece_with_map_style()
		else:
			draw_rect(rect, Color(0.97, 0.94, 0.86, 0.95), true)
			draw_rect(rect, Color(0.73, 0.23, 0.18, 0.35), false, 1.0)

		if count > 0:
			_draw_count_badge(rect, count)

	func _resolve_texture_for_draw() -> Texture2D:
		if _skin == null:
			return null
		var pid := str(piece_id).strip_edges()
		if pid.is_empty():
			return null

		var hints := PieceUiHintsRegistryClass.get_hints(pid)
		var style := str(hints.get("structure_style", "")).strip_edges()
		if (style == "player_logo" or style == "player_logo_bg") and owner_logo_id >= 0:
			var logo_ids_val = _skin.get_restaurant_logo_piece_ids() if _skin.has_method("get_restaurant_logo_piece_ids") else null
			if logo_ids_val is Array:
				var logo_ids: Array = logo_ids_val
				if owner_logo_id >= 0 and owner_logo_id < logo_ids.size():
					var base_key := str(logo_ids[owner_logo_id]).strip_edges()
					if not base_key.is_empty():
						var logo_key := base_key
						var suffix := str(hints.get("logo_variant_suffix", "")).strip_edges()
						if not suffix.is_empty():
							var var_key := "%s%s" % [base_key, suffix]
							var piece_textures_val = _skin.get("piece_textures")
							if piece_textures_val is Dictionary and Dictionary(piece_textures_val).has(var_key):
								logo_key = var_key
						return _skin.get_piece_texture(logo_key)

		return _skin.get_piece_texture(pid)

	func _draw_count_badge(rect: Rect2, c: int) -> void:
		var text := "x%d" % int(c)
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
