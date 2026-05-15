# game.tscn Smoke Test（Headless / Autorun）
# 目标：验证主游戏场景可加载、初始化完成，并能正常释放（避免脚本报错/节点路径漂移）。
extends Control

const MainMenuScene: PackedScene = preload("res://ui/scenes/main_menu.tscn")
const GameSetupScene: PackedScene = preload("res://ui/scenes/setup/game_setup.tscn")
const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const OnlineLobbyScene: PackedScene = preload("res://ui/scenes/online/online_lobby.tscn")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map/drawer/passes/structures_pass.gd")
const TilePreviewFactoryClass = preload("res://ui/components/reserve_area/tile_preview_factory.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

@onready var root_ui: Control = $Root
@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0
var _write_ui_log: bool = true
var _main_menu_instance: Node = null
var _game_setup_instance: Node = null
var _game_instance: Node = null
var _online_lobby_instance: Node = null

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless"

func _ready() -> void:
	_write_ui_log = not _is_headless_runtime()
	if not _write_ui_log and is_instance_valid(root_ui):
		root_ui.queue_free()
	_clear_output()
	_append_output("Game.tscn Smoke Test：加载 → 初始化 → 释放。\n")
	_append_output("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")

	if _should_autorun():
		_exit_code = await _run_test()
		if SceneManager != null and SceneManager.has_method("shutdown_current_scene_after_cleanup"):
			SceneManager.shutdown_current_scene_after_cleanup(self, Callable(self, "_prepare_runtime_cleanup_before_quit"), _exit_code)
			return
		await _prepare_runtime_cleanup_before_quit()
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
	_append_output("\n--- 开始测试 ---\n")
	print("[GameSmokeTest] START args=%s" % str(OS.get_cmdline_user_args()))

	if GameScene == null:
		return await _fail("预加载 game.tscn 失败（PackedScene 为空）")

	# MainMenu 场景基础加载（主入口）
	_append_output("检查主菜单场景可加载...\n")
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
	var rules_paths: PackedStringArray = [
		"CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/RulesButton",
		"CenterContainer/Card/Margin/VBoxContainer/RulesButton",
	]
	var rules_button = _find_first_existing_node(menu, rules_paths)
	if rules_button == null:
		return await _fail("main_menu.tscn 缺少 RulesButton 节点（节点路径漂移）")
	if rules_button is Button and (rules_button as Button).text != "规则详情":
		return await _fail("main_menu.tscn RulesButton 文案应为“规则详情”")
	var online_paths: PackedStringArray = [
		"CenterContainer/Card/OuterMargin/InnerBorder/InnerMargin/VBoxContainer/OnlineButton",
		"CenterContainer/Card/Margin/VBoxContainer/OnlineButton",
	]
	if _find_first_existing_node(menu, online_paths) == null:
		return await _fail("main_menu.tscn 缺少 OnlineButton 节点（节点路径漂移）")
	if menu.get_node_or_null("VersionLabel") == null:
		return await _fail("main_menu.tscn 缺少 VersionLabel 节点（节点路径漂移）")

	# GameSetup 场景基础加载（新局入口）
	_append_output("检查新局设置场景可加载...\n")
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
	if _find_first_existing_node(setup, setup_count_paths) == null and not _has_player_count_button_group(setup):
		return await _fail("game_setup.tscn 缺少玩家数量控件（旧版 SpinBox/新版按钮组）")
	var setup_seed_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn/SeedContainer/SeedLineEdit",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/LeftColumn/SeedContainer/SeedLineEdit",
	]
	if _find_first_existing_node(setup, setup_seed_paths) == null and _find_seed_line_edit_by_placeholder(setup) == null:
		return await _fail("game_setup.tscn 缺少随机种子输入框（SeedLineEdit）")

	# 关键：校验 game_setup.gd 的动态 UI 组装是否执行（避免 _ready/节点路径错误导致静默失败）
	var setup_players_section_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn/PlayersSection",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/LeftColumn/PlayersSection",
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn/PlayersContainer",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/LeftColumn/PlayersContainer",
	]
	var players_section = _find_first_existing_node(setup, setup_players_section_paths)
	if players_section == null:
		players_section = _find_node_by_name_recursive(setup, "PlayersSection")
	if players_section == null:
		players_section = _find_node_by_name_recursive(setup, "PlayersContainer")
	if players_section == null:
		return await _fail("game_setup.tscn 缺少 PlayersSection（可能是 game_setup.gd 未正确运行）")
	if not _has_player_control_mode_option(setup):
		return await _fail("game_setup.tscn 缺少玩家/电脑控制方式下拉")
	var setup_modules_section_paths: PackedStringArray = [
		"CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/RightColumn/ModulesSection",
		"CenterContainer/ContentCenter/Card/Margin/VBoxContainer/MainColumns/RightColumn/ModulesSection",
	]
	if _find_first_existing_node(setup, setup_modules_section_paths) == null:
		return await _fail("game_setup.tscn 缺少 ModulesSection（可能是 game_setup.gd 未正确运行）")

	# 本地人机冒烟：默认 seed=0 的初始顺位从 P2 开始；AI 应自动完成开局储备卡选择后停在玩家回合。
	Globals.player_count = 2
	Globals.random_seed = 0
	Globals.set_local_player_control_mode(0, "human")
	Globals.set_local_player_control_mode(1, "ai")

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
	if not await _wait_for_command_history_size(Globals.current_game_engine, 1, 90):
		return await _fail("本地电脑玩家未自动执行开局命令")
	var history: Array = Globals.current_game_engine.command_history
	var first_command = history[0] if history.size() > 0 else null
	if not (first_command is Command):
		return await _fail("本地电脑玩家命令历史类型错误")
	if str((first_command as Command).action_id) != "select_reserve_card":
		return await _fail("本地电脑玩家首个命令应为 select_reserve_card，实际为 %s" % str((first_command as Command).action_id))
	if not await _run_local_ai_restructuring_smoke(inst, Globals.current_game_engine):
		return await _fail("本地电脑玩家未在重组阶段自动提交")

	# OnlineLobby 场景基础加载（防止联机入口脚本/节点路径漂移导致“联机模式无法启动”）
	_append_output("检查联机大厅场景可加载...\n")
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
		"Center/Panel/OuterMargin/InnerBorder/Margin/Root/Pages/ConnectPage/ButtonsRow/ConnectButton",
		"Center/Panel/OuterMargin/InnerBorder/Margin/Root/Tabs/ConnectTab/ButtonsRow/ConnectButton",
		"Center/Panel/Margin/Root/Tabs/ConnectTab/ButtonsRow/ConnectButton",
	]
	if _find_first_existing_node(lobby, lobby_connect_paths) == null:
		return await _fail("online_lobby.tscn 缺少 ConnectButton 节点（节点路径漂移）")
	if lobby.get_node_or_null("ConfigDebounceTimer") == null:
		return await _fail("online_lobby.tscn 缺少 ConfigDebounceTimer 节点（节点路径漂移）")

	await _cleanup()

	_append_output("PASS\n")
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
	await _drain_frames(6)
	if NetClient != null:
		NetClient.shutdown()
	Globals.reset_game_config()

