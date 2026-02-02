# 游戏主场景脚本（协调器）
# 说明：将原先巨型脚本拆分为多个控制器，主脚本只做节点绑定与编排。
extends Control

# UI 节点引用
@onready var round_label: Label = $UIRoot/TopBar/InfoRow/RoundLabel
@onready var phase_label: Label = $UIRoot/TopBar/InfoRow/PhaseLabel
@onready var turn_order_display: Control = $UIRoot/MainContent/CenterSplit/GameArea/TurnOrderOverlay/TurnOrderDisplay
@onready var bank_label: Label = $UIRoot/TopBar/InfoRow/BankLabel
@onready var current_player_label: Label = $UIRoot/TopBar/InfoRow/CurrentPlayerLabel
@onready var toggle_left_panel_button: Button = $UIRoot/TopBar/ButtonRow/ToggleLeftPanelButton
@onready var toggle_right_panel_button: Button = $UIRoot/TopBar/ButtonRow/ToggleRightPanelButton
@onready var toggle_bottom_panel_button: Button = $MenuDialog/VBoxContainer/ToggleBottomPanelButton
@onready var menu_dialog: Control = $MenuDialog
@onready var menu_dialog_overlay: ColorRect = $MenuDialog/Overlay
@onready var menu_dialog_background_panel: Panel = $MenuDialog/BackgroundPanel
@onready var menu_resume_button: Button = $MenuDialog/VBoxContainer/ResumeButton
@onready var menu_save_button: Button = $MenuDialog/VBoxContainer/SaveButton
@onready var menu_settings_button: Button = $MenuDialog/VBoxContainer/SettingsButton
@onready var menu_quit_to_menu_button: Button = $MenuDialog/VBoxContainer/QuitToMenuButton
@onready var main_content: Control = $UIRoot/MainContent
@onready var center_split: HSplitContainer = $UIRoot/MainContent/CenterSplit
@onready var map_view: ScrollContainer = $UIRoot/MainContent/CenterSplit/GameArea/MapView
@onready var map_canvas: Control = $UIRoot/MainContent/CenterSplit/GameArea/MapView/Content/Canvas
@onready var map_mode_bar = $UIRoot/MainContent/CenterSplit/GameArea/MapModeBar
@onready var left_area: Control = $UIRoot/MainContent/LeftArea
@onready var game_log_panel: GameLogPanel = $UIRoot/MainContent/LeftArea/GameLogPanel
@onready var left_panel: Control = $UIRoot/MainContent/LeftArea/LeftPanel

# 新 UI 组件引用
@onready var right_panel_back_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow/BackButton
@onready var right_panel_title_label: Label = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow/TitleLabel
@onready var right_panel_close_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow/CloseButton
@onready var right_panel_default_stack: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack
@onready var right_panel_dock_host: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DockHost
@onready var right_panel_footer_row: Control = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow
@onready var right_panel_footer_cancel_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/CancelButton
@onready var right_panel_footer_secondary_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/SecondaryButton
@onready var right_panel_footer_primary_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/PrimaryButton

@onready var player_panel: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/PlayerPanel
@onready var turn_order_track: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/TurnOrderTrack
@onready var inventory_panel: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/InventoryPanel
@onready var action_panel: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/ActionPanel
@onready var hand_area: Control = $UIRoot/BottomPanel/HandArea
@onready var company_structure: Control = $UIRoot/BottomPanel/CompanyStructure
@onready var bottom_panel: Control = $UIRoot/BottomPanel

