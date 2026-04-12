# 设置对话框组件
# 游戏设置、音量、显示选项等
class_name SettingsDialog
extends ModalDialogBase

signal settings_changed(settings: Dictionary)
signal closed()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var background_panel: Panel = $BackgroundPanel
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var page_panel: PanelContainer = $MarginContainer/VBoxContainer/ContentHBox/PagePanel
@onready var close_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CloseButton
@onready var reset_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ResetButton

# 导航按钮
@onready var audio_nav_btn: Button = %AudioNavBtn
@onready var display_nav_btn: Button = %DisplayNavBtn
@onready var game_nav_btn: Button = %GameNavBtn
@onready var debug_nav_btn: Button = %DebugNavBtn

# 页面
@onready var audio_page: VBoxContainer = %AudioPage
@onready var display_page: VBoxContainer = %DisplayPage
@onready var game_page: VBoxContainer = %GamePage
@onready var debug_page: VBoxContainer = %DebugPage

# 音频选项
@onready var master_volume: HSlider = %MasterSlider
@onready var music_volume: HSlider = %MusicSlider
@onready var sfx_volume: HSlider = %SFXSlider
@onready var mute_check: CheckBox = %MuteCheck
@onready var master_value_label: Label = %MasterValue
@onready var music_value_label: Label = %MusicValue
@onready var sfx_value_label: Label = %SFXValue

# 显示选项
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VsyncCheck
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var ui_scale_slider: HSlider = %UIScaleSlider
@onready var font_scale_slider: HSlider = %FontScaleSlider
@onready var log_font_scale_slider: HSlider = %LogFontScaleSlider
@onready var ui_scale_value_label: Label = %UIScaleValue
@onready var font_scale_value_label: Label = %FontScaleValue
@onready var log_font_scale_value_label: Label = %LogFontScaleValue
@onready var show_tile_ids_check: CheckBox = %ShowTileIdsCheck
@onready var show_cell_hover_tooltip_check: CheckBox = %ShowCellHoverTooltipCheck

# 游戏选项
@onready var auto_save_check: CheckBox = %AutoSaveCheck
@onready var confirm_actions_check: CheckBox = %ConfirmActionsCheck
@onready var show_hints_check: CheckBox = %ShowHintsCheck
@onready var replay_load_playable_check: CheckBox = %ReplayLoadPlayableCheck
@onready var tutorial_enabled_check: CheckBox = %TutorialEnabledCheck
@onready var reset_tutorial_progress_button: Button = %ResetTutorialProgressButton
@onready var animation_speed_slider: HSlider = %AnimSpeedSlider
@onready var anim_speed_value_label: Label = %AnimSpeedValue

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1536, 864),
	Vector2i(1600, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2160, 1440),
	Vector2i(2256, 1504),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(2880, 1800),
	Vector2i(3200, 1800),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]

var _current_settings: Dictionary = {}
var _default_settings: Dictionary = {
	"master_volume": 0.8,
	"music_volume": 0.3,
	"sfx_volume": 0.8,
	"mute": false,
	"fullscreen": false,
	"vsync": true,
	"resolution": Vector2i(1920, 1080),
	"ui_scale": 1.0,
	"font_scale": 1.1,
	"log_font_scale": 1.35,
	"show_tile_ids": false,
	"show_cell_hover_tooltip": false,
	"auto_save": true,
	"confirm_actions": true,
	"show_hints": true,
	"replay_load_playable": false,
	"tutorial_enabled": true,
	"animation_speed": 1.0,
}

var _nav_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_page_index: int = 0
var _syncing_ui: bool = false

func _ready() -> void:
	super._ready()
	UiStylesClass.apply_dialog_surface(background_panel)
	UiStylesClass.apply_button_secondary(reset_btn)
	UiStylesClass.apply_button_primary(close_btn)
	UiStylesClass.apply_panel_poster_alt(page_panel)

	_nav_buttons = [audio_nav_btn, display_nav_btn, game_nav_btn, debug_nav_btn]
	_pages = [audio_page, display_page, game_page, debug_page]

	_apply_visual_styles()
	_connect_nav_buttons()
	_connect_slider_value_labels()

	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	if reset_btn != null:
		reset_btn.pressed.connect(_on_reset_pressed)

	_setup_resolution_options()
	_load_settings()
	_connect_setting_change_signals()
	_switch_page(0)

