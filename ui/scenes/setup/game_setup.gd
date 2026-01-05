# 游戏设置场景脚本
extends Control

@onready var player_count_spinbox: SpinBox = $CenterContainer/VBoxContainer/PlayerCountContainer/PlayerCountSpinBox
@onready var seed_edit: LineEdit = $CenterContainer/VBoxContainer/SeedContainer/SeedLineEdit

func _ready() -> void:
	GameLog.info("GameSetup", "游戏设置界面已加载")
	# 设置默认值
	player_count_spinbox.value = Globals.player_count
	if Globals.random_seed != 0:
		seed_edit.text = str(Globals.random_seed)

func _on_back_pressed() -> void:
	GameLog.info("GameSetup", "返回主菜单")
	SceneManager.go_back()

func _on_start_pressed() -> void:
	# 保存设置
	Globals.player_count = int(player_count_spinbox.value)

	# 处理随机种子
	if seed_edit.text.is_empty():
		Globals.generate_seed()
		GameLog.info("GameSetup", "生成随机种子: %d" % Globals.random_seed)
	else:
		Globals.random_seed = seed_edit.text.to_int()
		GameLog.info("GameSetup", "使用指定种子: %d" % Globals.random_seed)

	GameLog.info("GameSetup", "开始游戏 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])

	# 进入游戏场景
	SceneManager.goto_game()
