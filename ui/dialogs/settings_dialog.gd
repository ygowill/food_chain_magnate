# 设置对话框组件
# 游戏设置、音量、显示选项等
class_name SettingsDialog
extends Window

signal settings_changed(settings: Dictionary)
signal closed()

@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var close_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CloseButton
@onready var apply_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ApplyButton
@onready var reset_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ResetButton

# 音频选项
@onready var master_volume: HSlider = $MarginContainer/VBoxContainer/TabContainer/Audio/VBoxContainer/MasterRow/MasterSlider
@onready var music_volume: HSlider = $MarginContainer/VBoxContainer/TabContainer/Audio/VBoxContainer/MusicRow/MusicSlider
@onready var sfx_volume: HSlider = $MarginContainer/VBoxContainer/TabContainer/Audio/VBoxContainer/SFXRow/SFXSlider
@onready var mute_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Audio/VBoxContainer/MuteCheck

# 显示选项
@onready var fullscreen_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Display/VBoxContainer/FullscreenCheck
@onready var vsync_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Display/VBoxContainer/VsyncCheck
@onready var resolution_option: OptionButton = $MarginContainer/VBoxContainer/TabContainer/Display/VBoxContainer/ResolutionRow/ResolutionOption
@onready var ui_scale_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Display/VBoxContainer/UIScaleRow/UIScaleSlider
@onready var ui_layout_option: OptionButton = $MarginContainer/VBoxContainer/TabContainer/Display/VBoxContainer/UILayoutRow/UILayoutOption
@onready var show_tile_ids_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Display/VBoxContainer/ShowTileIdsCheck

# 游戏选项
@onready var auto_save_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Game/VBoxContainer/AutoSaveCheck
@onready var confirm_actions_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Game/VBoxContainer/ConfirmActionsCheck
@onready var show_hints_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Game/VBoxContainer/ShowHintsCheck
@onready var animation_speed_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Game/VBoxContainer/AnimSpeedRow/AnimSpeedSlider

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

const UI_LAYOUT_OPTIONS: Array[String] = [
	"经典布局（v1）",
	"新布局（v2，试验）",
]

var _current_settings: Dictionary = {}
var _default_settings: Dictionary = {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"mute": false,
	"fullscreen": false,
	"vsync": true,
	"resolution": Vector2i(1920, 1080),
	"ui_scale": 1.0,
	"ui_layout_version": 2,
	"show_tile_ids": false,
	"auto_save": true,
	"confirm_actions": true,
	"show_hints": true,
	"animation_speed": 1.0,
}

func _ready() -> void:
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	if apply_btn != null:
		apply_btn.pressed.connect(_on_apply_pressed)
	if reset_btn != null:
		reset_btn.pressed.connect(_on_reset_pressed)

	close_requested.connect(_on_close_pressed)

	_setup_resolution_options()
	_setup_ui_layout_options()
	_load_settings()

func _setup_resolution_options() -> void:
	if resolution_option == null:
		return

	resolution_option.clear()
	for res in RESOLUTIONS:
		resolution_option.add_item("%dx%d" % [res.x, res.y])

func _setup_ui_layout_options() -> void:
	if ui_layout_option == null:
		return
	ui_layout_option.clear()
	for title in UI_LAYOUT_OPTIONS:
		ui_layout_option.add_item(title)

