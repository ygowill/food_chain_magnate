# 箭头形阶段进度条：每个阶段是一个 chevron 色块，无缝拼接。
# 支持：当前阶段高亮、已过阶段淡化、鼠标悬停提示。
class_name PhaseTrackStrip
extends Control

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")

signal phase_hover_changed(phase_key: String, hover_global_pos: Vector2)
signal phase_hover_exited()

const PHASE_KEYS: PackedStringArray = [
	"Restructuring", "OrderOfBusiness", "Working", "Dinnertime", "Payday", "Marketing", "Cleanup"
]
const PHASE_NAMES: PackedStringArray = [
	"重组结构", "商业秩序", "工作时间", "晚餐时间", "发薪日", "营销结算", "清理阶段"
]

var _current_phase: String = ""
var _hover_index: int = -1
var _font_size: int = 15
var _h_padding: int = 10
var _arrow_depth: int = 8
var _v_padding: int = 11
var _v_inset: int = 3
var _use_inline_tooltip: bool = false

# 已过阶段
var _bg_past := Color(0.56, 0.17, 0.14, 0.28)
var _border_past := Color(0.56, 0.17, 0.14, 0.60)
var _text_past := UiStylesClass.COLOR_TEXT_PRIMARY
# 未来阶段
var _bg_future := Color(0.50, 0.45, 0.35, 0.14)
var _border_future := Color(0.50, 0.45, 0.35, 0.18)
var _text_future := UiStylesClass.COLOR_TEXT_MUTED
# 当前阶段
var _bg_current := Color(0.73, 0.23, 0.18, 0.22)
var _border_current := Color(0.73, 0.23, 0.18, 0.50)
var _text_current := UiStylesClass.COLOR_TEXT_PRIMARY
# 悬停叠加
var _hover_brighten := Color(1.0, 1.0, 1.0, 0.08)

# 自定义 tooltip（Godot 内置 tooltip 不支持同一 Control 内按位置刷新）
var _tip_panel: PanelContainer = null
var _tip_label: Label = null

func set_current_phase(phase_key: String) -> void:
	if _current_phase == phase_key:
		return
	_current_phase = phase_key
	queue_redraw()

func set_font_size(fs: int) -> void:
	fs = maxi(9, fs)
	if _font_size == fs:
		return
	_font_size = fs
	_refresh_size()
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_size()
	if _use_inline_tooltip:
		_create_tip()

func _exit_tree() -> void:
	if _tip_panel != null and is_instance_valid(_tip_panel):
		_tip_panel.queue_free()
		_tip_panel = null
		_tip_label = null