func _prepare_runtime_cleanup_before_quit() -> void:
	UiSkinCacheClass.clear_cache()
	EmployeeCardClass.clear_icon_texture_cache()
	StructuresPassClass.clear_drink_source_texture_cache()
	TilePreviewFactoryClass.clear_cached_script()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	await _drain_frames(6)

func _fail(msg: String) -> int:
	_append_output("FAIL: %s\n" % msg)
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
	return _is_headless_runtime()

func _append_output(text: String) -> void:
	if not _write_ui_log:
		return
	if is_instance_valid(output):
		output.append_text(text)

func _clear_output() -> void:
	if not _write_ui_log:
		return
	if is_instance_valid(output):
		output.clear()

func _drain_frames(count: int) -> void:
	var n := maxi(1, int(count))
	for _i in range(n):
		await get_tree().process_frame

func _wait_for_command_history_size(engine: GameEngine, minimum_size: int, max_frames: int) -> bool:
	if engine == null:
		return false
	for _i in range(maxi(1, max_frames)):
		if int(engine.command_history.size()) >= int(minimum_size):
			return true
		await get_tree().process_frame
	return int(engine.command_history.size()) >= int(minimum_size)

func _run_local_ai_restructuring_smoke(game_scene: Node, engine: GameEngine) -> bool:
	if engine == null:
		return false
	var advance := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_RESTRUCTURING, 120)
	if not advance.ok:
		return false
	var state := engine.get_state()
	if state == null or state.players.size() < 2:
		return false

	state.current_player_index = 0
	state.turn_order = [0, 1]
	if not (state.round_state is Dictionary):
		state.round_state = {}
	state.round_state["restructuring"] = {
		"submitted": {0: false, 1: false},
		"finalized": false,
	}
	var pending_phase_actions := {}
	var existing_pending = state.round_state.get("pending_phase_actions", null)
	if existing_pending is Dictionary:
		pending_phase_actions = Dictionary(existing_pending).duplicate(true)
	pending_phase_actions[DefsClass.PHASE_RESTRUCTURING] = [0, 1]
	state.round_state["pending_phase_actions"] = pending_phase_actions

	var state_ref: GameState = state
	if state_ref == null:
		return false
	var player0 := state_ref.get_player(0)
	var player1 := state_ref.get_player(1)
	if player0.is_empty() or player1.is_empty():
		return false
	state_ref.players[0] = player0
	state_ref.players[1] = player1

	# 触发本地 AI 泵；它应当跳过人类 pending，直接处理 AI 的重组提交。
	if is_instance_valid(game_scene) and game_scene.has_method("_request_local_ai_pump"):
		game_scene.call("_request_local_ai_pump")
	for _i in range(20):
		await get_tree().process_frame
		var updated := engine.get_state()
		if updated == null or not (updated.round_state is Dictionary):
			continue
		var restructuring_val = updated.round_state.get("restructuring", null)
		if not (restructuring_val is Dictionary):
			continue
		var restructuring: Dictionary = restructuring_val
		var submitted_val = restructuring.get("submitted", null)
		if not (submitted_val is Dictionary):
			continue
		var submitted: Dictionary = submitted_val
		if bool(submitted.get(1, false)) and not bool(submitted.get(0, false)):
			return true
	return false

