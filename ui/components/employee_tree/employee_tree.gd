# 员工升级路线树（独立视图）
class_name EmployeeTree
extends Control

signal closed()
signal build_finished()

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const InfoDialogClass = preload("res://ui/dialogs/info_dialog.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1
const ZOOM_MIN_PERCENT := 50
const ZOOM_MAX_PERCENT := 200
const ZOOM_STEP_PERCENT := 10
const COLOR_SLIDER_TRACK := Color(0.86, 0.81, 0.70, 0.95)
const COLOR_SLIDER_BORDER := Color(0.17, 0.13, 0.09, 0.26)
const COLOR_SLIDER_FILL := Color(0.73, 0.23, 0.18, 0.32)
const COLOR_SLIDER_FILL_HOVER := Color(0.73, 0.23, 0.18, 0.45)

@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var zoom_bar: PanelZoomBar = $MarginContainer/VBoxContainer/HeaderRow/ZoomBar
@onready var fit_button: Button = $MarginContainer/VBoxContainer/HeaderRow/FitButton
@onready var fit_width_button: Button = $MarginContainer/VBoxContainer/HeaderRow/FitWidthButton
@onready var loading_center: Control = $MarginContainer/VBoxContainer/LoadingCenter
@onready var viewport: Control = $MarginContainer/VBoxContainer/Viewport
@onready var pan_background: Control = $MarginContainer/VBoxContainer/Viewport/PanBackground
@onready var graph: EmployeeTreeGraph = $MarginContainer/VBoxContainer/Viewport/Graph

var _zoom: float = 1.0
var _dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO

var _detail_dialog = null
var _built: bool = false
var _build_in_progress: bool = false
var _needs_fit_after_show: bool = false

func _ready() -> void:
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
	if is_instance_valid(fit_button):
		fit_button.pressed.connect(_fit_to_view)
	if is_instance_valid(fit_width_button):
		fit_width_button.pressed.connect(_fit_to_width)
	if is_instance_valid(zoom_bar):
		zoom_bar.configure(ZOOM_MIN_PERCENT, ZOOM_MAX_PERCENT, ZOOM_STEP_PERCENT, int(round(_zoom * 100.0)))
		zoom_bar.zoom_changed.connect(_on_zoom_bar_changed)
		zoom_bar.set_enabled(false)
		_apply_zoom_bar_theme()
	if is_instance_valid(pan_background):
		pan_background.gui_input.connect(_on_background_gui_input)
	if is_instance_valid(graph):
		graph.employee_clicked.connect(_on_employee_clicked)

	UiStylesClass.apply_button_secondary(close_button)
	UiStylesClass.apply_button_secondary(fit_button)
	UiStylesClass.apply_button_secondary(fit_width_button)

	_set_loading_visible(true)

func open() -> void:
	if _built:
		_set_loading_visible(false)
		if _needs_fit_after_show:
			call_deferred("_fit_to_view_after_open")
		return
	_set_loading_visible(true)
	begin_background_build()

func begin_background_build() -> void:
	if _built or _build_in_progress:
		return
	_build_in_progress = true
	call_deferred("_run_background_build")

func _run_background_build() -> void:
	# 先让“加载中...”有机会显示出来（避免 open 同帧就做重建导致看不到占位）。
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if not is_instance_valid(graph):
		_build_in_progress = false
		return

	graph.scale = Vector2.ONE
	graph.rebuild_from_registry(1.0)
	await _fit_to_view()

	_built = true
	_build_in_progress = false
	_set_loading_visible(false)
	build_finished.emit()

func _on_close_pressed() -> void:
	# 先通知外层控制器执行统一的“关闭 + UI 重建”流程，
	# 避免先置 hidden 导致外层误判为“并未从可见态关闭”。
	closed.emit()
	# 兜底：若未被外层接管，仍保证面板可关闭。
	if visible:
		visible = false

func _set_loading_visible(loading: bool) -> void:
	if is_instance_valid(loading_center):
		loading_center.visible = loading
	if is_instance_valid(viewport):
		viewport.visible = not loading
	if is_instance_valid(zoom_bar):
		zoom_bar.set_enabled((not loading) and _built)
	if is_instance_valid(fit_button):
		fit_button.disabled = loading
	if is_instance_valid(fit_width_button):
		fit_width_button.disabled = loading

func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN) and e.pressed:
			if _try_apply_wheel_zoom(e.button_index, e.position):
				get_viewport().set_input_as_handled()
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click and e.pressed:
				_fit_to_view()
				return
			if e.pressed:
				_dragging = true
				_drag_start_mouse = e.position
				_drag_start_pos = graph.position if is_instance_valid(graph) else Vector2.ZERO
			else:
				_dragging = false
		return

	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event
		if touch_event.pressed:
			_dragging = true
			_drag_start_mouse = touch_event.position
			_drag_start_pos = graph.position if is_instance_valid(graph) else Vector2.ZERO
		else:
			_dragging = false
		return

	if event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		if _dragging and is_instance_valid(graph):
			graph.position = _drag_start_pos + (m.position - _drag_start_mouse)
		return

	if event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event
		if _dragging and is_instance_valid(graph):
			graph.position = _drag_start_pos + (drag_event.position - _drag_start_mouse)
		return

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _built:
		return
	if not is_instance_valid(viewport) or not is_instance_valid(graph):
		return

	if event is InputEventMagnifyGesture:
		var g: InputEventMagnifyGesture = event
		var vp_rect := viewport.get_global_rect()
		if not vp_rect.has_point(g.position):
			return
		var local := g.position - vp_rect.position
		_set_zoom_at(_zoom * float(g.factor), local)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not _built:
		return
	if not is_instance_valid(viewport) or not is_instance_valid(graph):
		return

	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if not (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			return
		if not e.pressed:
			return

		if _try_apply_wheel_zoom(e.button_index, e.position):
			get_viewport().set_input_as_handled()

func _try_apply_wheel_zoom(button_index: int, global_position: Vector2) -> bool:
	if not is_instance_valid(viewport) or not is_instance_valid(graph):
		return false
	if not _built:
		return false

	var vp_rect := viewport.get_global_rect()
	if not vp_rect.has_point(global_position):
		return false

	var local := global_position - vp_rect.position
	var dir := 0
	if button_index == MOUSE_BUTTON_WHEEL_UP:
		dir = 1
	elif button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dir = -1
	if dir == 0:
		return false

	_set_zoom_at(_zoom + float(dir) * ZOOM_STEP, local)
	return true

func _set_zoom_at(target_zoom: float, viewport_local: Vector2) -> void:
	if not is_instance_valid(graph):
		return

	var new_zoom := _normalize_zoom(target_zoom)
	if is_equal_approx(new_zoom, _zoom):
		return

	# 保持鼠标指向的“世界点”不动
	var world := (viewport_local - graph.position) / _zoom
	_zoom = new_zoom
	graph.scale = Vector2.ONE
	graph.rebuild_from_registry(_zoom)
	graph.position = viewport_local - world * _zoom
	graph.position = Vector2(round(graph.position.x), round(graph.position.y))
	_sync_zoom_bar()

func _fit_to_view() -> void:
	if not is_instance_valid(viewport) or not is_instance_valid(graph):
		return

	await get_tree().process_frame

	var vp_size := viewport.size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		_needs_fit_after_show = true
		return

	graph.scale = Vector2.ONE
	graph.rebuild_from_registry(1.0)

	await get_tree().process_frame

	var base_size := graph.get_combined_minimum_size()
	if base_size == Vector2.ZERO:
		base_size = graph.custom_minimum_size
	if base_size.x <= 0.0 or base_size.y <= 0.0:
		_needs_fit_after_show = true
		return

	var s := minf(vp_size.x / base_size.x, vp_size.y / base_size.y)
	s = _normalize_zoom(s)
	_zoom = s
	graph.rebuild_from_registry(_zoom)
	_sync_zoom_bar()

	await get_tree().process_frame

	var content_size := graph.get_combined_minimum_size()
	if content_size == Vector2.ZERO:
		content_size = graph.custom_minimum_size
	graph.position = (vp_size - content_size) * 0.5
	graph.position = Vector2(round(graph.position.x), round(graph.position.y))
	_needs_fit_after_show = false

func _fit_to_width() -> void:
	if not is_instance_valid(viewport) or not is_instance_valid(graph):
		return

	await get_tree().process_frame

	var vp_size := viewport.size
	if vp_size.x <= 0.0:
		return

	graph.scale = Vector2.ONE
	graph.rebuild_from_registry(1.0)

	await get_tree().process_frame

	var base_size := graph.get_combined_minimum_size()
	if base_size == Vector2.ZERO:
		base_size = graph.custom_minimum_size
	if base_size.x <= 0.0:
		return

	var s := vp_size.x / base_size.x
	s = _normalize_zoom(s)
	_zoom = s
	graph.rebuild_from_registry(_zoom)
	_sync_zoom_bar()

	await get_tree().process_frame

	var content_size := graph.get_combined_minimum_size()
	if content_size == Vector2.ZERO:
		content_size = graph.custom_minimum_size

	var pos := Vector2((vp_size.x - content_size.x) * 0.5, (vp_size.y - content_size.y) * 0.5)
	if content_size.y > vp_size.y:
		pos.y = 0.0
	graph.position = Vector2(round(pos.x), round(pos.y))

func _normalize_zoom(target_zoom: float) -> float:
	var clamped := clampf(target_zoom, ZOOM_MIN, ZOOM_MAX)
	var stepped := snappedf(clamped, ZOOM_STEP)
	return clampf(stepped, ZOOM_MIN, ZOOM_MAX)

func _sync_zoom_bar() -> void:
	if is_instance_valid(zoom_bar):
		zoom_bar.set_zoom_factor(_zoom, false)

func _on_zoom_bar_changed(zoom_factor: float) -> void:
	if not _built:
		return
	if not is_instance_valid(viewport):
		return
	var local_center := viewport.size * 0.5
	_set_zoom_at(zoom_factor, local_center)

func _fit_to_view_after_open() -> void:
	if not _built:
		return
	await _fit_to_view()

func _apply_zoom_bar_theme() -> void:
	if not is_instance_valid(zoom_bar):
		return
	if is_instance_valid(zoom_bar.zoom_out_button):
		UiStylesClass.apply_button_secondary(zoom_bar.zoom_out_button)
	if is_instance_valid(zoom_bar.zoom_in_button):
		UiStylesClass.apply_button_secondary(zoom_bar.zoom_in_button)
	if is_instance_valid(zoom_bar.zoom_label):
		UiStylesClass.apply_label_dark(zoom_bar.zoom_label)
	if is_instance_valid(zoom_bar.zoom_slider):
		zoom_bar.zoom_slider.add_theme_stylebox_override("slider", _make_zoom_slider_track_style())
		zoom_bar.zoom_slider.add_theme_stylebox_override("grabber_area", _make_zoom_slider_fill_style(COLOR_SLIDER_FILL))
		zoom_bar.zoom_slider.add_theme_stylebox_override("grabber_area_highlight", _make_zoom_slider_fill_style(COLOR_SLIDER_FILL_HOVER))

func _make_zoom_slider_track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SLIDER_TRACK
	style.border_color = COLOR_SLIDER_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_top = 2
	style.content_margin_right = 0
	style.content_margin_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style

func _make_zoom_slider_fill_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(bg.r, bg.g, bg.b, 0.9)
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_top = 2
	style.content_margin_right = 0
	style.content_margin_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style

func _ensure_detail_dialog() -> void:
	if _detail_dialog != null and is_instance_valid(_detail_dialog):
		return
	_detail_dialog = InfoDialogClass.new()
	add_child(_detail_dialog)

func _on_employee_clicked(employee_id: String) -> void:
	if employee_id.is_empty():
		return
	_ensure_detail_dialog()
	if _detail_dialog == null or not is_instance_valid(_detail_dialog):
		return

	var lines: Array[String] = []
	lines.append("ID: %s" % employee_id)

	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val is EmployeeDefClass:
			var def: EmployeeDef = def_val
			lines.append("名称: %s" % str(def.name))
			if not def.description.is_empty():
				lines.append("")
				lines.append(def.description)
			lines.append("")
			lines.append("职责: %s" % str(def.get_role()))
			lines.append("薪资: %s" % ("有" if bool(def.salary) else "无"))
			if not def.train_to.is_empty():
				var tt: Array[String] = []
				for t in def.train_to:
					var s := str(t)
					if not s.is_empty():
						tt.append(s)
				tt.sort()
				lines.append("可培训为: %s" % ", ".join(tt))

	if _detail_dialog.has_method("show_info"):
		_detail_dialog.call("show_info", "员工详情", "\n".join(lines), Vector2i(520, 360), "关闭")
