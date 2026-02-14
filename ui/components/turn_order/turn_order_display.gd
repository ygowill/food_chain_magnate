# 顶部顺序显示（展示用）
# 默认紧凑模式用于弹窗，地图顶部可切换为“卡槽条”样式。
class_name TurnOrderDisplay
extends Control

signal position_selected(position: int)

@export var use_map_strip_style: bool = false:
	set(value):
		var enabled := true if value else false
		if use_map_strip_style == enabled:
			return
		use_map_strip_style = enabled
		_apply_layout_style()
		_rebuild()

@onready var background: ColorRect = $Background
@onready var title_label: Label = $TitleLabel
@onready var hint_label: Label = $HintLabel
@onready var slots_container: HBoxContainer = $SlotsContainer

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const STRIP_BG_COLOR := Color("#c9342f")

class FlagMarker extends Control:
	const POLE_COLOR := Color("#3d2413")
	const PENNANT_COLOR := Color("#d83d30")
	const PENNANT_BORDER_COLOR := Color("#5d150f")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 0.0 or h <= 0.0:
			return

		var pole_w: float = maxf(2.0, floorf(w * 0.14))
		draw_rect(Rect2(0.0, 0.0, pole_w, h), POLE_COLOR, true)

		var pennant_top: float = floorf(h * 0.14)
		var pennant_h: float = maxf(5.0, floorf(h * 0.56))
		var pennant_w: float = maxf(8.0, w - pole_w - 1.0)
		var p0 := Vector2(pole_w, pennant_top)
		var p1 := Vector2(pole_w + pennant_w, pennant_top + pennant_h * 0.50)
		var p2 := Vector2(pole_w, pennant_top + pennant_h)
		var pts := PackedVector2Array([p0, p1, p2])
		draw_colored_polygon(pts, PENNANT_COLOR)
		draw_polyline(PackedVector2Array([p0, p1, p2, p0]), PENNANT_BORDER_COLOR, 1.0, true)

var _game_state: GameState = null
var _skin = null
var _skin_modules_key: String = ""
var _state_seed: int = 0
var _player_restaurant_logo_ids: Dictionary = {} # player_id -> logo_id
var _fallback_logo_ids: Array[int] = []

var _player_count: int = 0
var _current_selections: Dictionary = {} # position -> player_id
var _current_player_id: int = -1
var _slot_nodes: Array[OrderBadge] = []
var _selectable: bool = false

func _ready() -> void:
	_apply_layout_style()
	_rebuild()

func set_player_count(count: int) -> void:
	_player_count = clampi(count, 0, Globals.MAX_PLAYERS)
	_rebuild()

func set_game_state(state: GameState) -> void:
	_game_state = state
	_ensure_skin()
	_rebuild_player_logo_ids()
	_update_display()

func set_current_selections(selections: Dictionary) -> void:
	_current_selections = selections.duplicate()
	_update_display()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
	_update_display()

func set_selectable(can_select: bool) -> void:
	_selectable = true if can_select else false
	_update_display()

func _apply_layout_style() -> void:
	if not is_instance_valid(slots_container):
		return

	slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_container.anchor_left = 0.0
	slots_container.anchor_top = 0.0
	slots_container.anchor_right = 1.0
	slots_container.anchor_bottom = 1.0

	if use_map_strip_style:
		custom_minimum_size = Vector2(620, 140)
		slots_container.offset_left = 18.0
		slots_container.offset_top = 40.0
		slots_container.offset_right = -18.0
		slots_container.offset_bottom = -12.0
		slots_container.add_theme_constant_override("separation", 14)
		if is_instance_valid(background):
			background.visible = true
			background.color = STRIP_BG_COLOR
		if is_instance_valid(title_label):
			title_label.visible = true
			title_label.text = "回合顺位"
		if is_instance_valid(hint_label):
			hint_label.visible = true
			hint_label.text = "数字越小越先行动 · 旗子标记表示当前玩家"
	else:
		custom_minimum_size = Vector2(220, 88)
		slots_container.offset_left = 2.0
		slots_container.offset_top = 0.0
		slots_container.offset_right = -2.0
		slots_container.offset_bottom = 0.0
		slots_container.add_theme_constant_override("separation", 8)
		if is_instance_valid(background):
			background.visible = false
		if is_instance_valid(title_label):
			title_label.visible = false
		if is_instance_valid(hint_label):
			hint_label.visible = false

