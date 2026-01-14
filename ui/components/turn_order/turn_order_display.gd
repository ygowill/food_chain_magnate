# 顶部顺序显示（展示用）
# 以紧凑形式显示玩家回合顺序位置，高亮当前行动玩家。
class_name TurnOrderDisplay
extends Control

@onready var slots_container: HBoxContainer = $SlotsContainer

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")

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

func _ready() -> void:
	_rebuild()

func set_player_count(count: int) -> void:
	_player_count = clamp(count, 0, 5)
	_rebuild()

func set_game_state(state: GameState) -> void:
	_game_state = state
	_rebuild_player_logo_ids()
	_ensure_skin()
	_update_display()

func set_current_selections(selections: Dictionary) -> void:
	_current_selections = selections.duplicate()
	_update_display()

func set_current_player(player_id: int) -> void:
	_current_player_id = player_id
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
		else:
			slot.set_empty(pos == 0 and _player_count == 0)

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

	var logo_count := MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS.size()
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
	if not (_skin.has_method("get_piece_texture")):
		return null
	var logo_count := MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS.size()
	if logo_count <= 0:
		return null
	var logo_id := int(_player_restaurant_logo_ids.get(player_id, -1))
	if logo_id < 0 or logo_id >= logo_count:
		logo_id = _fallback_logo_id_for_player(player_id, _fallback_logo_ids)
	var key: String = MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS[logo_id]
	return _skin.get_piece_texture(key)


class OrderBadge extends PanelContainer:
	var slot_position: int = 0

	var _icon: TextureRect
	var _label: Label
	var _player_id: int = -1
	var _player_color: Color = Color(0.7, 0.7, 0.7, 1)
	var _is_current: bool = false
	var _occupied: bool = false
	var _logo_texture: Texture2D = null

	func _ready() -> void:
		custom_minimum_size = Vector2(26, 26)
		_icon = TextureRect.new()
		_icon.anchors_preset = Control.PRESET_FULL_RECT
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.offset_left = 3
		_icon.offset_top = 3
		_icon.offset_right = -3
		_icon.offset_bottom = -3
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 12)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_update()

	func set_player(player_id: int, color: Color, is_current: bool, logo_texture: Texture2D) -> void:
		_player_id = player_id
		_player_color = color
		_is_current = is_current
		_occupied = true
		_logo_texture = logo_texture
		_update()

	func set_empty(_unused: bool = false) -> void:
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
			_label.text = "" if (_occupied and _logo_texture != null) else (str(_player_id + 1) if _occupied else "")

		var style := StyleBoxFlat.new()
		style.bg_color = Color(_player_color.r, _player_color.g, _player_color.b, 0.28) if _occupied else Color(0.15, 0.15, 0.18, 0.8)
		style.border_color = Color(0.95, 0.95, 0.95, 0.95) if _is_current else (_player_color if _occupied else Color(0.3, 0.3, 0.35, 0.6))
		style.set_border_width_all(2 if _is_current else 1)
		style.set_corner_radius_all(13)
		add_theme_stylebox_override("panel", style)

		if _occupied:
			tooltip_text = "顺位 %d: %s" % [slot_position + 1, Globals.get_player_name(_player_id)]
		else:
			tooltip_text = "顺位 %d: （空）" % (slot_position + 1)