func _find_first_existing_node(root: Node, paths: PackedStringArray) -> Node:
	if root == null:
		return null
	for path in paths:
		var n = root.get_node_or_null(path)
		if n != null:
			return n
	return null

func _has_player_count_button_group(root: Node) -> bool:
	if root == null:
		return false
	var marks := {
		"2": false,
		"3": false,
		"4": false,
		"5": false,
		"6": false,
	}
	_collect_player_count_button_marks(root, marks)
	for key in marks.keys():
		if not bool(marks[key]):
			return false
	return true

func _collect_player_count_button_marks(node: Node, marks: Dictionary) -> void:
	if node == null:
		return
	if node is Button:
		var text := str((node as Button).text).strip_edges()
		if marks.has(text):
			marks[text] = true
	for child in node.get_children():
		if child is Node:
			_collect_player_count_button_marks(child, marks)

func _find_seed_line_edit_by_placeholder(node: Node) -> LineEdit:
	if node == null:
		return null
	if node is LineEdit:
		var edit: LineEdit = node
		if str(edit.placeholder_text).strip_edges() == "留空自动生成":
			return edit
	for child in node.get_children():
		if not (child is Node):
			continue
		var found := _find_seed_line_edit_by_placeholder(child)
		if found != null:
			return found
	return null

func _has_player_control_mode_option(root: Node) -> bool:
	if root == null:
		return false
	var options: Array[OptionButton] = []
	_collect_option_buttons(root, options)
	for opt in options:
		if not is_instance_valid(opt):
			continue
		if opt.item_count < 2:
			continue
		if str(opt.get_item_text(0)).strip_edges() == "玩家" and str(opt.get_item_text(1)).strip_edges() == "电脑":
			return true
	return false

func _collect_option_buttons(node: Node, out: Array[OptionButton]) -> void:
	if node == null:
		return
	if node is OptionButton:
		out.append(node as OptionButton)
	for child in node.get_children():
		if child is Node:
			_collect_option_buttons(child, out)

func _find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	if node == null:
		return null
	if str(node.name) == str(target_name):
		return node
	for child in node.get_children():
		if not (child is Node):
			continue
		var found := _find_node_by_name_recursive(child, target_name)
		if found != null:
			return found
	return null
