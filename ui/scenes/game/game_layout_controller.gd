# Game scene：布局/响应式控制器
# 负责：左侧信息区、右侧操作区、底部面板的显示与响应式布局参数。
class_name GameLayoutController
extends RefCounted

const LEFT_AREA_MIN_WIDTH := 460
const PLAYER_TAB_MIN_SIZE := 68
const PLAYER_TAB_SEPARATION := 8
const PLAYER_TAB_PANEL_H_PADDING := 16
const PLAYER_TAB_PANEL_EXTRA_PADDING := 8

var _scene = null

var _round_label: Label = null
var _phase_track: Control = null
var _bank_label: Label = null

var _toggle_left_panel_button: Button = null
var _toggle_right_panel_button: Button = null
var _toggle_bottom_panel_button: Button = null

var _main_content: Control = null
var _center_split: HSplitContainer = null
var _left_area: Control = null
var _left_panel: Control = null
var _game_log_panel: GameLogPanel = null
var _bottom_panel: Control = null
var _right_panel: Control = null

var _player_panel: Control = null
var _inventory_panel: Control = null

var _left_area_visible: bool = true
var _main_content_default_split_offset: int = 460
var _left_area_user_resized: bool = false

var _bottom_panel_visible: bool = true

var _right_panel_visible: bool = true
var _center_split_default_split_offset: int = -340

var _responsive_mode: String = ""
var _responsive_font_scale: float = -1.0

func _init(
	scene,
	round_label: Label,
	phase_track: Control,
	bank_label: Label,
	toggle_left_panel_button: Button,
	toggle_right_panel_button: Button,
	toggle_bottom_panel_button: Button,
	main_content: Control,
	center_split: HSplitContainer,
	left_area: Control,
	left_panel: Control,
	game_log_panel: GameLogPanel,
	bottom_panel: Control,
	right_panel: Control,
	player_panel: Control,
	inventory_panel: Control
) -> void:
	_scene = scene
	_round_label = round_label
	_phase_track = phase_track
	_bank_label = bank_label
	_toggle_left_panel_button = toggle_left_panel_button
	_toggle_right_panel_button = toggle_right_panel_button
	_toggle_bottom_panel_button = toggle_bottom_panel_button
	_main_content = main_content
	_center_split = center_split
	_left_area = left_area
	_left_panel = left_panel
	_game_log_panel = game_log_panel
	_bottom_panel = bottom_panel
	_right_panel = right_panel
	_player_panel = player_panel
	_inventory_panel = inventory_panel

func is_left_area_visible() -> bool:
	return _left_area_visible

func is_right_panel_visible() -> bool:
	return _right_panel_visible

func on_main_content_dragged(offset: int) -> void:
	if not _left_area_visible:
		return
	_left_area_user_resized = true
	# 只限制最小宽度（issue_tracker #61）：避免把“用户拖到的宽度”写回 custom_minimum_size 导致无法再缩小。
	var min_w := _get_left_area_min_width()
	var clamped := maxi(int(offset), min_w)
	_main_content_default_split_offset = clamped
	if is_instance_valid(_main_content):
		_main_content.split_offset = clamped
	if is_instance_valid(_left_area):
		_left_area.custom_minimum_size.x = min_w

func init_left_panel_toggle() -> void:
	var min_w := _get_left_area_min_width()
	if is_instance_valid(_main_content):
		_main_content_default_split_offset = maxi(int(_main_content.split_offset), min_w)
	_left_area_visible = is_instance_valid(_left_area) and _left_area.visible
	_update_left_panel_toggle_button()

func ensure_left_area_visible() -> void:
	if _left_area_visible:
		return
	_left_area_visible = true
	if is_instance_valid(_left_area):
		_left_area.visible = true
	if is_instance_valid(_main_content):
		_main_content.split_offset = maxi(_main_content_default_split_offset, _get_left_area_min_width())
	_update_left_panel_toggle_button()

func on_toggle_left_panel_pressed() -> void:
	_left_area_visible = not _left_area_visible
	if is_instance_valid(_left_area):
		_left_area.visible = _left_area_visible
	if is_instance_valid(_main_content):
		if _left_area_visible:
			_main_content.split_offset = maxi(_main_content_default_split_offset, _get_left_area_min_width())
		else:
			_main_content.split_offset = 0
	_update_left_panel_toggle_button()

