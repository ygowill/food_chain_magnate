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
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")
const STRIP_BG_COLOR := Color("#c9342f")
const STRIP_SIDE_PAD := 10.0
const STRIP_BOTTOM_PAD := 8.0
const STRIP_TOP_TITLE_PAD := 30.0
const STRIP_SLOT_GAP := 10.0

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
var _intro_roll_active: bool = false
var _intro_roll_token: int = 0
var _logo_snapshot: Dictionary = {}
var _display_snapshot: Dictionary = {}

func _ready() -> void:
	_apply_layout_style()
	_rebuild()

func set_player_count(count: int) -> void:
	var c := clampi(count, 0, Globals.MAX_PLAYERS)
	if _player_count == c:
		return
	_player_count = c
	_rebuild()

func set_game_state(state: GameState) -> void:
	_game_state = state
	_ensure_skin()
	var next_logo_snapshot := _build_logo_snapshot()
	if next_logo_snapshot != _logo_snapshot:
		_logo_snapshot = next_logo_snapshot
		_rebuild_player_logo_ids()
	if _intro_roll_active:
		return
	_update_display()

func set_display_context(state: GameState, selections: Dictionary, current_player_id: int) -> void:
	_game_state = state
	_current_selections = selections.duplicate()
	_current_player_id = int(current_player_id)
	_ensure_skin()
	var next_logo_snapshot := _build_logo_snapshot()
	if next_logo_snapshot != _logo_snapshot:
		_logo_snapshot = next_logo_snapshot
		_rebuild_player_logo_ids()
	if _intro_roll_active:
		return
	_update_display()

func set_current_selections(selections: Dictionary) -> void:
	var next_selections := selections.duplicate()
	if next_selections == _current_selections:
		return
	_current_selections = next_selections
	if _intro_roll_active:
		return
	_update_display()

func set_current_player(player_id: int) -> void:
	if _current_player_id == player_id:
		return
	_current_player_id = player_id
	if _intro_roll_active:
		return
	_update_display()

func set_selectable(can_select: bool) -> void:
	var next_selectable := true if can_select else false
	if _selectable == next_selectable:
		return
	_selectable = next_selectable
	if _intro_roll_active:
		return
	_update_display()

func _apply_layout_style() -> void:
	if not is_instance_valid(slots_container):
		return

	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slots_container.anchor_left = 0.0
	slots_container.anchor_top = 0.0
	slots_container.anchor_right = 1.0
	slots_container.anchor_bottom = 1.0

	if use_map_strip_style:
		var slot_count := maxi(1, _player_count)
		var slot_w := OrderBadge.MAP_SLOT_SIDE
		var slot_h := OrderBadge.MAP_SLOT_SIDE + OrderBadge.MAP_FRAME_TOP
		var strip_w := STRIP_SIDE_PAD * 2.0 + slot_count * slot_w + maxi(0, slot_count - 1) * STRIP_SLOT_GAP
		var strip_h := STRIP_TOP_TITLE_PAD + slot_h + STRIP_BOTTOM_PAD
		custom_minimum_size = Vector2(strip_w, strip_h)
		slots_container.offset_left = STRIP_SIDE_PAD
		slots_container.offset_top = STRIP_TOP_TITLE_PAD
		slots_container.offset_right = -STRIP_SIDE_PAD
		slots_container.offset_bottom = -STRIP_BOTTOM_PAD
		slots_container.add_theme_constant_override("separation", int(STRIP_SLOT_GAP))
		if is_instance_valid(background):
			background.visible = true
			background.color = STRIP_BG_COLOR
		if is_instance_valid(title_label):
			title_label.visible = true
			title_label.text = "回合顺位"
			title_label.offset_left = 10.0
			title_label.offset_top = 4.0
			title_label.offset_right = -10.0
			title_label.offset_bottom = 24.0
		if is_instance_valid(hint_label):
			hint_label.visible = false
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
	_display_snapshot.clear()

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

	if _intro_roll_active:
		return
	_update_display()

func _update_display() -> void:
	var snapshot := {
		"player_count": _player_count,
		"current_selections": _current_selections.duplicate(true),
		"current_player_id": _current_player_id,
		"selectable": _selectable,
		"logo_ids": _player_restaurant_logo_ids.duplicate(true),
	}
	if snapshot == _display_snapshot:
		return
	_display_snapshot = snapshot
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

func _build_logo_snapshot() -> Dictionary:
	if _game_state == null or not (_game_state.players is Array):
		return {}
	var players: Array = []
	for p_val in _game_state.players:
		if not (p_val is Dictionary):
			players.append(null)
			continue
		var p: Dictionary = p_val
		players.append(p.get("restaurant_logo_id", null))
	return {
		"seed": int(_game_state.seed),
		"modules": Array(_game_state.modules, TYPE_STRING, "", null),
		"players": players,
	}

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

