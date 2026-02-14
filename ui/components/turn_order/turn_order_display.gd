# 顶部顺序显示（展示用）
# 默认紧凑模式用于弹窗，地图顶部可切换为“卡槽条”样式。
class_name TurnOrderDisplay
extends Control

signal position_selected(position: int)

@export var use_map_strip_style: bool = false:
	set(value):
		var enabled := bool(value)
		if use_map_strip_style == enabled:
			return
		use_map_strip_style = enabled
		_apply_layout_style()
		_rebuild()

@onready var background: ColorRect = $Background
@onready var slots_container: HBoxContainer = $SlotsContainer

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const STRIP_BG_COLOR := Color("#c9342f")

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
	_selectable = bool(can_select)
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
		custom_minimum_size = Vector2(560, 112)
		slots_container.offset_left = 18.0
		slots_container.offset_top = 10.0
		slots_container.offset_right = -18.0
		slots_container.offset_bottom = -12.0
		slots_container.add_theme_constant_override("separation", 16)
		if is_instance_valid(background):
			background.visible = true
			background.color = STRIP_BG_COLOR
	else:
		custom_minimum_size = Vector2(220, 88)
		slots_container.offset_left = 2.0
		slots_container.offset_top = 0.0
		slots_container.offset_right = -2.0
		slots_container.offset_bottom = 0.0
		slots_container.add_theme_constant_override("separation", 8)
		if is_instance_valid(background):
			background.visible = false

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
	const MAP_SLOT_MIN_SIZE := Vector2(136, 94)
	const COMPACT_SLOT_MIN_SIZE := Vector2(82, 90)

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
	var _player_strip: ColorRect

	func _ready() -> void:
		_build_ui()
		_apply_metrics()
		gui_input.connect(_on_gui_input)
		_update()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_apply_metrics()

	func set_map_strip_style(enabled: bool) -> void:
		_map_strip_style = bool(enabled)
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
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

		_number_badge = PanelContainer.new()
		_number_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_number_badge)

		_number_label = Label.new()
		_number_label.anchors_preset = Control.PRESET_FULL_RECT
		_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_number_badge.add_child(_number_label)

		_frame = PanelContainer.new()
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)

		_icon = TextureRect.new()
		_icon.anchors_preset = Control.PRESET_FULL_RECT
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_icon)

		_fallback_label = Label.new()
		_fallback_label.anchors_preset = Control.PRESET_FULL_RECT
		_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_fallback_label)

		_player_strip = ColorRect.new()
		_player_strip.anchor_left = 0.0
		_player_strip.anchor_top = 1.0
		_player_strip.anchor_right = 1.0
		_player_strip.anchor_bottom = 1.0
		_player_strip.offset_left = 0.0
		_player_strip.offset_top = -6.0
		_player_strip.offset_right = 0.0
		_player_strip.offset_bottom = 0.0
		_player_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_player_strip.visible = false
		_frame.add_child(_player_strip)

	func _apply_metrics() -> void:
		if not is_instance_valid(_frame) or not is_instance_valid(_number_badge):
			return

		var slot_size := MAP_SLOT_MIN_SIZE if _map_strip_style else COMPACT_SLOT_MIN_SIZE
		var badge_size := Vector2(46, 32) if _map_strip_style else Vector2(34, 24)
		var frame_top := 14.0 if _map_strip_style else 11.0
		var content_pad := 7.0 if _map_strip_style else 5.0
		var number_font_size := 30 if _map_strip_style else 20
		var fallback_font_size := 21 if _map_strip_style else 18
		var strip_height := 6.0 if _map_strip_style else 4.0

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

		_icon.offset_left = content_pad
		_icon.offset_top = content_pad
		_icon.offset_right = -content_pad
		_icon.offset_bottom = -content_pad
		_fallback_label.offset_left = content_pad
		_fallback_label.offset_top = content_pad
		_fallback_label.offset_right = -content_pad
		_fallback_label.offset_bottom = -content_pad
		_number_label.add_theme_font_size_override("font_size", number_font_size)
		_fallback_label.add_theme_font_size_override("font_size", fallback_font_size)
		_player_strip.offset_top = -strip_height

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
			var bg := RESTAURANT_BG_COLOR
			bg.a = 0.96
			frame_style.bg_color = bg
		elif _highlighted:
			frame_style.bg_color = Color(0.97, 0.95, 0.87, 0.98)
		else:
			frame_style.bg_color = Color(0.95, 0.91, 0.82, 0.90)
		frame_style.border_color = frame_border
		frame_style.set_border_width_all(3 if _is_current else 2)
		frame_style.set_corner_radius_all(4 if _map_strip_style else 3)
		if is_instance_valid(_frame):
			_frame.add_theme_stylebox_override("panel", frame_style)

		var badge_style := StyleBoxFlat.new()
		if _occupied:
			badge_style.bg_color = Color(0.83, 0.80, 0.77, 0.98)
		elif _highlighted:
			badge_style.bg_color = Color(0.88, 0.86, 0.80, 0.98)
		else:
			badge_style.bg_color = Color(0.82, 0.80, 0.76, 0.98)
		badge_style.border_color = frame_border if _is_current else OUTLINE_COLOR
		badge_style.set_border_width_all(2)
		badge_style.set_corner_radius_all(6 if _map_strip_style else 4)
		if is_instance_valid(_number_badge):
			_number_badge.add_theme_stylebox_override("panel", badge_style)

		if is_instance_valid(_player_strip):
			_player_strip.visible = _occupied
			var strip_color := _player_color
			strip_color.a = 0.90
			_player_strip.color = strip_color

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