func _update_left_panel_toggle_button() -> void:
	if not is_instance_valid(_toggle_left_panel_button):
		return
	_toggle_left_panel_button.text = "隐藏信息" if _left_area_visible else "显示信息"

func init_right_panel_toggle() -> void:
	if is_instance_valid(_center_split):
		_center_split_default_split_offset = _center_split.split_offset
	_right_panel_visible = is_instance_valid(_right_panel) and _right_panel.visible
	_update_right_panel_toggle_button()

func ensure_right_panel_visible() -> void:
	if _right_panel_visible:
		return
	_right_panel_visible = true
	if is_instance_valid(_right_panel):
		_right_panel.visible = true
	if is_instance_valid(_center_split):
		_center_split.split_offset = _center_split_default_split_offset
	_update_right_panel_toggle_button()

func on_toggle_right_panel_pressed() -> void:
	_right_panel_visible = not _right_panel_visible
	if not is_instance_valid(_right_panel):
		_update_right_panel_toggle_button()
		return

	if OS.has_feature("headless"):
		_right_panel.visible = _right_panel_visible
	else:
		await _animate_right_panel_visibility(_right_panel, _right_panel_visible)

	if is_instance_valid(_center_split) and _right_panel_visible:
		_center_split.split_offset = _center_split_default_split_offset

	_update_right_panel_toggle_button()

func _update_right_panel_toggle_button() -> void:
	if not is_instance_valid(_toggle_right_panel_button):
		return
	_toggle_right_panel_button.text = "隐藏操作" if _right_panel_visible else "显示操作"

func _animate_right_panel_visibility(right_panel: Control, make_visible: bool) -> void:
	if not is_instance_valid(right_panel):
		return
	if OS.has_feature("headless"):
		right_panel.visible = make_visible
		return
	if _scene == null or not (_scene.has_method("get_ui_animation_manager")):
		right_panel.visible = make_visible
		return
	var anim_manager = _scene.get_ui_animation_manager()
	if anim_manager == null:
		right_panel.visible = make_visible
		return

	if make_visible:
		right_panel.visible = true
		if _scene != null and is_instance_valid(_scene):
			await _scene.get_tree().process_frame
		if anim_manager.has_method("animate_slide_in"):
			anim_manager.call("animate_slide_in", right_panel, "right")
	else:
		if not anim_manager.has_method("animate_slide_out"):
			right_panel.visible = false
			return
		var original_pos := right_panel.position
		anim_manager.call("animate_slide_out", right_panel, "right", Callable(self, "_finish_hide_right_panel").bind(right_panel, original_pos))

func _finish_hide_right_panel(right_panel: Control, original_pos: Vector2) -> void:
	if not is_instance_valid(right_panel):
		return
	right_panel.visible = false
	right_panel.position = original_pos

func apply_ui_layout() -> void:
	# 强制新布局（v2），不再支持 v1（issue_tracker #60）。
	if is_instance_valid(_player_panel):
		_player_panel.visible = false
	if is_instance_valid(_inventory_panel):
		_inventory_panel.visible = false
	if is_instance_valid(_left_panel):
		_left_panel.visible = true
		if is_instance_valid(_game_log_panel):
			_game_log_panel.visible = false
			if _left_panel.has_method("bind_game_log_panel"):
				_left_panel.call("bind_game_log_panel", _game_log_panel)
			elif _left_panel.has_method("attach_game_log_panel"):
				_left_panel.call("attach_game_log_panel", _game_log_panel)
		if _scene != null and is_instance_valid(_scene) and _left_panel.has_signal("logs_requested"):
			var sig := Signal(_left_panel, &"logs_requested")
			var cb := Callable(_scene, "_on_left_panel_logs_requested")
			if not sig.is_connected(cb):
				sig.connect(cb)

	if is_instance_valid(_bottom_panel):
		_bottom_panel.visible = false
	_bottom_panel_visible = false
	if is_instance_valid(_toggle_bottom_panel_button):
		_toggle_bottom_panel_button.visible = false

func init_bottom_panel_toggle() -> void:
	_bottom_panel_visible = false
	_update_bottom_panel_toggle_button()

func on_toggle_bottom_panel_pressed() -> void:
	_bottom_panel_visible = not _bottom_panel_visible
	if is_instance_valid(_bottom_panel):
		_bottom_panel.visible = _bottom_panel_visible
	_update_bottom_panel_toggle_button()