func play_intro_roll(final_order: Array, config: Dictionary = {}) -> void:
	# 仅用于开局“抽顺位”动画；不影响实际 state.turn_order。
	if OS.has_feature("headless"):
		_intro_roll_active = false
		_update_display()
		return

	var slot_count := _slot_nodes.size()
	if slot_count <= 0 and _player_count > 0:
		_intro_roll_active = true
		_rebuild()
		slot_count = _slot_nodes.size()
	if slot_count <= 0:
		_intro_roll_active = false
		return

	var final: Array[int] = []
	for i in range(slot_count):
		var pid := -1
		if i < final_order.size():
			var v = final_order[i]
			if v is int:
				pid = int(v)
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					pid = int(f)
		if pid < 0 and _current_selections.has(i):
			pid = int(_current_selections[i])
		if pid < 0:
			pid = i
		final.append(pid)

	var spin_sec := clampf(float(config.get("spin_sec", config.get("base_spin_sec", 1.10))), 0.20, 6.00)
	var tick_min_sec := clampf(float(config.get("tick_min_sec", 0.05)), 0.01, 0.20)
	var tick_max_sec := clampf(float(config.get("tick_max_sec", 0.18)), tick_min_sec, 0.60)

	var candidates := _get_roll_candidates()
	if candidates.is_empty():
		_intro_roll_active = false
		_update_display()
		return

	_intro_roll_active = true
	_intro_roll_token += 1
	var token := _intro_roll_token

	for slot in _slot_nodes:
		if not is_instance_valid(slot):
			continue
		slot.set_clickable(false)
		slot.set_highlighted(false)
		slot.set_empty()

	var rngs: Array[RandomNumberGenerator] = []
	for i in range(slot_count):
		var rng := RandomNumberGenerator.new()
		var seed := int(_state_seed) ^ int(0x524F4C4C) ^ int(i * 4099)
		rng.seed = seed
		rng.state = seed
		rngs.append(rng)

	var start_ms := int(Time.get_ticks_msec())
	var next_tick := 0.0
	while token == _intro_roll_token:
		var elapsed := float(int(Time.get_ticks_msec()) - start_ms) / 1000.0
		if elapsed >= spin_sec:
			break

		if elapsed >= float(next_tick):
			var t := clampf(elapsed / spin_sec, 0.0, 1.0)
			var interval := lerpf(tick_min_sec, tick_max_sec, t)
			next_tick = elapsed + interval
			for i in range(slot_count):
				var pid := candidates[rngs[i].randi_range(0, candidates.size() - 1)]
				_apply_slot_preview(_slot_nodes[i], pid)

		await get_tree().process_frame

	if token != _intro_roll_token:
		return

	for i in range(slot_count):
		_apply_slot_preview(_slot_nodes[i], final[i])

	_intro_roll_active = false
	_update_display()

func _get_roll_candidates() -> Array[int]:
	var ids: Array[int] = []
	if _game_state != null and (_game_state.players is Array):
		for i in range(_game_state.players.size()):
			var p_val = _game_state.players[i]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var pid := int(p.get("id", i))
			if pid >= 0:
				ids.append(pid)
	if ids.is_empty():
		for i in range(_player_count):
			ids.append(i)
	return ids

func _apply_slot_preview(slot: OrderBadge, player_id: int) -> void:
	if not is_instance_valid(slot):
		return
	var pid := int(player_id)
	var tex := _get_player_restaurant_logo_texture(pid)
	slot.set_player(pid, Globals.get_player_color(pid), false, tex)
	slot.set_highlighted(false)
	slot.set_clickable(false)