func open() -> void:
	_load_audio_settings()
	_sync_display_ui_from_runtime()
	super.open()

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless"

func _sync_display_ui_from_runtime() -> void:
	if _is_headless_runtime():
		return

	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	var vsync_mode := DisplayServer.window_get_vsync_mode()
	var vsync_enabled := (vsync_mode != DisplayServer.VSYNC_DISABLED)
	var size := DisplayServer.window_get_size()

	_current_settings["fullscreen"] = is_fullscreen
	_current_settings["vsync"] = vsync_enabled
	if not is_fullscreen and size.x > 0 and size.y > 0:
		_current_settings["resolution"] = Vector2i(size.x, size.y)

	_update_ui_from_settings()

func _apply_visual_styles() -> void:
	UiStylesClass.apply_label_dark(title_label)
	_apply_section_label_styles()
	_apply_form_control_styles()

func _apply_section_label_styles() -> void:
	for page in _pages:
		if page == null:
			continue
		for child in page.get_children():
			if child is Label and child.name.ends_with("SectionLabel"):
				UiStylesClass.apply_label_hint_dark(child)
			elif child is Label:
				UiStylesClass.apply_label_dark(child)
			elif child is HBoxContainer:
				for sub in child.get_children():
					if sub is Label:
						UiStylesClass.apply_label_dark(sub)

func _apply_form_control_styles() -> void:
	UiStylesClass.apply_check_box_field(mute_check)
	UiStylesClass.apply_check_box_field(fullscreen_check)
	UiStylesClass.apply_check_box_field(vsync_check)
	UiStylesClass.apply_check_box_field(show_tile_ids_check)
	UiStylesClass.apply_check_box_field(show_cell_hover_tooltip_check)
	UiStylesClass.apply_check_box_field(auto_save_check)
	UiStylesClass.apply_check_box_field(confirm_actions_check)
	UiStylesClass.apply_check_box_field(show_hints_check)
	UiStylesClass.apply_check_box_field(replay_load_playable_check)
	UiStylesClass.apply_check_box_field(tutorial_enabled_check)
	UiStylesClass.apply_option_button_field(resolution_option)
	UiStylesClass.apply_button_secondary(reset_tutorial_progress_button)

# ── 导航 ──────────────────────────────────────────────

func _connect_nav_buttons() -> void:
	for i in range(_nav_buttons.size()):
		var btn := _nav_buttons[i]
		if btn != null:
			btn.pressed.connect(_on_nav_pressed.bind(i))

func _on_nav_pressed(index: int) -> void:
	_switch_page(index)

func _switch_page(index: int) -> void:
	_current_page_index = clampi(index, 0, _pages.size() - 1)
	for i in range(_pages.size()):
		if _pages[i] != null:
			_pages[i].visible = (i == _current_page_index)
	_update_nav_styles()

func _update_nav_styles() -> void:
	for i in range(_nav_buttons.size()):
		var btn := _nav_buttons[i]
		if btn == null:
			continue
		var selected := (i == _current_page_index)
		UiStylesClass.apply_nav_button(btn, selected)

# ── Slider 数值标签 ───────────────────────────────────

func _connect_slider_value_labels() -> void:
	_bind_slider_label(master_volume, master_value_label)
	_bind_slider_label(music_volume, music_value_label)
	_bind_slider_label(sfx_volume, sfx_value_label)
	_bind_slider_label(ui_scale_slider, ui_scale_value_label)
	_bind_slider_label(font_scale_slider, font_scale_value_label)
	_bind_slider_label(log_font_scale_slider, log_font_scale_value_label)
	_bind_slider_label(animation_speed_slider, anim_speed_value_label)

func _bind_slider_label(slider: HSlider, label: Label) -> void:
	if slider == null or label == null:
		return
	slider.value_changed.connect(func(val: float) -> void: label.text = "%d%%" % int(val))

# ── 焦点 ─────────────────────────────────────────────

func _grab_default_focus() -> void:
	if close_btn != null:
		close_btn.grab_focus()

# ── 分辨率 ────────────────────────────────────────────

