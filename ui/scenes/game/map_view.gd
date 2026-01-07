# 游戏地图视图（M8：MapCanvas 分层绘制 + 缩放功能）
extends ScrollContainer

signal zoom_changed(zoom_level: float)

@onready var canvas: Control = $Canvas

# 缩放配置
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 0.1
const ZOOM_SMOOTH_SPEED: float = 10.0

var _current_zoom: float = 1.0
var _target_zoom: float = 1.0
var _zoom_center: Vector2 = Vector2.ZERO
var _is_zooming: bool = false

# 拖拽平移
var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _scroll_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	# 启用鼠标滚轮缩放
	set_process_input(true)

func _process(delta: float) -> void:
	# 平滑缩放
	if _is_zooming:
		var diff := _target_zoom - _current_zoom
		if absf(diff) < 0.001:
			_current_zoom = _target_zoom
			_is_zooming = false
		else:
			_current_zoom = lerpf(_current_zoom, _target_zoom, delta * ZOOM_SMOOTH_SPEED)
		_apply_zoom()

func _gui_input(event: InputEvent) -> void:
	# 鼠标滚轮缩放
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_zoom_at(mb.position, ZOOM_STEP)
					accept_event()
				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom_at(mb.position, -ZOOM_STEP)
					accept_event()
				MOUSE_BUTTON_MIDDLE:
					# 中键拖拽
					_is_dragging = true
					_drag_start_pos = mb.position
					_scroll_start = Vector2(scroll_horizontal, scroll_vertical)
					accept_event()
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_dragging = false

	# 拖拽平移
	if event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var delta := _drag_start_pos - mm.position
		scroll_horizontal = int(_scroll_start.x + delta.x)
		scroll_vertical = int(_scroll_start.y + delta.y)
		accept_event()

func _zoom_at(screen_pos: Vector2, delta: float) -> void:
	var old_zoom := _target_zoom
	_target_zoom = clampf(_target_zoom + delta, ZOOM_MIN, ZOOM_MAX)

	if old_zoom == _target_zoom:
		return

	# 计算缩放中心（相对于画布的位置）
	_zoom_center = screen_pos + Vector2(scroll_horizontal, scroll_vertical)
	_is_zooming = true

	zoom_changed.emit(_target_zoom)

func _apply_zoom() -> void:
	if not is_instance_valid(canvas):
		return

	# 保存当前视图中心点（世界坐标）
	var viewport_center := Vector2(scroll_horizontal, scroll_vertical) + size / 2
	var world_center := viewport_center / canvas.scale.x

	# 应用新缩放
	canvas.scale = Vector2(_current_zoom, _current_zoom)

	# 调整画布最小尺寸以适应缩放
	if canvas.has_method("get_base_size"):
		var base_size: Vector2 = canvas.call("get_base_size")
		canvas.custom_minimum_size = base_size * _current_zoom
	else:
		canvas.custom_minimum_size = canvas.custom_minimum_size * (_current_zoom / canvas.scale.x) if canvas.scale.x > 0 else canvas.custom_minimum_size

	# 尝试保持视图中心不变
	await get_tree().process_frame
	var new_viewport_center := world_center * _current_zoom
	scroll_horizontal = int(new_viewport_center.x - size.x / 2)
	scroll_vertical = int(new_viewport_center.y - size.y / 2)

func set_game_state(state: GameState) -> void:
	if state == null:
		clear()
		return
	if is_instance_valid(canvas) and canvas.has_method("set_game_state"):
		canvas.call("set_game_state", state)

func set_map_data(map_data: Dictionary) -> void:
	if map_data.is_empty():
		clear()
		return
	if is_instance_valid(canvas) and canvas.has_method("set_map_data"):
		canvas.call("set_map_data", map_data)

func clear() -> void:
	if is_instance_valid(canvas) and canvas.has_method("clear"):
		canvas.call("clear")

# === 公共缩放控制方法 ===

func set_zoom(zoom_level: float, animate: bool = true) -> void:
	_target_zoom = clampf(zoom_level, ZOOM_MIN, ZOOM_MAX)
	if animate:
		_is_zooming = true
	else:
		_current_zoom = _target_zoom
		_apply_zoom()
	zoom_changed.emit(_target_zoom)

func get_zoom() -> float:
	return _current_zoom

func zoom_in() -> void:
	set_zoom(_target_zoom + ZOOM_STEP)

func zoom_out() -> void:
	set_zoom(_target_zoom - ZOOM_STEP)

func reset_zoom() -> void:
	set_zoom(1.0)

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

	set_zoom(clampf(fit_zoom, ZOOM_MIN, ZOOM_MAX))

func center_on_position(world_pos: Vector2i) -> void:
	if not is_instance_valid(canvas):
		return

	var cell_size: int = 40  # 默认值
	if canvas.has_method("get_cell_size"):
		cell_size = canvas.call("get_cell_size")

	var screen_pos := Vector2(world_pos) * cell_size * _current_zoom
	var target_scroll := screen_pos - size / 2

	scroll_horizontal = int(target_scroll.x)
	scroll_vertical = int(target_scroll.y)