func _rebuild() -> void:
	for slot in _slot_nodes:
		if is_instance_valid(slot):
			slot.queue_free()
	_slot_nodes.clear()

	if not is_instance_valid(slots_container):
		return

	_apply_layout_style()
	for i in range(_player_count):
		var badge := OrderBadge.new()
		badge.slot_position = i
		badge.set_map_strip_style(use_map_strip_style)
		badge.clicked.connect(_on_badge_clicked)
		slots_container.add_child(badge)
		_slot_nodes.append(badge)

	_update_display()

func _update_display() -> void:
	for slot in _slot_nodes:
		if not is_instance_valid(slot):
			continue

		var pos := slot.slot_position
		if _current_selections.has(pos):
			var pid := int(_current_selections[pos])
			var tex := _get_player_restaurant_logo_texture(pid)
			slot.set_player(pid, Globals.get_player_color(pid), pid == _current_player_id, tex)
			slot.set_highlighted(false)
			slot.set_clickable(false)
		else:
			slot.set_empty()
			var can_pick := _selectable and not _current_selections.has(pos)
			slot.set_highlighted(can_pick)
			slot.set_clickable(can_pick)

func _on_badge_clicked(position: int) -> void:
	if not _selectable:
		return
	if _current_selections.has(position):
		return
	position_selected.emit(position)

func _ensure_skin() -> void:
	if _game_state == null:
		_skin = null
		_skin_modules_key = ""
		return

	var mods: Array[String] = Array(_game_state.modules, TYPE_STRING, "", null)
	var key: String = str(mods)
	if _skin != null and key == _skin_modules_key:
		return
	_skin_modules_key = key
	_skin = UiSkinCacheClass.get_skin_for_modules(Globals.modules_v2_base_dir, mods, 40)

func _read_logo_id(value, logo_count: int) -> int:
	if logo_count <= 0:
		return -1
	var logo_id := -1
	if value is int:
		logo_id = int(value)
	elif value is float:
		var f: float = float(value)
		if f == floor(f):
			logo_id = int(f)
	if logo_id < 0 or logo_id >= logo_count:
		return -1
	return logo_id

func _build_fallback_logo_ids(logo_count: int) -> Array[int]:
	if logo_count <= 0:
		return []
	var ids: Array[int] = []
	for i in range(logo_count):
		ids.append(i)

	var rng := RandomNumberGenerator.new()
	var logo_seed := int(_state_seed) ^ int(0x4C4F474F) # 'LOGO'
	rng.seed = int(logo_seed)
	rng.state = int(logo_seed)
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := ids[i]
		ids[i] = ids[j]
		ids[j] = tmp

	return ids

func _fallback_logo_id_for_player(player_id: int, fallback_logo_ids: Array[int]) -> int:
	if fallback_logo_ids.is_empty():
		return -1
	var pid := maxi(0, int(player_id))
	return int(fallback_logo_ids[pid % fallback_logo_ids.size()])

func _rebuild_player_logo_ids() -> void:
	_player_restaurant_logo_ids.clear()
	_fallback_logo_ids.clear()
	_state_seed = 0
	if _game_state == null:
		return
	_state_seed = int(_game_state.seed)

	var logo_count := 0
	if _skin != null and _skin.has_method("get_restaurant_logo_piece_ids"):
		var ids_val = _skin.get_restaurant_logo_piece_ids()
		if ids_val is Array:
			logo_count = (ids_val as Array).size()
	_fallback_logo_ids = _build_fallback_logo_ids(logo_count)
	for i in range(_game_state.players.size()):
		var p_val = _game_state.players[i]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var pid := int(p.get("id", i))
		if pid < 0:
			continue

		var logo_id := _read_logo_id(p.get("restaurant_logo_id", null), logo_count)
		if logo_id >= 0:
			_player_restaurant_logo_ids[pid] = logo_id
		else:
			_player_restaurant_logo_ids[pid] = _fallback_logo_id_for_player(pid, _fallback_logo_ids)

func _get_player_restaurant_logo_texture(player_id: int) -> Texture2D:
	if _skin == null:
		return null
	if not (_skin.has_method("get_restaurant_logo_piece_ids")) or not (_skin.has_method("get_restaurant_logo_texture_by_id")):
		return null
	var logo_count := (_skin.get_restaurant_logo_piece_ids() as Array).size()
	if logo_count <= 0:
		return null
	var logo_id := int(_player_restaurant_logo_ids.get(player_id, -1))
	if logo_id < 0 or logo_id >= logo_count:
		logo_id = _fallback_logo_id_for_player(player_id, _fallback_logo_ids)
	return _skin.get_restaurant_logo_texture_by_id(logo_id)


