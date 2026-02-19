# 游戏地图视图（M8：MapCanvas 分层绘制 + 缩放功能）
extends ScrollContainer

signal zoom_changed(zoom_level: float)

@onready var canvas: Control = $Content/Canvas

# 缩放配置
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 0.1

var _current_zoom: float = 1.0
var _target_zoom: float = 1.0
var _zoom_center: Vector2 = Vector2.ZERO
var _is_zooming: bool = false

# 拖拽平移
var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _scroll_start: Vector2 = Vector2.ZERO

var _auto_fit_base_size: Vector2 = Vector2.ZERO
var _auto_fit_done_for_base_size: bool = false
var _auto_fit_scheduled: bool = false

func _ready() -> void:
	# 缩放/拖拽使用 _gui_input（依赖 MapCanvas/Content.mouse_filter=PASS 冒泡到 MapView）
	set_process(false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# 鼠标滚轮缩放（wheel 事件在不同平台/设备下可能不走 pressed=true）
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(get_local_mouse_position(), ZOOM_STEP)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(get_local_mouse_position(), -ZOOM_STEP)
			accept_event()
			return

		# 中键/右键拖拽平移
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_is_dragging = true
				_drag_start_pos = mb.position
				_scroll_start = Vector2(scroll_horizontal, scroll_vertical)
				accept_event()
				return
			if not mb.pressed and _is_dragging:
				_is_dragging = false
				accept_event()
				return

	# 拖拽平移
	if event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var delta := _drag_start_pos - mm.position
		scroll_horizontal = int(_scroll_start.x + delta.x)
		scroll_vertical = int(_scroll_start.y + delta.y)
		accept_event()

func _zoom_at(screen_pos: Vector2, delta: float) -> void:
	set_zoom(_target_zoom + delta, false)

func _apply_zoom(prev_zoom: float) -> void:
	if not is_instance_valid(canvas):
		return

	var safe_prev_zoom := maxf(0.0001, prev_zoom)

	# 保存当前视图中心点（以“未缩放像素”表示）
	var viewport_center := Vector2(scroll_horizontal, scroll_vertical) + size / 2
	var base_center := viewport_center / safe_prev_zoom

	# 应用新缩放（由 MapCanvas 负责更新 custom_minimum_size 与绘制尺寸）
	if canvas.has_method("set_zoom"):
		canvas.call("set_zoom", _current_zoom)
	else:
		canvas.scale = Vector2(_current_zoom, _current_zoom)

	# 尝试保持视图中心不变
	await get_tree().process_frame
	var new_viewport_center := base_center * _current_zoom
	scroll_horizontal = maxi(0, int(new_viewport_center.x - size.x / 2))
	scroll_vertical = maxi(0, int(new_viewport_center.y - size.y / 2))
	# 缩放后内容尺寸可能变小/变大，需把滚动位置 clamp 回有效范围，避免“缩放后看到大片空白”。
	var max_scroll_x := maxi(0, int(canvas.size.x - size.x))
	var max_scroll_y := maxi(0, int(canvas.size.y - size.y))
	scroll_horizontal = clampi(scroll_horizontal, 0, max_scroll_x)
	scroll_vertical = clampi(scroll_vertical, 0, max_scroll_y)

func set_game_state(state: GameState) -> void:
	if state == null:
		clear()
		return
	if is_instance_valid(canvas) and canvas.has_method("set_game_state"):
		canvas.call("set_game_state", state)
	_request_auto_fit_if_needed()

func set_map_data(map_data: Dictionary) -> void:
	if map_data.is_empty():
		clear()
		return
	if is_instance_valid(canvas) and canvas.has_method("set_map_data"):
		canvas.call("set_map_data", map_data)
	_request_auto_fit_if_needed()

func clear() -> void:
	if is_instance_valid(canvas) and canvas.has_method("clear"):
		canvas.call("clear")
	_auto_fit_base_size = Vector2.ZERO
	_auto_fit_done_for_base_size = false
	_auto_fit_scheduled = false

# === 公共缩放控制方法 ===

func set_zoom(zoom_level: float, animate: bool = true) -> void:
	var prev_zoom := _current_zoom
	_target_zoom = clampf(zoom_level, ZOOM_MIN, ZOOM_MAX)
	# 先保证可用：缩放当帧生效（不依赖 _process）
	_current_zoom = _target_zoom
	_is_zooming = false
	_apply_zoom(prev_zoom)
	zoom_changed.emit(_current_zoom)

func get_zoom() -> float:
	return _current_zoom

func zoom_in() -> void:
	set_zoom(_target_zoom + ZOOM_STEP, false)

func zoom_out() -> void:
	set_zoom(_target_zoom - ZOOM_STEP, false)

func reset_zoom() -> void:
	set_zoom(1.0, false)

func fit_to_view() -> void:
	if not is_instance_valid(canvas):
		return

	var canvas_size: Vector2
	if canvas.has_method("get_base_size"):
		canvas_size = canvas.call("get_base_size")
	else:
		canvas_size = canvas.custom_minimum_size

	if canvas_size.x <= 0 or canvas_size.y <= 0:
		return

	var view_size := size
	var zoom_x := view_size.x / canvas_size.x
	var zoom_y := view_size.y / canvas_size.y
	var fit_zoom := minf(zoom_x, zoom_y) * 0.95  # 留一点边距

	set_zoom(clampf(fit_zoom, ZOOM_MIN, ZOOM_MAX), false)

func _request_auto_fit_if_needed() -> void:
	if not is_instance_valid(canvas):
		return

	var canvas_size: Vector2
	if canvas.has_method("get_base_size"):
		canvas_size = canvas.call("get_base_size")
	else:
		canvas_size = canvas.custom_minimum_size

	if canvas_size.x <= 0 or canvas_size.y <= 0:
		return

	# 仅在“首次拿到 map_size”或 map_size 变化时自动 fit 一次，避免覆盖玩家手动缩放。
	if canvas_size != _auto_fit_base_size:
		_auto_fit_base_size = canvas_size
		_auto_fit_done_for_base_size = false

	if _auto_fit_done_for_base_size:
		return

	_schedule_auto_fit()

func _schedule_auto_fit() -> void:
	if _auto_fit_scheduled:
		return
	_auto_fit_scheduled = true
	call_deferred("_auto_fit_if_needed")

func _auto_fit_if_needed() -> void:
	_auto_fit_scheduled = false
	if _auto_fit_done_for_base_size:
		return

	# 等待布局稳定，避免 size/custom_minimum_size 还未生效时 fit 失败。
	await get_tree().process_frame
	await get_tree().process_frame

	if size.x <= 0 or size.y <= 0:
		_schedule_auto_fit()
		return

	fit_to_view()
	_auto_fit_done_for_base_size = true

func center_on_position(world_pos: Vector2i) -> void:
	if not is_instance_valid(canvas):
		return

	var cell_size: int = 40  # 默认值
	if canvas.has_method("get_cell_size"):
		cell_size = int(canvas.call("get_cell_size"))

	var world_origin := Vector2i.ZERO
	if canvas.has_method("get_world_origin"):
		var wo = canvas.call("get_world_origin")
		if wo is Vector2i:
			world_origin = wo

	var view_pos := world_pos - world_origin
	var screen_pos := Vector2(view_pos) * float(cell_size)
	var target_scroll := screen_pos - size / 2

	scroll_horizontal = maxi(0, int(target_scroll.x))
	scroll_vertical = maxi(0, int(target_scroll.y))