const GameEventLogControllerClass = preload("res://ui/scenes/game/game_event_log_controller.gd")
const GameMenuDebugControllerClass = preload("res://ui/scenes/game/game_menu_debug_controller.gd")
const GameSaveLoadControllerClass = preload("res://ui/scenes/game/game_save_load_controller.gd")
const GameLayoutControllerClass = preload("res://ui/scenes/game/game_layout_controller.gd")
const GameRightPanelDockControllerClass = preload("res://ui/scenes/game/game_right_panel_dock_controller.gd")
const GameOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_controller.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")
const GamePanelControllerClass = preload("res://ui/scenes/game/game_panel_controller.gd")
const GameOnlineResyncControllerClass = preload("res://ui/scenes/game/game_online_resync_controller.gd")
const GameTimelineControllerClass = preload("res://ui/scenes/game/game_timeline_controller.gd")
const DebugPanelScene = preload("res://ui/scenes/debug/debug_panel.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const EventTimelineBuildClass = preload("res://gameplay/replay/event_timeline_build.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

# 游戏状态
var game_engine: GameEngine = null

# 控制器
var _event_log_controller = null
var _menu_debug_controller = null
var _save_load_controller = null
var _layout_controller = null
var _right_panel_dock_controller = null
var _overlay_controller = null
var _map_controller = null
var _panel_controller = null
var _online_resync_controller = null
var _timeline_controller = null

# 调试面板
var _debug_panel: Window = null

# 确认对话框（复用）
var _confirm_dialog: ConfirmDialog = null
var _confirm_dialog_on_confirm: Callable = Callable()
var _confirm_dialog_on_cancel: Callable = Callable()
var _online_turn_toast_last_player_id: int = -999
var _phase_toast_last_phase: String = ""

var _background_ui_warmup_started: bool = false
var _startup_profile_reported: bool = false

const AUTO_MANDATORY_ACTION_IDS := {
	ActionIdsClass.SET_PRICE: true,
	ActionIdsClass.SET_DISCOUNT: true,
	ActionIdsClass.SET_LUXURY_PRICE: true,
}

func _ready() -> void:
	var span_ready := PerfTraceClass.begin_span("game:_ready")
	GameLog.info("Game", "游戏场景已加载")

	# 初始化/读档可能耗时：确保加载遮罩至少绘制一帧，避免“卡住”的观感。
	var need_show_loading := true
	if SceneManager != null and SceneManager.has_method("is_loading_visible"):
		need_show_loading = not SceneManager.is_loading_visible()
	if need_show_loading and SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在进入游戏...")
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	var startup_replay_from_main_menu := false
	var startup_replay_path := ""

	# 主菜单入口：选择回放文件后，进入 Game 并自动打开回放播放器。
	if Globals != null:
		var p := str(Globals.pending_replay_file_path).strip_edges()
		if not p.is_empty():
			startup_replay_from_main_menu = true
			startup_replay_path = p
			Globals.pending_replay_file_path = ""

	var should_restore_log_history := false
	if Globals.current_game_engine != null and Globals.current_game_engine is GameEngine:
		var existing_engine: GameEngine = Globals.current_game_engine
		should_restore_log_history = existing_engine.get_state() != null

	if not should_restore_log_history and EventBus != null:
		EventBus.clear_history()

	var span_layout := PerfTraceClass.begin_span("game:layout+controllers_init")
	_apply_menu_dialog_styles()
	_layout_controller = GameLayoutControllerClass.new(
		self,
		round_label,
		phase_label,
		bank_label,
		current_player_label,
		toggle_left_panel_button,
		toggle_right_panel_button,
		toggle_bottom_panel_button,
		main_content,
		center_split,
		left_area,
		left_panel,
		game_log_panel,
		bottom_panel,
		$UIRoot/MainContent/CenterSplit/RightPanel,
		player_panel,
		inventory_panel
	)
	_apply_ui_layout()
	_init_left_panel_toggle()
	_init_right_panel_toggle()
	_init_right_panel_header()
	_init_right_panel_footer()

	_overlay_controller = GameOverlayControllerClass.new(self, map_view, map_canvas, game_log_panel)
	_overlay_controller.initialize()

	_map_controller = GameMapInteractionControllerClass.new(self, map_canvas, _overlay_controller)
	_map_controller.connect_signals()
	UiSignalHelpersClass.safe_connect(_map_controller, "mode_changed", _on_map_mode_changed)

	_panel_controller = GamePanelControllerClass.new(
		self,
		_map_controller,
		_overlay_controller,
		Callable(self, "_execute_command"),
		Callable(self, "_update_ui")
	)
	_panel_controller.connect_signals(action_panel, turn_order_track, hand_area, company_structure)

	_menu_debug_controller = GameMenuDebugControllerClass.new(self, menu_dialog)
	_save_load_controller = GameSaveLoadControllerClass.new(self, SaveLoadDialogScript, Callable(self, "_start_replay_from_file"))
	_right_panel_dock_controller = GameRightPanelDockControllerClass.new(
		Callable(self, "_ensure_right_panel_visible"),
		Callable(self, "_cancel_right_panel_docked_panel"),
		Callable(self, "toggle_game_log"),
		game_log_panel,
		right_panel_default_stack,
		right_panel_dock_host,
		right_panel_back_button,
		right_panel_title_label,
		right_panel_footer_row,
		right_panel_footer_cancel_button,
		right_panel_footer_secondary_button,
		right_panel_footer_primary_button
	)
	# M4.3：日志面板统一使用 step 时间线视图（由 StepTimelineBuild.build_full 重建），
	# 不再依赖 EventBus 订阅追加日志。
	_event_log_controller = null
	UiSignalHelpersClass.safe_connect(game_log_panel, "close_requested", toggle_game_log)

	_timeline_controller = GameTimelineControllerClass.new(
		self,
		game_log_panel,
		action_panel,
		Callable(self, "_get_game_engine"),
		Callable(self, "_set_active_game_engine"),
		Callable(self, "_update_ui"),
		Callable(self, "_show_confirm"),
		Callable(self, "_show_game_log_panel_in_right_panel"),
		Callable(self, "_open_replay_load_dialog"),
		Callable(self, "_is_online_resync_in_progress")
	)
	_timeline_controller.set_startup_replay_from_main_menu(startup_replay_from_main_menu)
	_timeline_controller.initialize()

	PerfTraceClass.end_span(span_layout)

	var span_init_game := PerfTraceClass.begin_span("game:_initialize_game")
	_initialize_game()
	PerfTraceClass.end_span(span_init_game)
	if game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())
		_online_resync_controller = GameOnlineResyncControllerClass.new(
			self,
			game_log_panel,
			Callable(self, "_get_game_engine"),
			Callable(_timeline_controller, "apply_live_log_timeline_from_engine"),
			Callable(self, "_update_ui"),
			Callable(self, "_reset_timeline_state_after_online_resync"),
			Callable(self, "_show_confirm"),
			Callable(self, "_goto_online_lobby")
		)
		_online_resync_controller.initialize()

	# 初始化调试面板
	_setup_debug_panel()
	DebugFlags.debug_panel_toggled.connect(_on_debug_panel_toggled)
	_on_debug_panel_toggled(DebugFlags.show_console)

	_init_bottom_panel_toggle()
	_init_left_area_resize()
	_apply_responsive_layout()
	UiSignalHelpersClass.safe_connect(self, "resized", _on_root_resized)
	if startup_replay_from_main_menu and not startup_replay_path.is_empty():
		# 回放入口：保持加载遮罩，避免先渲染“新开局”的 UI 再切换到回放造成闪烁。
		_start_replay_from_file(startup_replay_path)
	else:
		var span_update_ui := PerfTraceClass.begin_span("game:_update_ui(first)")
		_update_ui()
		PerfTraceClass.end_span(span_update_ui)
		_on_map_mode_changed("", {})

		# 若开局需要强制弹出“储备卡选择”，则保留加载遮罩直到弹窗真正打开，
		# 避免先露出一帧游戏 UI 再弹窗导致的闪烁体验。
		var keep_loading_until_reserve_modal := false
		if game_engine != null:
			var s := game_engine.get_state()
			if s != null and str(s.phase) == DefsClass.PHASE_SETUP and str(s.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
				keep_loading_until_reserve_modal = true
		if not keep_loading_until_reserve_modal:
			if SceneManager != null and SceneManager.has_method("hide_loading"):
				SceneManager.hide_loading()

		# 非关键面板后台预热（issue_tracker #71）：不阻塞首帧交互；未完成时打开面板显示“加载中...”。
		call_deferred("_start_background_ui_warmup")

	PerfTraceClass.end_span(span_ready)
	if PerfTraceClass.enabled() and not _startup_profile_reported:
		_startup_profile_reported = true
		call_deferred("_report_startup_profile")

func _apply_menu_dialog_styles() -> void:
	if is_instance_valid(menu_dialog):
		menu_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(menu_dialog_overlay):
		menu_dialog_overlay.color = Color(0, 0, 0, 0.62)
		menu_dialog_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStylesClass.apply_dialog_surface(menu_dialog_background_panel)
	UiStylesClass.apply_button_primary(menu_resume_button)
	UiStylesClass.apply_button_secondary(menu_save_button)
	UiStylesClass.apply_button_secondary(menu_settings_button)
	UiStylesClass.apply_button_secondary(toggle_bottom_panel_button)
	UiStylesClass.apply_button_secondary(menu_quit_to_menu_button)

func _report_startup_profile() -> void:
	# 让首帧/次帧的 deferred/UI queue 跑完，避免漏掉 MapSkin 构建等同步耗时的尾部。
	await get_tree().process_frame
	await get_tree().process_frame
	PerfTraceClass.report(20)

func _start_background_ui_warmup() -> void:
	if _background_ui_warmup_started:
		return
	_background_ui_warmup_started = true

	var span_warmup := PerfTraceClass.begin_span("game:background_ui_warmup")
	# 让游戏 UI 先进入可交互状态，再开始后台构建。
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	if game_engine == null or _panel_controller == null:
		return
	var state := game_engine.get_state()
	if state == null:
		return

	# 复用 MapCanvas 的 MapSkin；避免后台预热时触发 MapSkinBuilder 重复加载。
	var skin = null
	if is_instance_valid(map_canvas) and map_canvas.has_method("get_skin"):
		skin = map_canvas.call("get_skin")

	# 1) 升级路线（EmployeeTree）
	var tree = _panel_controller.call("get_employee_tree_panel") if _panel_controller.has_method("get_employee_tree_panel") else null
	if is_instance_valid(tree) and tree.has_method("begin_background_build"):
		var span_tree := PerfTraceClass.begin_span("warmup:employee_tree")
		tree.call("begin_background_build")
		if tree.has_signal("build_finished"):
			await tree.build_finished
		PerfTraceClass.end_span(span_tree)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	# 2) 里程碑全屏视图
	if skin != null:
		var ms = _panel_controller.call("get_milestone_full_screen_view") if _panel_controller.has_method("get_milestone_full_screen_view") else null
		if is_instance_valid(ms) and ms.has_method("begin_background_build"):
			var span_ms := PerfTraceClass.begin_span("warmup:milestones")
			ms.call("begin_background_build", state, skin)
			if ms.has_signal("build_finished"):
				await ms.build_finished
			PerfTraceClass.end_span(span_ms)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	# 3) 供应堆全屏视图
	if skin != null:
		var supply = _panel_controller.call("get_reserve_area_full_screen_view") if _panel_controller.has_method("get_reserve_area_full_screen_view") else null
		if is_instance_valid(supply) and supply.has_method("begin_background_build"):
			var span_supply := PerfTraceClass.begin_span("warmup:supply_pile")
			supply.call("begin_background_build", state, skin)
			if supply.has_signal("build_finished"):
				await supply.build_finished
			PerfTraceClass.end_span(span_supply)

	PerfTraceClass.end_span(span_warmup)

func _exit_tree() -> void:
	_dispose_runtime()

func _dispose_runtime() -> void:
	# 释放 RefCounted 控制器（避免 headless 测试退出时资源泄漏）
	if _event_log_controller != null and _event_log_controller.has_method("dispose"):
		_event_log_controller.dispose()
	_event_log_controller = null

	if _panel_controller != null and _panel_controller.has_method("dispose"):
		_panel_controller.dispose()
	_panel_controller = null

	if _map_controller != null and _map_controller.has_method("dispose"):
		_map_controller.dispose()
	_map_controller = null

	if _overlay_controller != null and _overlay_controller.has_method("dispose"):
		_overlay_controller.dispose()
	_overlay_controller = null

	if _menu_debug_controller != null and _menu_debug_controller.has_method("dispose"):
		_menu_debug_controller.dispose()
	_menu_debug_controller = null

	if _save_load_controller != null and _save_load_controller.has_method("dispose"):
		_save_load_controller.dispose()
	_save_load_controller = null

	if _layout_controller != null and _layout_controller.has_method("dispose"):
		_layout_controller.dispose()
	_layout_controller = null

	if _right_panel_dock_controller != null and _right_panel_dock_controller.has_method("dispose"):
		_right_panel_dock_controller.dispose()
	_right_panel_dock_controller = null

	if _online_resync_controller != null and _online_resync_controller.has_method("dispose"):
		_online_resync_controller.dispose()
	_online_resync_controller = null

	if _timeline_controller != null and _timeline_controller.has_method("dispose"):
		_timeline_controller.dispose()
	_timeline_controller = null

	if Globals != null and Globals.current_game_engine == game_engine:
		Globals.current_game_engine = null
	if Globals != null:
		Globals.is_game_active = false

	game_engine = null

func _on_root_resized() -> void:
	_apply_responsive_layout()

func _init_left_area_resize() -> void:
	if not is_instance_valid(main_content):
		return
	if not (main_content is SplitContainer):
		return
	var sc: SplitContainer = main_content
	if not sc.dragged.is_connected(_on_main_content_dragged):
		sc.dragged.connect(_on_main_content_dragged)

func _on_main_content_dragged(offset: int) -> void:
	if _layout_controller != null:
		_layout_controller.on_main_content_dragged(offset)

func _init_left_panel_toggle() -> void:
	if _layout_controller != null:
		_layout_controller.init_left_panel_toggle()

func _ensure_left_area_visible() -> void:
	if _layout_controller != null:
		_layout_controller.ensure_left_area_visible()

func _on_toggle_left_panel_pressed() -> void:
	if _layout_controller != null:
		_layout_controller.on_toggle_left_panel_pressed()

func _init_right_panel_toggle() -> void:
	if _layout_controller != null:
		_layout_controller.init_right_panel_toggle()

func _init_right_panel_header() -> void:
	if is_instance_valid(right_panel_back_button):
		if not right_panel_back_button.pressed.is_connected(_on_right_panel_back_pressed):
			right_panel_back_button.pressed.connect(_on_right_panel_back_pressed)
	if is_instance_valid(right_panel_close_button):
		if not right_panel_close_button.pressed.is_connected(_on_right_panel_close_pressed):
			right_panel_close_button.pressed.connect(_on_right_panel_close_pressed)
	_sync_right_panel_docked_view()

func _init_right_panel_footer() -> void:
	if is_instance_valid(right_panel_footer_cancel_button):
		if not right_panel_footer_cancel_button.pressed.is_connected(_on_right_panel_footer_cancel_pressed):
			right_panel_footer_cancel_button.pressed.connect(_on_right_panel_footer_cancel_pressed)
	if is_instance_valid(right_panel_footer_secondary_button):
		if not right_panel_footer_secondary_button.pressed.is_connected(_on_right_panel_footer_secondary_pressed):
			right_panel_footer_secondary_button.pressed.connect(_on_right_panel_footer_secondary_pressed)
	if is_instance_valid(right_panel_footer_primary_button):
		if not right_panel_footer_primary_button.pressed.is_connected(_on_right_panel_footer_primary_pressed):
			right_panel_footer_primary_button.pressed.connect(_on_right_panel_footer_primary_pressed)
	_sync_right_panel_docked_view()

func _ensure_right_panel_visible() -> void:
	if _layout_controller != null:
		_layout_controller.ensure_right_panel_visible()

func dock_popup_into_right_panel(panel: Control) -> bool:
	if _right_panel_dock_controller == null:
		return false
	return _right_panel_dock_controller.dock_popup(panel)

func _sync_right_panel_docked_view() -> void:
	if _right_panel_dock_controller != null:
		_right_panel_dock_controller.sync_docked_view()

func _on_right_panel_footer_cancel_pressed() -> void:
	if _right_panel_dock_controller != null:
		_right_panel_dock_controller.on_footer_cancel_pressed()

func _on_right_panel_footer_primary_pressed() -> void:
	if _right_panel_dock_controller != null:
		_right_panel_dock_controller.on_footer_primary_pressed()

func _on_right_panel_footer_secondary_pressed() -> void:
	if _right_panel_dock_controller != null:
		_right_panel_dock_controller.on_footer_secondary_pressed()

func _on_right_panel_back_pressed() -> void:
	if _right_panel_dock_controller != null:
		_right_panel_dock_controller.on_back_pressed()
		return
	_on_right_panel_footer_cancel_pressed()

func _on_right_panel_close_pressed() -> void:
	if _layout_controller != null and _layout_controller.is_right_panel_visible():
		_on_toggle_right_panel_pressed()

func _cancel_right_panel_docked_panel() -> void:
	if _panel_controller == null:
		return

	var map_mode_active := false
	if _map_controller != null and _map_controller.has_method("get_mode"):
		map_mode_active = not str(_map_controller.get_mode()).is_empty()

	if map_mode_active:
		if _panel_controller.has_method("hide_all"):
			_panel_controller.hide_all()
		return

	if _panel_controller.has_method("hide_all_keep_selection"):
		_panel_controller.hide_all_keep_selection()
	elif _panel_controller.has_method("hide_all"):
		_panel_controller.hide_all()

func _on_toggle_right_panel_pressed() -> void:
	if _layout_controller != null:
		await _layout_controller.on_toggle_right_panel_pressed()

func _apply_ui_layout() -> void:
	if _layout_controller != null:
		_layout_controller.apply_ui_layout()

func _init_bottom_panel_toggle() -> void:
	if _layout_controller != null:
		_layout_controller.init_bottom_panel_toggle()

func _on_toggle_bottom_panel_pressed() -> void:
	if _layout_controller != null:
		_layout_controller.on_toggle_bottom_panel_pressed()

func _apply_responsive_layout() -> void:
	if _layout_controller != null:
		_layout_controller.apply_responsive_layout()

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
	# 银行储备卡在进入游戏后由玩家秘密选择（Setup/ReserveCards），这里不从游戏设置注入选择结果。
	var logo_choices: Array[int] = []
	for pid in range(Globals.player_count):
		logo_choices.append(Globals.get_player_restaurant_logo_choice(pid))
	var init_result := game_engine.initialize(Globals.player_count, Globals.random_seed, Globals.enabled_modules_v2, Globals.modules_v2_base_dir, [], logo_choices)
	if not init_result.ok:
		GameLog.error("Game", "游戏初始化失败: %s" % init_result.error)
		return

	Globals.current_game_engine = game_engine
	Globals.is_game_active = true

	GameLog.info("Game", "游戏初始化完成 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])
	var dump_span := PerfTraceClass.begin_span("game:GameState.dump") if PerfTraceClass.enabled() else -1
	var state_dump := game_engine.get_state().dump()
	if PerfTraceClass.enabled():
		PerfTraceClass.end_span(dump_span)
	GameLog.info("Game", "初始状态:\n%s" % state_dump)

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
	var do_profile := PerfTraceClass.enabled() and not _startup_profile_reported
	round_label.text = "回合: %d" % state.round_number
	phase_label.text = "阶段: %s%s" % [
		state.phase,
		(" / %s" % state.sub_phase) if not state.sub_phase.is_empty() else ""
	]
	var pid := state.get_current_player_id()
	var current_name := Globals.get_player_name(pid) if pid >= 0 else "-"
	var view_id := pid
	if _panel_controller != null and _panel_controller.has_method("get_view_player_id"):
		var v := int(_panel_controller.call("get_view_player_id"))
		if v >= 0:
			view_id = v
	var view_name := Globals.get_player_name(view_id) if view_id >= 0 else "-"

	var head_index := game_engine.command_history.size() - 1
	var cursor_index := int(game_engine.current_command_index)
	var replay_suffix := ""
	if _timeline_controller != null:
		var hc = _timeline_controller.get_ui_head_cursor(game_engine)
		head_index = int(hc.x)
		cursor_index = int(hc.y)
		replay_suffix = _timeline_controller.get_ui_replay_suffix(game_engine, head_index, cursor_index)

	if state.phase == DefsClass.PHASE_RESTRUCTURING:
		var submitted_count := 0
		var total := state.players.size()
		if state.round_state is Dictionary:
			var r_val = state.round_state.get("restructuring", null)
			if r_val is Dictionary:
				var r: Dictionary = r_val
				var submitted_val = r.get("submitted", null)
				if submitted_val is Dictionary:
					var submitted: Dictionary = submitted_val
					for pid2 in range(total):
						var v2 = submitted.get(pid2, null)
						if v2 == null and submitted.has(str(pid2)):
							v2 = submitted.get(str(pid2), null)
						if bool(v2):
							submitted_count += 1

		current_player_label.text = "重组（同时）%s｜查看: %s｜提交: %d/%d" % [
			replay_suffix,
			view_name,
			submitted_count,
			total
		]
	else:
		current_player_label.text = "行动%s: %s｜查看: %s" % [
			replay_suffix,
			current_name,
			view_name
		]
	bank_label.text = "银行: $%d" % state.bank.get("total", 0)

	if is_instance_valid(game_log_panel) and game_log_panel.has_method("set_player_count"):
		game_log_panel.set_player_count(state.players.size())

	# 地图渲染（M2 接入）
	if is_instance_valid(map_view) and map_view.has_method("set_game_state"):
		var span_map := PerfTraceClass.begin_span("ui:map_view.set_game_state") if do_profile else -1
		map_view.call("set_game_state", state)
		if do_profile:
			PerfTraceClass.end_span(span_map)

	# UI 同步（面板/覆盖层）
	if _panel_controller != null:
		var span_panels := PerfTraceClass.begin_span("ui:panel_controller.sync") if do_profile else -1
		var force_refresh := false
		if _timeline_controller != null:
			force_refresh = bool(_timeline_controller.consume_force_full_panel_sync_next_update())
		_panel_controller.sync(state, force_refresh)
		_sync_right_panel_docked_view()
		if do_profile:
			PerfTraceClass.end_span(span_panels)
	if _overlay_controller != null:
		var span_overlays := PerfTraceClass.begin_span("ui:overlay_controller.sync") if do_profile else -1
		_overlay_controller.sync_dinnertime_overlay(state)
		_overlay_controller.sync_demand_indicator(state)
		if do_profile:
			PerfTraceClass.end_span(span_overlays)

	# 回放/复盘：日志时间线指针 + ReplayBar 显示 + ActionPanel 禁用
	if _timeline_controller != null:
		_timeline_controller.sync_timeline_ui(head_index, cursor_index, state)

	_maybe_show_online_turn_toast(head_index, cursor_index, state)
	_maybe_show_phase_change_toast(head_index, cursor_index, state)

	# 同步调试面板
	if _debug_panel != null and _debug_panel.visible:
		_debug_panel.refresh_state()

func _maybe_show_online_turn_toast(head_index: int, cursor_index: int, state: GameState) -> void:
	if OS.has_feature("headless"):
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		_online_turn_toast_last_player_id = -999
		return
	if _online_resync_controller != null and _online_resync_controller.is_resync_in_progress():
		return
	if state == null:
		return
	if _timeline_controller != null and (_timeline_controller.is_replay_mode_active() or _timeline_controller.is_history_step_timeline_active()):
		return
	if cursor_index < head_index:
		return
	if str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
		return

	var local_pid := int(NetContext.local_player_id)
	if local_pid < 0:
		return
	var current_pid := int(state.get_current_player_id())
	if current_pid < 0:
		return
	if current_pid == _online_turn_toast_last_player_id:
		return
	_online_turn_toast_last_player_id = current_pid

	if current_pid != local_pid:
		return

	if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
		_overlay_controller.show_toast("轮到你行动")

	var sm := SoundManager.get_instance()
	if sm != null and is_instance_valid(sm):
		# 占位：若资源缺失则静默；后续补齐 res://ui/audio/sfx/event_turn_start.(wav/ogg/mp3)
		sm.play(SoundManager.SOUND_TURN_START)

func _maybe_show_phase_change_toast(head_index: int, cursor_index: int, state: GameState) -> void:
	if OS.has_feature("headless"):
		return
	if state == null:
		return

	# 回放/复盘/时间线回退时会频繁切换阶段：避免刷屏，仅在“实时头部”显示。
	if _timeline_controller != null and (_timeline_controller.is_replay_mode_active() or _timeline_controller.is_history_step_timeline_active()):
		_phase_toast_last_phase = ""
		return
	if cursor_index < head_index:
		return

	var phase := str(state.phase).strip_edges()
	if phase.is_empty():
		return
	if _phase_toast_last_phase.is_empty():
		_phase_toast_last_phase = phase
		return
	if phase == _phase_toast_last_phase:
		return
	_phase_toast_last_phase = phase

	# 只提示大阶段；Working 内子阶段不提示（sub_phase 忽略）。
	var display_name = GameLogPanel.PHASE_DISPLAY_NAMES.get(phase, phase)
	var msg := "进入阶段：%s" % str(display_name)
	if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
		_overlay_controller.show_toast(msg)

func _on_debug_command_executed(command: String, _result: String) -> void:
	# undo/redo/restore/load 会“改写时间线”；
	# M4.3：日志面板统一使用 step_timeline，因此时间线变化后需要重建 step_timeline 视图。
	var cmd := str(command).strip_edges()
	var head := cmd.split(" ", false, 1)[0] if not cmd.is_empty() else ""
	var is_timeline_change := (head == "undo" or head == "redo" or head == "restore" or head == "load")

	# 避免时间线变化后仍停留在旧面板/选点上下文导致“看起来没回退”；
	# 不再强制 hide：保持面板打开，但下一帧强制从 state 全量同步，避免残留旧 UI 缓存。
	if is_timeline_change:
		if _timeline_controller != null:
			_timeline_controller.request_force_full_panel_sync_next_update()
			_timeline_controller.apply_live_log_timeline_from_engine()
			# 调试面板的 undo/redo 需要进入“时间线编辑模式”，否则 undo 后 UI 会处于只读态导致无法继续操作。
			if head == "undo" or head == "redo":
				_timeline_controller.set_timeline_edit_mode_active(true)

	# 调试命令执行后刷新游戏 UI
	_update_ui()

func rewind_to_turn_start() -> void:
	if game_engine == null:
		return
	if _timeline_controller != null and _timeline_controller.is_replay_mode_active():
		GameLog.warn("Game", "回放模式下无法回退回合")
		return

	var idx_r: Result = game_engine.find_current_player_turn_start_command_index()
	if not idx_r.ok:
		GameLog.warn("Game", "计算回合开始索引失败: %s" % idx_r.error)
		return

	var target_index := int(idx_r.value)
	var current_index := int(game_engine.current_command_index)
	if target_index >= current_index:
		return

	var state := game_engine.get_state()
	var pid := state.get_current_player_id()
	var phase_name := str(state.phase)
	var steps := current_index - target_index

	_show_confirm(
		"回退到回合开始",
		"确定要回退到当前玩家（P%d）的回合开始吗？\n将撤销从该回合开始以来的 %d 步操作。\n（阶段：%s）" % [pid + 1, steps, phase_name],
		Callable(self, "_confirm_rewind_to_turn_start").bind(target_index),
		Callable(),
		"回退",
		"取消"
	)

func _confirm_rewind_to_turn_start(target_index: int) -> void:
	if game_engine == null:
		return

	# 联机：回退必须由 server 执行并广播（否则会导致各客户端状态不一致）。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		if _online_resync_controller == null:
			GameLog.warn("Game", "联机模式下回退失败：控制器未就绪")
			return
		# 避免重复触发（例如用户连续点击）
		if _online_resync_controller.is_resync_in_progress():
			return
		_online_resync_controller.begin_rewind_to_turn_start_request()
		return

	var result := game_engine.rewind_to_command(target_index)
	if not result.ok:
		GameLog.warn("Game", "回退到回合开始失败: %s" % result.error)
	else:
		if _timeline_controller != null:
			_timeline_controller.set_timeline_edit_mode_active(true)
			_timeline_controller.request_force_full_panel_sync_next_update()
			_timeline_controller.apply_live_log_timeline_from_engine()
	_update_ui()

func _execute_command(command: Command) -> Result:
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")
	if _timeline_controller != null and _timeline_controller.is_replay_mode_active():
		return Result.failure("回放模式下无法执行命令")

	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		if _online_resync_controller == null:
			return Result.failure("联机同步未就绪")
		return _online_resync_controller.try_send_online_action(command)

	var head_index := game_engine.command_history.size() - 1
	var was_in_history := int(game_engine.current_command_index) < head_index
	var can_edit_timeline = (_timeline_controller != null and _timeline_controller.is_timeline_edit_mode_active())
	if was_in_history and not can_edit_timeline:
		return Result.failure("查看历史中无法执行命令（请先返回最新）")

	var auto := _maybe_auto_complete_mandatory_actions_before_skip(command)
	if auto is Result and not auto.ok:
		GameLog.warn("Game", "自动完成强制动作失败: %s" % auto.error)
		_update_ui()
		return auto

	var result := game_engine.execute_command(command)
	if not result.ok:
		GameLog.warn("Game", "命令执行失败: %s" % result.error)
		_maybe_show_payday_blocker_prompt(command, result)
	else:
		GameLog.info("Game", "命令执行成功: %s" % command.action_id)
		# 时间线被回退过时，执行新命令会截断未来时间线并生成新分支：需要重建 step_timeline 视图，避免 UI 仍引用旧 head。
		# 其它情况下：仅在日志面板可见时重建（降低每步全量回放开销）。
		if was_in_history or (is_instance_valid(game_log_panel) and game_log_panel.visible):
			if _timeline_controller != null:
				_timeline_controller.apply_live_log_timeline_from_engine()
		if was_in_history and _timeline_controller != null:
			_timeline_controller.set_timeline_edit_mode_active(false)

	_update_ui()
	return result

func _get_last_working_sub_phase_name() -> String:
	var last_sub_phase := DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if game_engine != null and game_engine.phase_manager != null and game_engine.phase_manager.has_method("get_working_sub_phase_order_names"):
		var order = game_engine.phase_manager.get_working_sub_phase_order_names()
		if order is Array and not order.is_empty():
			last_sub_phase = str(order[order.size() - 1])
	return last_sub_phase

func _maybe_auto_complete_mandatory_actions_before_skip(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if str(command.action_id).strip_edges() != ActionIdsClass.SKIP:
		return Result.success()
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")

	var state: GameState = game_engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")
	if str(state.phase) != DefsClass.PHASE_WORKING:
		return Result.success()
	if str(state.sub_phase) != _get_last_working_sub_phase_name():
		return Result.success()

	var current_player_id := state.get_current_player_id()
	if int(command.actor) != int(current_player_id):
		return Result.success()

	var player := state.get_player(current_player_id)
	var required := MandatoryActionsRulesClass.get_required_mandatory_actions(player)
	if required.is_empty():
		return Result.success()

	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has("mandatory_actions_completed"):
		return Result.failure("round_state.mandatory_actions_completed 缺失")
	var mac_val = state.round_state["mandatory_actions_completed"]
	if not (mac_val is Dictionary):
		return Result.failure("round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mac: Dictionary = mac_val
	if not mac.has(current_player_id):
		return Result.failure("mandatory_actions_completed 缺少玩家 key: %d" % current_player_id)
	var completed_val = mac[current_player_id]
	if not (completed_val is Array):
		return Result.failure("mandatory_actions_completed[%d] 类型错误（期望 Array）" % current_player_id)
	var completed: Array = completed_val

	var missing: Array[String] = []
	for action_id in required:
		var aid := str(action_id).strip_edges()
		if aid.is_empty():
			continue
		if not AUTO_MANDATORY_ACTION_IDS.has(aid):
			continue
		if completed.has(aid):
			continue
		missing.append(aid)

	for aid2 in missing:
		var cmd := Command.create(str(aid2), current_player_id, {"auto": true})
		var r := game_engine.execute_command(cmd)
		if not r.ok:
			return Result.failure("自动执行强制动作失败(%s): %s" % [aid2, r.error])

	return Result.success()

func _maybe_show_payday_blocker_prompt(_command: Command, result: Result) -> void:
	if result == null or result.ok:
		return
	if OS.has_feature("headless"):
		return
	if game_engine == null:
		return

	var state := game_engine.get_state()
	if state == null:
		return
	if str(state.phase) != DefsClass.PHASE_PAYDAY:
		return

	var err := str(result.error).strip_edges()
	if err.is_empty():
		return
	if err.find("薪水不足") == -1:
		return

	if _panel_controller != null and _panel_controller.has_method("show_payday_panel"):
		_panel_controller.call("show_payday_panel")

	_show_confirm(
		"无法结束发薪日",
		"%s\n\n请在发薪日解雇员工以支付薪资，然后再确认结束。" % err,
		Callable(self, "_open_payday_panel_from_prompt"),
		Callable(),
		"打开发薪日",
		"知道了"
	)

func _open_payday_panel_from_prompt() -> void:
	if _panel_controller != null and _panel_controller.has_method("show_payday_panel"):
		_panel_controller.call("show_payday_panel")

func _on_advance_phase_pressed() -> void:
	_execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))

func _on_advance_sub_phase_pressed() -> void:
	_execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"}))

func _on_skip_pressed() -> void:
	if game_engine == null:
		return
	if bool(Globals.confirm_actions):
		_show_confirm(
			"确认结束",
			"确定要结束当前阶段/子阶段吗？",
			Callable(self, "_confirm_skip")
		)
		return
	_confirm_skip()

func _confirm_skip() -> void:
	if game_engine == null:
		return
	var current_player_id := game_engine.get_state().get_current_player_id()
	_execute_command(Command.create(ActionIdsClass.SKIP, current_player_id))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e: InputEventKey = event
		if not e.pressed or e.echo:
			return

		match e.keycode:
			KEY_ESCAPE:
				if _handle_escape():
					accept_event()
					return
				_on_menu_pressed()
				accept_event()
			KEY_ENTER, KEY_KP_ENTER:
				var handled := false
				if e.shift_pressed:
					handled = _try_trigger_right_panel_footer_secondary()
				else:
					handled = _try_trigger_right_panel_footer_primary()
				if handled:
					accept_event()
			KEY_D:
				toggle_distance_tool()
				accept_event()
			KEY_R:
				if _try_rotate_placement():
					accept_event()

func _try_trigger_right_panel_footer_primary() -> bool:
	if not is_instance_valid(right_panel_footer_row) or not right_panel_footer_row.visible:
		return false
	if not is_instance_valid(right_panel_footer_primary_button) or not right_panel_footer_primary_button.visible:
		return false
	if right_panel_footer_primary_button.disabled:
		return false
	_on_right_panel_footer_primary_pressed()
	return true

func _try_trigger_right_panel_footer_secondary() -> bool:
	if not is_instance_valid(right_panel_footer_row) or not right_panel_footer_row.visible:
		return false
	if not is_instance_valid(right_panel_footer_secondary_button) or not right_panel_footer_secondary_button.visible:
		return false
	if right_panel_footer_secondary_button.disabled:
		return false
	_on_right_panel_footer_secondary_pressed()
	return true

func _handle_escape() -> bool:
	# 关闭顶层对话框
	if is_instance_valid(menu_dialog) and menu_dialog.visible:
		_on_menu_dialog_close_requested()
		return true
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog) and _confirm_dialog.visible:
		if _confirm_dialog.has_method("_on_cancel_pressed"):
			_confirm_dialog.call("_on_cancel_pressed")
		else:
			_confirm_dialog.hide()
		return true

	if _overlay_controller != null:
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
			if dlg.has_method("_on_close_pressed"):
				dlg.call("_on_close_pressed")
			else:
				dlg.hide()
			return true

	# 关闭全屏浏览视图（例如里程碑/保留区），避免影响底层面板/选中状态。
	if _panel_controller != null and _panel_controller.has_method("hide_top_overlays_if_open"):
		var closed = _panel_controller.call("hide_top_overlays_if_open")
		if closed is bool and bool(closed):
			return true

	# 关闭阶段面板/取消地图模式
	if _panel_controller != null:
		var map_mode_active := (_map_controller != null and not str(_map_controller.get_mode()).is_empty())
		if map_mode_active:
			_panel_controller.hide_all()
			return true
		if _panel_controller.has_open_phase_ui():
			if _panel_controller.has_method("hide_all_keep_selection"):
				_panel_controller.hide_all_keep_selection()
			else:
				_panel_controller.hide_all()
			return true

	return false

func _try_rotate_placement() -> bool:
	# 若有顶层对话框，优先不处理
	if is_instance_valid(menu_dialog) and menu_dialog.visible:
		return false
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog) and _confirm_dialog.visible:
		return false
	if _overlay_controller != null:
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
			return false

	if _map_controller == null:
		return false
	var mode := str(_map_controller.get_mode())

	if mode == "restaurant_placement":
		var ov = _map_controller.restaurant_placement_overlay
		if is_instance_valid(ov) and ov.visible and ov.has_method("rotate_cw"):
			ov.rotate_cw()
			return true
	if mode == "house_placement":
		var ov2 = _map_controller.house_placement_overlay
		if is_instance_valid(ov2) and ov2.visible and ov2.has_method("rotate_cw"):
			ov2.rotate_cw()
			return true

	return false

