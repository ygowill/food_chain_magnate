# 主菜单场景脚本
extends Control

const SettingsDialogScene = preload("res://ui/dialogs/settings_dialog.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")
const RulesDocsClass = preload("res://ui/utils/rules_docs.gd")
const TITLE_LOGO_PATHS: PackedStringArray = [
	"res://assets/main_title_logo_1080.png",
	"res://assets/main_title_logo.png",
]
const MUTE_ICON_ON_PATH := "res://assets/images/musicOn.png"
const MUTE_ICON_OFF_PATH := "res://assets/images/musicOff.png"

var _mute_icon_on: Texture2D = null
var _mute_icon_off: Texture2D = null
var _mute_icon_load_warned: bool = false

@onready var version_label: Label = $VersionLabel
@onready var wall_background: ColorRect = $WallBackground
@onready var vignette_overlay: ColorRect = $VignetteOverlay
@onready var card: PanelContainer = $CenterContainer/Card
@onready var inner_border: PanelContainer = $CenterContainer/Card/OuterMargin/InnerBorder
@onready var paper_texture: ColorRect = $CenterContainer/Card/OuterMargin/InnerBorder/PaperTexture
@onready var title_logo: TextureRect = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/TitleLogo
@onready var decorative_line: ColorRect = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/DecorativeLine
@onready var new_game_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/NewGameButton
@onready var rules_tutorial_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/RulesTutorialButton
@onready var tutorial_campaign_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/TutorialCampaignButton
@onready var online_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/OnlineButton
@onready var rules_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/RulesButton
@onready var load_game_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/LoadGameButton
@onready var settings_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/SystemButtons/SettingsButton
@onready var quit_button: Button = $CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/SystemButtons/QuitButton
@onready var mute_icon: TextureRect = $MuteIcon

var _message_dialog: Control = null
var _settings_dialog: Control = null
var _save_load_dialog = null

func _ready() -> void:
	GameLog.info("MainMenu", "主菜单已加载")
	version_label.text = "v%s" % Globals.get_version()
	_apply_title_logo_texture()

	# 墙壁背景纹理（带 fallback 纯色）
	UiStylesClass.apply_tiled_texture(
		wall_background,
		UiStylesClass.WALL_TEXTURE_PATHS,
		3.0,
		Color(0.93, 0.88, 0.75, 1.0)
	)

	# 暗角效果
	UiStylesClass.apply_vignette(vignette_overlay, 0.45, 0.5)

	# 外层卡片（粗边框）
	UiStylesClass.apply_dialog_surface(card)

	# 内层红色细边框（双线效果）
	UiStylesClass.apply_poster_inner_border(inner_border)

	# 纸张纹理叠加层（带 fallback）
	UiStylesClass.apply_tiled_texture(
		paper_texture,
		UiStylesClass.PAPER_TEXTURE_PATHS,
		4.0,
		Color(0.97, 0.94, 0.86, 0.3)
	)

	# 按钮样式
	UiStylesClass.apply_button_secondary(new_game_button)
	UiStylesClass.apply_button_secondary(rules_tutorial_button)
	UiStylesClass.apply_button_secondary(tutorial_campaign_button)
	UiStylesClass.apply_button_primary(online_button)
	UiStylesClass.apply_button_secondary(rules_button)
	UiStylesClass.apply_button_secondary(load_game_button)
	UiStylesClass.apply_button_secondary(settings_button)
	UiStylesClass.apply_button_secondary(quit_button)
	if mute_icon != null:
		mute_icon.gui_input.connect(_on_mute_icon_gui_input)
		mute_icon.mouse_filter = Control.MOUSE_FILTER_STOP
		mute_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ensure_mute_icon_textures_loaded()
	_update_mute_icon_ui()
	if Globals != null and not Globals.audio_muted_changed.is_connected(_on_audio_muted_changed):
		Globals.audio_muted_changed.connect(_on_audio_muted_changed)
	online_button.grab_focus()
	_kick_bgm_autoplay()
	call_deferred("_attempt_auto_resume_on_startup")

func _kick_bgm_autoplay() -> void:
	if _is_headless_runtime():
		return
	call_deferred("_deferred_kick_bgm_autoplay")

func _deferred_kick_bgm_autoplay() -> void:
	if _is_headless_runtime():
		return
	# 避免启动时序导致的第一次播放无声：等待至少两帧再触发一次。
	await get_tree().process_frame
	await get_tree().process_frame
	var mm := MusicManager.get_instance()
	if mm == null or not is_instance_valid(mm):
		return
	mm.play(MusicManager.MusicTrack.MENU, false)

func _is_headless_runtime() -> bool:
	# Web 平台在 Godot 4.3+ 默认使用 sample playback（绕过 AudioServer 混音），
	# AudioServer driver 可能为 Dummy，但这不等同于 headless。
	return DisplayServer.get_name() == "headless"

func _apply_title_logo_texture() -> void:
	if title_logo == null:
		return
	for path in TITLE_LOGO_PATHS:
		var tex := _load_texture_if_exists(path)
		if tex == null:
			continue
		title_logo.texture = tex
		return
	GameLog.warn("MainMenu", "标题图片加载失败: %s" % str(TITLE_LOGO_PATHS))

func _on_new_game_pressed() -> void:
	GameLog.info("MainMenu", "点击本地游戏")
	if Globals != null and Globals.has_method("clear_tutorial_runtime_flags"):
		Globals.clear_tutorial_runtime_flags()
	SceneManager.goto_game_setup()

func _on_rules_tutorial_pressed() -> void:
	GameLog.info("MainMenu", "点击规则教学")
	if Globals != null and Globals.has_method("request_rules_tutorial"):
		Globals.request_rules_tutorial()
	SceneManager.goto_game_setup()

