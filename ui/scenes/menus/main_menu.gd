# 主菜单场景脚本
extends Control

const SettingsDialogScene = preload("res://ui/dialogs/settings_dialog.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")

@onready var version_label: Label = $VersionLabel

var _settings_dialog: Window = null
var _message_dialog: Window = null

func _ready() -> void:
	GameLog.info("MainMenu", "主菜单已加载")
	version_label.text = "v%s" % Globals.get_version()

func _on_new_game_pressed() -> void:
	GameLog.info("MainMenu", "点击新游戏")
	SceneManager.goto_game_setup()

func _on_load_game_pressed() -> void:
	GameLog.info("MainMenu", "点击载入游戏")
	var path := Globals.get_default_save_path()
	if not FileAccess.file_exists(path):
		_show_message("载入失败", "未找到存档文件：\n%s" % path)
		return

	var engine := GameEngine.new()
	var load_result: Result = engine.load_from_file(path)
	if not load_result.ok:
		_show_message("载入失败", "存档读取失败：\n%s" % load_result.error)
		return

	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)

	GameLog.info("MainMenu", "载入成功，进入游戏场景: %s" % path)
	SceneManager.goto_game()

func _on_settings_pressed() -> void:
	GameLog.info("MainMenu", "点击设置")
	_ensure_settings_dialog()
	if _settings_dialog.has_method("show_dialog"):
		_settings_dialog.call("show_dialog")
	else:
		_settings_dialog.show()

func _on_tile_editor_pressed() -> void:
	GameLog.info("MainMenu", "打开板块编辑器")
	SceneManager.goto_tile_editor()

func _on_replay_test_pressed() -> void:
	GameLog.info("MainMenu", "打开回放测试")
	SceneManager.goto_replay_test()

func _on_quit_pressed() -> void:
	GameLog.info("MainMenu", "退出游戏")
	get_tree().quit()

func _ensure_settings_dialog() -> void:
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		return

	_settings_dialog = SettingsDialogScene.instantiate()
	add_child(_settings_dialog)

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