func _create_tip() -> void:
	_tip_panel = PanelContainer.new()
	_tip_panel.top_level = true
	UiZClass.apply_absolute(_tip_panel, UiZClass.MAP_OVERLAY)
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.86, 0.96)
	style.border_color = Color(0.50, 0.45, 0.35, 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_top = 2
	style.content_margin_right = 6
	style.content_margin_bottom = 2
	_tip_panel.add_theme_stylebox_override("panel", style)

	_tip_label = Label.new()
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.add_theme_font_size_override("font_size", 12)
	_tip_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	_tip_panel.add_child(_tip_label)
	add_child(_tip_panel)

func _refresh_size() -> void:
	var font := get_theme_default_font()
	var total_w := 0.0
	for i in range(PHASE_NAMES.size()):
		var tw := font.get_string_size(PHASE_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		total_w += tw + _h_padding * 2
	total_w += _arrow_depth
	var h := _font_size + _v_padding * 2 + _v_inset * 2
	custom_minimum_size = Vector2(total_w, h)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var new_idx := _get_phase_index_at(event.position)
		if new_idx != _hover_index:
			_hover_index = new_idx
			queue_redraw()
		_emit_phase_hover(new_idx, event.position)
		if _use_inline_tooltip:
			_sync_tip(event.position, new_idx)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover_index >= 0:
			_hover_index = -1
			queue_redraw()
		_hide_tip()
		phase_hover_exited.emit()

func _emit_phase_hover(idx: int, local_pos: Vector2) -> void:
	if idx < 0 or idx >= PHASE_KEYS.size():
		phase_hover_exited.emit()
		return
	var phase_key := str(PHASE_KEYS[idx]).strip_edges()
	var hover_global_pos := global_position + local_pos + Vector2(8, size.y + 2)
	phase_hover_changed.emit(phase_key, hover_global_pos)

func _sync_tip(local_pos: Vector2, idx: int) -> void:
	if _tip_panel == null or not is_instance_valid(_tip_panel):
		return
	if idx < 0 or idx >= PHASE_NAMES.size():
		_tip_panel.visible = false
		return
	_tip_label.text = PHASE_NAMES[idx]
	_tip_panel.visible = true
	# 定位到鼠标下方
	var gp := global_position + local_pos
	_tip_panel.global_position = Vector2(gp.x + 8, gp.y + size.y + 2)

func _hide_tip() -> void:
	if _tip_panel != null and is_instance_valid(_tip_panel):
		_tip_panel.visible = false

func _get_phase_index_at(pos: Vector2) -> int:
	var font := get_theme_default_font()
	var slot_x := 0.0
	for i in range(PHASE_NAMES.size()):
		var tw := font.get_string_size(PHASE_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		var body_w := tw + _h_padding * 2
		var right_edge := slot_x + body_w
		if i == PHASE_NAMES.size() - 1:
			right_edge += float(_arrow_depth)
		if pos.x <= right_edge:
			return i
		slot_x += body_w
	return -1

func _draw() -> void:
	var font := get_theme_default_font()
	var full_h := size.y
	var inset := float(_v_inset)
	var y0 := inset
	var h := full_h - inset * 2.0
	if h < 4.0:
		h = full_h
		y0 = 0.0
	var d := float(_arrow_depth)
	var slot_x := 0.0

	var current_idx := -1
	for ci in range(PHASE_KEYS.size()):
		if PHASE_KEYS[ci] == _current_phase:
			current_idx = ci
			break

	for i in range(PHASE_NAMES.size()):
		var text := PHASE_NAMES[i]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		var body_w := tw + _h_padding * 2
		var is_current := (i == current_idx)
		var is_past := (current_idx >= 0 and i < current_idx)
		var is_first := (i == 0)
		var is_last := (i == PHASE_NAMES.size() - 1)
		var is_hovered := (i == _hover_index)

		# 构建多边形
		var pts := PackedVector2Array()
		if is_first:
			pts.append(Vector2(slot_x, y0))
			pts.append(Vector2(slot_x + body_w, y0))
			pts.append(Vector2(slot_x + body_w + d, y0 + h / 2.0))
			pts.append(Vector2(slot_x + body_w, y0 + h))
			pts.append(Vector2(slot_x, y0 + h))
		elif is_last:
			pts.append(Vector2(slot_x, y0))
			pts.append(Vector2(slot_x + body_w + d, y0))
			pts.append(Vector2(slot_x + body_w + d, y0 + h))
			pts.append(Vector2(slot_x, y0 + h))
			pts.append(Vector2(slot_x + d, y0 + h / 2.0))
		else:
			pts.append(Vector2(slot_x, y0))
			pts.append(Vector2(slot_x + body_w, y0))
			pts.append(Vector2(slot_x + body_w + d, y0 + h / 2.0))
			pts.append(Vector2(slot_x + body_w, y0 + h))
			pts.append(Vector2(slot_x, y0 + h))
			pts.append(Vector2(slot_x + d, y0 + h / 2.0))

		# 选色
		var bg: Color
		var border: Color
		var text_color: Color
		if is_current:
			bg = _bg_current
			border = _border_current
			text_color = _text_current
		elif is_past:
			bg = _bg_past
			border = _border_past
			text_color = _text_past
		else:
			bg = _bg_future
			border = _border_future
			text_color = _text_future

		if is_hovered:
			bg = Color(bg.r + _hover_brighten.r * _hover_brighten.a,
					   bg.g + _hover_brighten.g * _hover_brighten.a,
					   bg.b + _hover_brighten.b * _hover_brighten.a,
					   minf(bg.a + 0.10, 0.45))
			border = Color(border.r, border.g, border.b, minf(border.a + 0.12, 0.65))

		draw_colored_polygon(pts, bg)

		# 描边
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, border, 1.0, true)

		# 文字
		var text_x: float
		if is_first:
			text_x = slot_x + (body_w - tw) / 2.0
		elif is_last:
			text_x = slot_x + d + (body_w - tw) / 2.0
		else:
			text_x = slot_x + d + (body_w - d - tw) / 2.0
		var ascent := font.get_ascent(_font_size)
		var descent := font.get_descent(_font_size)
		var text_y := y0 + (h - ascent - descent) / 2.0 + ascent
		draw_string(font, Vector2(text_x, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, text_color)

		slot_x += body_w