func _on_map_mode_changed(mode: String, payload: Dictionary) -> void:
	if not is_instance_valid(map_mode_bar):
		return

	var m := str(mode)
	if m.is_empty():
		map_mode_bar.hide_mode()
		return

	match m:
		"marketing":
			var mt := str(payload.get("marketing_type", ""))
			var title := "📍 营销放置" if mt.is_empty() else "📍 营销放置：%s" % mt
			var hint := "点击地图选择位置｜ESC 取消"
			if mt == "airplane":
				hint = "点击地图边缘选择位置｜角落需选择横/竖飞｜ESC 取消"
			map_mode_bar.show_mode(title, hint)
		"restaurant_placement":
			var action_id := str(payload.get("action_id", ""))
			var title2 := "🏪 放置餐厅" if action_id != "move_restaurant" else "🏪 移动餐厅"
			map_mode_bar.show_mode(title2, "点击地图选择位置｜R 旋转｜右侧确认/取消｜ESC 取消")
		"house_placement":
			var action_id2 := str(payload.get("action_id", ""))
			var title3 := "🏠 放置房屋" if action_id2 != "add_garden" else "🌳 添加花园"
			if action_id2 == "add_garden":
				map_mode_bar.show_mode(title3, "点击地图选择房屋｜右侧选择方向并确认｜ESC 取消")
			else:
				map_mode_bar.show_mode(title3, "点击地图选择位置｜R 旋转｜右侧确认/取消｜ESC 取消")
		"distance_tool":
			map_mode_bar.show_mode("📏 距离工具", "只允许点道路格｜点起点再点终点｜测完点任意道路格重开｜D/ESC 关闭")
		_:
			map_mode_bar.show_mode("模式：%s" % m, "ESC 取消")

