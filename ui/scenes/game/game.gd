# 游戏主场景脚本（协调器）
# 说明：将原先巨型脚本拆分为多个控制器，主脚本只做节点绑定与编排。
extends Control

# UI 节点引用
@onready var status_bar: PanelContainer = $UIRoot/TopBar/StatusBar
@onready var round_label: Label = $UIRoot/TopBar/StatusBar/StatusContent/RoundSection/RoundValueLabel
@onready var phase_track: Control = $UIRoot/TopBar/StatusBar/StatusContent/PhaseTrack
@onready var turn_order_display: Control = $UIRoot/MainContent/CenterSplit/GameArea/TurnOrderOverlay/TurnOrderDisplay
@onready var bank_label: Label = $UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankValueLabel
@onready var bank_break_tag: Label = $UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankBreakTag
@onready var toggle_left_panel_button: Button = $UIRoot/TopBar/ToggleLeftPanelButton
@onready var toggle_right_panel_button: Button = $UIRoot/TopBar/ToggleRightPanelButton
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
@onready var background: ColorRect = $Background
@onready var vignette_overlay: ColorRect = $VignetteOverlay

# 新 UI 组件引用
@onready var right_panel_header_row: Control = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow
@onready var right_panel_back_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow/BackButton
@onready var right_panel_title_label: Label = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow/TitleLabel
@onready var right_panel_close_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/HeaderRow/CloseButton
@onready var right_panel_default_stack: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack
@onready var right_panel_dock_host: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DockHost
@onready var right_panel_footer_row: Control = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow
@onready var right_panel_footer_cancel_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/CancelButton
@onready var right_panel_footer_secondary_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/SecondaryButton
@onready var right_panel_footer_primary_button: Button = $UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/PrimaryButton
@onready var action_flow_controls: Control = $UIRoot/MainContent/CenterSplit/RightPanel/ActionFlowControls

@onready var player_panel: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/PlayerPanel
@onready var turn_order_track: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/TurnOrderTrack
@onready var inventory_panel: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/InventoryPanel
@onready var action_panel: Control = $UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/ActionPanel
@onready var hand_area: Control = $UIRoot/BottomPanel/HandArea
@onready var company_structure: Control = $UIRoot/BottomPanel/CompanyStructure
@onready var bottom_panel: Control = $UIRoot/BottomPanel

