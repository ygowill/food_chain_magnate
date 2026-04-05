# 玩家信息面板组件（RightPanel 顶部）
# - 顶部：餐厅 logo tab（复用顺位显示的图标风格）
# - 下方：当前查看玩家的简要信息
class_name PlayerPanel
extends Control

signal player_selected(player_id: int)

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")

const RESTAURANT_BG_COLOR := Color("#f4edd1")

@onready var player_tabs: HBoxContainer = $MarginContainer/VBoxContainer/PlayerTabs
@onready var selected_row: HBoxContainer = $MarginContainer/VBoxContainer/SelectedRow
@onready var icon_badge: PanelContainer = $MarginContainer/VBoxContainer/SelectedRow/IconBadge
@onready var icon: TextureRect = $MarginContainer/VBoxContainer/SelectedRow/IconBadge/Icon
@onready var name_label: Label = $MarginContainer/VBoxContainer/SelectedRow/InfoVBox/NameLabel
@onready var stats_label: Label = $MarginContainer/VBoxContainer/SelectedRow/InfoVBox/StatsLabel
@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer

var _game_state: GameState = null
var _current_player_id: int = -1
var _view_player_id: int = -1

var _player_count: int = 0
var _tab_buttons: Array[Button] = []

var _skin = null
var _skin_modules_key: String = ""
var _state_seed: int = 0
var _player_restaurant_logo_ids: Dictionary = {} # player_id -> logo_id
var _fallback_logo_ids: Array[int] = []
var _logo_snapshot: Dictionary = {}
var _selected_player_snapshot: Dictionary = {}
var _tab_style_snapshot: Dictionary = {}

func _ready() -> void:
	if is_instance_valid(items_container):
		items_container.visible = false
	_rebuild_player_tabs()
	apply_font_settings()
	_refresh()

func set_game_state(state: GameState) -> void:
	_game_state = state
	_ensure_skin()
	var next_logo_snapshot := _build_logo_snapshot()
	if next_logo_snapshot != _logo_snapshot:
		_logo_snapshot = next_logo_snapshot
		_rebuild_player_logo_ids()

	var count := 0
	if state != null and (state.players is Array):
		count = state.players.size()
	if count != _player_count:
		_player_count = count
		_rebuild_player_tabs()
	else:
		_update_player_tab_icons()

	_refresh()

func set_current_player(player_id: int) -> void:
	if _current_player_id == player_id:
		return
	_current_player_id = player_id
	_update_tab_styles()
	_refresh_selected_player()

func set_view_player(player_id: int) -> void:
	if _view_player_id == player_id:
		return
	_view_player_id = player_id
	_update_tab_styles()
	_refresh_selected_player()

func refresh() -> void:
	_refresh()

func apply_font_settings() -> void:
	var fs_main := 14
	var fs_small := 12
	if Globals != null:
		fs_main = int(Globals.get_scaled_font_size(14))
		fs_small = int(Globals.get_scaled_font_size(12))

	if is_instance_valid(name_label):
		name_label.add_theme_font_size_override("font_size", fs_main)
	if is_instance_valid(stats_label):
		stats_label.add_theme_font_size_override("font_size", fs_small)

func _refresh() -> void:
	_update_tab_styles()
	_refresh_selected_player()

func _rebuild_player_tabs() -> void:
	if not is_instance_valid(player_tabs):
		return

	for ch in player_tabs.get_children():
		if is_instance_valid(ch):
			ch.queue_free()
	_tab_buttons.clear()

	var group := ButtonGroup.new()
	for i in range(_player_count):
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(52, 52)
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.toggled.connect(_on_player_tab_toggled.bind(i))
		player_tabs.add_child(btn)
		_tab_buttons.append(btn)

	_update_player_tab_icons()
	_update_tab_styles()

func _on_player_tab_toggled(toggled_on: bool, player_id: int) -> void:
	if not toggled_on:
		return
	player_selected.emit(int(player_id))

func _resolve_view_player_id() -> int:
	var view_id := _view_player_id
	if _game_state != null and (view_id < 0 or view_id >= _game_state.players.size()):
		view_id = _current_player_id
	return view_id

