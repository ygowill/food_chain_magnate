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
	_load_settings()

func _setup_resolution_options() -> void:
	if resolution_option == null:
		return

	resolution_option.clear()
	for res in RESOLUTIONS:
		resolution_option.add_item("%dx%d" % [res.x, res.y])

func _load_settings() -> void:
	# 尝试从配置文件加载
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")

	if err == OK:
		_current_settings = {
			"master_volume": config.get_value("audio", "master_volume", _default_settings.master_volume),
			"music_volume": config.get_value("audio", "music_volume", _default_settings.music_volume),
			"sfx_volume": config.get_value("audio", "sfx_volume", _default_settings.sfx_volume),
			"mute": config.get_value("audio", "mute", _default_settings.mute),
			"fullscreen": config.get_value("display", "fullscreen", _default_settings.fullscreen),
			"vsync": config.get_value("display", "vsync", _default_settings.vsync),
			"resolution": config.get_value("display", "resolution", _default_settings.resolution),
			"ui_scale": config.get_value("display", "ui_scale", _default_settings.ui_scale),
			"auto_save": config.get_value("game", "auto_save", _default_settings.auto_save),
			"confirm_actions": config.get_value("game", "confirm_actions", _default_settings.confirm_actions),
			"show_hints": config.get_value("game", "show_hints", _default_settings.show_hints),
			"animation_speed": config.get_value("game", "animation_speed", _default_settings.animation_speed),
		}
	else:
		_current_settings = _default_settings.duplicate()

	_update_ui_from_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg") # 保留其它系统写入的设置（例如玩家名称/模块选择）

	config.set_value("audio", "master_volume", _current_settings.master_volume)
	config.set_value("audio", "music_volume", _current_settings.music_volume)
	config.set_value("audio", "sfx_volume", _current_settings.sfx_volume)
	config.set_value("audio", "mute", _current_settings.mute)

	config.set_value("display", "fullscreen", _current_settings.fullscreen)
	config.set_value("display", "vsync", _current_settings.vsync)
	config.set_value("display", "resolution", _current_settings.resolution)
	config.set_value("display", "ui_scale", _current_settings.ui_scale)

	config.set_value("game", "auto_save", _current_settings.auto_save)
	config.set_value("game", "confirm_actions", _current_settings.confirm_actions)
	config.set_value("game", "show_hints", _current_settings.show_hints)
	config.set_value("game", "animation_speed", _current_settings.animation_speed)

	config.save("user://settings.cfg")

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
