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
@onready var mute_icon: TextureRect = $UIRoot/TopBar/MuteIcon
@onready var toggle_bottom_panel_button: Button = $MenuDialog/VBoxContainer/ToggleBottomPanelButton
@onready var menu_dialog: Control = $MenuDialog
@onready var menu_dialog_overlay: ColorRect = $MenuDialog/Overlay
@onready var menu_dialog_background_panel: Panel = $MenuDialog/BackgroundPanel
@onready var menu_resume_button: Button = $MenuDialog/VBoxContainer/ResumeButton
@onready var menu_save_button: Button = $MenuDialog/VBoxContainer/SaveButton
@onready var menu_rules_button: Button = $MenuDialog/VBoxContainer/RulesButton
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

const GameControllersBuilderClass = preload("res://ui/scenes/game/controllers/builder.gd")
const GameOnlineResyncControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")
const GameUiStyleApplierClass = preload("res://ui/scenes/game/controllers/ui_style_applier.gd")
const GameRuntimeDisposerClass = preload("res://ui/scenes/game/controllers/runtime_disposer.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const RulesDocsClass = preload("res://ui/utils/rules_docs.gd")

const MUTE_ICON_ON_PATH := "res://assets/images/musicOn.png"
const MUTE_ICON_OFF_PATH := "res://assets/images/musicOff.png"

var _mute_icon_on: Texture2D = null
var _mute_icon_off: Texture2D = null
var _mute_icon_load_warned: bool = false

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
var _procurement_log_preview_controller = null
var _warmup_controller = null
var _debug_panel_controller = null
var _startup_profile_reported: bool = false
var _startup_suppress_game_over_modal: bool = false
var _startup_intro_played: bool = false
var _startup_intro_running: bool = false
var _online_waiting_log_auto_opened: bool = false
var _online_waiting_action_ui_hidden: bool = false
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
	UiStylesClass.apply_native_tooltip_theme(self)
	GameUiStyleApplierClass.apply_all(self)
	if mute_icon != null:
		mute_icon.gui_input.connect(_on_mute_icon_gui_input)
		mute_icon.mouse_filter = Control.MOUSE_FILTER_STOP
		mute_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ensure_mute_icon_textures_loaded()
	_update_mute_icon_ui()
	if Globals != null and not Globals.audio_muted_changed.is_connected(_on_audio_muted_changed):
		Globals.audio_muted_changed.connect(_on_audio_muted_changed)
	var build := GameControllersBuilderClass.build(self, {
		"round_label": round_label,
		"phase_track": phase_track,
		"bank_label": bank_label,
		"bank_break_tag": bank_break_tag,
		"toggle_left_panel_button": toggle_left_panel_button,
		"toggle_right_panel_button": toggle_right_panel_button,
		"toggle_bottom_panel_button": toggle_bottom_panel_button,
		"main_content": main_content,
		"center_split": center_split,
		"left_area": left_area,
		"left_panel": left_panel,
		"game_log_panel": game_log_panel,
		"bottom_panel": bottom_panel,
		"right_panel_root": $UIRoot/MainContent/CenterSplit/RightPanel,
		"right_panel_header_row": right_panel_header_row,
		"right_panel_back_button": right_panel_back_button,
		"right_panel_title_label": right_panel_title_label,
		"right_panel_default_stack": right_panel_default_stack,
		"right_panel_dock_host": right_panel_dock_host,
		"right_panel_footer_row": right_panel_footer_row,
		"right_panel_footer_cancel_button": right_panel_footer_cancel_button,
		"right_panel_footer_secondary_button": right_panel_footer_secondary_button,
		"right_panel_footer_primary_button": right_panel_footer_primary_button,
		"action_flow_controls": action_flow_controls,
		"player_panel": player_panel,
		"turn_order_track": turn_order_track,
		"inventory_panel": inventory_panel,
		"action_panel": action_panel,
		"hand_area": hand_area,
		"company_structure": company_structure,
		"map_view": map_view,
		"map_canvas": map_canvas,
		"map_mode_bar": map_mode_bar,
		"menu_dialog": menu_dialog,
	}, {
		"execute_command": Callable(self, "_execute_command"),
		"update_ui": Callable(self, "_update_ui"),
		"get_game_engine": Callable(self, "_get_game_engine"),
		"set_active_game_engine": Callable(self, "_set_active_game_engine"),
		"show_confirm": Callable(self, "_show_confirm"),
		"show_game_log_panel_in_right_panel": Callable(self, "_show_game_log_panel_in_right_panel"),
		"open_replay_load_dialog": Callable(self, "_open_replay_load_dialog"),
		"is_online_resync_in_progress": Callable(self, "_is_online_resync_in_progress"),
		"start_replay_from_file": Callable(self, "_start_replay_from_file"),
		"on_debug_command_executed": Callable(self, "_on_debug_command_executed"),
		"ensure_right_panel_visible": Callable(self, "_ensure_right_panel_visible"),
		"ensure_left_area_visible": Callable(self, "_ensure_left_area_visible"),
		"cancel_right_panel_docked_panel": Callable(self, "_cancel_right_panel_docked_panel"),
		"sync_right_panel_docked_view": Callable(self, "_sync_right_panel_docked_view"),
		"dock_popup_into_right_panel": Callable(self, "dock_popup_into_right_panel"),
		"toggle_game_log": Callable(self, "toggle_game_log"),
		"show_settings_dialog": Callable(self, "show_settings_dialog"),
		"show_rules_dialog": Callable(self, "show_rules_dialog"),
		"show_milestone_panel": Callable(self, "show_milestone_panel"),
		"toggle_distance_tool": Callable(self, "toggle_distance_tool"),
		"can_open_menu": Callable(self, "_can_open_menu"),
	}, startup_replay_from_main_menu)

	_layout_controller = build.get("layout_controller", null)
	_menu_debug_controller = build.get("menu_debug_controller", null)
	_menu_controller = build.get("menu_controller", null)
	_save_load_controller = build.get("save_load_controller", null)
	_right_panel_dock_controller = build.get("right_panel_dock_controller", null)
	_overlay_controller = build.get("overlay_controller", null)
	_map_controller = build.get("map_controller", null)
	_map_mode_bar_controller = build.get("map_mode_bar_controller", null)
	_panel_controller = build.get("panel_controller", null)
	_timeline_controller = build.get("timeline_controller", null)
	_procurement_log_preview_controller = build.get("procurement_log_preview_controller", null)
	_log_dock_controller = build.get("log_dock_controller", null)
	_ui_sync_controller = build.get("ui_sync_controller", null)
	_debug_panel_controller = build.get("debug_panel_controller", null)
	_command_controller = build.get("command_controller", null)
	_input_controller = build.get("input_controller", null)
	_warmup_controller = build.get("warmup_controller", null)

	_apply_ui_layout()
	_init_left_panel_toggle()
	_init_right_panel_toggle()
	_init_right_panel_header()
	_init_right_panel_footer()

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
	GameRuntimeDisposerClass.dispose_runtime(self)

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
	# 面板隐藏按钮已移除：保持信息区常驻可见
	_ensure_left_area_visible()

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
	# 右侧动作区不允许关闭（避免隐藏导致误操作/软锁）
	_ensure_right_panel_visible()

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
	# 面板隐藏按钮已移除：保持右侧操作区常驻可见
	_ensure_right_panel_visible()

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
	_startup_suppress_game_over_modal = false
	# 载入游戏：主菜单可能已在 Globals 中准备好 GameEngine。
	if Globals.current_game_engine != null and Globals.current_game_engine is GameEngine:
		var existing: GameEngine = Globals.current_game_engine
		if existing.get_state() != null:
			_set_active_game_engine(existing)
			var s: GameState = existing.get_state()
			if s != null and str(s.phase) == DefsClass.PHASE_GAME_OVER:
				_startup_suppress_game_over_modal = true
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

	_set_active_game_engine(game_engine)

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
	# 先执行一次联机等待态切换：确保“轮到自己时”先关闭日志，再进入面板同步，
	# 避免本帧先出现“继续xx”占位卡，再下一帧才打开真实动作页面。
	_sync_online_waiting_log_auto_switch()
	var do_profile := PerfTraceClass.enabled() and not _startup_profile_reported
	var start_intro := _prepare_startup_intro_before_ui_sync()
	if _ui_sync_controller != null and _ui_sync_controller.has_method("update_ui"):
		_ui_sync_controller.update_ui(do_profile)
	# 同步后再收敛一次，保证最终显示状态稳定。
	_sync_online_waiting_log_auto_switch()
	if start_intro:
		_run_startup_intro()

func _prepare_startup_intro_before_ui_sync() -> bool:
	# 在 UI 同步前把地图/顺位条“隐藏到动画起点”，避免先闪现完整结果再播放动画。
	if _startup_intro_played or _startup_intro_running:
		return false
	if OS.has_feature("headless"):
		_startup_intro_played = true
		return false
	# 回放/时间线回退：不播放开局动画，避免干扰复盘/测试。
	if is_replay_mode_active() or is_timeline_read_only_active():
		_startup_intro_played = true
		return false
	if _is_online_resync_in_progress():
		return false
	if game_engine == null:
		return false

	var state: GameState = game_engine.get_state()
	if state == null:
		return false
	# 仅在新开局（Setup，且 ReserveCards 已结束/跳过）播放一次。
	if int(state.round_number) != 0:
		_startup_intro_played = true
		return false
	if str(state.phase) != DefsClass.PHASE_SETUP:
		_startup_intro_played = true
		return false
	if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
		return false
	# 玩家已经开始放置起始餐厅后，不再播放开局动画。
	for p_val in Array(state.players):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var r_val = p.get("restaurants", null)
		if r_val is Array and not (r_val as Array).is_empty():
			_startup_intro_played = true
			return false

	_startup_intro_running = true

	# 先隐藏顺位条：避免一开始就显示最终顺位。
	if is_instance_valid(turn_order_display):
		turn_order_display.visible = false

	# 地图锁交互 + 准备 reveal（tile 边框也会随 reveal 同步出现）
	if is_instance_valid(map_canvas) and map_canvas.has_method("set_interaction_enabled"):
		map_canvas.call("set_interaction_enabled", false)
	if is_instance_valid(map_canvas) and map_canvas.has_method("prepare_intro_reveal"):
		map_canvas.call("prepare_intro_reveal")

	return true

func _run_startup_intro() -> void:
	# 先让“空地图/隐藏顺位条”渲染一帧，再开始生成动画。
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	var speed := 1.0
	if Globals != null and "animation_speed" in Globals:
		speed = maxf(0.1, float(Globals.animation_speed))

	var map_reveal_sec := 1.6 / speed
	if is_instance_valid(map_canvas) and map_canvas.has_method("play_intro_reveal_animation"):
		await map_canvas.call("play_intro_reveal_animation", map_reveal_sec)

	var final_order: Array = []
	if game_engine != null:
		var state: GameState = game_engine.get_state()
		if state != null and (state.turn_order is Array):
			final_order = Array(state.turn_order)

	if is_instance_valid(turn_order_display) and turn_order_display.has_method("play_intro_roll") and not final_order.is_empty():
		turn_order_display.visible = true
		var roll_cfg := {
			"spin_sec": 1.20 / speed,
			"tick_min_sec": 0.05 / speed,
			"tick_max_sec": 0.18 / speed,
		}
		await turn_order_display.call("play_intro_roll", final_order, roll_cfg)
	else:
		if is_instance_valid(turn_order_display):
			turn_order_display.visible = true

	# 动画结束：恢复正常绘制/交互。
	if is_instance_valid(map_canvas) and map_canvas.has_method("reset_intro_reveal"):
		map_canvas.call("reset_intro_reveal")
	if is_instance_valid(map_canvas) and map_canvas.has_method("set_interaction_enabled"):
		map_canvas.call("set_interaction_enabled", true)

	_startup_intro_running = false
	_startup_intro_played = true

func _on_debug_command_executed(command: String, _result: String) -> void:
	if _ui_sync_controller != null and _ui_sync_controller.has_method("on_debug_command_executed"):
		_ui_sync_controller.on_debug_command_executed(command)
	else:
		_update_ui()

func _is_online_waiting_for_other_player() -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if game_engine == null:
		return false

	var state: GameState = game_engine.get_state()
	if state == null:
		return false
	if str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
		return false

	var local_pid := int(NetContext.local_player_id)
	if local_pid < 0:
		return true
	var current_pid := int(state.get_current_player_id())
	if current_pid < 0:
		return true
	return current_pid != local_pid

func _set_action_ui_visible(visible: bool) -> void:
	if is_instance_valid(action_panel):
		action_panel.visible = visible
	if is_instance_valid(action_flow_controls):
		action_flow_controls.visible = visible

func _sync_online_waiting_log_auto_switch() -> void:
	var waiting_others := _is_online_waiting_for_other_player()
	if waiting_others:
		if not _online_waiting_action_ui_hidden:
			if _panel_controller != null and _panel_controller.has_method("hide_non_modal_action_ui_for_waiting"):
				_panel_controller.call("hide_non_modal_action_ui_for_waiting")
			_set_action_ui_visible(false)
			_online_waiting_action_ui_hidden = true
	else:
		if _online_waiting_action_ui_hidden:
			_set_action_ui_visible(true)
			_online_waiting_action_ui_hidden = false

	# 回放/复盘期间由时间线控制器主导日志显示，不做自动切换。
	if is_timeline_read_only_active():
		return
	if _log_dock_controller == null:
		_online_waiting_log_auto_opened = false
		return
	if not _log_dock_controller.has_method("is_game_log_visible_in_right_panel"):
		_online_waiting_log_auto_opened = false
		return

	var log_visible := bool(_log_dock_controller.call("is_game_log_visible_in_right_panel"))

	if waiting_others:
		if not log_visible and _log_dock_controller.has_method("show_game_log_panel_in_right_panel"):
			_log_dock_controller.call("show_game_log_panel_in_right_panel")
			log_visible = bool(_log_dock_controller.call("is_game_log_visible_in_right_panel"))
		if log_visible:
			_online_waiting_log_auto_opened = true
		return

	if _online_waiting_log_auto_opened:
		if log_visible and _log_dock_controller.has_method("hide_game_log_panel_in_right_panel"):
			# 自动回到“默认动作区”（而不是恢复之前被隐藏的某个 docked 面板）。
			_log_dock_controller.call("hide_game_log_panel_in_right_panel", false)
		_online_waiting_log_auto_opened = false

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

func _on_reserve_cards_button_pressed() -> void:
	show_reserve_cards_overview()

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

func _on_mute_icon_gui_input(event: InputEvent) -> void:
	if event == null:
		return

	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if not e.pressed:
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if not t.pressed:
			return
	else:
		return

	if Globals != null and Globals.has_method("toggle_audio_muted"):
		Globals.toggle_audio_muted()
	_update_mute_icon_ui()
	accept_event()

func _on_audio_muted_changed(_muted: bool) -> void:
	_update_mute_icon_ui()

func _ensure_mute_icon_textures_loaded() -> void:
	if _mute_icon_on != null and _mute_icon_off != null:
		return

	_mute_icon_on = _load_texture_if_exists(MUTE_ICON_ON_PATH)
	_mute_icon_off = _load_texture_if_exists(MUTE_ICON_OFF_PATH)
	if not _mute_icon_load_warned and (_mute_icon_on == null or _mute_icon_off == null):
		_mute_icon_load_warned = true
		GameLog.warn("Game", "静音图标缺失：请确保存在 %s 与 %s" % [MUTE_ICON_ON_PATH, MUTE_ICON_OFF_PATH])

func _load_texture_if_exists(path: String) -> Texture2D:
	var p := str(path).strip_edges()
	if p.is_empty():
		return null
	if not ResourceLoader.exists(p):
		return null
	var res = load(p)
	if res is Texture2D:
		return res
	return null

func _update_mute_icon_ui() -> void:
	if mute_icon == null:
		return
	_ensure_mute_icon_textures_loaded()

	var muted := false
	if Globals != null and Globals.has_method("is_audio_muted"):
		muted = bool(Globals.is_audio_muted())

	var tex: Texture2D = _mute_icon_off if muted else _mute_icon_on
	if tex != null:
		mute_icon.texture = tex
	mute_icon.tooltip_text = "点击取消静音" if muted else "点击静音"

func _on_menu_dialog_close_requested() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_menu_dialog_close_requested"):
		_menu_controller.call("on_menu_dialog_close_requested")

func _on_resume_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_resume_pressed"):
		_menu_controller.call("on_resume_pressed")

func _on_save_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_save_pressed"):
		_menu_controller.call("on_save_pressed")

func _on_rules_pressed() -> void:
	if _menu_controller != null and _menu_controller.has_method("on_rules_pressed"):
		_menu_controller.call("on_rules_pressed")

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

func should_suppress_game_over_modal() -> bool:
	return _startup_suppress_game_over_modal

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
	var ui_metadata_apply := ModuleUiMetadataBootstrapClass.apply(engine)
	if not ui_metadata_apply.ok:
		GameLog.error("Game", "模块 UI metadata 装配失败: %s" % ui_metadata_apply.error)

	game_engine = engine
	if Globals != null:
		Globals.current_game_engine = engine
		Globals.is_game_active = true

	if _debug_panel_controller != null and _debug_panel_controller.has_method("set_game_engine"):
		_debug_panel_controller.call("set_game_engine", game_engine)

	if _panel_controller != null and game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

func _open_replay_load_dialog() -> void:
	GameLog.info("Game", "游戏内载入已禁用（仅主菜单可载入）")

func _open_replay_save_dialog() -> void:
	if _save_load_controller != null:
		_save_load_controller.open_for_save(game_engine, "保存回放")

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

func show_reserve_cards_overview(focus_player_id: int = -1) -> void:
	if _panel_controller != null and _panel_controller.has_method("show_reserve_cards_overview"):
		_panel_controller.call("show_reserve_cards_overview", focus_player_id)

func toggle_game_log() -> void:
	var was_visible := false
	if _log_dock_controller != null and _log_dock_controller.has_method("is_game_log_visible_in_right_panel"):
		was_visible = bool(_log_dock_controller.call("is_game_log_visible_in_right_panel"))

	if _log_dock_controller != null and _log_dock_controller.has_method("toggle_game_log"):
		_log_dock_controller.toggle_game_log()

	# 关闭日志后：刷新 UI 以恢复“动作流自动打开”的默认体验（ActionPanel 已不再显示动作按钮列表）。
	if was_visible:
		_update_ui()

func _show_game_log_panel_in_right_panel() -> void:
	if _log_dock_controller != null and _log_dock_controller.has_method("show_game_log_panel_in_right_panel"):
		_log_dock_controller.show_game_log_panel_in_right_panel()

func show_settings_dialog() -> void:
	if _overlay_controller != null:
		_overlay_controller.show_settings_dialog()

func show_rules_dialog() -> void:
	RulesDocsClass.show_rules_dialog(self)

func toggle_distance_tool() -> void:
	if _map_controller != null:
		_map_controller.toggle_distance_tool()

func get_ui_animation_manager() -> Node:
	if _overlay_controller != null:
		return _overlay_controller.get_ui_animation_manager()
	return null