func _on_tutorial_campaign_pressed() -> void:
	GameLog.info("MainMenu", "点击教学战役")
	if Globals != null and Globals.has_method("clear_tutorial_runtime_flags"):
		Globals.clear_tutorial_runtime_flags()
	SceneManager.goto_tutorial_campaign()

func _on_online_pressed() -> void:
	GameLog.info("MainMenu", "点击联机游戏")
	if Globals != null and Globals.has_method("clear_tutorial_runtime_flags"):
		Globals.clear_tutorial_runtime_flags()
	SceneManager.goto_online_lobby()

func _attempt_auto_resume_on_startup() -> void:
	if not _should_auto_resume_on_startup():
		return
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("检测到未完成联机对局，正在恢复...")
	if NetContext != null and NetContext.has_method("is_online_resume_in_game") and NetContext.is_online_resume_in_game():
		SceneManager.goto_game()
		return
	SceneManager.goto_online_lobby()

func _should_auto_resume_on_startup() -> bool:
	if Globals != null and str(Globals.pending_replay_file_path).strip_edges() != "":
		return false
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	if not NetContext.has_online_resume_context():
		return false
	if NetClient != null and NetClient.is_online_client_connected():
		return false
	return true

func _on_rules_pressed() -> void:
	GameLog.info("MainMenu", "点击规则")
	RulesDocsClass.show_rules_dialog(self)

func _on_load_game_pressed() -> void:
	GameLog.info("MainMenu", "点击载入回放")
	_ensure_save_load_dialog()
	_save_load_dialog.open_for_replay()

func _on_settings_pressed() -> void:
	GameLog.info("MainMenu", "点击设置")
	_ensure_settings_dialog()
	if _settings_dialog.has_method("show_dialog"):
		_settings_dialog.call("show_dialog")
	else:
		_settings_dialog.show()

func _on_quit_pressed() -> void:
	GameLog.info("MainMenu", "退出游戏")
	get_tree().quit()

func _on_mute_icon_gui_input(event: InputEvent) -> void:
	if event == null:
		return

	if not UiPointerInputClass.is_primary_press(event):
		return

	if Globals != null and Globals.has_method("toggle_audio_muted"):
		Globals.toggle_audio_muted()
	_update_mute_icon_ui()
	accept_event()

func _on_audio_muted_changed(_muted: bool) -> void:
	_update_mute_icon_ui()

func _ensure_mute_icon_textures_loaded() -> void:
	if _mute_icon_on != null and _mute_icon_off != null:
		return

	_mute_icon_on = _load_texture_if_exists(MUTE_ICON_ON_PATH)
	_mute_icon_off = _load_texture_if_exists(MUTE_ICON_OFF_PATH)
	if not _mute_icon_load_warned and (_mute_icon_on == null or _mute_icon_off == null):
		_mute_icon_load_warned = true
		GameLog.warn("MainMenu", "静音图标缺失：请确保存在 %s 与 %s" % [MUTE_ICON_ON_PATH, MUTE_ICON_OFF_PATH])

func _load_texture_if_exists(path: String) -> Texture2D:
	var p := str(path).strip_edges()
	if p.is_empty():
		return null
	if not ResourceLoader.exists(p):
		return null
	var res = load(p)
	if res is Texture2D:
		return res
	return null

func _update_mute_icon_ui() -> void:
	if mute_icon == null:
		return
	_ensure_mute_icon_textures_loaded()

	var muted := false
	if Globals != null and Globals.has_method("is_audio_muted"):
		muted = bool(Globals.is_audio_muted())

	var tex: Texture2D = _mute_icon_off if muted else _mute_icon_on
	if tex != null:
		mute_icon.texture = tex
	mute_icon.tooltip_text = "点击取消静音" if muted else "点击静音"

func _ensure_settings_dialog() -> void:
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		return

	_settings_dialog = SettingsDialogScene.instantiate()
	add_child(_settings_dialog)

func _ensure_save_load_dialog() -> void:
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		return

	_save_load_dialog = SaveLoadDialogScript.new()
	add_child(_save_load_dialog)

	if _save_load_dialog.has_signal("load_selected"):
		if not _save_load_dialog.load_selected.is_connected(_on_save_load_selected):
			_save_load_dialog.load_selected.connect(_on_save_load_selected)

func _on_save_load_selected(path: String) -> void:
	if path.is_empty():
		return

	if EventBus != null:
		EventBus.clear_history()

	# 回放文件读取可能耗时：先显示加载遮罩，避免"卡住"的观感
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在载入回放...")
		await get_tree().process_frame

	# 主菜单“载入”改为回放入口：将文件路径交给 Game 场景自动进入回放模式。
	if Globals != null and Globals.has_method("clear_tutorial_runtime_flags"):
		Globals.clear_tutorial_runtime_flags()
	Globals.pending_replay_file_path = path
	Globals.current_game_engine = null
	Globals.is_game_active = false
	GameLog.info("MainMenu", "回放文件已选择，进入游戏场景: %s" % path)
	SceneManager.goto_game()

func _show_message(title: String, message: String) -> void:
	if _message_dialog != null and is_instance_valid(_message_dialog):
		_message_dialog.hide()
		_message_dialog.queue_free()
		_message_dialog = null

	_message_dialog = ConfirmDialogScene.instantiate()
	add_child(_message_dialog)
	if _message_dialog.has_method("setup"):
		_message_dialog.call("setup", title, message, "确定", "关闭")
	if _message_dialog.has_method("show_dialog"):
		_message_dialog.call("show_dialog")
	else:
		_message_dialog.show()
