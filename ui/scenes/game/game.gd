# 游戏主场景脚本（协调器）
# 说明：将原先巨型脚本拆分为多个控制器，主脚本只做节点绑定与编排。
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
@onready var map_view: ScrollContainer = $MainContent/CenterSplit/GameArea/MapView
@onready var map_canvas: Control = $MainContent/CenterSplit/GameArea/MapView/Canvas
@onready var game_log_panel: GameLogPanel = $MainContent/GameLogPanel

# 新 UI 组件引用
@onready var player_panel: Control = $MainContent/CenterSplit/RightPanel/PlayerPanel
@onready var turn_order_track: Control = $MainContent/CenterSplit/RightPanel/TurnOrderTrack
@onready var inventory_panel: Control = $MainContent/CenterSplit/RightPanel/InventoryPanel
@onready var action_panel: Control = $MainContent/CenterSplit/RightPanel/ActionPanel
@onready var hand_area: Control = $BottomPanel/HandArea
@onready var company_structure: Control = $BottomPanel/CompanyStructure

const GameEventLogControllerClass = preload("res://ui/scenes/game/game_event_log_controller.gd")
const GameMenuDebugControllerClass = preload("res://ui/scenes/game/game_menu_debug_controller.gd")
const GameOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_controller.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")
const GamePanelControllerClass = preload("res://ui/scenes/game/game_panel_controller.gd")
const DebugPanelScene = preload("res://ui/scenes/debug/debug_panel.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const ReplayPlayerScene = preload("res://ui/components/replay_player/replay_player.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")

# 游戏状态
var game_engine: GameEngine = null

# 控制器
var _event_log_controller = null
var _menu_debug_controller = null
var _overlay_controller = null
var _map_controller = null
var _panel_controller = null

# 调试面板
var _debug_panel: Window = null

# 确认对话框（复用）
var _confirm_dialog: ConfirmDialog = null
var _confirm_dialog_on_confirm: Callable = Callable()
var _confirm_dialog_on_cancel: Callable = Callable()

# 回放播放器（P2）
var _replay_player: ReplayPlayer = null
var _replay_mode_active: bool = false
var _replay_original_engine: GameEngine = null
var _replay_file_path: String = ""

# 存档管理（多槽 + 文件选择）
var _save_load_dialog = null
var _save_load_context: String = ""

func _ready() -> void:
	GameLog.info("Game", "游戏场景已加载")

	_overlay_controller = GameOverlayControllerClass.new(self, map_view, map_canvas, game_log_panel)
	_overlay_controller.initialize()

	_map_controller = GameMapInteractionControllerClass.new(self, map_canvas, _overlay_controller)
	_map_controller.connect_signals()

	_panel_controller = GamePanelControllerClass.new(
		self,
		_map_controller,
		_overlay_controller,
		Callable(self, "_execute_command"),
		Callable(self, "_update_ui")
	)
	_panel_controller.connect_signals(action_panel, turn_order_track, hand_area, company_structure)

	_menu_debug_controller = GameMenuDebugControllerClass.new(self, menu_dialog, debug_dialog, debug_text)

	_event_log_controller = GameEventLogControllerClass.new()
	_event_log_controller.setup(game_log_panel)

	_initialize_game()
	if game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

	# 初始化调试面板
	_setup_debug_panel()
	DebugFlags.debug_panel_toggled.connect(_on_debug_panel_toggled)
	_on_debug_panel_toggled(DebugFlags.show_console)

	_update_ui()

func _initialize_game() -> void:
	# 载入游戏：主菜单可能已在 Globals 中准备好 GameEngine。
	if Globals.current_game_engine != null and Globals.current_game_engine is GameEngine:
		var existing: GameEngine = Globals.current_game_engine
		if existing.get_state() != null:
			game_engine = existing
			GameLog.info("Game", "复用已载入的游戏引擎")
			return
		Globals.current_game_engine = null
		Globals.is_game_active = false

	game_engine = GameEngine.new()
	var init_result := game_engine.initialize(Globals.player_count, Globals.random_seed, Globals.enabled_modules_v2, Globals.modules_v2_base_dir, Globals.reserve_card_selected_by_player)
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

func _setup_debug_panel() -> void:
	if not DebugFlags.is_debug_mode():
		return

	if _debug_panel != null and is_instance_valid(_debug_panel):
		return

	_debug_panel = DebugPanelScene.instantiate()
	add_child(_debug_panel)
	_debug_panel.set_game_engine(game_engine)
	_debug_panel.hide()

	# 连接命令执行信号以刷新 UI
	_debug_panel.command_executed.connect(_on_debug_command_executed)

func _update_ui() -> void:
	if game_engine == null:
		return

	var state := game_engine.get_state()
	round_label.text = "回合: %d" % state.round_number
	phase_label.text = "阶段: %s%s" % [
		state.phase,
		(" / %s" % state.sub_phase) if not state.sub_phase.is_empty() else ""
	]
	var pid := state.get_current_player_id()
	var player_label := "玩家: %s" % Globals.get_player_name(pid)
	if _replay_mode_active:
		player_label += "（回放）"
	current_player_label.text = player_label
	bank_label.text = "银行: $%d" % state.bank.get("total", 0)

	# 计算状态哈希（截断显示）
	var full_hash := state.compute_hash()
	state_hash_label.text = "Hash: %s..." % full_hash.substr(0, 8)

	# 命令计数
	command_count_label.text = "命令: %d" % game_engine.get_command_history().size()

	# 地图渲染（M2 接入）
	if is_instance_valid(map_view) and map_view.has_method("set_game_state"):
		map_view.call("set_game_state", state)

	# UI 同步（面板/覆盖层）
	if _panel_controller != null:
		_panel_controller.sync(state)
	if _overlay_controller != null:
		_overlay_controller.sync_dinnertime_overlay(state)
		_overlay_controller.sync_demand_indicator(state)

	if _menu_debug_controller != null:
		_menu_debug_controller.sync_debug_text_if_visible()

	# 同步调试面板
	if _debug_panel != null and _debug_panel.visible:
		_debug_panel.refresh_state()

func _on_debug_command_executed(_command: String, _result: String) -> void:
	# 调试命令执行后刷新游戏 UI
	_update_ui()

func _execute_command(command: Command) -> Result:
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")
	if _replay_mode_active:
		return Result.failure("回放模式下无法执行命令")

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

# === 菜单/调试（TopBar + Dialogs）===

func _on_menu_pressed() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.open_menu()
	else:
		menu_dialog.show()

func _on_menu_dialog_close_requested() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.close_menu()
	else:
		menu_dialog.hide()

func _on_resume_pressed() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.resume()
	else:
		menu_dialog.hide()

func _on_save_pressed() -> void:
	_ensure_save_load_dialog()
	_save_load_context = "save"
	_save_load_dialog.open_for_save(game_engine)
	_on_menu_dialog_close_requested()

func _on_settings_pressed() -> void:
	show_settings_dialog()
	_on_menu_dialog_close_requested()

func _on_toggle_log_pressed() -> void:
	toggle_game_log()
	_on_menu_dialog_close_requested()

func _on_milestones_pressed() -> void:
	show_milestone_panel()
	_on_menu_dialog_close_requested()

func _on_distance_tool_pressed() -> void:
	toggle_distance_tool()
	_on_menu_dialog_close_requested()

func _on_replay_pressed() -> void:
	_ensure_save_load_dialog()
	_save_load_context = "replay"
	_save_load_dialog.open_for_replay()
	_on_menu_dialog_close_requested()

func _on_quit_to_menu_pressed() -> void:
	_on_menu_dialog_close_requested()
	_show_confirm(
		"返回主菜单",
		"确定要返回主菜单吗？\n未保存的进度将丢失。",
		Callable(self, "_confirm_quit_to_menu"),
		Callable(self, "_cancel_quit_to_menu")
	)

func _on_debug_pressed() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.open_debug()
	else:
		debug_dialog.show()

func _on_debug_dialog_close_requested() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.close_debug()
	else:
		debug_dialog.hide()

# === 确认弹窗（P2）===

func _show_confirm(title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> void:
	if _confirm_dialog == null or not is_instance_valid(_confirm_dialog):
		_confirm_dialog = ConfirmDialogScene.instantiate()
		add_child(_confirm_dialog)
		_confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
		_confirm_dialog.cancelled.connect(_on_confirm_dialog_cancelled)

	_confirm_dialog_on_confirm = on_confirm
	_confirm_dialog_on_cancel = on_cancel
	_confirm_dialog.setup(title, message)
	_confirm_dialog.show_dialog()

func _on_confirm_dialog_confirmed() -> void:
	var cb := _confirm_dialog_on_confirm
	_confirm_dialog_on_confirm = Callable()
	_confirm_dialog_on_cancel = Callable()
	if cb.is_valid():
		cb.call()

func _on_confirm_dialog_cancelled() -> void:
	var cb := _confirm_dialog_on_cancel
	_confirm_dialog_on_confirm = Callable()
	_confirm_dialog_on_cancel = Callable()
	if cb.is_valid():
		cb.call()

func _confirm_quit_to_menu() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.quit_to_menu()
	else:
		Globals.reset_game_config()
		SceneManager.goto_main_menu()

func _cancel_quit_to_menu() -> void:
	if _menu_debug_controller != null:
		_menu_debug_controller.open_menu()
	elif is_instance_valid(menu_dialog):
		menu_dialog.show()

# === P2 工具方法（对外 API）===

func _ensure_save_load_dialog() -> void:
	if _save_load_dialog != null and is_instance_valid(_save_load_dialog):
		return

	_save_load_dialog = SaveLoadDialogScript.new()
	add_child(_save_load_dialog)

	if _save_load_dialog.has_signal("load_selected"):
		if not _save_load_dialog.load_selected.is_connected(_on_save_load_selected):
			_save_load_dialog.load_selected.connect(_on_save_load_selected)
	if _save_load_dialog.has_signal("save_completed"):
		if not _save_load_dialog.save_completed.is_connected(_on_save_completed):
			_save_load_dialog.save_completed.connect(_on_save_completed)

func _on_save_load_selected(path: String) -> void:
	if path.is_empty():
		return
	if _save_load_context == "replay":
		show_replay_player(path)
		return

	# 预留：未来可支持“游戏内载入存档”
	GameLog.warn("Game", "未支持的存档载入上下文: %s (%s)" % [_save_load_context, path])

func _on_save_completed(path: String) -> void:
	if path.is_empty():
		return
	GameLog.info("Game", "存档已保存: %s" % path)

func show_replay_player(file_path: String) -> void:
	if file_path.is_empty():
		return
	_replay_file_path = file_path

	if _replay_player == null or not is_instance_valid(_replay_player):
		_replay_player = ReplayPlayerScene.instantiate()
		_replay_player.visible = false
		add_child(_replay_player)

		if _replay_player.has_signal("close_requested"):
			_replay_player.close_requested.connect(_on_replay_close_requested)
		if _replay_player.has_signal("state_changed"):
			_replay_player.state_changed.connect(_on_replay_state_changed)
		if _replay_player.has_signal("error_occurred"):
			_replay_player.error_occurred.connect(_on_replay_error)

	_replay_player.visible = true
	_replay_player.z_index = 1000
	_center_replay_player()
	call_deferred("_load_replay_from_file")

func hide_replay_player() -> void:
	if _replay_player != null and is_instance_valid(_replay_player):
		_replay_player.visible = false
	_exit_replay_mode()

func _center_replay_player() -> void:
	if _replay_player == null or not is_instance_valid(_replay_player):
		return
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var panel_size := _replay_player.size
	if panel_size == Vector2.ZERO:
		panel_size = _replay_player.custom_minimum_size
	_replay_player.position = (viewport_size - panel_size) / 2.0

func _load_replay_from_file() -> void:
	if _replay_player == null or not is_instance_valid(_replay_player):
		return
	if _replay_file_path.is_empty():
		return

	var load_result: Result = _replay_player.load_from_file(_replay_file_path)
	if not load_result.ok:
		GameLog.error("Game", "回放加载失败: %s" % load_result.error)
		_show_confirm("回放加载失败", load_result.error, Callable(), Callable())
		return

	var replay_engine: GameEngine = _replay_player.get_game_engine()
	if replay_engine == null:
		GameLog.error("Game", "回放加载失败: GameEngine 为空")
		_show_confirm("回放加载失败", "内部错误: GameEngine 为空", Callable(), Callable())
		return

	_enter_replay_mode(replay_engine)

func _enter_replay_mode(engine: GameEngine) -> void:
	if engine == null:
		return
	if not _replay_mode_active:
		_replay_original_engine = game_engine

	_replay_mode_active = true
	game_engine = engine
	Globals.current_game_engine = engine
	Globals.is_game_active = true

	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.set_game_engine(game_engine)

	if _panel_controller != null and game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

	_update_ui()

func _exit_replay_mode() -> void:
	if not _replay_mode_active:
		return

	_replay_mode_active = false

	var restore_engine := _replay_original_engine
	_replay_original_engine = null

	if restore_engine != null:
		game_engine = restore_engine
		Globals.current_game_engine = restore_engine
		Globals.is_game_active = true

	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.set_game_engine(game_engine)

	if _panel_controller != null and game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

	_update_ui()

func _on_replay_state_changed(_command_index: int, _state: GameState) -> void:
	if not _replay_mode_active:
		return
	if _replay_player == null or not is_instance_valid(_replay_player):
		return

	var replay_engine: GameEngine = _replay_player.get_game_engine()
	if replay_engine == null:
		return

	if replay_engine != game_engine:
		_enter_replay_mode(replay_engine)
	else:
		_update_ui()

func _on_replay_error(message: String) -> void:
	GameLog.warn("ReplayPlayer", message)

func _on_replay_close_requested() -> void:
	hide_replay_player()

func show_distance_overlay(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	if _overlay_controller != null:
		_overlay_controller.show_distance_overlay(from_position, to_positions)

func hide_distance_overlay() -> void:
	if _overlay_controller != null:
		_overlay_controller.hide_distance_overlay()

func show_marketing_range_overlay(campaigns: Array[Dictionary]) -> void:
	if _overlay_controller != null:
		_overlay_controller.show_marketing_range_overlay(campaigns)

func hide_marketing_range_overlay() -> void:
	if _overlay_controller != null:
		_overlay_controller.hide_marketing_range_overlay()

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String) -> void:
	if _overlay_controller != null:
		_overlay_controller.preview_marketing_range(position, range_val, marketing_type)

func show_milestone_panel() -> void:
	if _panel_controller != null:
		_panel_controller.show_milestone_panel()

func toggle_game_log() -> void:
	if _overlay_controller != null:
		_overlay_controller.toggle_game_log()

func show_settings_dialog() -> void:
	if _overlay_controller != null:
		_overlay_controller.show_settings_dialog()

func toggle_distance_tool() -> void:
	if _map_controller != null:
		_map_controller.toggle_distance_tool()

func get_ui_animation_manager() -> Node:
	if _overlay_controller != null:
		return _overlay_controller.get_ui_animation_manager()
	return null

func _on_debug_panel_toggled(visible: bool) -> void:
	if not DebugFlags.is_debug_mode():
		if _debug_panel != null and is_instance_valid(_debug_panel):
			_debug_panel.hide()
		return

	if visible:
		if _debug_panel == null or not is_instance_valid(_debug_panel):
			_debug_panel = null
			_setup_debug_panel()
		if _debug_panel != null:
			_debug_panel.show()
			_debug_panel.refresh_state()
	else:
		if _debug_panel != null and is_instance_valid(_debug_panel):
			_debug_panel.hide()