func _setup_resolution_options() -> void:
	if resolution_option == null:
		return
	resolution_option.clear()
	for res in RESOLUTIONS:
		resolution_option.add_item("%dx%d" % [res.x, res.y])

func _rebuild_resolution_options(selected_res: Vector2i) -> void:
	if resolution_option == null:
		return
	resolution_option.clear()
	var found_index := -1
	for i in range(RESOLUTIONS.size()):
		var res := RESOLUTIONS[i]
		resolution_option.add_item("%dx%d" % [res.x, res.y])
		if res == selected_res:
			found_index = i
	if found_index >= 0:
		resolution_option.select(found_index)
		return
	if selected_res.x > 0 and selected_res.y > 0:
		resolution_option.add_item("%dx%d（当前）" % [selected_res.x, selected_res.y])
		resolution_option.select(resolution_option.item_count - 1)

# ── 设置读写 ──────────────────────────────────────────

func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")

	if err == OK:
		_current_settings = {
			"fullscreen": config.get_value("display", "fullscreen", _default_settings.fullscreen),
			"vsync": config.get_value("display", "vsync", _default_settings.vsync),
			"resolution": config.get_value("display", "resolution", _default_settings.resolution),
			"ui_scale": config.get_value("display", "ui_scale", _default_settings.ui_scale),
			"font_scale": float(config.get_value("display", "font_scale", _default_settings.font_scale)),
			"log_font_scale": float(config.get_value("display", "log_font_scale", _default_settings.log_font_scale)),
			"show_tile_ids": bool(config.get_value("display", "show_tile_ids", _default_settings.show_tile_ids)),
			"show_cell_hover_tooltip": bool(config.get_value("display", "show_cell_hover_tooltip", _default_settings.show_cell_hover_tooltip)),
			"auto_save": config.get_value("game", "auto_save", _default_settings.auto_save),
			"confirm_actions": config.get_value("game", "confirm_actions", _default_settings.confirm_actions),
			"show_hints": config.get_value("game", "show_hints", _default_settings.show_hints),
			"replay_load_playable": config.get_value("game", "replay_load_playable", _default_settings.replay_load_playable),
			"tutorial_enabled": bool(config.get_value("game", "tutorial_enabled", _default_settings.tutorial_enabled)),
			"animation_speed": config.get_value("game", "animation_speed", _default_settings.animation_speed),
		}
	else:
		_current_settings = _default_settings.duplicate()

	_load_audio_settings()
	_update_ui_from_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")

	config.set_value("display", "fullscreen", _current_settings.fullscreen)
	config.set_value("display", "vsync", _current_settings.vsync)
	config.set_value("display", "resolution", _current_settings.resolution)
	config.set_value("display", "ui_scale", _current_settings.ui_scale)
	config.set_value("display", "font_scale", float(_current_settings.get("font_scale", 1.0)))
	config.set_value("display", "log_font_scale", float(_current_settings.get("log_font_scale", 1.0)))
	config.set_value("display", "show_tile_ids", bool(_current_settings.get("show_tile_ids", false)))
	config.set_value("display", "show_cell_hover_tooltip", bool(_current_settings.get("show_cell_hover_tooltip", false)))

	config.set_value("game", "auto_save", _current_settings.auto_save)
	config.set_value("game", "confirm_actions", _current_settings.confirm_actions)
	config.set_value("game", "show_hints", _current_settings.show_hints)
	config.set_value("game", "replay_load_playable", _current_settings.replay_load_playable)
	config.set_value("game", "tutorial_enabled", bool(_current_settings.get("tutorial_enabled", true)))
	if config.has_section_key("game", "tutorial_auto_popup"):
		config.erase_section_key("game", "tutorial_auto_popup")
	config.set_value("game", "animation_speed", _current_settings.animation_speed)

	config.save("user://settings.cfg")
	_save_audio_settings()

# ── UI ↔ 设置 ────────────────────────────────────────

func _set_slider_percent(slider: HSlider, value_0_1: float) -> void:
	if slider == null:
		return
	slider.value = clampf(float(value_0_1), 0.0, 1.0) * 100.0

func _read_slider_percent(slider: HSlider, fallback_0_1: float) -> float:
	if slider == null:
		return float(fallback_0_1)
	return clampf(float(slider.value) / 100.0, 0.0, 1.0)