class OrderBadge extends PanelContainer:
	const RESTAURANT_BG_COLOR := Color("#f4edd1")
	const CURRENT_BORDER_COLOR := Color("#d83d30")
	const HIGHLIGHT_BORDER_COLOR := Color("#7f9f59")
	const OUTLINE_COLOR := Color("#101010")
	const MAP_SLOT_MIN_SIZE := Vector2(132, 102)
	const COMPACT_SLOT_MIN_SIZE := Vector2(84, 90)

	signal clicked(position: int)

	var slot_position: int = 0

	var _player_id: int = -1
	var _player_color: Color = Color(0.7, 0.7, 0.7, 1)
	var _is_current: bool = false
	var _occupied: bool = false
	var _logo_texture: Texture2D = null
	var _highlighted: bool = false
	var _clickable: bool = false
	var _map_strip_style: bool = false

	var _frame: PanelContainer
	var _number_badge: PanelContainer
	var _number_label: Label
	var _icon: TextureRect
	var _fallback_label: Label
	var _current_flag: FlagMarker
	var _content_pad: float = 2.0

	func _ready() -> void:
		_build_ui()
		_apply_metrics()
		gui_input.connect(_on_gui_input)
		_update()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_apply_metrics()

	func set_map_strip_style(enabled: bool) -> void:
		_map_strip_style = true if enabled else false
		_apply_metrics()
		_update()

	func set_highlighted(highlighted: bool) -> void:
		_highlighted = highlighted
		_update()

	func set_clickable(clickable: bool) -> void:
		_clickable = clickable
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW

	func set_player(player_id: int, color: Color, is_current: bool, logo_texture: Texture2D) -> void:
		_player_id = player_id
		_player_color = color
		_is_current = is_current
		_occupied = true
		_logo_texture = logo_texture
		_update()

	func set_empty() -> void:
		_player_id = -1
		_player_color = Color(0.35, 0.35, 0.4, 0.8)
		_is_current = false
		_occupied = false
		_logo_texture = null
		_update()

	func _build_ui() -> void:
		if is_instance_valid(_frame):
			return
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = false
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

		_number_badge = PanelContainer.new()
		_number_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_number_badge.z_index = 3
		add_child(_number_badge)

		_number_label = Label.new()
		_number_label.anchors_preset = Control.PRESET_FULL_RECT
		_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_number_badge.add_child(_number_label)

		_frame = PanelContainer.new()
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.z_index = 1
		add_child(_frame)

		_icon = TextureRect.new()
		_icon.anchors_preset = Control.PRESET_FULL_RECT
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_icon)

		_fallback_label = Label.new()
		_fallback_label.anchors_preset = Control.PRESET_FULL_RECT
		_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_fallback_label)

		_current_flag = FlagMarker.new()
		_current_flag.anchor_left = 1.0
		_current_flag.anchor_top = 0.0
		_current_flag.anchor_right = 1.0
		_current_flag.anchor_bottom = 0.0
		_current_flag.offset_left = -16.0
		_current_flag.offset_top = 0.0
		_current_flag.offset_right = -2.0
		_current_flag.offset_bottom = 24.0
		_current_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_current_flag.visible = false
		_current_flag.z_index = 4
		_frame.add_child(_current_flag)

	func _apply_metrics() -> void:
		if not is_instance_valid(_frame) or not is_instance_valid(_number_badge) or not is_instance_valid(_current_flag):
			return

		var slot_size := MAP_SLOT_MIN_SIZE if _map_strip_style else COMPACT_SLOT_MIN_SIZE
		var badge_size := Vector2(38, 24) if _map_strip_style else Vector2(32, 20)
		var frame_top := 24.0 if _map_strip_style else 20.0
		var number_font_size := 19 if _map_strip_style else 16
		var fallback_font_size := 20 if _map_strip_style else 16
		var current_flag_size := Vector2(18, 22) if _map_strip_style else Vector2(14, 18)
		_content_pad = 2.0 if _map_strip_style else 1.0

		custom_minimum_size = slot_size
		size_flags_horizontal = Control.SIZE_EXPAND_FILL if _map_strip_style else Control.SIZE_SHRINK_CENTER

		_number_badge.anchor_left = 0.5
		_number_badge.anchor_top = 0.0
		_number_badge.anchor_right = 0.5
		_number_badge.anchor_bottom = 0.0
		_number_badge.offset_left = -badge_size.x * 0.5
		_number_badge.offset_top = 0.0
		_number_badge.offset_right = badge_size.x * 0.5
		_number_badge.offset_bottom = badge_size.y

		_frame.anchor_left = 0.0
		_frame.anchor_top = 0.0
		_frame.anchor_right = 1.0
		_frame.anchor_bottom = 1.0
		_frame.offset_left = 0.0
		_frame.offset_top = frame_top
		_frame.offset_right = 0.0
		_frame.offset_bottom = 0.0

		_number_label.add_theme_font_size_override("font_size", number_font_size)
		_fallback_label.add_theme_font_size_override("font_size", fallback_font_size)
		_current_flag.offset_left = -current_flag_size.x - 2.0
		_current_flag.offset_top = 2.0
		_current_flag.offset_right = -2.0
		_current_flag.offset_bottom = 2.0 + current_flag_size.y
		_current_flag.queue_redraw()

		_layout_logo_square()

	func _layout_logo_square() -> void:
		if not is_instance_valid(_frame) or not is_instance_valid(_icon) or not is_instance_valid(_fallback_label):
			return
		var frame_size: Vector2 = _frame.size
		if frame_size.x <= 0.0 or frame_size.y <= 0.0:
			return
		var side := minf(frame_size.x, frame_size.y) - (_content_pad * 2.0)
		side = maxf(8.0, side)
		var left: float = floorf((frame_size.x - side) * 0.5)
		var top: float = floorf((frame_size.y - side) * 0.5)
		var right: float = frame_size.x - left - side
		var bottom: float = frame_size.y - top - side

		_icon.offset_left = left
		_icon.offset_top = top
		_icon.offset_right = -right
		_icon.offset_bottom = -bottom
		_fallback_label.offset_left = left
		_fallback_label.offset_top = top
		_fallback_label.offset_right = -right
		_fallback_label.offset_bottom = -bottom

	func _update() -> void:
		if is_instance_valid(_number_label):
			_number_label.text = str(slot_position + 1)
			_number_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 0.95))

		if is_instance_valid(_icon):
			_icon.texture = _logo_texture
			_icon.visible = _occupied and _logo_texture != null

		if is_instance_valid(_fallback_label):
			_fallback_label.visible = _occupied and _logo_texture == null
			_fallback_label.text = "P%d" % (_player_id + 1) if _occupied else ""
			var fallback_color := _player_color if _occupied else Color(0.17, 0.13, 0.09, 0.9)
			fallback_color.a = 0.95
			_fallback_label.add_theme_color_override("font_color", fallback_color)

		var frame_border := OUTLINE_COLOR
		if _is_current:
			frame_border = CURRENT_BORDER_COLOR
		elif _highlighted and _clickable:
			frame_border = HIGHLIGHT_BORDER_COLOR

		var frame_style := StyleBoxFlat.new()
		if _occupied:
			frame_style.bg_color = Color(RESTAURANT_BG_COLOR.r, RESTAURANT_BG_COLOR.g, RESTAURANT_BG_COLOR.b, 1.0)
		elif _highlighted:
			frame_style.bg_color = Color(0.98, 0.96, 0.88, 1.0)
		else:
			frame_style.bg_color = Color(0.95, 0.91, 0.82, 1.0)
		frame_style.border_color = frame_border
		frame_style.set_border_width_all(3 if _is_current else 2)
		frame_style.set_corner_radius_all(2 if _map_strip_style else 2)
		if is_instance_valid(_frame):
			_frame.add_theme_stylebox_override("panel", frame_style)

		var badge_style := StyleBoxFlat.new()
		if _occupied:
			badge_style.bg_color = Color(0.82, 0.80, 0.76, 1.0)
		elif _highlighted:
			badge_style.bg_color = Color(0.86, 0.84, 0.79, 1.0)
		else:
			badge_style.bg_color = Color(0.82, 0.80, 0.76, 1.0)
		badge_style.border_color = frame_border if _is_current else OUTLINE_COLOR
		badge_style.set_border_width_all(2)
		badge_style.set_corner_radius_all(3 if _map_strip_style else 2)
		if is_instance_valid(_number_badge):
			_number_badge.add_theme_stylebox_override("panel", badge_style)

		if is_instance_valid(_current_flag):
			_current_flag.visible = _occupied and _is_current

		_layout_logo_square()

		if _occupied:
			tooltip_text = "顺位 %d: %s" % [slot_position + 1, Globals.get_player_name(_player_id)]
		else:
			tooltip_text = "顺位 %d: （空）" % (slot_position + 1)

	func _on_gui_input(event: InputEvent) -> void:
		if not _clickable:
			return
		if event is InputEventMouseButton:
			var e: InputEventMouseButton = event
			if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				clicked.emit(slot_position)
