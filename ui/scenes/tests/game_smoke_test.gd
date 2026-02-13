# game.tscn Smoke Test（Headless / Autorun）
# 目标：验证主游戏场景可加载、初始化完成，并能正常释放（避免脚本报错/节点路径漂移）。
extends Control

const MainMenuScene: PackedScene = preload("res://ui/scenes/main_menu.tscn")
const GameSetupScene: PackedScene = preload("res://ui/scenes/setup/game_setup.tscn")
const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const OnlineLobbyScene: PackedScene = preload("res://ui/scenes/online/online_lobby.tscn")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0
var _main_menu_instance: Node = null
var _game_setup_instance: Node = null
var _game_instance: Node = null
var _online_lobby_instance: Node = null

func _ready() -> void:
	if is_instance_valid(output):
		output.clear()
		output.append_text("Game.tscn Smoke Test：加载 → 初始化 → 释放。\n")
		output.append_text("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")

	if _should_autorun():
		_exit_code = await _run_test()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = await _run_test()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_test() -> int:
	if is_instance_valid(output):
		output.append_text("\n--- 开始测试 ---\n")
	print("[GameSmokeTest] START args=%s" % str(OS.get_cmdline_user_args()))

	if GameScene == null:
		return await _fail("预加载 game.tscn 失败（PackedScene 为空）")

	# MainMenu 场景基础加载（主入口）
	if is_instance_valid(output):
		output.append_text("检查主菜单场景可加载...\n")
	print("[GameSmokeTest] STEP main_menu")

	if MainMenuScene == null:
		return await _fail("预加载 main_menu.tscn 失败（PackedScene 为空）")

	var menu = MainMenuScene.instantiate()
	if menu == null:
		return await _fail("实例化 main_menu.tscn 失败（instantiate 为空）")

	add_child(menu)
	_main_menu_instance = menu
	if menu is CanvasItem:
		(menu as CanvasItem).visible = false

	await get_tree().process_frame
	await get_tree().process_frame

	var new_game_paths: PackedStringArray = [
		"CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/NewGameButton",
		"CenterContainer/Card/Margin/VBoxContainer/NewGameButton",
	]
	if _find_first_existing_node(menu, new_game_paths) == null:
		return await _fail("main_menu.tscn 缺少 NewGameButton 节点（节点路径漂移）")
	var online_paths: PackedStringArray = [
		"CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/OnlineButton",
		"CenterContainer/Card/Margin/VBoxContainer/OnlineButton",
	]
	if _find_first_existing_node(menu, online_paths) == null:
		return await _fail("main_menu.tscn 缺少 OnlineButton 节点（节点路径漂移）")
	if menu.get_node_or_null("VersionLabel") == null:
		return await _fail("main_menu.tscn 缺少 VersionLabel 节点（节点路径漂移）")

	# GameSetup 场景基础加载（新局入口）
	if is_instance_valid(output):
		output.append_text("检查新局设置场景可加载...\n")
	print("[GameSmokeTest] STEP game_setup")

	if GameSetupScene == null:
		return await _fail("预加载 game_setup.tscn 失败（PackedScene 为空）")

	var setup = GameSetupScene.instantiate()
	if setup == null:
		return await _fail("实例化 game_setup.tscn 失败（instantiate 为空）")

	add_child(setup)
	_game_setup_instance = setup
	if setup is CanvasItem:
		(setup as CanvasItem).visible = false

	await get_tree().process_frame
	await get_tree().process_frame

	var setup_back_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/ButtonContainer/BackButton",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/ButtonContainer/BackButton",
	]
	if _find_first_existing_node(setup, setup_back_paths) == null:
		return await _fail("game_setup.tscn 缺少 BackButton 节点（节点路径漂移）")
	var setup_start_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/ButtonContainer/StartButton",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/ButtonContainer/StartButton",
	]
	if _find_first_existing_node(setup, setup_start_paths) == null:
		return await _fail("game_setup.tscn 缺少 StartButton 节点（节点路径漂移）")
	var setup_count_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn/PlayerCountContainer/PlayerCountSpinBox",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/LeftColumn/PlayerCountContainer/PlayerCountSpinBox",
	]
	if _find_first_existing_node(setup, setup_count_paths) == null:
		return await _fail("game_setup.tscn 缺少 PlayerCountSpinBox 节点（节点路径漂移）")
	var setup_seed_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn/SeedContainer/SeedLineEdit",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/LeftColumn/SeedContainer/SeedLineEdit",
	]
	if _find_first_existing_node(setup, setup_seed_paths) == null:
		return await _fail("game_setup.tscn 缺少 SeedLineEdit 节点（节点路径漂移）")

	# 关键：校验 game_setup.gd 的动态 UI 组装是否执行（避免 _ready/节点路径错误导致静默失败）
	var setup_players_section_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn/PlayersSection",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/LeftColumn/PlayersSection",
	]
	if _find_first_existing_node(setup, setup_players_section_paths) == null:
		return await _fail("game_setup.tscn 缺少 PlayersSection（可能是 game_setup.gd 未正确运行）")
	var setup_modules_section_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/RightColumn/ModulesSection",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/RightColumn/ModulesSection",
	]
	if _find_first_existing_node(setup, setup_modules_section_paths) == null:
		return await _fail("game_setup.tscn 缺少 ModulesSection（可能是 game_setup.gd 未正确运行）")

	var inst = GameScene.instantiate()
	if inst == null:
		return await _fail("实例化 game.tscn 失败（instantiate 为空）")

	add_child(inst)
	_game_instance = inst
	if inst is CanvasItem:
		(inst as CanvasItem).visible = false

	# 等待若干帧，确保 _ready/_process_frame 已运行
	await get_tree().process_frame
	await get_tree().process_frame

	# 基本健康检查：Game.gd 初始化会写入 Globals.current_game_engine / is_game_active
	if Globals.current_game_engine == null:
		return await _fail("Globals.current_game_engine 为空（game 初始化失败或未完成）")
	if not bool(Globals.is_game_active):
		return await _fail("Globals.is_game_active 为 false（game 初始化失败或未完成）")

	# OnlineLobby 场景基础加载（防止联机入口脚本/节点路径漂移导致“联机模式无法启动”）
	if is_instance_valid(output):
		output.append_text("检查联机大厅场景可加载...\n")
	print("[GameSmokeTest] STEP online_lobby")

	if OnlineLobbyScene == null:
		return await _fail("预加载 online_lobby.tscn 失败（PackedScene 为空）")

	var lobby = OnlineLobbyScene.instantiate()
	if lobby == null:
		return await _fail("实例化 online_lobby.tscn 失败（instantiate 为空）")

	add_child(lobby)
	_online_lobby_instance = lobby
	if lobby is CanvasItem:
		(lobby as CanvasItem).visible = false

	await get_tree().process_frame
	await get_tree().process_frame

	var lobby_back_paths: PackedStringArray = [
		"Center/Panel/OuterMargin/InnerBorder/Margin/Root/TopBar/BackButton",
		"Center/Panel/Margin/Root/TopBar/BackButton",
	]
	if _find_first_existing_node(lobby, lobby_back_paths) == null:
		return await _fail("online_lobby.tscn 缺少 BackButton 节点（节点路径漂移）")
	var lobby_connect_paths: PackedStringArray = [
		"Center/Panel/OuterMargin/InnerBorder/Margin/Root/Tabs/ConnectTab/ButtonsRow/ConnectButton",
		"Center/Panel/Margin/Root/Tabs/ConnectTab/ButtonsRow/ConnectButton",
	]
	if _find_first_existing_node(lobby, lobby_connect_paths) == null:
		return await _fail("online_lobby.tscn 缺少 ConnectButton 节点（节点路径漂移）")
	if lobby.get_node_or_null("ConfigDebounceTimer") == null:
		return await _fail("online_lobby.tscn 缺少 ConfigDebounceTimer 节点（节点路径漂移）")

	await _cleanup()

	if is_instance_valid(output):
		output.append_text("PASS\n")
	print("[GameSmokeTest] PASS")
	return 0

func _cleanup() -> void:
	if is_instance_valid(_online_lobby_instance):
		_online_lobby_instance.queue_free()
		_online_lobby_instance = null
	if is_instance_valid(_game_instance):
		_game_instance.queue_free()
		_game_instance = null
	if is_instance_valid(_game_setup_instance):
		_game_setup_instance.queue_free()
		_game_setup_instance = null
	if is_instance_valid(_main_menu_instance):
		_main_menu_instance.queue_free()
		_main_menu_instance = null
	await get_tree().process_frame
	if NetClient != null:
		NetClient.shutdown()
	Globals.reset_game_config()

func _fail(msg: String) -> int:
	if is_instance_valid(output):
		output.append_text("FAIL: %s\n" % msg)
	push_error("[GameSmokeTest] FAIL: %s" % msg)
	print("[GameSmokeTest] FAIL: %s" % msg)
	await _cleanup()
	return 1

func _should_autorun() -> bool:
	var tree = get_tree()
	if tree == null or tree.current_scene != self:
		return false
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")

func _find_first_existing_node(root: Node, paths: PackedStringArray) -> Node:
	if root == null:
		return null
	for path in paths:
		var n = root.get_node_or_null(path)
		if n != null:
			return n
	return null