func _load_settings() -> void:
	# 尝试从配置文件加载
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")

	if err == OK:
		_current_settings = {
			"fullscreen": config.get_value("display", "fullscreen", _default_settings.fullscreen),
			"vsync": config.get_value("display", "vsync", _default_settings.vsync),
			"resolution": config.get_value("display", "resolution", _default_settings.resolution),
			"ui_scale": config.get_value("display", "ui_scale", _default_settings.ui_scale),
			"ui_layout_version": clampi(int(config.get_value("display", "ui_layout_version", _default_settings.ui_layout_version)), 1, 2),
			"show_tile_ids": bool(config.get_value("display", "show_tile_ids", _default_settings.show_tile_ids)),
			"auto_save": config.get_value("game", "auto_save", _default_settings.auto_save),
			"confirm_actions": config.get_value("game", "confirm_actions", _default_settings.confirm_actions),
			"show_hints": config.get_value("game", "show_hints", _default_settings.show_hints),
			"animation_speed": config.get_value("game", "animation_speed", _default_settings.animation_speed),
		}
	else:
		_current_settings = _default_settings.duplicate()

	# 音频设置：统一从 sound_settings.cfg 读取（若不存在则回退到 settings.cfg 或默认）
	_load_audio_settings()

	_update_ui_from_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg") # 保留其它系统写入的设置（例如玩家名称/模块选择）

	config.set_value("display", "fullscreen", _current_settings.fullscreen)
	config.set_value("display", "vsync", _current_settings.vsync)
	config.set_value("display", "resolution", _current_settings.resolution)
	config.set_value("display", "ui_scale", _current_settings.ui_scale)
	config.set_value("display", "ui_layout_version", int(_current_settings.get("ui_layout_version", 1)))
	config.set_value("display", "show_tile_ids", bool(_current_settings.get("show_tile_ids", false)))

	config.set_value("game", "auto_save", _current_settings.auto_save)
	config.set_value("game", "confirm_actions", _current_settings.confirm_actions)
	config.set_value("game", "show_hints", _current_settings.show_hints)
	config.set_value("game", "animation_speed", _current_settings.animation_speed)

	config.save("user://settings.cfg")
	_save_audio_settings()

func _update_ui_from_settings() -> void:
	# 音频
	if master_volume != null:
		master_volume.value = float(_current_settings.master_volume) * 100
	if music_volume != null:
		music_volume.value = float(_current_settings.music_volume) * 100
	if sfx_volume != null:
		sfx_volume.value = float(_current_settings.sfx_volume) * 100
	if mute_check != null:
		mute_check.button_pressed = bool(_current_settings.mute)

	# 显示
	if fullscreen_check != null:
		fullscreen_check.button_pressed = bool(_current_settings.fullscreen)
	if vsync_check != null:
		vsync_check.button_pressed = bool(_current_settings.vsync)
	if resolution_option != null:
		var res: Vector2i = _current_settings.resolution
		for i in range(RESOLUTIONS.size()):
			if RESOLUTIONS[i] == res:
				resolution_option.select(i)
				break
	if ui_scale_slider != null:
		ui_scale_slider.value = float(_current_settings.ui_scale) * 100
	if ui_layout_option != null:
		var v := clampi(int(_current_settings.get("ui_layout_version", 1)), 1, 2)
		ui_layout_option.select(v - 1)
	if show_tile_ids_check != null:
		show_tile_ids_check.button_pressed = bool(_current_settings.get("show_tile_ids", false))

	# 游戏
	if auto_save_check != null:
		auto_save_check.button_pressed = bool(_current_settings.auto_save)
	if confirm_actions_check != null:
		confirm_actions_check.button_pressed = bool(_current_settings.confirm_actions)
	if show_hints_check != null:
		show_hints_check.button_pressed = bool(_current_settings.show_hints)
	if animation_speed_slider != null:
		animation_speed_slider.value = float(_current_settings.animation_speed) * 100