func _update_tab_styles() -> void:
	var view_id := _resolve_view_player_id()
	var snapshot := {
		"view_player_id": view_id,
		"current_player_id": _current_player_id,
		"tab_count": _tab_buttons.size(),
	}
	if snapshot == _tab_style_snapshot:
		return
	_tab_style_snapshot = snapshot
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if not is_instance_valid(btn):
			continue

		btn.set_pressed_no_signal(i == view_id)

		var color := Globals.get_player_color(i)
		var is_current := i == _current_player_id
		var is_view := i == view_id

		var bg := RESTAURANT_BG_COLOR
		bg.a = 0.95

		var normal := StyleBoxFlat.new()
		normal.bg_color = bg
		normal.border_color = Color(color.r, color.g, color.b, 0.85)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(26)

		var pressed := StyleBoxFlat.new()
		pressed.bg_color = bg
		pressed.border_color = color
		pressed.set_border_width_all(3 if is_view else 1)
		pressed.set_corner_radius_all(26)

		# 当前行动玩家：优先白色边框
		if is_current:
			var current_border := Color(0.95, 0.95, 0.95, 0.9)
			pressed.border_color = current_border
			pressed.set_border_width_all(3)
			if not is_view:
				normal.border_color = current_border
				normal.set_border_width_all(3)

		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("hover", pressed)

		btn.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.add_theme_color_override("font_hover_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.add_theme_color_override("font_pressed_color", Color(0.15, 0.15, 0.15, 0.9))
		btn.add_theme_color_override("font_focus_color", Color(0.15, 0.15, 0.15, 0.9))

func _refresh_selected_player() -> void:
	if not is_instance_valid(name_label) or not is_instance_valid(stats_label):
		return

	var view_id := _resolve_view_player_id()
	if _game_state == null or not (_game_state.players is Array) or view_id < 0 or view_id >= _game_state.players.size():
		if _selected_player_snapshot == {"empty": true}:
			return
		_selected_player_snapshot = {"empty": true}
		name_label.text = "查看: -"
		stats_label.text = ""
		if is_instance_valid(icon):
			icon.texture = null
		_apply_icon_badge_style(Color(0.3, 0.3, 0.35, 0.6), false)
		return

	var player_val = _game_state.players[view_id]
	var player: Dictionary = player_val if (player_val is Dictionary) else {}

	var pname := Globals.get_player_name(view_id) if Globals != null else ("玩家%d" % (view_id + 1))

	var cash := int(player.get("cash", 0))
	var emp_count := 0
	emp_count += Array(player.get("employees", [])).size()
	emp_count += Array(player.get("reserve_employees", [])).size()
	emp_count += Array(player.get("busy_marketers", [])).size()
	var rest_count := Array(player.get("restaurants", [])).size()
	var snapshot := {
		"view_player_id": view_id,
		"current_player_id": _current_player_id,
		"cash": cash,
		"employee_count": emp_count,
		"restaurant_count": rest_count,
		"name": pname,
		"logo_id": int(_player_restaurant_logo_ids.get(view_id, -1)),
	}
	if snapshot == _selected_player_snapshot:
		return
	_selected_player_snapshot = snapshot

	name_label.text = "查看: %s" % pname
	stats_label.text = "$%d | %d人 | %d店" % [cash, emp_count, rest_count]

	if is_instance_valid(icon):
		icon.texture = _get_player_restaurant_logo_texture(view_id)

	var border := Globals.get_player_color(view_id)
	var is_current := view_id == _current_player_id
	if is_current:
		border = Color(0.95, 0.95, 0.95, 0.9)
	_apply_icon_badge_style(border, is_current)

func _apply_icon_badge_style(border_color: Color, is_current: bool) -> void:
	if not is_instance_valid(icon_badge):
		return
	var bg := RESTAURANT_BG_COLOR
	bg.a = 0.95
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(3 if is_current else 2)
	style.set_corner_radius_all(26)
	icon_badge.add_theme_stylebox_override("panel", style)

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

func _apply_player_tab_icon(btn: Button, player_id: int) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var tex := _get_player_restaurant_logo_texture(player_id)
	if tex != null:
		btn.text = ""
		btn.icon = tex
	else:
		btn.icon = null
		btn.text = str(player_id + 1)

func _update_player_tab_icons() -> void:
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if not is_instance_valid(btn):
			continue
		_apply_player_tab_icon(btn, i)