const GameMenuDebugControllerClass = preload("res://ui/scenes/game/game_menu_debug_controller.gd")
const GameMenuControllerClass = preload("res://ui/scenes/game/game_menu_controller.gd")
const GameSaveLoadControllerClass = preload("res://ui/scenes/game/game_save_load_controller.gd")
const GameLayoutControllerClass = preload("res://ui/scenes/game/game_layout_controller.gd")
const GameRightPanelDockControllerClass = preload("res://ui/scenes/game/game_right_panel_dock_controller.gd")
const GameUiSyncControllerClass = preload("res://ui/scenes/game/game_ui_sync_controller.gd")
const GameCommandControllerClass = preload("res://ui/scenes/game/game_command_controller.gd")
const GameInputControllerClass = preload("res://ui/scenes/game/game_input_controller.gd")
const GameLogDockControllerClass = preload("res://ui/scenes/game/game_log_dock_controller.gd")
const GameBackgroundWarmupControllerClass = preload("res://ui/scenes/game/game_background_warmup_controller.gd")
const GameDebugPanelControllerClass = preload("res://ui/scenes/game/game_debug_panel_controller.gd")
const GameOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_controller.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")
const GameMapModeBarControllerClass = preload("res://ui/scenes/game/game_map_mode_bar_controller.gd")
const GamePanelControllerClass = preload("res://ui/scenes/game/game_panel_controller.gd")
const GameOnlineResyncControllerClass = preload("res://ui/scenes/game/game_online_resync_controller.gd")
const GameTimelineControllerClass = preload("res://ui/scenes/game/game_timeline_controller.gd")
const DebugPanelScene = preload("res://ui/scenes/debug/debug_panel.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const DrinksProcurementInputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

# 游戏状态
var game_engine: GameEngine = null

# 控制器
var _menu_debug_controller = null
var _menu_controller = null
var _save_load_controller = null
var _layout_controller = null
var _right_panel_dock_controller = null
var _overlay_controller = null
var _map_controller = null
var _map_mode_bar_controller = null
var _panel_controller = null
var _online_resync_controller = null
var _timeline_controller = null
var _ui_sync_controller = null
var _command_controller = null
var _input_controller = null
var _log_dock_controller = null
var _warmup_controller = null
var _debug_panel_controller = null
var _startup_profile_reported: bool = false

var _procurement_log_preview_pinned_entry_id: int = -1
var _procurement_log_preview_hover_entry_id: int = -1
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
	UiStylesClass.apply_tiled_texture(background, UiStylesClass.WALL_TEXTURE_PATHS, 3.0, Color(0.85, 0.80, 0.68, 1.0))
	UiStylesClass.apply_vignette(vignette_overlay, 0.25, 0.5)
	_apply_menu_dialog_styles()
	_apply_topbar_button_styles()
	_apply_status_bar_styles()
	_layout_controller = GameLayoutControllerClass.new(
		self,
		round_label,
		phase_track,
		bank_label,
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
	_map_mode_bar_controller = GameMapModeBarControllerClass.new(map_mode_bar)
	UiSignalHelpersClass.safe_connect(_map_controller, "mode_changed", Callable(_map_mode_bar_controller, "on_map_mode_changed"))

	_panel_controller = GamePanelControllerClass.new(
		self,
		_map_controller,
		_overlay_controller,
		Callable(self, "_execute_command"),
		Callable(self, "_update_ui")
	)
	_panel_controller.connect_signals(action_panel, action_flow_controls, turn_order_track, hand_area, company_structure)
	_warmup_controller = GameBackgroundWarmupControllerClass.new(self, Callable(self, "_get_game_engine"), _panel_controller, map_canvas)

	_menu_debug_controller = GameMenuDebugControllerClass.new(self, menu_dialog)
	_save_load_controller = GameSaveLoadControllerClass.new(self, SaveLoadDialogScript, Callable(self, "_start_replay_from_file"))
	_menu_controller = GameMenuControllerClass.new(
		self,
		_menu_debug_controller,
		menu_dialog,
		ConfirmDialogScene,
		_save_load_controller,
		Callable(self, "_get_game_engine"),
		Callable(self, "show_settings_dialog"),
		Callable(self, "toggle_game_log"),
		Callable(self, "show_milestone_panel"),
		Callable(self, "toggle_distance_tool"),
		Callable(self, "_can_open_menu")
	)
	_right_panel_dock_controller = GameRightPanelDockControllerClass.new(
		Callable(self, "_ensure_right_panel_visible"),
		Callable(self, "_cancel_right_panel_docked_panel"),
		Callable(self, "toggle_game_log"),
		game_log_panel,
		right_panel_default_stack,
		right_panel_dock_host,
		right_panel_header_row,
		right_panel_back_button,
		right_panel_title_label,
		right_panel_footer_row,
		right_panel_footer_cancel_button,
		right_panel_footer_secondary_button,
		right_panel_footer_primary_button
	)
	_input_controller = GameInputControllerClass.new(
		_menu_controller,
		_overlay_controller,
		_panel_controller,
		_map_controller,
		_right_panel_dock_controller,
		right_panel_footer_row,
		right_panel_footer_secondary_button,
		right_panel_footer_primary_button
	)
	# M4.3：日志面板统一使用 step 时间线视图（由 StepTimelineBuild.build_full 重建），
	# 不再依赖 EventBus 订阅追加日志。
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
	UiSignalHelpersClass.safe_connect(game_log_panel, "replay_toggle_changed", Callable(self, "_on_game_log_replay_toggle_changed"))
	UiSignalHelpersClass.safe_connect(game_log_panel, "log_entry_hovered", Callable(self, "_on_game_log_entry_hovered"))
	UiSignalHelpersClass.safe_connect(game_log_panel, "log_entry_clicked", Callable(self, "_on_game_log_entry_clicked_for_map_preview"))

	_log_dock_controller = GameLogDockControllerClass.new(
		Callable(self, "_ensure_left_area_visible"),
		Callable(self, "_ensure_right_panel_visible"),
		Callable(self, "_cancel_right_panel_docked_panel"),
		Callable(self, "_sync_right_panel_docked_view"),
		Callable(self, "dock_popup_into_right_panel"),
		game_log_panel,
		right_panel_dock_host,
		_timeline_controller
	)

	_ui_sync_controller = GameUiSyncControllerClass.new(
		Callable(self, "_get_game_engine"),
		Callable(self, "_update_ui"),
		Callable(self, "_sync_right_panel_docked_view"),
		round_label,
		phase_track,
		bank_label,
		bank_break_tag,
		game_log_panel,
		map_view,
		_panel_controller,
		_overlay_controller,
		_timeline_controller
	)

	_debug_panel_controller = GameDebugPanelControllerClass.new(
		self,
		DebugPanelScene,
		Callable(self, "_get_game_engine"),
		Callable(self, "_on_debug_command_executed"),
		_ui_sync_controller
	)

	_command_controller = GameCommandControllerClass.new(
		Callable(self, "_get_game_engine"),
		Callable(self, "_update_ui"),
		Callable(self, "_show_confirm"),
		_timeline_controller,
		_panel_controller,
		game_log_panel
	)

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
		if _ui_sync_controller != null and _ui_sync_controller.has_method("set_online_resync_controller"):
			_ui_sync_controller.set_online_resync_controller(_online_resync_controller)
		if _command_controller != null and _command_controller.has_method("set_online_resync_controller"):
			_command_controller.set_online_resync_controller(_online_resync_controller)

	# 初始化调试面板
	if _debug_panel_controller != null and _debug_panel_controller.has_method("setup_debug_panel"):
		_debug_panel_controller.call("setup_debug_panel")
	if DebugFlags != null and _debug_panel_controller != null:
		UiSignalHelpersClass.safe_connect(DebugFlags, "debug_panel_toggled", Callable(_debug_panel_controller, "on_debug_panel_toggled"))
		if _debug_panel_controller.has_method("on_debug_panel_toggled"):
			_debug_panel_controller.call("on_debug_panel_toggled", DebugFlags.show_console)

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
		if _map_mode_bar_controller != null and _map_mode_bar_controller.has_method("on_map_mode_changed"):
			_map_mode_bar_controller.call("on_map_mode_changed", "", {})

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
		menu_dialog.z_index = 1200
	if is_instance_valid(menu_dialog_overlay):
		menu_dialog_overlay.color = Color(0.05, 0.04, 0.03, 0.75)
		menu_dialog_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStylesClass.apply_dialog_surface(menu_dialog_background_panel)
	UiStylesClass.apply_button_primary(menu_resume_button)
	UiStylesClass.apply_button_primary(menu_save_button)
	UiStylesClass.apply_button_primary(menu_settings_button)
	UiStylesClass.apply_button_primary(toggle_bottom_panel_button)
	UiStylesClass.apply_button_primary(menu_quit_to_menu_button)

func _apply_topbar_button_styles() -> void:
	var button_paths := [
		"UIRoot/TopBar/AdvancePhaseButton",
		"UIRoot/TopBar/AdvanceSubPhaseButton",
		"UIRoot/TopBar/ToggleLeftPanelButton",
		"UIRoot/TopBar/ToggleRightPanelButton",
		"UIRoot/TopBar/MenuButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/EmployeeTreeButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/LogButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/MilestonesButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/ReserveAreaButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/DistanceToolButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/SettingsButton",
	]
	for path in button_paths:
		var btn = get_node_or_null(path)
		if btn is Button:
			UiStylesClass.apply_button_secondary(btn)

func _apply_status_bar_styles() -> void:
	UiStylesClass.apply_status_panel(status_bar)
	UiStylesClass.apply_break_tag(bank_break_tag)
	# Icon labels - accent colors
	var icon_styles: Array[Array] = [
		["UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankIconLabel", Color(0.72, 0.62, 0.25)],
		["UIRoot/TopBar/StatusBar/StatusContent/RoundSection/RoundIconLabel", Color(0.35, 0.55, 0.75)],
	]
	for entry in icon_styles:
		var lbl = get_node_or_null(str(entry[0]))
		if lbl is Label:
			(lbl as Label).add_theme_color_override("font_color", entry[1] as Color)
			(lbl as Label).add_theme_font_size_override("font_size", 17)
	# Bank title label - same size as value labels
	var title_lbl = get_node_or_null("UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankTitleLabel")
	if title_lbl is Label:
		UiStylesClass.apply_label_dark(title_lbl)
		(title_lbl as Label).add_theme_font_size_override("font_size", 17)
	# Value labels - primary, larger
	for lbl in [round_label, bank_label]:
		if lbl is Label:
			UiStylesClass.apply_label_dark(lbl)
			(lbl as Label).add_theme_font_size_override("font_size", 17)
	# Phase track - 自定义绘制，初始字号
	if is_instance_valid(phase_track) and phase_track.has_method("set_font_size"):
		phase_track.set_font_size(16)

func _report_startup_profile() -> void:
	# 让首帧/次帧的 deferred/UI queue 跑完，避免漏掉 MapSkin 构建等同步耗时的尾部。
	await get_tree().process_frame
	await get_tree().process_frame
	PerfTraceClass.report(20)

func _start_background_ui_warmup() -> void:
	if _warmup_controller != null and _warmup_controller.has_method("start_background_ui_warmup"):
		await _warmup_controller.start_background_ui_warmup()

func _exit_tree() -> void:
	_dispose_runtime()

func _dispose_runtime() -> void:
	# 释放 RefCounted 控制器（避免 headless 测试退出时资源泄漏）
	if _panel_controller != null and _panel_controller.has_method("dispose"):
		_panel_controller.dispose()
	_panel_controller = null

	if _map_controller != null and _map_controller.has_method("dispose"):
		_map_controller.dispose()
	_map_controller = null

	if _overlay_controller != null and _overlay_controller.has_method("dispose"):
		_overlay_controller.dispose()
	_overlay_controller = null

	if _input_controller != null and _input_controller.has_method("dispose"):
		_input_controller.dispose()
	_input_controller = null

	if _map_mode_bar_controller != null and _map_mode_bar_controller.has_method("dispose"):
		_map_mode_bar_controller.dispose()
	_map_mode_bar_controller = null

	if _menu_controller != null and _menu_controller.has_method("dispose"):
		_menu_controller.dispose()
	_menu_controller = null

	if _log_dock_controller != null and _log_dock_controller.has_method("dispose"):
		_log_dock_controller.dispose()
	_log_dock_controller = null

	if _warmup_controller != null and _warmup_controller.has_method("dispose"):
		_warmup_controller.dispose()
	_warmup_controller = null

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

	if _debug_panel_controller != null and _debug_panel_controller.has_method("dispose"):
		_debug_panel_controller.dispose()
	_debug_panel_controller = null

	if _ui_sync_controller != null and _ui_sync_controller.has_method("dispose"):
		_ui_sync_controller.dispose()
	_ui_sync_controller = null

	if _command_controller != null and _command_controller.has_method("dispose"):
		_command_controller.dispose()
	_command_controller = null

	if game_engine != null and game_engine.has_method("dispose"):
		game_engine.dispose()

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

func _update_ui() -> void:
	var do_profile := PerfTraceClass.enabled() and not _startup_profile_reported
	if _ui_sync_controller != null and _ui_sync_controller.has_method("update_ui"):
		_ui_sync_controller.update_ui(do_profile)

func _on_debug_command_executed(command: String, _result: String) -> void:
	if _ui_sync_controller != null and _ui_sync_controller.has_method("on_debug_command_executed"):
		_ui_sync_controller.on_debug_command_executed(command)
	else:
		_update_ui()

func rewind_to_turn_start() -> void:
	if _command_controller != null and _command_controller.has_method("rewind_to_turn_start"):
		_command_controller.rewind_to_turn_start()

func _execute_command(command: Command) -> Result:
	if _command_controller != null and _command_controller.has_method("execute_command"):
		var r_val = _command_controller.execute_command(command)
		if r_val is Result:
			return r_val
	return Result.failure("命令控制器未就绪")

func _on_advance_phase_pressed() -> void:
	if _command_controller != null and _command_controller.has_method("on_advance_phase_pressed"):
		_command_controller.on_advance_phase_pressed()

func _on_advance_sub_phase_pressed() -> void:
	if _command_controller != null and _command_controller.has_method("on_advance_sub_phase_pressed"):
		_command_controller.on_advance_sub_phase_pressed()

func _on_skip_pressed() -> void:
	if _command_controller != null and _command_controller.has_method("on_skip_pressed"):
		_command_controller.on_skip_pressed()

func _unhandled_input(event: InputEvent) -> void:
	if _input_controller != null and _input_controller.has_method("handle_unhandled_input"):
		var handled = _input_controller.handle_unhandled_input(event)
		if handled is bool and bool(handled):
			accept_event()

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

func _can_open_menu() -> bool:
	if _panel_controller != null and _panel_controller.has_method("has_blocking_modal_ui"):
		if bool(_panel_controller.call("has_blocking_modal_ui")):
			return false
	return true

func _ensure_game_menu_closed_for_blocking_modal() -> void:
	if _menu_controller == null:
		return
	if not _menu_controller.has_method("handle_escape"):
		return

	for _i in range(2):
		var closed_val = _menu_controller.call("handle_escape")
		if not (closed_val is bool) or not bool(closed_val):
			break

func _on_menu_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_menu_pressed"):
		_menu_controller.call("on_menu_pressed")

func _on_menu_dialog_close_requested() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_menu_dialog_close_requested"):
		_menu_controller.call("on_menu_dialog_close_requested")

func _on_resume_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_resume_pressed"):
		_menu_controller.call("on_resume_pressed")

func _on_save_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_save_pressed"):
		_menu_controller.call("on_save_pressed")

func _on_settings_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_settings_pressed"):
		_menu_controller.call("on_settings_pressed")

func _on_toggle_log_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_toggle_log_pressed"):
		_menu_controller.call("on_toggle_log_pressed")

func _on_milestones_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_milestones_pressed"):
		_menu_controller.call("on_milestones_pressed")

func _on_distance_tool_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_distance_tool_pressed"):
		_menu_controller.call("on_distance_tool_pressed")

func _on_replay_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_replay_pressed"):
		_menu_controller.call("on_replay_pressed")

func _on_quit_to_menu_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_quit_to_menu_pressed"):
		_menu_controller.call("on_quit_to_menu_pressed")

func _show_confirm(title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable(), confirm_text: String = "确认", cancel_text: String = "取消") -> void:
	if _menu_controller != null and _menu_controller.has_method("show_confirm"):
		_menu_controller.call("show_confirm", title, message, on_confirm, on_cancel, confirm_text, cancel_text)

# === 时间线/回放（由 GameTimelineController 负责）===

func _get_game_engine() -> GameEngine:
	return game_engine

func is_replay_mode_active() -> bool:
	if _timeline_controller != null and _timeline_controller.has_method("is_replay_mode_active"):
		return bool(_timeline_controller.call("is_replay_mode_active"))
	return false

func is_timeline_read_only_active() -> bool:
	if _timeline_controller != null and _timeline_controller.has_method("is_timeline_read_only_active"):
		var eng: GameEngine = _get_game_engine()
		return bool(_timeline_controller.call("is_timeline_read_only_active", eng))
	return false

func _set_active_game_engine(engine: GameEngine) -> void:
	if engine == null:
		return

	game_engine = engine
	if Globals != null:
		Globals.current_game_engine = engine
		Globals.is_game_active = true

	if _debug_panel_controller != null and _debug_panel_controller.has_method("set_game_engine"):
		_debug_panel_controller.call("set_game_engine", game_engine)

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

func _on_game_log_replay_toggle_changed(active: bool) -> void:
	if _timeline_controller != null and _timeline_controller.has_method("set_manual_replay_enabled"):
		_timeline_controller.call("set_manual_replay_enabled", bool(active))
	_clear_procurement_log_preview()

func _on_game_log_entry_hovered(entry_id: int, hovering: bool) -> void:
	if not _is_procurement_log_preview_enabled():
		return

	if bool(hovering):
		if not _is_drinks_procurement_log_entry(entry_id):
			return
		_procurement_log_preview_hover_entry_id = int(entry_id)
	else:
		if _procurement_log_preview_hover_entry_id != int(entry_id):
			return
		_procurement_log_preview_hover_entry_id = -1

	_refresh_procurement_log_preview_overlay()

func _on_game_log_entry_clicked_for_map_preview(entry_id: int) -> void:
	if not _is_procurement_log_preview_enabled():
		return

	var eid := int(entry_id)
	if not _is_drinks_procurement_log_entry(eid):
		_procurement_log_preview_pinned_entry_id = -1
		_refresh_procurement_log_preview_overlay()
		return

	if _procurement_log_preview_pinned_entry_id == eid:
		_procurement_log_preview_pinned_entry_id = -1
	else:
		_procurement_log_preview_pinned_entry_id = eid
	_refresh_procurement_log_preview_overlay()

func _is_procurement_log_preview_enabled() -> bool:
	# 仅在“正常模式”下启用：回放/复盘/时间线手动回放打开时不干预日志点击行为。
	if _timeline_controller != null and is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("is_manual_replay_enabled") and bool(_timeline_controller.call("is_manual_replay_enabled")):
			return false
		if _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
			return false
		if _timeline_controller.has_method("is_timeline_read_only_active"):
			var eng: GameEngine = _get_game_engine()
			if bool(_timeline_controller.call("is_timeline_read_only_active", eng)):
				return false
	return true

func _is_drinks_procurement_log_entry(entry_id: int) -> bool:
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return false
	if not game_log_panel.has_method("get_entry_by_id"):
		return false
	var entry: Dictionary = game_log_panel.call("get_entry_by_id", int(entry_id))
	if entry.is_empty():
		return false
	var details_val = entry.get("details", null)
	var details: Dictionary = details_val if (details_val is Dictionary) else {}
	var event_type := str(details.get("event_type", entry.get("event_type", ""))).strip_edges()
	return event_type == EventBus.EventType.DRINKS_PROCURED

func _clear_procurement_log_preview() -> void:
	_procurement_log_preview_pinned_entry_id = -1
	_procurement_log_preview_hover_entry_id = -1
	_hide_procurement_log_preview_overlay()

func _refresh_procurement_log_preview_overlay() -> void:
	var show_id := -1
	if _procurement_log_preview_hover_entry_id >= 0:
		show_id = _procurement_log_preview_hover_entry_id
	elif _procurement_log_preview_pinned_entry_id >= 0:
		show_id = _procurement_log_preview_pinned_entry_id

	if show_id < 0:
		_hide_procurement_log_preview_overlay()
		return
	if not _try_show_procurement_log_preview_overlay(show_id):
		_hide_procurement_log_preview_overlay()

func _hide_procurement_log_preview_overlay() -> void:
	if _overlay_controller != null and _overlay_controller.has_method("hide_procurement_route_overlay"):
		_overlay_controller.call("hide_procurement_route_overlay")

func _try_show_procurement_log_preview_overlay(entry_id: int) -> bool:
	if _overlay_controller == null or not _overlay_controller.has_method("show_procurement_route_overlay"):
		return false
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return false
	if not game_log_panel.has_method("get_entry_by_id"):
		return false

	var entry: Dictionary = game_log_panel.call("get_entry_by_id", int(entry_id))
	if entry.is_empty():
		return false
	var details_val = entry.get("details", null)
	var details: Dictionary = details_val if (details_val is Dictionary) else {}
	var event_type := str(details.get("event_type", entry.get("event_type", ""))).strip_edges()
	if event_type != EventBus.EventType.DRINKS_PROCURED:
		return false

	var engine: GameEngine = _get_game_engine()
	if engine == null:
		return false

	var cmd_index := -999
	var ci_val = details.get("command_index", entry.get("command_index", null))
	if ci_val is int:
		cmd_index = int(ci_val)
	elif ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			cmd_index = int(f)
	if cmd_index < 0 or cmd_index >= engine.command_history.size():
		return false

	var cmd_val = engine.command_history[cmd_index]
	if not (cmd_val is Command):
		return false
	var cmd: Command = cmd_val
	if str(cmd.action_id).strip_edges() != "procure_drinks":
		return false

	var route_parse: Result = DrinksProcurementInputsClass.parse_route_positions(cmd.params.get("route", null))
	if not route_parse.ok:
		return false
	var route: Array[Vector2i] = route_parse.value
	if route.is_empty():
		return false

	# picked_sources 优先来自事件 data（更贴近实际“本次采购确认的来源”）；缺失则回退 selected_sources。
	var picked_sources: Array[Vector2i] = []
	var ps_val = details.get("picked_sources", null)
	if ps_val is Array:
		for src_val in Array(ps_val):
			if not (src_val is Dictionary):
				continue
			var src: Dictionary = src_val
			var wp_val = src.get("world_pos", null)
			if wp_val is Vector2i:
				picked_sources.append(Vector2i(wp_val))
			elif wp_val is Array:
				var a: Array = wp_val
				if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
					picked_sources.append(Vector2i(int(a[0]), int(a[1])))
	if picked_sources.is_empty():
		var selected_parse: Result = DrinksProcurementInputsClass.parse_route_positions(details.get("selected_sources", cmd.params.get("selected_sources", null)))
		if selected_parse.ok:
			picked_sources = selected_parse.value

	var restaurant_id := str(details.get("restaurant_id", cmd.params.get("restaurant_id", ""))).strip_edges()
	var entrance_pos := Vector2i(-1, -1)
	var start_restaurant_cells: Array[Vector2i] = []
	if not restaurant_id.is_empty():
		var s: GameState = engine.get_state()
		if s != null and s.map is Dictionary:
			var restaurants_val = s.map.get("restaurants", null)
			if restaurants_val is Dictionary:
				var rest_val = (restaurants_val as Dictionary).get(restaurant_id, null)
				if rest_val is Dictionary:
					var rest: Dictionary = rest_val
					var ep_val = rest.get("entrance_pos", null)
					if ep_val is Vector2i:
						entrance_pos = Vector2i(ep_val)
					var cells_val = rest.get("cells", null)
					if cells_val is Array:
						for p in (cells_val as Array):
							if p is Vector2i:
								start_restaurant_cells.append(Vector2i(p))
							elif p is Array:
								var a: Array = p
								if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
									start_restaurant_cells.append(Vector2i(int(a[0]), int(a[1])))

	var employee_type := str(details.get("employee_type", cmd.params.get("employee_type", ""))).strip_edges()
	var is_air := false
	if not employee_type.is_empty() and EmployeeRegistryClass.is_loaded():
		var emp_def: EmployeeDef = EmployeeRegistryClass.get_def(employee_type)
		if emp_def != null and str(emp_def.range_type).strip_edges() == "air":
			is_air = true

	if is_air:
		var tile_size_cells := int(MapUtils.TILE_SIZE)
		var state: GameState = engine.get_state()
		if state != null:
			var tile_size_r := TileRouteUtilsClass.get_tile_size(state)
			if tile_size_r.ok:
				tile_size_cells = int(tile_size_r.value)

		var opts := {
			"tile_mode": true,
			"tile_size_cells": tile_size_cells,
			"selected_tiles": route.duplicate(),
			"start_restaurant_cells": start_restaurant_cells,
		}
		var empty_route: Array[Vector2i] = []
		_overlay_controller.call("show_procurement_route_overlay", Vector2i(-1, -1), empty_route, picked_sources, opts)
		return true

	var opts2 := {
		"start_restaurant_cells": start_restaurant_cells,
	}
	_overlay_controller.call("show_procurement_route_overlay", entrance_pos, route, picked_sources, opts2)
	return true

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
	if _log_dock_controller != null and _log_dock_controller.has_method("toggle_game_log"):
		_log_dock_controller.toggle_game_log()

func _show_game_log_panel_in_right_panel() -> void:
	if _log_dock_controller != null and _log_dock_controller.has_method("show_game_log_panel_in_right_panel"):
		_log_dock_controller.show_game_log_panel_in_right_panel()

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