func _set_checkbox(check: CheckBox, value: bool) -> void:
	if check == null:
		return
	check.button_pressed = bool(value)

func _read_checkbox(check: CheckBox, fallback: bool) -> bool:
	if check == null:
		return bool(fallback)
	return bool(check.button_pressed)

func _update_ui_from_settings() -> void:
	var prev_sync := _syncing_ui
	_syncing_ui = true

	# 音频
	_set_slider_percent(master_volume, float(_current_settings.get("master_volume", _default_settings.master_volume)))
	_set_slider_percent(music_volume, float(_current_settings.get("music_volume", _default_settings.music_volume)))
	_set_slider_percent(sfx_volume, float(_current_settings.get("sfx_volume", _default_settings.sfx_volume)))
	_set_checkbox(mute_check, bool(_current_settings.get("mute", _default_settings.mute)))

	# 显示
	_set_checkbox(fullscreen_check, bool(_current_settings.get("fullscreen", _default_settings.fullscreen)))
	_set_checkbox(vsync_check, bool(_current_settings.get("vsync", _default_settings.vsync)))
	if resolution_option != null:
		var res: Vector2i = _current_settings.get("resolution", _default_settings.resolution)
		_rebuild_resolution_options(res)
	if ui_scale_slider != null:
		ui_scale_slider.value = float(_current_settings.get("ui_scale", _default_settings.ui_scale)) * 100
	if font_scale_slider != null:
		font_scale_slider.value = float(_current_settings.get("font_scale", 1.0)) * 100
	if log_font_scale_slider != null:
		log_font_scale_slider.value = float(_current_settings.get("log_font_scale", 1.0)) * 100
	_set_checkbox(show_tile_ids_check, bool(_current_settings.get("show_tile_ids", false)))
	_set_checkbox(show_cell_hover_tooltip_check, bool(_current_settings.get("show_cell_hover_tooltip", false)))

	# 游戏
	_set_checkbox(auto_save_check, bool(_current_settings.get("auto_save", _default_settings.auto_save)))
	_set_checkbox(confirm_actions_check, bool(_current_settings.get("confirm_actions", _default_settings.confirm_actions)))
	_set_checkbox(show_hints_check, bool(_current_settings.get("show_hints", _default_settings.show_hints)))
	_set_checkbox(replay_load_playable_check, bool(_current_settings.get("replay_load_playable", _default_settings.replay_load_playable)))
	_set_checkbox(tutorial_enabled_check, bool(_current_settings.get("tutorial_enabled", _default_settings.tutorial_enabled)))
	if animation_speed_slider != null:
		animation_speed_slider.value = float(_current_settings.get("animation_speed", _default_settings.animation_speed)) * 100

	# 同步数值标签
	_sync_all_value_labels()
	_update_resolution_ui_state()

	_syncing_ui = prev_sync

func _update_resolution_ui_state() -> void:
	if resolution_option == null:
		return
	var is_fullscreen := _read_checkbox(fullscreen_check, false)
	resolution_option.disabled = is_fullscreen
	resolution_option.tooltip_text = "全屏模式下分辨率由系统决定" if is_fullscreen else ""

func _sync_all_value_labels() -> void:
	_sync_value_label(master_volume, master_value_label)
	_sync_value_label(music_volume, music_value_label)
	_sync_value_label(sfx_volume, sfx_value_label)
	_sync_value_label(ui_scale_slider, ui_scale_value_label)
	_sync_value_label(font_scale_slider, font_scale_value_label)
	_sync_value_label(log_font_scale_slider, log_font_scale_value_label)
	_sync_value_label(animation_speed_slider, anim_speed_value_label)

func _sync_value_label(slider: HSlider, label: Label) -> void:
	if slider != null and label != null:
		label.text = "%d%%" % int(slider.value)