func _on_log_button_pressed() -> void:
	toggle_game_log()

func _on_left_panel_logs_requested() -> void:
	toggle_game_log()

func _on_milestones_button_pressed() -> void:
	show_milestone_panel()

func _on_reserve_area_button_pressed() -> void:
	if _panel_controller != null and _panel_controller.has_method("show_reserve_area_panel"):
		_panel_controller.call("show_reserve_area_panel")

func _on_employee_tree_button_pressed() -> void:
	if _panel_controller != null and _panel_controller.has_method("toggle_employee_tree"):
		_panel_controller.toggle_employee_tree()

func _on_distance_tool_button_pressed() -> void:
	toggle_distance_tool()

func _on_settings_button_pressed() -> void:
	show_settings_dialog()

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
	if _save_load_controller != null:
		_save_load_controller.open_for_save(game_engine)
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
	if _save_load_controller != null:
		_save_load_controller.open_for_replay()
	_on_menu_dialog_close_requested()

func _on_quit_to_menu_pressed() -> void:
	_on_menu_dialog_close_requested()
	_show_confirm(
		"返回主菜单",
		"确定要返回主菜单吗？\n未保存的进度将丢失。",
		Callable(self, "_confirm_quit_to_menu"),
		Callable(self, "_cancel_quit_to_menu")
	)