func _update_settings_from_ui() -> void:
	# 音频
	if master_volume != null:
		_current_settings.master_volume = master_volume.value / 100.0
	if music_volume != null:
		_current_settings.music_volume = music_volume.value / 100.0
	if sfx_volume != null:
		_current_settings.sfx_volume = sfx_volume.value / 100.0
	if mute_check != null:
		_current_settings.mute = mute_check.button_pressed

	# 显示
	if fullscreen_check != null:
		_current_settings.fullscreen = fullscreen_check.button_pressed
	if vsync_check != null:
		_current_settings.vsync = vsync_check.button_pressed
	if resolution_option != null:
		var idx := resolution_option.selected
		if idx >= 0 and idx < RESOLUTIONS.size():
			_current_settings.resolution = RESOLUTIONS[idx]
	if ui_scale_slider != null:
		_current_settings.ui_scale = ui_scale_slider.value / 100.0
	if ui_layout_option != null:
		_current_settings.ui_layout_version = clampi(int(ui_layout_option.selected) + 1, 1, 2)
	if show_tile_ids_check != null:
		_current_settings.show_tile_ids = show_tile_ids_check.button_pressed

	# 游戏
	if auto_save_check != null:
		_current_settings.auto_save = auto_save_check.button_pressed
	if confirm_actions_check != null:
		_current_settings.confirm_actions = confirm_actions_check.button_pressed
	if show_hints_check != null:
		_current_settings.show_hints = show_hints_check.button_pressed
	if animation_speed_slider != null:
		_current_settings.animation_speed = animation_speed_slider.value / 100.0

func _apply_settings() -> void:
	# 应用全屏
	if bool(_current_settings.fullscreen):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# 应用垂直同步
	if bool(_current_settings.vsync):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# 应用分辨率（仅窗口模式）
	if not bool(_current_settings.fullscreen):
		var res: Vector2i = _current_settings.resolution
		DisplayServer.window_set_size(res)

	_apply_ui_scale()
	_apply_audio_settings_runtime()
	_sync_globals_runtime_settings()

	settings_changed.emit(_current_settings)

func _on_apply_pressed() -> void:
	_update_settings_from_ui()
	_save_settings()
	_apply_settings()

func _on_reset_pressed() -> void:
	_current_settings = _default_settings.duplicate()
	_update_ui_from_settings()

func _on_close_pressed() -> void:
	hide()
	closed.emit()

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

func _linear_to_db_safe(linear: float) -> float:
	var v := clampf(linear, 0.0, 1.0)
	if v <= 0.0001:
		return -80.0
	return linear_to_db(v)

func _load_audio_settings() -> void:
	# 1) legacy: settings.cfg 的 audio（旧版本留下的字段）
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

	# 2) sound_settings.cfg：优先读取 mix（避免与 SoundManager/MusicManager 的 dB 存储冲突）
	var sound_cfg := ConfigFile.new()
	if sound_cfg.load("user://sound_settings.cfg") != OK:
		return

	if sound_cfg.has_section_key("mix", "master_volume"):
		_current_settings.master_volume = sound_cfg.get_value("mix", "master_volume", _current_settings.master_volume)
		_current_settings.music_volume = sound_cfg.get_value("mix", "music_volume", _current_settings.music_volume)
		_current_settings.sfx_volume = sound_cfg.get_value("mix", "sfx_volume", _current_settings.sfx_volume)
		_current_settings.mute = sound_cfg.get_value("mix", "mute", _current_settings.mute)
		return

	# 兜底：从 dB 反推到线性（无法还原 master/music/sfx 的分解，仅用于迁移）
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

	# 兼容：给现有音频系统写入 dB 字段
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

	# 优先使用音频管理器（若未初始化则静默跳过）
	var sm := SoundManager.get_instance()
	if sm != null and is_instance_valid(sm):
		sm.set_master_volume(sfx_db)
		sm.set_muted(muted)

	var mm := MusicManager.get_instance()
	if mm != null and is_instance_valid(mm):
		mm.set_volume(music_db)
		mm.set_muted(muted)

func _sync_globals_runtime_settings() -> void:
	# SettingsDialog 的设置项在运行时主要由 Globals 承载，供 Game/控制器读取。
	if Globals == null:
		return

	Globals.ui_scale = float(_current_settings.ui_scale)
	Globals.ui_layout_version = clampi(int(_current_settings.get("ui_layout_version", 1)), 1, 2)
	Globals.show_tile_ids = bool(_current_settings.get("show_tile_ids", false))
	Globals.confirm_actions = bool(_current_settings.confirm_actions)
	Globals.show_hints = bool(_current_settings.show_hints)
	Globals.animation_speed = float(_current_settings.animation_speed)