func _update_settings_from_ui() -> void:
	# 音频
	_current_settings["master_volume"] = _read_slider_percent(master_volume, float(_current_settings.get("master_volume", _default_settings.master_volume)))
	_current_settings["music_volume"] = _read_slider_percent(music_volume, float(_current_settings.get("music_volume", _default_settings.music_volume)))
	_current_settings["sfx_volume"] = _read_slider_percent(sfx_volume, float(_current_settings.get("sfx_volume", _default_settings.sfx_volume)))
	_current_settings["mute"] = _read_checkbox(mute_check, bool(_current_settings.get("mute", _default_settings.mute)))

	# 显示
	_current_settings["fullscreen"] = _read_checkbox(fullscreen_check, bool(_current_settings.get("fullscreen", _default_settings.fullscreen)))
	_current_settings["vsync"] = _read_checkbox(vsync_check, bool(_current_settings.get("vsync", _default_settings.vsync)))
	if resolution_option != null:
		var idx := resolution_option.selected
		if idx >= 0 and idx < RESOLUTIONS.size():
			_current_settings["resolution"] = RESOLUTIONS[idx]
	if ui_scale_slider != null:
		_current_settings["ui_scale"] = float(ui_scale_slider.value) / 100.0
	if font_scale_slider != null:
		_current_settings["font_scale"] = float(font_scale_slider.value) / 100.0
	if log_font_scale_slider != null:
		_current_settings["log_font_scale"] = float(log_font_scale_slider.value) / 100.0
	_current_settings["show_tile_ids"] = _read_checkbox(show_tile_ids_check, bool(_current_settings.get("show_tile_ids", false)))
	_current_settings["show_cell_hover_tooltip"] = _read_checkbox(show_cell_hover_tooltip_check, bool(_current_settings.get("show_cell_hover_tooltip", false)))

	# 游戏
	_current_settings["auto_save"] = _read_checkbox(auto_save_check, bool(_current_settings.get("auto_save", _default_settings.auto_save)))
	_current_settings["confirm_actions"] = _read_checkbox(confirm_actions_check, bool(_current_settings.get("confirm_actions", _default_settings.confirm_actions)))
	_current_settings["show_hints"] = _read_checkbox(show_hints_check, bool(_current_settings.get("show_hints", _default_settings.show_hints)))
	_current_settings["replay_load_playable"] = _read_checkbox(replay_load_playable_check, bool(_current_settings.get("replay_load_playable", _default_settings.replay_load_playable)))
	_current_settings["tutorial_enabled"] = _read_checkbox(tutorial_enabled_check, bool(_current_settings.get("tutorial_enabled", _default_settings.tutorial_enabled)))
	if animation_speed_slider != null:
		_current_settings["animation_speed"] = float(animation_speed_slider.value) / 100.0

func _connect_setting_change_signals() -> void:
	_connect_slider_change(master_volume)
	_connect_slider_change(music_volume)
	_connect_slider_change(sfx_volume)
	_connect_checkbox_change(mute_check)

	_connect_checkbox_change(fullscreen_check)
	_connect_checkbox_change(vsync_check)
	if resolution_option != null:
		resolution_option.item_selected.connect(func(_idx: int) -> void: _on_setting_changed())
	_connect_slider_change(ui_scale_slider)
	_connect_slider_change(font_scale_slider)
	_connect_slider_change(log_font_scale_slider)

	_connect_checkbox_change(auto_save_check)
	_connect_checkbox_change(confirm_actions_check)
	_connect_checkbox_change(show_hints_check)
	_connect_checkbox_change(replay_load_playable_check)
	_connect_checkbox_change(tutorial_enabled_check)
	_connect_slider_change(animation_speed_slider)

	_connect_checkbox_change(show_tile_ids_check)
	_connect_checkbox_change(show_cell_hover_tooltip_check)
	if reset_tutorial_progress_button != null:
		reset_tutorial_progress_button.pressed.connect(_on_reset_tutorial_progress_pressed)

func _connect_slider_change(slider: HSlider) -> void:
	if slider == null:
		return
	slider.value_changed.connect(func(_val: float) -> void: _on_setting_changed())

func _connect_checkbox_change(check: CheckBox) -> void:
	if check == null:
		return
	check.toggled.connect(func(_pressed: bool) -> void: _on_setting_changed())

func _on_setting_changed() -> void:
	if _syncing_ui:
		return

	var prev := _current_settings.duplicate(true)
	_update_settings_from_ui()
	_update_resolution_ui_state()
	_save_settings()
	_apply_runtime_changes(prev)

func _on_reset_pressed() -> void:
	var prev := _current_settings.duplicate(true)
	_current_settings = _default_settings.duplicate(true)
	_update_ui_from_settings()
	_save_settings()
	_apply_runtime_changes(prev)