func _update_bottom_panel_toggle_button() -> void:
	if is_instance_valid(_toggle_bottom_panel_button):
		_toggle_bottom_panel_button.text = "隐藏底部" if _bottom_panel_visible else "显示底部"

func apply_responsive_layout() -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	if not is_instance_valid(_main_content) or not is_instance_valid(_center_split):
		return

	var width := int(_scene.get_viewport_rect().size.x)
	var mode := "standard"
	if width < 1280:
		mode = "narrow"
	elif width > 1920:
		mode = "wide"

	var current_font_scale := 1.0
	if Globals != null:
		current_font_scale = float(Globals.font_scale)

	if mode == _responsive_mode and is_equal_approx(current_font_scale, _responsive_font_scale):
		return
	_responsive_mode = mode
	_responsive_font_scale = current_font_scale

	var left_width := 420
	var right_width := 340
	var font_size := 18
	var separation := 20

	match mode:
		"narrow":
			left_width = 360
			right_width = 300
			font_size = 14
			separation = 12
		"wide":
			left_width = 460
			right_width = 380
			font_size = 18
			separation = 24
		_:
			left_width = 420
			right_width = 340
			font_size = 18
			separation = 20

	var panel_tabs_min_width := _estimate_player_tabs_min_panel_width(_get_layout_player_count())
	var min_left_width := _get_left_area_min_width()
	right_width = maxi(int(right_width), panel_tabs_min_width)

	if _left_area_user_resized:
		left_width = maxi(int(_main_content_default_split_offset), min_left_width)
	else:
		left_width = maxi(int(left_width), min_left_width)
		left_width = maxi(int(left_width), panel_tabs_min_width)

	if is_instance_valid(_left_area):
		_left_area.custom_minimum_size.x = min_left_width
	_main_content_default_split_offset = left_width
	if _left_area_visible:
		_main_content.split_offset = left_width

	if is_instance_valid(_right_panel):
		_right_panel.custom_minimum_size.x = right_width
	_center_split_default_split_offset = -right_width
	if _right_panel_visible:
		_center_split.split_offset = _center_split_default_split_offset

	var top_bar = _scene.get_node_or_null("UIRoot/TopBar")
	if top_bar is HBoxContainer:
		(top_bar as HBoxContainer).add_theme_constant_override("separation", separation)

	var scaled_font_size := font_size
	if Globals != null:
		scaled_font_size = int(Globals.get_scaled_font_size(font_size))

	if is_instance_valid(_round_label):
		_round_label.add_theme_font_size_override("font_size", scaled_font_size)
	if is_instance_valid(_phase_track) and _phase_track.has_method("set_font_size"):
		_phase_track.set_font_size(maxi(13, scaled_font_size - 1))
	if is_instance_valid(_bank_label):
		_bank_label.add_theme_font_size_override("font_size", scaled_font_size)
	var bank_title_label = _scene.get_node_or_null("UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankTitleLabel")
	if bank_title_label is Label:
		(bank_title_label as Label).add_theme_font_size_override("font_size", scaled_font_size)

func _get_layout_player_count() -> int:
	var count := 0
	if _scene != null and is_instance_valid(_scene):
		var engine = _scene.game_engine if _scene != null else null
		if engine != null and engine.has_method("get_state"):
			var state: GameState = engine.get_state()
			if state != null and state.players is Array:
				count = state.players.size()
	if count <= 0 and Globals != null:
		count = int(Globals.player_count)
	return maxi(0, count)

func _estimate_player_tabs_min_panel_width(player_count: int) -> int:
	if player_count <= 0:
		return 0
	var tabs_width := int(player_count) * PLAYER_TAB_MIN_SIZE
	tabs_width += maxi(0, int(player_count) - 1) * PLAYER_TAB_SEPARATION
	return tabs_width + PLAYER_TAB_PANEL_H_PADDING + PLAYER_TAB_PANEL_EXTRA_PADDING

func _get_left_area_min_width() -> int:
	var min_w := LEFT_AREA_MIN_WIDTH
	if is_instance_valid(_left_panel):
		min_w = maxi(min_w, int(round(_left_panel.custom_minimum_size.x)))
	if is_instance_valid(_left_area):
		min_w = maxi(min_w, int(round(_left_area.custom_minimum_size.x)))
	return min_w
