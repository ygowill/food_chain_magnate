# 营销范围覆盖层组件
# 显示营销活动的影响范围
class_name MarketingRangeOverlay
extends Control

signal range_clicked(position: Vector2i)

var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO

var _marketing_campaigns: Array[Dictionary] = []  # [{position, range, type, player_id}]
var _range_rects: Array[ColorRect] = []
var _center_markers: Array[Control] = []

# 营销类型颜色
const MARKETING_COLORS: Dictionary = {
	"billboard": Color(0.4, 0.7, 0.9, 0.3),
	"mailbox": Color(0.5, 0.8, 0.5, 0.3),
	"airplane": Color(0.9, 0.7, 0.4, 0.3),
	"radio": Color(0.8, 0.5, 0.8, 0.2),
}

const MARKETING_BORDER_COLORS: Dictionary = {
	"billboard": Color(0.4, 0.7, 0.9, 0.8),
	"mailbox": Color(0.5, 0.8, 0.5, 0.8),
	"airplane": Color(0.9, 0.7, 0.4, 0.8),
	"radio": Color(0.8, 0.5, 0.8, 0.6),
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	_rebuild_visuals()

func set_map_offset(offset: Vector2) -> void:
	_map_offset = offset
	_rebuild_visuals()

func add_campaign(position: Vector2i, range_val: int, marketing_type: String, player_id: int = -1) -> void:
	var campaign: Dictionary = {
		"position": position,
		"range": range_val,
		"type": marketing_type,
		"player_id": player_id,
	}

	_marketing_campaigns.append(campaign)
	_add_campaign_visual(campaign)

func show_preview(position: Vector2i, range_val: int, marketing_type: String) -> void:
	# 清除旧预览
	clear_all()

	# 添加预览
	add_campaign(position, range_val, marketing_type, -1)

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

	var fill_color: Color = MARKETING_COLORS.get(m_type, Color(0.5, 0.5, 0.5, 0.3))
	var border_color: Color = MARKETING_BORDER_COLORS.get(m_type, Color(0.5, 0.5, 0.5, 0.6))

	# 电台广告：全图范围
	if range_val == 0:
		_add_fullscreen_overlay(fill_color)
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

	# 边框
	var border := ColorRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.color = Color(0, 0, 0, 0)
	marker.add_child(border)

	# 中心图标
	var icon_label := Label.new()
	icon_label.set_anchors_preset(Control.PRESET_CENTER)
	icon_label.add_theme_font_size_override("font_size", 20)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	match m_type:
		"billboard":
			icon_label.text = "B"
		"mailbox":
			icon_label.text = "M"
		"airplane":
			icon_label.text = "A"
		"radio":
			icon_label.text = "R"
		_:
			icon_label.text = "?"

	icon_label.add_theme_color_override("font_color", color)
	marker.add_child(icon_label)

	# 范围圈（使用自定义绘制）
	var range_circle := RangeCircle.new()
	range_circle.color = color
	range_circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.add_child(range_circle)

	return marker

func _rebuild_visuals() -> void:
	var campaigns_copy := _marketing_campaigns.duplicate(true)
	clear_all()
	_marketing_campaigns = campaigns_copy

	for campaign in _marketing_campaigns:
		_add_campaign_visual(campaign)


# === 内部类：范围圈绘制 ===
class RangeCircle extends Control:
	var color: Color = Color.WHITE

	func _draw() -> void:
		var center := size / 2
		var radius = min(size.x, size.y) / 2 - 2
		draw_arc(center, radius, 0, TAU, 32, color, 2.0)