# === 确认弹窗（P2）===

func _show_confirm(title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable(), confirm_text: String = "确认", cancel_text: String = "取消") -> void:
	if _confirm_dialog == null or not is_instance_valid(_confirm_dialog):
		_confirm_dialog = ConfirmDialogScene.instantiate()
		add_child(_confirm_dialog)
		_confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
		_confirm_dialog.cancelled.connect(_on_confirm_dialog_cancelled)

	_confirm_dialog_on_confirm = on_confirm
	_confirm_dialog_on_cancel = on_cancel
	_confirm_dialog.setup(title, message, confirm_text, cancel_text)
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

# === 时间线/回放（由 GameTimelineController 负责）===

func _get_game_engine() -> GameEngine:
	return game_engine

func _set_active_game_engine(engine: GameEngine) -> void:
	if engine == null:
		return

	game_engine = engine
	if Globals != null:
		Globals.current_game_engine = engine
		Globals.is_game_active = true

	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.set_game_engine(game_engine)

	if _panel_controller != null and game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

func _open_replay_load_dialog() -> void:
	if _save_load_controller != null:
		_save_load_controller.open_for_replay()

func _is_online_resync_in_progress() -> bool:
	if _online_resync_controller == null:
		return false
	if _online_resync_controller.has_method("is_resync_in_progress"):
		return bool(_online_resync_controller.call("is_resync_in_progress"))
	return false