func _on_close_pressed() -> void:
	close()
	closed.emit()

func _on_reset_tutorial_progress_pressed() -> void:
	_reset_tutorial_progress()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()

func get_setting(key: String, default_value = null):
	return _current_settings.get(key, default_value)

func _apply_ui_scale() -> void:
	if not _current_settings.has("ui_scale"):
		return
	var scale := clampf(float(_current_settings.ui_scale), 0.5, 2.0)
	if get_tree() == null or get_tree().root == null:
		return
	if get_tree().root is Window:
		var w: Window = get_tree().root
		w.content_scale_factor = scale

# ── 运行时应用 ──────────────────────────────────────────

func _apply_runtime_changes(prev_settings: Dictionary) -> void:
	_apply_display_settings_if_needed(prev_settings)

	if prev_settings.get("ui_scale", null) != _current_settings.get("ui_scale", null):
		_apply_ui_scale()

	if (
		prev_settings.get("master_volume", null) != _current_settings.get("master_volume", null)
		or prev_settings.get("music_volume", null) != _current_settings.get("music_volume", null)
		or prev_settings.get("sfx_volume", null) != _current_settings.get("sfx_volume", null)
		or prev_settings.get("mute", null) != _current_settings.get("mute", null)
	):
		_apply_audio_settings_runtime()

	_sync_globals_runtime_settings()
	settings_changed.emit(_current_settings)

func _apply_display_settings_if_needed(prev_settings: Dictionary) -> void:
	if _is_headless_runtime():
		return

	var fullscreen_changed := bool(prev_settings.get("fullscreen", false)) != bool(_current_settings.get("fullscreen", false))
	var vsync_changed := bool(prev_settings.get("vsync", true)) != bool(_current_settings.get("vsync", true))
	var res_changed: bool = prev_settings.get("resolution", null) != _current_settings.get("resolution", null)

	if not (fullscreen_changed or vsync_changed or res_changed):
		return

	if bool(_current_settings.fullscreen):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res: Vector2i = _current_settings.resolution
		if res.x > 0 and res.y > 0:
			DisplayServer.window_set_size(res)

	if bool(_current_settings.vsync):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

# ── 音频 ──────────────────────────────────────────────

func _linear_to_db_safe(linear: float) -> float:
	var v := clampf(linear, 0.0, 1.0)
	if v <= 0.0001:
		return -80.0
	return linear_to_db(v)

func _load_audio_settings() -> void:
	if not _current_settings.has("master_volume"):
		_current_settings.master_volume = _default_settings.master_volume
	if not _current_settings.has("music_volume"):
		_current_settings.music_volume = _default_settings.music_volume
	if not _current_settings.has("sfx_volume"):
		_current_settings.sfx_volume = _default_settings.sfx_volume
	if not _current_settings.has("mute"):
		_current_settings.mute = _default_settings.mute

	var legacy := ConfigFile.new()
	if legacy.load("user://settings.cfg") == OK:
		_current_settings.master_volume = legacy.get_value("audio", "master_volume", _current_settings.master_volume)
		_current_settings.music_volume = legacy.get_value("audio", "music_volume", _current_settings.music_volume)
		_current_settings.sfx_volume = legacy.get_value("audio", "sfx_volume", _current_settings.sfx_volume)
		_current_settings.mute = legacy.get_value("audio", "mute", _current_settings.mute)

	var sound_cfg := ConfigFile.new()
	if sound_cfg.load("user://sound_settings.cfg") != OK:
		return

	if sound_cfg.has_section_key("mix", "master_volume"):
		_current_settings.master_volume = sound_cfg.get_value("mix", "master_volume", _current_settings.master_volume)
		_current_settings.music_volume = sound_cfg.get_value("mix", "music_volume", _current_settings.music_volume)
		_current_settings.sfx_volume = sound_cfg.get_value("mix", "sfx_volume", _current_settings.sfx_volume)
		_current_settings.mute = sound_cfg.get_value("mix", "mute", _current_settings.mute)
		return

	var sfx_db_val = sound_cfg.get_value("audio", "master_volume", null)
	if sfx_db_val is int or sfx_db_val is float:
		_current_settings.sfx_volume = clampf(db_to_linear(float(sfx_db_val)), 0.0, 1.0)

	var music_db_val = sound_cfg.get_value("music", "volume", null)
	if music_db_val is int or music_db_val is float:
		_current_settings.music_volume = clampf(db_to_linear(float(music_db_val)), 0.0, 1.0)

	var mute_audio := bool(sound_cfg.get_value("audio", "muted", false))
	var mute_music := bool(sound_cfg.get_value("music", "muted", false))
	_current_settings.mute = mute_audio or mute_music

