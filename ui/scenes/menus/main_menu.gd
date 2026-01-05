# 主菜单场景脚本
extends Control

@onready var version_label: Label = $VersionLabel

func _ready() -> void:
	GameLog.info("MainMenu", "主菜单已加载")
	version_label.text = "v%s" % Globals.get_version()

func _on_new_game_pressed() -> void:
	GameLog.info("MainMenu", "点击新游戏")
	SceneManager.goto_game_setup()

func _on_load_game_pressed() -> void:
	GameLog.info("MainMenu", "点击载入游戏")
	# TODO: 实现载入游戏功能
	GameLog.warn("MainMenu", "载入游戏功能尚未实现")

func _on_settings_pressed() -> void:
	GameLog.info("MainMenu", "点击设置")
	# TODO: 实现设置功能
	GameLog.warn("MainMenu", "设置功能尚未实现")

func _on_tile_editor_pressed() -> void:
	GameLog.info("MainMenu", "打开板块编辑器")
	SceneManager.goto_tile_editor()

func _on_replay_test_pressed() -> void:
	GameLog.info("MainMenu", "打开回放测试")
	SceneManager.goto_replay_test()

func _on_quit_pressed() -> void:
	GameLog.info("MainMenu", "退出游戏")
	get_tree().quit()
