# 需求指示器组件
# 在地图上显示房屋的食物/饮料需求
class_name DemandIndicator
extends Control

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

const MARKER_BASE_TILE_SIZE := 40.0
const MARKER_MIN_SCALE := 0.35
const MARKER_MAX_SCALE := 1.0

var _house_demands: Dictionary = {}  # house_id -> {demands, position, satisfied}
var _demand_markers: Dictionary = {}  # house_id -> DemandMarker
var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO

var _visual_modules: Array[String] = []
var _skin = null

func _ready() -> void:
	# 确保在地图上层显示
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_visual_modules(modules: Array[String]) -> void:
	_visual_modules = Array(modules, TYPE_STRING, "", null)
	_skin = null
	_ensure_skin()
	_update_marker_skins()

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	var scale := _get_marker_scale()
	for marker in _demand_markers.values():
		if is_instance_valid(marker):
			marker.set_visual_scale(scale)
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
	var satisfied: bool = data.get("satisfied", false)

	if demands.is_empty():
		return

	var marker := DemandMarker.new()
	marker.house_id = house_id
	marker.demands = demands
	marker.is_satisfied = satisfied
	marker.skin = _skin
	marker.set_visual_scale(_get_marker_scale())
	marker.layout_changed.connect(_on_marker_layout_changed.bind(house_id))
	add_child(marker)
	_demand_markers[house_id] = marker

	_position_marker(house_id, marker)

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
	marker.skin = _skin
	marker.set_visual_scale(_get_marker_scale())
	marker.update_display()
	_position_marker(house_id, marker)

func _update_marker_positions() -> void:
	for house_id in _demand_markers.keys():
		var marker: DemandMarker = _demand_markers[house_id]
		if not is_instance_valid(marker):
			continue

		_position_marker(house_id, marker)

func _get_marker_scale() -> float:
	var ref := minf(_tile_size.x, _tile_size.y)
	if ref <= 0.0:
		ref = MARKER_BASE_TILE_SIZE
	return clampf(ref / MARKER_BASE_TILE_SIZE, MARKER_MIN_SCALE, MARKER_MAX_SCALE)

func _position_marker(house_id: String, marker: DemandMarker) -> void:
	if not is_instance_valid(marker):
		return
	var data: Dictionary = _house_demands.get(house_id, {})
	var grid_pos: Vector2i = data.get("position", Vector2i.ZERO)
	var pixel_pos := Vector2(float(grid_pos.x), float(grid_pos.y)) * _tile_size + _map_offset
	var margin_top := maxf(2.0, _tile_size.y * 0.10)
	marker.position = Vector2(
		pixel_pos.x + (_tile_size.x - marker.size.x) * 0.5,
		pixel_pos.y - marker.size.y - margin_top
	)

func _on_marker_layout_changed(house_id: String) -> void:
	if not _demand_markers.has(house_id):
		return
	var marker: DemandMarker = _demand_markers[house_id]
	if not is_instance_valid(marker):
		return
	_position_marker(house_id, marker)

func _ensure_skin() -> void:
	if _skin != null:
		return

	var base_dir := ModulesBaseDirClass.get_base_dir()
	var mods := _visual_modules
	if mods.is_empty() and Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)
	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _update_marker_skins() -> void:
	for house_id in _demand_markers.keys():
		var marker: DemandMarker = _demand_markers[house_id]
		if not is_instance_valid(marker):
			continue
		marker.skin = _skin
		marker.update_display()


# === 内部类：需求标记 ===
class DemandMarker extends Control:
	signal layout_changed

	var house_id: String = ""
	var demands: Dictionary = {}
	var is_satisfied: bool = false
	var skin = null
	var _visual_scale: float = 1.0
	var _layout_version: int = 0

	var _background: ColorRect
	var _icons_container: HBoxContainer

	func _ready() -> void:
		_build_ui()

	func set_visual_scale(scale: float) -> void:
		var s := clampf(float(scale), MARKER_MIN_SCALE, MARKER_MAX_SCALE)
		if is_equal_approx(_visual_scale, s):
			return
		_visual_scale = s
		update_display()

	func _build_ui() -> void:
		# marker 使用左上角定位，由外层 DemandIndicator 统一计算位置。
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		size = Vector2(40, 20)

		# 背景
		_background = ColorRect.new()
		_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		_background.color = Color(0.97, 0.94, 0.86, 0.92)
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
		_layout_version += 1
		var local_ver := _layout_version

		var icon_px := maxi(6, int(round(16.0 * _visual_scale)))
		var count_font_size := maxi(8, int(round(12.0 * _visual_scale)))
		var row_gap := maxi(1, int(round(2.0 * _visual_scale)))
		var padding_h := maxi(4, int(round(8.0 * _visual_scale)))
		var padding_v := maxi(2, int(round(4.0 * _visual_scale)))
		_icons_container.add_theme_constant_override("separation", row_gap)

		# 清除旧图标
		for child in _icons_container.get_children():
			child.queue_free()

		# 添加新图标
		var keys := demands.keys()
		keys.sort()
		for prod_type in keys:
			var count: int = int(demands.get(prod_type, 0))
			if count <= 0:
				continue

			var pid := str(prod_type)
			if pid == "cola":
				pid = "soda"

			var tex: Texture2D = null
			if skin != null and skin.has_method("get_product_icon_texture"):
				tex = skin.get_product_icon_texture(pid)

			var icon_rect := TextureRect.new()
			icon_rect.custom_minimum_size = Vector2(float(icon_px), float(icon_px))
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture = tex
			_icons_container.add_child(icon_rect)

			if count > 1:
				var count_label := Label.new()
				count_label.add_theme_font_size_override("font_size", count_font_size)
				count_label.text = "x%d" % count
				_icons_container.add_child(count_label)

		# 更新背景颜色
		if _background != null:
			if is_satisfied:
				_background.color = Color(0.90, 0.93, 0.85, 0.85)
			else:
				_background.color = Color(0.97, 0.94, 0.86, 0.92)

		# 调整大小
		await get_tree().process_frame
		if local_ver != _layout_version:
			return
		if not is_inside_tree():
			return
		var content_width := _icons_container.get_combined_minimum_size().x
		size.x = max(float(icon_px + padding_h * 2), content_width + float(padding_h * 2))
		size.y = float(icon_px + padding_v * 2)
		layout_changed.emit()
