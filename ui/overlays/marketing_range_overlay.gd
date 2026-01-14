# 营销范围覆盖层组件
# 显示营销活动的影响范围
class_name MarketingRangeOverlay
extends Control

signal range_clicked(position: Vector2i)

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")

var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO

var _marketing_campaigns: Array[Dictionary] = []  # [{position, range, type, player_id, tiles?}]
var _range_rects: Array[ColorRect] = []
var _center_markers: Array[Control] = []

const RANGE_BASE_COLOR := Color("#4A90D9")

var _visual_modules: Array[String] = []
var _skin = null
var _pulse_tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_pulse()

func set_visual_modules(modules: Array[String]) -> void:
	_visual_modules = Array(modules, TYPE_STRING, "", null)
	_skin = null
	_ensure_skin()
	_rebuild_visuals()

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	_rebuild_visuals()

func set_map_offset(offset: Vector2) -> void:
	_map_offset = offset
	_rebuild_visuals()

func add_campaign(position: Vector2i, range_val: int, marketing_type: String, player_id: int = -1, tiles: Array[Vector2i] = []) -> void:
	var campaign: Dictionary = {
		"position": position,
		"range": range_val,
		"type": marketing_type,
		"player_id": player_id,
	}
	if not tiles.is_empty():
		campaign["tiles"] = tiles.duplicate()

	_marketing_campaigns.append(campaign)
	_add_campaign_visual(campaign)

func show_preview(position: Vector2i, range_val: int, marketing_type: String, tiles: Array[Vector2i] = []) -> void:
	# 清除旧预览
	clear_all()

	# 添加预览
	add_campaign(position, range_val, marketing_type, -1, tiles)

func set_campaigns(campaigns: Array[Dictionary]) -> void:
	clear_all()
	for campaign in campaigns:
		_marketing_campaigns.append(campaign.duplicate())
		_add_campaign_visual(campaign)

func clear_all() -> void:
	_marketing_campaigns.clear()

	for rect in _range_rects:
		if is_instance_valid(rect):
			rect.queue_free()
	_range_rects.clear()

	for marker in _center_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_center_markers.clear()

func _add_campaign_visual(campaign: Dictionary) -> void:
	var center: Vector2i = campaign.position
	var range_val: int = campaign.range
	var m_type: String = campaign.type

	var fill_color := RANGE_BASE_COLOR
	fill_color.a = 0.3
	var border_color := RANGE_BASE_COLOR
	border_color.a = 0.8

	# 指定格子（例如：按规则计算的“受影响房屋”集合）
	var tiles_val = campaign.get("tiles", null)
	if tiles_val is Array and not (tiles_val as Array).is_empty():
		for tile_pos_val in (tiles_val as Array):
			if not (tile_pos_val is Vector2i):
				continue
			var tile_pos: Vector2i = tile_pos_val
			var rect := ColorRect.new()
			rect.position = Vector2(tile_pos.x, tile_pos.y) * _tile_size + _map_offset
			rect.size = _tile_size
			rect.color = fill_color
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(rect)
			_range_rects.append(rect)

		# 添加中心标记
		var center_marker2 := _create_center_marker(center, m_type, border_color)
		add_child(center_marker2)
		_center_markers.append(center_marker2)
		return

	# range_val <= 0：仅显示中心标记（例如：未提供 tiles 的轻量预览）
	if range_val <= 0:
		var center_marker3 := _create_center_marker(center, m_type, border_color)
		add_child(center_marker3)
		_center_markers.append(center_marker3)
		return

	# 获取范围内的所有格子
	var affected_tiles := _get_tiles_in_range(center, range_val)

	for tile_pos in affected_tiles:
		var rect := ColorRect.new()
		rect.position = Vector2(tile_pos.x, tile_pos.y) * _tile_size + _map_offset
		rect.size = _tile_size
		rect.color = fill_color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_range_rects.append(rect)

	# 添加中心标记
	var center_marker := _create_center_marker(center, m_type, border_color)
	add_child(center_marker)
	_center_markers.append(center_marker)

func _add_fullscreen_overlay(color: Color) -> void:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	_range_rects.append(rect)

func _get_tiles_in_range(center: Vector2i, range_val: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for dx in range(-range_val, range_val + 1):
		for dy in range(-range_val, range_val + 1):
			var distance := absi(dx) + absi(dy)
			if distance <= range_val:
				result.append(center + Vector2i(dx, dy))

	return result

func _create_center_marker(position: Vector2i, m_type: String, color: Color) -> Control:
	var marker := Control.new()
	var pixel_pos := Vector2(position.x, position.y) * _tile_size + _map_offset

	marker.position = pixel_pos
	marker.custom_minimum_size = _tile_size
	marker.size = _tile_size
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 边框
	var border := ColorRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.color = Color(0, 0, 0, 0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(border)

	# 中心图标（营销贴图）
	_ensure_skin()
	var icon_rect := TextureRect.new()
	icon_rect.set_anchors_preset(Control.PRESET_CENTER)
	icon_rect.custom_minimum_size = Vector2(24, 24)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _skin != null and _skin.has_method("get_marketing_texture"):
		icon_rect.texture = _skin.get_marketing_texture(m_type)
	marker.add_child(icon_rect)

	# 范围圈（使用自定义绘制）
	var range_circle := RangeCircle.new()
	range_circle.color = color
	range_circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	range_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(range_circle)

	return marker

func _rebuild_visuals() -> void:
	var campaigns_copy := _marketing_campaigns.duplicate(true)
	clear_all()
	_marketing_campaigns = campaigns_copy

	for campaign in _marketing_campaigns:
		_add_campaign_visual(campaign)

func _ensure_skin() -> void:
	if _skin != null:
		return

	var base_dir := "res://modules"
	if Globals != null:
		base_dir = str(Globals.modules_v2_base_dir)
	var mods := _visual_modules
	if mods.is_empty() and Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)
	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _start_pulse() -> void:
	if OS.has_feature("headless"):
		return
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(self, "modulate", Color(1, 1, 1, 0.85), 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# === 内部类：范围圈绘制 ===
class RangeCircle extends Control:
	var color: Color = Color.WHITE

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5 - 2.0
		var dash_count: int = 24
		var step: float = TAU / float(dash_count)
		var dash: float = step * 0.65
		for i in range(dash_count):
			var a1: float = float(i) * step
			var a2: float = a1 + dash
			var p1: Vector2 = center + Vector2(cos(a1), sin(a1)) * radius
			var p2: Vector2 = center + Vector2(cos(a2), sin(a2)) * radius
			draw_line(p1, p2, color, 2.0)