func _save_audio_settings() -> void:
	var master := clampf(float(_current_settings.master_volume), 0.0, 1.0)
	var music := clampf(float(_current_settings.music_volume), 0.0, 1.0)
	var sfx := clampf(float(_current_settings.sfx_volume), 0.0, 1.0)
	var muted := bool(_current_settings.mute)

	var effective_music := master * music
	var effective_sfx := master * sfx
	var music_db := _linear_to_db_safe(effective_music)
	var sfx_db := _linear_to_db_safe(effective_sfx)

	var cfg := ConfigFile.new()
	cfg.load("user://sound_settings.cfg")

	cfg.set_value("mix", "master_volume", master)
	cfg.set_value("mix", "music_volume", music)
	cfg.set_value("mix", "sfx_volume", sfx)
	cfg.set_value("mix", "mute", muted)

	cfg.set_value("audio", "master_volume", sfx_db)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("music", "volume", music_db)
	cfg.set_value("music", "muted", muted)

	cfg.save("user://sound_settings.cfg")

func _apply_audio_settings_runtime() -> void:
	var master := clampf(float(_current_settings.master_volume), 0.0, 1.0)
	var music := clampf(float(_current_settings.music_volume), 0.0, 1.0)
	var sfx := clampf(float(_current_settings.sfx_volume), 0.0, 1.0)
	var muted := bool(_current_settings.mute)

	var music_db := _linear_to_db_safe(master * music)
	var sfx_db := _linear_to_db_safe(master * sfx)

	var sm := SoundManager.get_instance()
	if sm != null and is_instance_valid(sm):
		sm.set_master_volume(sfx_db)

	var mm := MusicManager.get_instance()
	if mm != null and is_instance_valid(mm):
		mm.set_volume(music_db)
	if Globals != null and Globals.has_method("set_audio_muted"):
		Globals.set_audio_muted(muted)
	else:
		if sm != null and is_instance_valid(sm):
			sm.set_muted(muted)
		if mm != null and is_instance_valid(mm):
			mm.set_muted(muted)

func _sync_globals_runtime_settings() -> void:
	if Globals == null:
		return

	Globals.ui_scale = float(_current_settings.ui_scale)
	Globals.display_fullscreen = bool(_current_settings.get("fullscreen", Globals.display_fullscreen))
	Globals.display_vsync = bool(_current_settings.get("vsync", Globals.display_vsync))
	if _current_settings.has("resolution"):
		Globals.display_resolution = _current_settings.resolution
	Globals.show_tile_ids = bool(_current_settings.get("show_tile_ids", false))
	Globals.show_cell_hover_tooltip = bool(_current_settings.get("show_cell_hover_tooltip", false))
	Globals.font_scale = clampf(float(_current_settings.get("font_scale", Globals.font_scale)), 0.5, 2.0)
	Globals.log_font_scale = clampf(float(_current_settings.get("log_font_scale", Globals.log_font_scale)), 0.5, 3.0)
	Globals.confirm_actions = bool(_current_settings.confirm_actions)
	Globals.show_hints = bool(_current_settings.show_hints)
	Globals.replay_load_playable = bool(_current_settings.get("replay_load_playable", Globals.replay_load_playable))
	if Globals.has_method("apply_tutorial_preferences_from_settings"):
		Globals.apply_tutorial_preferences_from_settings(_current_settings)
	else:
		Globals.tutorial_enabled = bool(_current_settings.get("tutorial_enabled", Globals.tutorial_enabled))
	Globals.animation_speed = float(_current_settings.animation_speed)
	if Globals.has_method("apply_font_scale"):
		Globals.apply_font_scale()

func _reset_tutorial_progress() -> void:
	if Globals == null or not Globals.has_method("reset_tutorial_progress"):
		return
	Globals.reset_tutorial_progress(true)
