# 游戏主场景脚本
extends Control

# UI 节点引用
@onready var round_label: Label = $TopBar/RoundLabel
@onready var phase_label: Label = $TopBar/PhaseLabel
@onready var bank_label: Label = $TopBar/BankLabel
@onready var current_player_label: Label = $TopBar/CurrentPlayerLabel
@onready var state_hash_label: Label = $BottomBar/StateHashLabel
@onready var command_count_label: Label = $BottomBar/CommandCountLabel
@onready var menu_dialog: Window = $MenuDialog
@onready var debug_dialog: Window = $DebugDialog
@onready var debug_text: TextEdit = $DebugDialog/VBoxContainer/DebugText
@onready var map_view: ScrollContainer = $GameArea/MapView

# 游戏状态
var game_engine: GameEngine = null

func _ready() -> void:
	GameLog.info("Game", "游戏场景已加载")
	_initialize_game()
	_update_ui()

func _initialize_game() -> void:
	game_engine = GameEngine.new()
	var init_result := game_engine.initialize(Globals.player_count, Globals.random_seed, Globals.enabled_modules_v2, Globals.modules_v2_base_dir)
	if not init_result.ok:
		GameLog.error("Game", "游戏初始化失败: %s" % init_result.error)
		return

	Globals.current_game_engine = game_engine
	Globals.is_game_active = true

	GameLog.info("Game", "游戏初始化完成 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])
	GameLog.info("Game", "初始状态:\n%s" % game_engine.get_state().dump())

func _update_ui() -> void:
	if game_engine == null:
		return

	var state := game_engine.get_state()
	round_label.text = "回合: %d" % state.round_number
	phase_label.text = "阶段: %s%s" % [
		state.phase,
		(" / %s" % state.sub_phase) if not state.sub_phase.is_empty() else ""
	]
	current_player_label.text = "玩家: %d" % (state.get_current_player_id() + 1)
	bank_label.text = "银行: $%d" % state.bank.get("total", 0)

	# 计算状态哈希（截断显示）
	var full_hash := state.compute_hash()
	state_hash_label.text = "Hash: %s..." % full_hash.substr(0, 8)

	# 命令计数
	command_count_label.text = "命令: %d" % game_engine.get_command_history().size()

	# 地图渲染（M2 接入）
	if is_instance_valid(map_view) and map_view.has_method("set_game_state"):
		map_view.call("set_game_state", state)

	if is_instance_valid(debug_dialog) and debug_dialog.visible:
		_update_debug_text()

func _on_menu_pressed() -> void:
	GameLog.info("Game", "打开游戏菜单")
	menu_dialog.show()

func _on_menu_dialog_close_requested() -> void:
	menu_dialog.hide()

func _on_resume_pressed() -> void:
	GameLog.info("Game", "继续游戏")
	menu_dialog.hide()

func _on_save_pressed() -> void:
	GameLog.info("Game", "保存游戏")
	if game_engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法保存")
		menu_dialog.hide()
		return

	var path := "user://savegame.json"
	var save_result := game_engine.save_to_file(path)
	if not save_result.ok:
		GameLog.error("Game", "保存失败: %s" % save_result.error)
	else:
		GameLog.info("Game", "已保存到: %s" % path)
	menu_dialog.hide()

func _on_quit_to_menu_pressed() -> void:
	GameLog.info("Game", "返回主菜单")
	Globals.reset_game_config()
	SceneManager.goto_main_menu()

func _on_debug_pressed() -> void:
	GameLog.info("Game", "打开调试窗口")
	_update_debug_text()
	debug_dialog.show()

func _on_debug_dialog_close_requested() -> void:
	debug_dialog.hide()

func _update_debug_text() -> void:
	if game_engine == null:
		return
	if not is_instance_valid(debug_text):
		return
	var state := game_engine.get_state()

	var lines: Array[String] = []
	lines.append("round=%d phase=%s sub_phase=%s current_player=%d" % [
		state.round_number,
		state.phase,
		state.sub_phase,
		state.get_current_player_id(),
	])
	lines.append("")
	lines.append("bank=%s" % str(state.bank))
	lines.append("")
	lines.append("marketing_instances=%s" % str(state.marketing_instances))
	lines.append("")
	lines.append("round_state=%s" % str(state.round_state))

	debug_text.text = "\n".join(lines)

func _execute_command(command: Command) -> Result:
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")

	var result := game_engine.execute_command(command)
	if not result.ok:
		GameLog.warn("Game", "命令执行失败: %s" % result.error)
	else:
		GameLog.info("Game", "命令执行成功: %s" % command.action_id)

	_update_ui()
	return result

func _on_advance_phase_pressed() -> void:
	_execute_command(Command.create_system("advance_phase"))

func _on_advance_sub_phase_pressed() -> void:
	_execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))

func _on_skip_pressed() -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	_execute_command(Command.create("skip", current_player_id))

# 获取当前状态的关键值（用于调试）
func get_key_values() -> Dictionary:
	if game_engine != null:
		return game_engine.get_state().extract_key_values()
	return {}