class OrderBadge extends Control:
	const RESTAURANT_BG_COLOR := Color("#f4edd1")
	const HIGHLIGHT_BORDER_COLOR := Color("#7f9f59")
	const OUTLINE_COLOR := Color("#101010")
	const MAP_SLOT_SIDE := 92.0
	const COMPACT_SLOT_SIDE := 72.0
	const MAP_FRAME_TOP := 14.0
	const COMPACT_FRAME_TOP := 11.0
	const CURRENT_FLAG_TEXTURE_PATH := "res://assets/images/flag_triangle.png"
	const CURRENT_FLAG_TINT_COLOR := Color("#c9342f")

	static var _flag_texture_cached: Texture2D = null

	static func _get_flag_texture() -> Texture2D:
		if _flag_texture_cached != null:
			return _flag_texture_cached
		var res = ResourceLoader.load(CURRENT_FLAG_TEXTURE_PATH, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			_flag_texture_cached = res
		return _flag_texture_cached

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

	var _frame: Panel
	var _number_badge: Panel
	var _number_label: Label
	var _icon: TextureRect
	var _fallback_label: Label
	var _current_flag_icon: TextureRect
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

		_number_badge = Panel.new()
		_number_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_number_badge.z_index = 3
		add_child(_number_badge)

		_number_label = Label.new()
		_number_label.anchor_left = 0.0
		_number_label.anchor_top = 0.0
		_number_label.anchor_right = 1.0
		_number_label.anchor_bottom = 1.0
		_number_label.offset_left = 0.0
		_number_label.offset_top = 0.0
		_number_label.offset_right = 0.0
		_number_label.offset_bottom = 0.0
		_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_number_badge.add_child(_number_label)

		_frame = Panel.new()
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.z_index = 1
		add_child(_frame)

		_icon = TextureRect.new()
		_icon.anchor_left = 0.0
		_icon.anchor_top = 0.0
		_icon.anchor_right = 1.0
		_icon.anchor_bottom = 1.0
		_icon.offset_left = 0.0
		_icon.offset_top = 0.0
		_icon.offset_right = 0.0
		_icon.offset_bottom = 0.0
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_icon)

		_fallback_label = Label.new()
		_fallback_label.anchor_left = 0.0
		_fallback_label.anchor_top = 0.0
		_fallback_label.anchor_right = 1.0
		_fallback_label.anchor_bottom = 1.0
		_fallback_label.offset_left = 0.0
		_fallback_label.offset_top = 0.0
		_fallback_label.offset_right = 0.0
		_fallback_label.offset_bottom = 0.0
		_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_fallback_label)

		_current_flag_icon = TextureRect.new()
		_current_flag_icon.anchor_left = 1.0
		_current_flag_icon.anchor_top = 0.0
		_current_flag_icon.anchor_right = 1.0
		_current_flag_icon.anchor_bottom = 0.0
		_current_flag_icon.offset_left = -18.0
		_current_flag_icon.offset_top = 3.0
		_current_flag_icon.offset_right = -3.0
		_current_flag_icon.offset_bottom = 18.0
		_current_flag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_current_flag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_current_flag_icon.texture = _get_flag_texture()
		_current_flag_icon.self_modulate = CURRENT_FLAG_TINT_COLOR
		_current_flag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_current_flag_icon.visible = false
		_current_flag_icon.z_index = 4
		_frame.add_child(_current_flag_icon)

	func _apply_metrics() -> void:
		if not is_instance_valid(_frame) or not is_instance_valid(_number_badge) or not is_instance_valid(_current_flag_icon):
			return

		var slot_side := MAP_SLOT_SIDE if _map_strip_style else COMPACT_SLOT_SIDE
		var frame_top := MAP_FRAME_TOP if _map_strip_style else COMPACT_FRAME_TOP
		var badge_size := 28.0 if _map_strip_style else 20.0
		var number_font_size := 16 if _map_strip_style else 13
		var fallback_font_size := 20 if _map_strip_style else 15
		var current_flag_size := 20.0 if _map_strip_style else 16.0
		_content_pad = 2.0 if _map_strip_style else 1.0

		custom_minimum_size = Vector2(slot_side, slot_side + frame_top)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

		_number_badge.anchor_left = 0.5
		_number_badge.anchor_top = 0.0
		_number_badge.anchor_right = 0.5
		_number_badge.anchor_bottom = 0.0
		_number_badge.offset_left = -badge_size * 0.5
		_number_badge.offset_top = frame_top - badge_size * 0.55
		_number_badge.offset_right = badge_size * 0.5
		_number_badge.offset_bottom = frame_top + badge_size * 0.45

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
		_current_flag_icon.offset_left = -current_flag_size - 3.0
		_current_flag_icon.offset_top = 3.0
		_current_flag_icon.offset_right = -3.0
		_current_flag_icon.offset_bottom = 3.0 + current_flag_size

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
		if _highlighted and _clickable:
			frame_border = HIGHLIGHT_BORDER_COLOR

		var frame_style := StyleBoxFlat.new()
		if _occupied:
			frame_style.bg_color = Color(RESTAURANT_BG_COLOR.r, RESTAURANT_BG_COLOR.g, RESTAURANT_BG_COLOR.b, 1.0)
		elif _highlighted:
			frame_style.bg_color = Color(0.98, 0.96, 0.88, 1.0)
		else:
			frame_style.bg_color = Color(0.95, 0.91, 0.82, 1.0)
		frame_style.border_color = frame_border
		frame_style.set_border_width_all(2)
		frame_style.set_corner_radius_all(4 if _map_strip_style else 3)
		if is_instance_valid(_frame):
			_frame.add_theme_stylebox_override("panel", frame_style)

		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Color(0.74, 0.74, 0.74, 1.0)
		badge_style.border_color = Color(0.28, 0.28, 0.28, 1.0)
		badge_style.set_border_width_all(2)
		badge_style.set_corner_radius_all(999)
		if is_instance_valid(_number_badge):
			_number_badge.add_theme_stylebox_override("panel", badge_style)

		if is_instance_valid(_current_flag_icon):
			_current_flag_icon.visible = _occupied and _is_current and _current_flag_icon.texture != null

		_layout_logo_square()

		if _occupied:
			tooltip_text = "顺位 %d: %s" % [slot_position + 1, Globals.get_player_name(_player_id)]
		else:
			tooltip_text = "顺位 %d: （空）" % (slot_position + 1)

	func _on_gui_input(event: InputEvent) -> void:
		if not _clickable:
			return
		if UiPointerInputClass.is_primary_press(event):
			clicked.emit(slot_position)