func _reset_timeline_state_after_online_resync() -> void:
	if _timeline_controller != null:
		_timeline_controller.set_timeline_edit_mode_active(false)
		_timeline_controller.request_force_full_panel_sync_next_update()

func _goto_online_lobby() -> void:
	if SceneManager != null and SceneManager.has_method("goto_online_lobby"):
		SceneManager.goto_online_lobby()

func _start_replay_from_file(file_path: String) -> void:
	if _timeline_controller != null:
		_timeline_controller.start_replay_from_file(file_path)

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

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String, extra: Dictionary = {}) -> void:
	if _overlay_controller != null:
		_overlay_controller.preview_marketing_range(position, range_val, marketing_type, extra)

func show_milestone_panel() -> void:
	if _panel_controller != null:
		_panel_controller.show_milestone_panel()

func toggle_game_log() -> void:
	if not is_instance_valid(game_log_panel):
		return

	var show_logs: bool = not bool(game_log_panel.visible)
	if show_logs:
		# 玩家信息与日志需要同屏：确保左侧信息区可见，同时确保右侧面板可见以承载日志。
		_ensure_left_area_visible()
		_ensure_right_panel_visible()

		# M4.3：打开日志时，按当前引擎状态重建 step 时间线视图（保证实时/回放一致）。
		if _timeline_controller != null:
			_timeline_controller.apply_live_log_timeline_from_engine()

		# 若右侧已有 docked 操作面板/弹窗，先关闭它们，避免日志被遮挡或出现多个 docked 视图竞争焦点。
		var has_other_docked := false
		if is_instance_valid(right_panel_dock_host):
			for ch in right_panel_dock_host.get_children():
				if ch == game_log_panel:
					continue
				if ch is Control and (ch as Control).visible:
					has_other_docked = true
					break
		if has_other_docked:
			_cancel_right_panel_docked_panel()
			_sync_right_panel_docked_view()

		# 将日志面板嵌入到 RightPanel 抽屉区域（覆盖 ActionPanel），并显示。
		game_log_panel.set_meta("popup_title", "日志")
		dock_popup_into_right_panel(game_log_panel)
	else:
		# 关闭日志：返回默认右侧动作区。
		game_log_panel.visible = false
		_sync_right_panel_docked_view()

func _show_game_log_panel_in_right_panel() -> void:
	# 回放/复盘默认显示日志：避免 ReplayBar/时间线功能“藏在被关闭的面板里”。
	if not is_instance_valid(game_log_panel):
		return

	# 已在 RightPanel 抽屉中显示
	if game_log_panel.visible and is_instance_valid(right_panel_dock_host) and game_log_panel.get_parent() == right_panel_dock_host:
		return

	_ensure_left_area_visible()
	_ensure_right_panel_visible()

	# 若右侧已有 docked 操作面板/弹窗，先关闭它们，避免多个 docked 视图竞争焦点。
	var has_other_docked := false
	if is_instance_valid(right_panel_dock_host):
		for ch in right_panel_dock_host.get_children():
			if ch == game_log_panel:
				continue
			if ch is Control and (ch as Control).visible:
				has_other_docked = true
				break
	if has_other_docked:
		_cancel_right_panel_docked_panel()
		_sync_right_panel_docked_view()

	game_log_panel.set_meta("popup_title", "日志")
	dock_popup_into_right_panel(game_log_panel)

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
