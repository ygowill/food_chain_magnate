# 主菜单场景脚本
extends Control

const SettingsDialogScene = preload("res://ui/dialogs/settings_dialog.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var version_label: Label = $VersionLabel
@onready var card: PanelContainer = $CenterContainer/Card
@onready var new_game_button: Button = $CenterContainer/Card/Margin/VBoxContainer/NewGameButton
@onready var online_button: Button = $CenterContainer/Card/Margin/VBoxContainer/OnlineButton
@onready var load_game_button: Button = $CenterContainer/Card/Margin/VBoxContainer/LoadGameButton
@onready var settings_button: Button = $CenterContainer/Card/Margin/VBoxContainer/SettingsButton
@onready var replay_player_button: Button = $CenterContainer/Card/Margin/VBoxContainer/ReplayPlayerButton
@onready var quit_button: Button = $CenterContainer/Card/Margin/VBoxContainer/QuitButton

var _settings_dialog: Window = null
var _message_dialog: Window = null
var _save_load_dialog = null
var _save_load_context: String = ""

func _ready() -> void:
	GameLog.info("MainMenu", "主菜单已加载")
	version_label.text = "v%s" % Globals.get_version()
	UiStylesClass.apply_dialog_surface(card)
	UiStylesClass.apply_button_primary(new_game_button)
	UiStylesClass.apply_button_secondary(online_button)
	UiStylesClass.apply_button_secondary(load_game_button)
	UiStylesClass.apply_button_secondary(settings_button)
	UiStylesClass.apply_button_secondary(replay_player_button)
	UiStylesClass.apply_button_secondary(quit_button)

func _on_new_game_pressed() -> void:
	GameLog.info("MainMenu", "点击新游戏")
	SceneManager.goto_game_setup()

func _on_online_pressed() -> void:
	GameLog.info("MainMenu", "点击联机")
	SceneManager.goto_online_lobby()

func _on_load_game_pressed() -> void:
	GameLog.info("MainMenu", "点击载入游戏")
	_ensure_save_load_dialog()
	_save_load_context = "load"
	_save_load_dialog.open_for_load()

func _on_settings_pressed() -> void:
	GameLog.info("MainMenu", "点击设置")
	_ensure_settings_dialog()
	if _settings_dialog.has_method("show_dialog"):
		_settings_dialog.call("show_dialog")
	else:
		_settings_dialog.show()

func _on_replay_player_pressed() -> void:
	GameLog.info("MainMenu", "打开回放播放器")
	_ensure_save_load_dialog()
	_save_load_context = "replay"
	_save_load_dialog.open_for_replay()

func _on_quit_pressed() -> void:
	GameLog.info("MainMenu", "退出游戏")
	get_tree().quit()

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
	if _save_load_context == "replay":
		if EventBus != null:
			EventBus.clear_history()
		if Globals != null:
			Globals.current_game_engine = null
			Globals.is_game_active = false
			Globals.pending_replay_file_path = path

		# 存档读取可能耗时：先显示加载遮罩，避免“卡住”的观感
		if SceneManager != null and SceneManager.has_method("show_loading"):
			SceneManager.show_loading("正在进入回放...")
			await get_tree().process_frame

		GameLog.info("MainMenu", "进入回放: %s" % path)
		SceneManager.goto_game()
		return

	if EventBus != null:
		EventBus.clear_history()

	# 存档读取可能耗时：先显示加载遮罩，避免“卡住”的观感
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在载入存档...")
		await get_tree().process_frame

	var engine := GameEngine.new()
	var load_result: Result = engine.load_from_file(path)
	if not load_result.ok:
		if SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		_show_message("载入失败", "存档读取失败：\n%s" % load_result.error)
		return

	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)

	GameLog.info("MainMenu", "载入成功，进入游戏场景: %s" % path)
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
