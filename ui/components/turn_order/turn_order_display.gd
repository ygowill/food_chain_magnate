# 顶部顺序显示（展示用）
# 以紧凑形式显示玩家回合顺序位置，高亮当前行动玩家。
class_name TurnOrderDisplay
extends Control

signal position_selected(position: int)

@onready var slots_container: HBoxContainer = $SlotsContainer

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")

const BADGE_SIZE := 78 # 26 * 3 (triple height for better logo readability)
const BADGE_ICON_MARGIN := 6

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

func _rebuild() -> void:
	for slot in _slot_nodes:
		if is_instance_valid(slot):
			slot.queue_free()
	_slot_nodes.clear()

	if not is_instance_valid(slots_container):
		return

	for i in range(_player_count):
		var badge := OrderBadge.new()
		badge.slot_position = i
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
	const CURRENT_BORDER_COLOR := Color("#e74c3c")

	signal clicked(position: int)

	var slot_position: int = 0

	var _icon: TextureRect
	var _label: Label
	var _player_id: int = -1
	var _player_color: Color = Color(0.7, 0.7, 0.7, 1)
	var _is_current: bool = false
	var _occupied: bool = false
	var _logo_texture: Texture2D = null
	var _highlighted: bool = false
	var _clickable: bool = false

	func _ready() -> void:
		custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gui_input.connect(_on_gui_input)
		_icon = TextureRect.new()
		_icon.anchors_preset = Control.PRESET_FULL_RECT
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.offset_left = BADGE_ICON_MARGIN
		_icon.offset_top = BADGE_ICON_MARGIN
		_icon.offset_right = -BADGE_ICON_MARGIN
		_icon.offset_bottom = -BADGE_ICON_MARGIN
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 24)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
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

	func _update() -> void:
		if _icon != null:
			_icon.texture = _logo_texture
			_icon.visible = _occupied and _logo_texture != null
		if _label != null:
			if _occupied:
				_label.text = "" if _logo_texture != null else str(_player_id + 1)
				_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 0.9))
			else:
				_label.text = str(slot_position + 1)
				_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8, 0.8))

			var style := StyleBoxFlat.new()
			if _occupied:
				var bg := RESTAURANT_BG_COLOR
				bg.a = 0.95
				style.bg_color = bg
			elif _highlighted:
				style.bg_color = Color(0.20, 0.30, 0.22, 0.85)
			else:
				style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
			style.border_color = CURRENT_BORDER_COLOR if _is_current else (_player_color if _occupied else Color(0.3, 0.3, 0.35, 0.6))
			style.set_border_width_all(3 if _is_current else 1)
			style.set_corner_radius_all(int(BADGE_SIZE / 2))
			add_theme_stylebox_override("panel", style)

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
