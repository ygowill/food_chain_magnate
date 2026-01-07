# 需求指示器组件
# 在地图上显示房屋的食物/饮料需求
class_name DemandIndicator
extends Control

var _house_demands: Dictionary = {}  # house_id -> {demands, position, satisfied}
var _demand_markers: Dictionary = {}  # house_id -> DemandMarker
var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO

# 产品图标
const PRODUCT_ICONS: Dictionary = {
	"burger": "🍔",
	"pizza": "🍕",
	"drink": "🥤",
	"lemonade": "🍋",
	"beer": "🍺",
}

func _ready() -> void:
	# 确保在地图上层显示
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	_update_marker_positions()

func set_map_offset(offset: Vector2) -> void:
	_map_offset = offset
	_update_marker_positions()

func set_house_demands(demands: Dictionary) -> void:
	_house_demands = demands.duplicate(true)
	_rebuild_markers()

func update_house_demand(house_id: String, demand: Dictionary) -> void:
	_house_demands[house_id] = demand.duplicate()
	_update_marker(house_id)

func mark_satisfied(house_id: String, satisfied: bool) -> void:
	if _house_demands.has(house_id):
		_house_demands[house_id]["satisfied"] = satisfied
		_update_marker(house_id)

func clear_all() -> void:
	_house_demands.clear()
	for marker in _demand_markers.values():
		if is_instance_valid(marker):
			marker.queue_free()
	_demand_markers.clear()

func _rebuild_markers() -> void:
	# 清除旧标记
	for marker in _demand_markers.values():
		if is_instance_valid(marker):
			marker.queue_free()
	_demand_markers.clear()

	# 创建新标记
	for house_id in _house_demands.keys():
		_create_marker(house_id)

func _create_marker(house_id: String) -> void:
	var data: Dictionary = _house_demands.get(house_id, {})
	var demands: Dictionary = data.get("demands", {})
	var grid_pos: Vector2i = data.get("position", Vector2i(0, 0))
	var satisfied: bool = data.get("satisfied", false)

	if demands.is_empty():
		return

	var marker := DemandMarker.new()
	marker.house_id = house_id
	marker.demands = demands
	marker.is_satisfied = satisfied
	add_child(marker)
	_demand_markers[house_id] = marker

	# 设置位置（在格子上方）
	var pixel_pos := Vector2(grid_pos.x, grid_pos.y) * _tile_size + _map_offset
	marker.position = pixel_pos + Vector2(_tile_size.x / 2, -10)

func _update_marker(house_id: String) -> void:
	if not _demand_markers.has(house_id):
		if _house_demands.has(house_id):
			_create_marker(house_id)
		return

	var marker: DemandMarker = _demand_markers[house_id]
	if not is_instance_valid(marker):
		if _house_demands.has(house_id):
			_create_marker(house_id)
		return

	var data: Dictionary = _house_demands.get(house_id, {})
	marker.demands = data.get("demands", {})
	marker.is_satisfied = data.get("satisfied", false)
	marker.update_display()

func _update_marker_positions() -> void:
	for house_id in _demand_markers.keys():
		var marker: DemandMarker = _demand_markers[house_id]
		if not is_instance_valid(marker):
			continue

		var data: Dictionary = _house_demands.get(house_id, {})
		var grid_pos: Vector2i = data.get("position", Vector2i(0, 0))
		var pixel_pos := Vector2(grid_pos.x, grid_pos.y) * _tile_size + _map_offset
		marker.position = pixel_pos + Vector2(_tile_size.x / 2, -10)


# === 内部类：需求标记 ===
class DemandMarker extends Control:
	var house_id: String = ""
	var demands: Dictionary = {}
	var is_satisfied: bool = false

	var _background: ColorRect
	var _icons_container: HBoxContainer

	const PRODUCT_ICONS: Dictionary = {
		"burger": "🍔",
		"pizza": "🍕",
		"drink": "🥤",
		"lemonade": "🍋",
		"beer": "🍺",
	}

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		# 设置锚点使其居中显示
		set_anchors_preset(Control.PRESET_CENTER_TOP)
		size = Vector2(80, 24)
		position -= size / 2

		# 背景
		_background = ColorRect.new()
		_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		_background.color = Color(0.1, 0.1, 0.1, 0.85)
		add_child(_background)

		# 图标容器
		_icons_container = HBoxContainer.new()
		_icons_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		_icons_container.alignment = BoxContainer.ALIGNMENT_CENTER
		_icons_container.add_theme_constant_override("separation", 2)
		add_child(_icons_container)

		update_display()

	func update_display() -> void:
		if _icons_container == null:
			return

		# 清除旧图标
		for child in _icons_container.get_children():
			child.queue_free()

		# 添加新图标
		for prod_type in demands.keys():
			var count: int = int(demands[prod_type])
			if count <= 0:
				continue

			var icon_label := Label.new()
			icon_label.add_theme_font_size_override("font_size", 12)
			var icon: String = PRODUCT_ICONS.get(prod_type, "?")

			if count > 1:
				icon_label.text = "%s×%d" % [icon, count]
			else:
				icon_label.text = icon

			_icons_container.add_child(icon_label)

		# 更新背景颜色
		if _background != null:
			if is_satisfied:
				_background.color = Color(0.15, 0.25, 0.15, 0.8)
			else:
				_background.color = Color(0.1, 0.1, 0.1, 0.85)

		# 调整大小
		await get_tree().process_frame
		var content_width := _icons_container.get_combined_minimum_size().x
		size.x = max(40, content_width + 16)
		position.x = -size.x / 2
