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
@onready var menu_dialog: Window = $MenuDialog
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
const GameOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_controller.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/game_map_interaction_controller.gd")
const GamePanelControllerClass = preload("res://ui/scenes/game/game_panel_controller.gd")
const DebugPanelScene = preload("res://ui/scenes/debug/debug_panel.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const ReplayPlayerScene = preload("res://ui/components/replay_player/replay_player.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const EventTimelineBuildClass = preload("res://core/engine/game_engine/event_timeline_build.gd")
const StepTimelineBuildClass = preload("res://core/engine/game_engine/step_timeline_build.gd")
const GameEventLogFormatterClass = preload("res://ui/scenes/game/game_event_log_formatter.gd")

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
var _replay_original_log_entries: Array[Dictionary] = []
var _replay_file_path: String = ""
var _replay_step_timeline: Dictionary = {} # {initial_state_dict, steps, events}
var _replay_head_step_index: int = -1
var _replay_cursor_step_index: int = -1

# 复盘（非回放）：当 cursor < head 时，切换到 step_index 时间线（支持大阶段切分），并在返回最新时恢复实时日志。
var _history_step_timeline_active: bool = false
var _history_step_timeline: Dictionary = {} # {initial_state_dict, steps, events}
var _history_head_step_index: int = -1
var _history_cursor_step_index: int = -1
var _history_original_log_entries: Array[Dictionary] = []
var _history_latest_state_dict: Dictionary = {}
var _startup_replay_from_main_menu: bool = false
var _startup_replay_file_path: String = ""

var _background_ui_warmup_started: bool = false
var _startup_profile_reported: bool = false

const AUTO_MANDATORY_ACTION_IDS := {
	"set_price": true,
	"set_discount": true,
	"set_luxury_price": true,
}

# 存档管理（多槽 + 文件选择）
var _save_load_dialog = null
var _save_load_context: String = ""

var _left_area_visible: bool = true
var _main_content_default_split_offset: int = 360
var _left_area_user_resized: bool = false
const LEFT_AREA_MIN_WIDTH := 200

var _bottom_panel_visible: bool = true
var _right_panel_visible: bool = true
var _center_split_default_split_offset: int = -340

var _responsive_mode: String = ""
var _responsive_font_scale: float = -1.0
var _right_panel_footer_source: Object = null

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

	# 主菜单入口：选择回放文件后，进入 Game 并自动打开回放播放器。
	if Globals != null:
		var p := str(Globals.pending_replay_file_path).strip_edges()
		if not p.is_empty():
			_startup_replay_from_main_menu = true
			_startup_replay_file_path = p
			Globals.pending_replay_file_path = ""

	var should_restore_log_history := false
	if Globals.current_game_engine != null and Globals.current_game_engine is GameEngine:
		var existing_engine: GameEngine = Globals.current_game_engine
		should_restore_log_history = existing_engine.get_state() != null

	if not should_restore_log_history and EventBus != null:
		EventBus.clear_history()

	var span_layout := PerfTraceClass.begin_span("game:layout+controllers_init")
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
	# M4.3：日志面板统一使用 step 时间线视图（由 StepTimelineBuild.build_full 重建），
	# 不再依赖 EventBus 订阅追加日志。
	_event_log_controller = null
	UiSignalHelpersClass.safe_connect(game_log_panel, "close_requested", toggle_game_log)
	UiSignalHelpersClass.safe_connect(game_log_panel, "log_entry_clicked", _on_log_entry_clicked)
	if game_log_panel.has_signal("timeline_seek_requested"):
		UiSignalHelpersClass.safe_connect(game_log_panel, "timeline_seek_requested", _on_timeline_seek_requested)
	_init_replay_bar()
	PerfTraceClass.end_span(span_layout)

	var span_init_game := PerfTraceClass.begin_span("game:_initialize_game")
	_initialize_game()
	PerfTraceClass.end_span(span_init_game)
	if game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

	# 初始化调试面板
	_setup_debug_panel()
	DebugFlags.debug_panel_toggled.connect(_on_debug_panel_toggled)
	_on_debug_panel_toggled(DebugFlags.show_console)

	_init_bottom_panel_toggle()
	_init_left_area_resize()
	_apply_responsive_layout()
	UiSignalHelpersClass.safe_connect(self, "resized", _on_root_resized)
	if _startup_replay_from_main_menu and not _startup_replay_file_path.is_empty():
		# 回放入口：保持加载遮罩，避免先渲染“新开局”的 UI 再切换到回放造成闪烁。
		_start_replay_from_file(_startup_replay_file_path)
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
			if s != null and str(s.phase) == "Setup" and str(s.sub_phase) == "ReserveCards":
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

	_right_panel_footer_source = null

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
	if not _left_area_visible:
		return
	_left_area_user_resized = true
	# 只限制最小宽度（issue_tracker #61）：避免把“用户拖到的宽度”写回 custom_minimum_size 导致无法再缩小。
	var clamped := maxi(int(offset), LEFT_AREA_MIN_WIDTH)
	_main_content_default_split_offset = clamped
	if is_instance_valid(main_content):
		main_content.split_offset = clamped
	if is_instance_valid(left_area):
		left_area.custom_minimum_size.x = LEFT_AREA_MIN_WIDTH

func _init_left_panel_toggle() -> void:
	if is_instance_valid(main_content):
		_main_content_default_split_offset = maxi(int(main_content.split_offset), LEFT_AREA_MIN_WIDTH)
	_left_area_visible = is_instance_valid(left_area) and left_area.visible
	_update_left_panel_toggle_button()

func _update_left_panel_toggle_button() -> void:
	if not is_instance_valid(toggle_left_panel_button):
		return
	toggle_left_panel_button.text = "隐藏信息" if _left_area_visible else "显示信息"

func _ensure_left_area_visible() -> void:
	if _left_area_visible:
		return
	_left_area_visible = true
	if is_instance_valid(left_area):
		left_area.visible = true
	if is_instance_valid(main_content):
		main_content.split_offset = _main_content_default_split_offset
	_update_left_panel_toggle_button()

func _on_toggle_left_panel_pressed() -> void:
	_left_area_visible = not _left_area_visible
	if is_instance_valid(left_area):
		left_area.visible = _left_area_visible
	if is_instance_valid(main_content):
		if _left_area_visible:
			main_content.split_offset = _main_content_default_split_offset
		else:
			main_content.split_offset = 0
	_update_left_panel_toggle_button()

func _init_right_panel_toggle() -> void:
	if is_instance_valid(center_split):
		_center_split_default_split_offset = center_split.split_offset
	var right_panel := $UIRoot/MainContent/CenterSplit/RightPanel
	_right_panel_visible = is_instance_valid(right_panel) and right_panel.visible
	_update_right_panel_toggle_button()

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

func _update_right_panel_toggle_button() -> void:
	if not is_instance_valid(toggle_right_panel_button):
		return
	toggle_right_panel_button.text = "隐藏操作" if _right_panel_visible else "显示操作"

func _ensure_right_panel_visible() -> void:
	if _right_panel_visible:
		return
	_right_panel_visible = true
	var right_panel := $UIRoot/MainContent/CenterSplit/RightPanel
	if is_instance_valid(right_panel):
		right_panel.visible = true
	if is_instance_valid(center_split):
		center_split.split_offset = _center_split_default_split_offset
	_update_right_panel_toggle_button()

func dock_popup_into_right_panel(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	if not is_instance_valid(right_panel_dock_host):
		return false

	_ensure_right_panel_visible()

	# 避免“首次添加到场景 root 时闪一下/溢出”：先以隐藏状态移动，再在抽屉中显示。
	panel.visible = false
	if panel.get_parent() != right_panel_dock_host:
		var old_parent := panel.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(panel)
		right_panel_dock_host.add_child(panel)

	if panel.has_method("set_embedded_in_right_panel"):
		panel.call("set_embedded_in_right_panel", true)

	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0

	panel.visible = true
	_sync_right_panel_docked_view()
	return true

func _sync_right_panel_docked_view() -> void:
	var active: Control = null
	if is_instance_valid(right_panel_dock_host):
		for ch in right_panel_dock_host.get_children():
			if not (ch is Control):
				continue
			var c: Control = ch
			if is_instance_valid(c) and c.visible:
				active = c
				break

	var has_docked := active != null

	if is_instance_valid(right_panel_default_stack):
		right_panel_default_stack.visible = not has_docked
	if is_instance_valid(right_panel_dock_host):
		right_panel_dock_host.visible = has_docked
	if is_instance_valid(right_panel_back_button):
		right_panel_back_button.visible = has_docked
	if is_instance_valid(right_panel_title_label):
		if has_docked and is_instance_valid(active):
			var title := ""
			if active.has_meta("popup_title"):
				title = str(active.get_meta("popup_title")).strip_edges()
			if title.is_empty():
				title = str(active.name)
			right_panel_title_label.text = title
		else:
			right_panel_title_label.text = "操作"

	_bind_right_panel_footer_source(active)
	_sync_right_panel_footer(active)

func _bind_right_panel_footer_source(active_panel: Object) -> void:
	if _right_panel_footer_source == active_panel:
		return

	var handler := Callable(self, "_on_right_panel_footer_changed")

	if is_instance_valid(_right_panel_footer_source) and _right_panel_footer_source.has_signal("right_panel_footer_changed"):
		var old_sig := Signal(_right_panel_footer_source, &"right_panel_footer_changed")
		if old_sig.is_connected(handler):
			old_sig.disconnect(handler)

	_right_panel_footer_source = active_panel

	if is_instance_valid(_right_panel_footer_source) and _right_panel_footer_source.has_signal("right_panel_footer_changed"):
		var new_sig := Signal(_right_panel_footer_source, &"right_panel_footer_changed")
		if not new_sig.is_connected(handler):
			new_sig.connect(handler)

func _sync_right_panel_footer(active_panel: Object) -> void:
	if not is_instance_valid(right_panel_footer_row):
		return
	if not is_instance_valid(right_panel_footer_cancel_button) or not is_instance_valid(right_panel_footer_primary_button) or not is_instance_valid(right_panel_footer_secondary_button):
		right_panel_footer_row.visible = false
		return

	if active_panel == null or not is_instance_valid(active_panel):
		right_panel_footer_row.visible = false
		return

	var config: Dictionary = {}
	if active_panel.has_method("right_panel_get_footer_config"):
		var r = active_panel.call("right_panel_get_footer_config")
		if r is Dictionary:
			config = r

	if config.is_empty():
		right_panel_footer_row.visible = false
		return

	var show_cancel := bool(config.get("show_cancel", true))
	var cancel_text := str(config.get("cancel_text", "取消"))
	var cancel_enabled := bool(config.get("cancel_enabled", true))

	var show_secondary := bool(config.get("show_secondary", false))
	var secondary_text := str(config.get("secondary_text", ""))
	var secondary_enabled := bool(config.get("secondary_enabled", true))

	var show_primary := bool(config.get("show_primary", true))
	var primary_text := str(config.get("primary_text", ""))
	var primary_enabled := bool(config.get("primary_enabled", true))

	if secondary_text.is_empty():
		show_secondary = false
	if primary_text.is_empty():
		show_primary = false

	right_panel_footer_row.visible = show_cancel or show_secondary or show_primary

	right_panel_footer_cancel_button.visible = show_cancel
	right_panel_footer_cancel_button.text = cancel_text
	right_panel_footer_cancel_button.disabled = not cancel_enabled

	right_panel_footer_secondary_button.visible = show_secondary
	right_panel_footer_secondary_button.text = secondary_text
	right_panel_footer_secondary_button.disabled = not secondary_enabled

	right_panel_footer_primary_button.visible = show_primary
	right_panel_footer_primary_button.text = primary_text
	right_panel_footer_primary_button.disabled = not primary_enabled

func _on_right_panel_footer_changed() -> void:
	_sync_right_panel_docked_view()

func _on_right_panel_footer_cancel_pressed() -> void:
	_cancel_right_panel_docked_panel()
	_sync_right_panel_docked_view()

func _on_right_panel_footer_primary_pressed() -> void:
	var active: Control = null
	if is_instance_valid(right_panel_dock_host):
		for ch in right_panel_dock_host.get_children():
			if not (ch is Control):
				continue
			var c: Control = ch
			if is_instance_valid(c) and c.visible:
				active = c
				break

	if active == null or not is_instance_valid(active):
		return
	if active.has_method("right_panel_footer_primary"):
		active.call("right_panel_footer_primary")
		return

func _on_right_panel_footer_secondary_pressed() -> void:
	var active: Control = null
	if is_instance_valid(right_panel_dock_host):
		for ch in right_panel_dock_host.get_children():
			if not (ch is Control):
				continue
			var c: Control = ch
			if is_instance_valid(c) and c.visible:
				active = c
				break

	if active == null or not is_instance_valid(active):
		return
	if active.has_method("right_panel_footer_secondary"):
		active.call("right_panel_footer_secondary")
		return

func _on_right_panel_back_pressed() -> void:
	# 日志面板作为 RightPanel 抽屉视图时：返回键应关闭日志，而不是走“取消当前动作/面板”的逻辑。
	if is_instance_valid(game_log_panel) and game_log_panel.visible and is_instance_valid(right_panel_dock_host) and game_log_panel.get_parent() == right_panel_dock_host:
		toggle_game_log()
		return
	_on_right_panel_footer_cancel_pressed()

func _on_right_panel_close_pressed() -> void:
	if _right_panel_visible:
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
	_right_panel_visible = not _right_panel_visible

	var right_panel := $UIRoot/MainContent/CenterSplit/RightPanel
	if is_instance_valid(right_panel):
		if OS.has_feature("headless"):
			right_panel.visible = _right_panel_visible
		else:
			await _animate_right_panel_visibility(right_panel, _right_panel_visible)

	if is_instance_valid(center_split) and _right_panel_visible:
		center_split.split_offset = _center_split_default_split_offset

	_update_right_panel_toggle_button()

func _animate_right_panel_visibility(right_panel: Control, make_visible: bool) -> void:
	if not is_instance_valid(right_panel):
		return
	if OS.has_feature("headless"):
		right_panel.visible = make_visible
		return
	if not (has_method("get_ui_animation_manager")):
		right_panel.visible = make_visible
		return
	var anim_manager = get_ui_animation_manager()
	if anim_manager == null:
		right_panel.visible = make_visible
		return

	if make_visible:
		right_panel.visible = true
		await get_tree().process_frame
		if anim_manager.has_method("animate_slide_in"):
			anim_manager.call("animate_slide_in", right_panel, "right")
	else:
		if not anim_manager.has_method("animate_slide_out"):
			right_panel.visible = false
			return
		var original_pos := right_panel.position
		anim_manager.call("animate_slide_out", right_panel, "right", Callable(self, "_finish_hide_right_panel").bind(right_panel, original_pos))

func _finish_hide_right_panel(right_panel: Control, original_pos: Vector2) -> void:
	if not is_instance_valid(right_panel):
		return
	right_panel.visible = false
	right_panel.position = original_pos

func _apply_ui_layout() -> void:
	# 强制新布局（v2），不再支持 v1（issue_tracker #60）。
	if is_instance_valid(player_panel):
		player_panel.visible = false
	if is_instance_valid(inventory_panel):
		inventory_panel.visible = false
	if is_instance_valid(left_panel):
		left_panel.visible = true
		if is_instance_valid(game_log_panel):
			game_log_panel.visible = false
			if left_panel.has_method("bind_game_log_panel"):
				left_panel.call("bind_game_log_panel", game_log_panel)
			elif left_panel.has_method("attach_game_log_panel"):
				left_panel.call("attach_game_log_panel", game_log_panel)
		if left_panel.has_signal("logs_requested"):
			var sig := Signal(left_panel, &"logs_requested")
			var cb := Callable(self, "_on_left_panel_logs_requested")
			if not sig.is_connected(cb):
				sig.connect(cb)

	if is_instance_valid(bottom_panel):
		bottom_panel.visible = false
	_bottom_panel_visible = false
	if is_instance_valid(toggle_bottom_panel_button):
		toggle_bottom_panel_button.visible = false

func _init_bottom_panel_toggle() -> void:
	_bottom_panel_visible = false
	_update_bottom_panel_toggle_button()

func _update_bottom_panel_toggle_button() -> void:
	if is_instance_valid(toggle_bottom_panel_button):
		toggle_bottom_panel_button.text = "隐藏底部" if _bottom_panel_visible else "显示底部"

func _on_toggle_bottom_panel_pressed() -> void:
	_bottom_panel_visible = not _bottom_panel_visible
	if is_instance_valid(bottom_panel):
		bottom_panel.visible = _bottom_panel_visible
	_update_bottom_panel_toggle_button()

func _apply_responsive_layout() -> void:
	if not is_instance_valid(main_content) or not is_instance_valid(center_split):
		return

	var width := int(get_viewport_rect().size.x)
	var mode := "standard"
	if width < 1280:
		mode = "narrow"
	elif width > 1920:
		mode = "wide"

	var current_font_scale := 1.0
	if Globals != null:
		current_font_scale = float(Globals.font_scale)

	if mode == _responsive_mode and is_equal_approx(current_font_scale, _responsive_font_scale):
		return
	_responsive_mode = mode
	_responsive_font_scale = current_font_scale

	var left_width := 360
	var right_width := 340
	var font_size := 18
	var separation := 20

	match mode:
		"narrow":
			left_width = 260
			right_width = 300
			font_size = 14
			separation = 12
		"wide":
			left_width = 320
			right_width = 380
			font_size = 18
			separation = 24
		_:
			left_width = 280
			right_width = 340
			font_size = 18
			separation = 20

	if _left_area_user_resized:
		left_width = maxi(int(_main_content_default_split_offset), LEFT_AREA_MIN_WIDTH)
	else:
		left_width = maxi(int(left_width), LEFT_AREA_MIN_WIDTH)

	if is_instance_valid(left_area):
		left_area.custom_minimum_size.x = LEFT_AREA_MIN_WIDTH
	_main_content_default_split_offset = left_width
	if _left_area_visible:
		main_content.split_offset = left_width

	var right_panel := $UIRoot/MainContent/CenterSplit/RightPanel
	if is_instance_valid(right_panel):
		right_panel.custom_minimum_size.x = right_width
	_center_split_default_split_offset = -right_width
	if _right_panel_visible:
		center_split.split_offset = _center_split_default_split_offset

	var top_bar := $UIRoot/TopBar
	if top_bar is VBoxContainer:
		var info_row := (top_bar as VBoxContainer).get_node_or_null("InfoRow")
		if info_row is HBoxContainer:
			(info_row as HBoxContainer).add_theme_constant_override("separation", separation)
		var button_row := (top_bar as VBoxContainer).get_node_or_null("ButtonRow")
		if button_row is HBoxContainer:
			(button_row as HBoxContainer).add_theme_constant_override("separation", separation)
	elif top_bar is FlowContainer:
		# 单行布局（可自动换行）：InfoRow + ButtonRow。
		top_bar.add_theme_constant_override("h_separation", separation)
		top_bar.add_theme_constant_override("v_separation", 6)
		var info_row := top_bar.get_node_or_null("InfoRow")
		if info_row is HBoxContainer:
			(info_row as HBoxContainer).add_theme_constant_override("separation", separation)
		var button_row := top_bar.get_node_or_null("ButtonRow")
		if button_row is HBoxContainer:
			(button_row as HBoxContainer).add_theme_constant_override("separation", separation)
	elif top_bar is HBoxContainer:
		(top_bar as HBoxContainer).add_theme_constant_override("separation", separation)

	var scaled_font_size := font_size
	if Globals != null:
		scaled_font_size = int(Globals.get_scaled_font_size(font_size))

	if is_instance_valid(round_label):
		round_label.add_theme_font_size_override("font_size", scaled_font_size)
	if is_instance_valid(phase_label):
		phase_label.add_theme_font_size_override("font_size", scaled_font_size)
	if is_instance_valid(bank_label):
		bank_label.add_theme_font_size_override("font_size", scaled_font_size)
	if is_instance_valid(current_player_label):
		current_player_label.add_theme_font_size_override("font_size", scaled_font_size)

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
	if _replay_mode_active and _replay_step_timeline.has("steps"):
		head_index = _replay_head_step_index
		cursor_index = _replay_cursor_step_index
	elif _history_step_timeline_active and _history_step_timeline.has("steps"):
		head_index = _history_head_step_index
		cursor_index = _history_cursor_step_index
	var replay_suffix := ""
	if _replay_mode_active:
		replay_suffix = "（回放）"
	elif cursor_index < head_index:
		replay_suffix = "（复盘）"

	if state.phase == "Restructuring":
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
		_panel_controller.sync(state)
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
	_sync_timeline_ui(head_index, cursor_index)

	# 同步调试面板
	if _debug_panel != null and _debug_panel.visible:
		_debug_panel.refresh_state()

func _on_debug_command_executed(command: String, _result: String) -> void:
	# undo/redo/restore/load 会“改写时间线”；
	# M4.3：日志面板统一使用 step_timeline，因此时间线变化后需要重建 step_timeline 视图。
	var cmd := str(command).strip_edges()
	var head := cmd.split(" ", false, 1)[0] if not cmd.is_empty() else ""
	var is_timeline_change := (head == "undo" or head == "redo" or head == "restore" or head == "load")

	# 避免时间线变化后仍停留在旧面板/选点上下文导致“看起来没回退”；
	# 先 hide，再走 _update_ui 的 sync，让必要的强制弹窗可按新 state 重新打开。
	if is_timeline_change:
		if _panel_controller != null and _panel_controller.has_method("hide_all"):
			_panel_controller.hide_all()
		_apply_live_log_timeline_from_engine()

	# 调试命令执行后刷新游戏 UI
	_update_ui()

func rewind_to_phase_start() -> void:
	if game_engine == null:
		return
	if _replay_mode_active:
		GameLog.warn("Game", "回放模式下无法回退阶段")
		return

	var idx_r: Result = game_engine.find_phase_start_command_index()
	if not idx_r.ok:
		GameLog.warn("Game", "计算阶段开始索引失败: %s" % idx_r.error)
		return

	var target_index := int(idx_r.value)
	var current_index := int(game_engine.current_command_index)
	if target_index >= current_index:
		return

	var state := game_engine.get_state()
	var phase_name := str(state.phase)
	var steps := current_index - target_index

	_show_confirm(
		"回退到阶段开始",
		"确定要回退到【%s】阶段开始吗？\n将撤销本阶段的 %d 步操作。" % [phase_name, steps],
		Callable(self, "_confirm_rewind_to_phase_start").bind(target_index),
		Callable(),
		"回退",
		"取消"
	)

func _confirm_rewind_to_phase_start(target_index: int) -> void:
	if game_engine == null:
		return
	if _panel_controller != null and _panel_controller.has_method("hide_all"):
		_panel_controller.hide_all()

	var result := game_engine.rewind_to_command(target_index)
	if not result.ok:
		GameLog.warn("Game", "回退到阶段开始失败: %s" % result.error)
	else:
		_apply_live_log_timeline_from_engine()
	_update_ui()

func _execute_command(command: Command) -> Result:
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")
	if _replay_mode_active:
		return Result.failure("回放模式下无法执行命令")
	var head_index := game_engine.command_history.size() - 1
	if int(game_engine.current_command_index) < head_index:
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
		# 实时日志：仅在日志面板可见时重建（降低每步全量回放开销）。
		if is_instance_valid(game_log_panel) and game_log_panel.visible:
			_apply_live_log_timeline_from_engine()

	_update_ui()
	return result

func _get_last_working_sub_phase_name() -> String:
	var last_sub_phase := "PlaceRestaurants"
	if game_engine != null and game_engine.phase_manager != null and game_engine.phase_manager.has_method("get_working_sub_phase_order_names"):
		var order = game_engine.phase_manager.get_working_sub_phase_order_names()
		if order is Array and not order.is_empty():
			last_sub_phase = str(order[order.size() - 1])
	return last_sub_phase

func _maybe_auto_complete_mandatory_actions_before_skip(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if command.action_id != "skip":
		return Result.success()
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")

	var state: GameState = game_engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")
	if str(state.phase) != "Working":
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
	if str(state.phase) != "Payday":
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
	_execute_command(Command.create_system("advance_phase"))

func _on_advance_sub_phase_pressed() -> void:
	_execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))

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
	_execute_command(Command.create("skip", current_player_id))

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
	# 关闭顶层 Window
	if is_instance_valid(menu_dialog) and menu_dialog.visible:
		_on_menu_dialog_close_requested()
		return true
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog) and _confirm_dialog.visible:
		_confirm_dialog.hide()
		return true

	if _overlay_controller != null:
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
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

# === P2 工具方法（对外 API）===

func is_replay_mode_active() -> bool:
	return _replay_mode_active

func is_timeline_read_only_active() -> bool:
	# Read-only whenever we're using a replay engine, or when the local engine cursor is behind head (reviewing history).
	if _replay_mode_active:
		return true
	if game_engine == null:
		return false
	var head_index := game_engine.command_history.size() - 1
	var cursor_index := int(game_engine.current_command_index)
	return cursor_index < head_index

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
		_start_replay_from_file(path)
		return

	# 预留：未来可支持“游戏内载入存档”
	GameLog.warn("Game", "未支持的存档载入上下文: %s (%s)" % [_save_load_context, path])

func _on_save_completed(path: String) -> void:
	if path.is_empty():
		return
	GameLog.info("Game", "存档已保存: %s" % path)

func _init_replay_bar() -> void:
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return
	if not game_log_panel.has_method("get_replay_bar"):
		return
	var rb = game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return

	if rb.has_signal("seek_requested"):
		UiSignalHelpersClass.safe_connect(rb, "seek_requested", _on_replay_bar_seek_requested)
	if rb.has_signal("return_latest_requested"):
		UiSignalHelpersClass.safe_connect(rb, "return_latest_requested", _on_replay_bar_return_latest_requested)
	if rb.has_signal("load_requested"):
		UiSignalHelpersClass.safe_connect(rb, "load_requested", _on_replay_bar_load_requested)
	if rb.has_signal("close_requested"):
		UiSignalHelpersClass.safe_connect(rb, "close_requested", _on_replay_bar_close_requested)

	if rb.has_method("set_active"):
		rb.call("set_active", false)

func _set_replay_bar_state(head_index: int, cursor_index: int, read_only: bool) -> void:
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return
	if not game_log_panel.has_method("get_replay_bar"):
		return
	var rb = game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return

	if rb.has_method("set_active"):
		rb.call("set_active", true)
	if rb.has_method("set_timeline"):
		var extra := ""
		if _replay_mode_active and _replay_step_timeline.has("steps"):
			extra = _build_replay_bar_status_extra(cursor_index, _replay_step_timeline)
		elif _history_step_timeline_active and _history_step_timeline.has("steps"):
			extra = _build_replay_bar_status_extra(cursor_index, _history_step_timeline)
		rb.call("set_timeline", head_index, cursor_index, read_only, extra)

func _build_replay_bar_status_extra(step_index: int, timeline: Dictionary) -> String:
	# M4.3：不展示 step/cmd，仅展示“当前阶段”。
	if timeline == null or timeline.is_empty():
		return ""

	var idx := int(step_index)
	var phase := ""
	if idx < 0:
		var init_val = timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			phase = str(Dictionary(init_val).get("phase", "")).strip_edges()
	else:
		var steps_val = timeline.get("steps", null)
		if not (steps_val is Array):
			return ""
		var steps: Array = steps_val
		if idx >= steps.size():
			return ""
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			return ""
		phase = str(Dictionary(s_val).get("phase", "")).strip_edges()

	var display_name = GameLogPanel.PHASE_DISPLAY_NAMES.get(phase, phase)
	if str(display_name).strip_edges().is_empty():
		return "初始"
	return "阶段：%s" % str(display_name)

func _hide_replay_bar() -> void:
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return
	if not game_log_panel.has_method("get_replay_bar"):
		return
	var rb = game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return
	if rb.has_method("set_active"):
		rb.call("set_active", false)

func _sync_timeline_ui(head_index: int, cursor_index: int) -> void:
	if is_instance_valid(game_log_panel):
		game_log_panel.set_timeline_head(head_index)
		game_log_panel.set_timeline_cursor(cursor_index)

	var show_bar := _replay_mode_active or cursor_index < head_index
	if show_bar:
		_set_replay_bar_state(head_index, cursor_index, _replay_mode_active)
	else:
		_hide_replay_bar()

	# 回放/查看历史：禁用 ActionPanel（避免时间线分支与误操作）。
	if is_instance_valid(action_panel) and action_panel.has_method("set_globally_disabled"):
		var reason := ""
		if _replay_mode_active:
			reason = "回放中不可操作"
		elif cursor_index < head_index:
			reason = "查看历史中不可操作"
		action_panel.set_globally_disabled(reason)

func _start_replay_from_file(file_path: String) -> void:
	if file_path.is_empty():
		return
	_replay_file_path = file_path

	# 若是从对局中进入回放：保留原日志，退出回放时可恢复。
	if not _replay_mode_active and is_instance_valid(game_log_panel) and game_log_panel.has_method("get_entries"):
		_replay_original_log_entries = game_log_panel.get_entries()

	var engine := GameEngine.new()
	var load_result: Result = engine.load_from_file(file_path)
	if not load_result.ok:
		GameLog.error("Game", "回放加载失败: %s" % load_result.error)
		if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		_show_confirm("回放加载失败", load_result.error, Callable(), Callable())
		return

	if _startup_replay_from_main_menu and Globals != null and Globals.has_method("sync_runtime_config_from_engine"):
		Globals.sync_runtime_config_from_engine(engine)

	_enter_replay_mode(engine)
	_apply_full_replay_log_timeline(engine)
	_show_game_log_panel_in_right_panel()

	if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
		SceneManager.hide_loading()
	if _startup_replay_from_main_menu:
		call_deferred("_start_background_ui_warmup")

func _apply_full_replay_log_timeline(engine: GameEngine) -> void:
	if engine == null or not is_instance_valid(engine):
		return
	if not is_instance_valid(game_log_panel):
		return

	# M4.2：构建 step_index 时间线（阶段切分点 + 状态快照），用于回放步进与日志高亮。
	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		GameLog.error("Game", "构建 step 时间线失败: %s" % build_r.error)
		_show_confirm("回放加载失败", "构建 step 时间线失败: %s" % build_r.error, Callable(), Callable())
		return

	var timeline_val = build_r.value
	if not (timeline_val is Dictionary):
		_show_confirm("回放加载失败", "构建 step 时间线失败: 内部错误（返回类型错误）", Callable(), Callable())
		return

	_replay_step_timeline = Dictionary(timeline_val).duplicate(true)

	var events_val = _replay_step_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := _build_log_entries_from_timeline_events(events)
	if game_log_panel.has_method("load_step_timeline"):
		game_log_panel.load_step_timeline(_replay_step_timeline, entries, true)
	else:
		game_log_panel.load_entries(entries)

	var steps_val = _replay_step_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	_replay_head_step_index = steps.size() - 1
	_replay_cursor_step_index = _replay_head_step_index

	game_log_panel.set_timeline_head(_replay_head_step_index)
	game_log_panel.set_timeline_cursor(_replay_cursor_step_index)
	_set_replay_bar_state(_replay_head_step_index, _replay_cursor_step_index, true)

func _apply_live_log_timeline_from_engine() -> void:
	# M4.3：正常对局（实时）也使用 step_timeline 来渲染日志结构。
	# - 仅在本地 engine 下使用（回放模式由 _apply_full_replay_log_timeline 负责）。
	# - timeline 的结构来自 steps，内容来自 formatter(entries)。
	if _replay_mode_active:
		return
	if game_engine == null:
		return
	if not is_instance_valid(game_log_panel):
		return

	var build_r: Result = StepTimelineBuildClass.build_full(game_engine)
	if not build_r.ok:
		GameLog.warn("Game", "构建 step 时间线失败（实时日志将为空/不更新）: %s" % build_r.error)
		return
	if not (build_r.value is Dictionary):
		GameLog.warn("Game", "构建 step 时间线失败（返回类型错误）")
		return

	_history_step_timeline = Dictionary(build_r.value).duplicate(true)
	_history_step_timeline_active = true

	var events_val = _history_step_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := _build_log_entries_from_timeline_events(events)
	if game_log_panel.has_method("load_step_timeline"):
		# 保留 UI-only 日志（例如动作失败提示），避免 rebuild 覆盖用户可见反馈。
		game_log_panel.load_step_timeline(_history_step_timeline, entries, false)
	else:
		game_log_panel.load_entries(entries)

	var steps_val = _history_step_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	_history_head_step_index = steps.size() - 1

	# 默认定位到“当前引擎指针”的稳定落点：
	# - 若在最新：cursor=head_step；
	# - 若在历史：cursor=该 command_index 对应的最后一个 step（通常是该命令链路结束后的稳定状态）。
	var head_cmd := game_engine.command_history.size() - 1
	var cursor_cmd := int(game_engine.current_command_index)
	if cursor_cmd < 0:
		_history_cursor_step_index = -1
	elif cursor_cmd >= head_cmd:
		_history_cursor_step_index = _history_head_step_index
	else:
		_history_cursor_step_index = _command_index_to_last_step_index(cursor_cmd, _history_step_timeline)
		if _history_cursor_step_index < -1:
			_history_cursor_step_index = _history_head_step_index

	game_log_panel.set_timeline_head(_history_head_step_index)
	game_log_panel.set_timeline_cursor(_history_cursor_step_index)

func _command_index_to_last_step_index(command_index: int, timeline: Dictionary) -> int:
	var cmd := int(command_index)
	if cmd < 0:
		return -1
	if timeline == null or timeline.is_empty():
		return -1
	var steps_val = timeline.get("steps", null)
	if not (steps_val is Array):
		return -1
	var steps: Array = steps_val
	for idx in range(steps.size() - 1, -1, -1):
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if int(s.get("anchor_command_index", -999)) == cmd:
			return idx
	return -1

func _build_log_entries_from_timeline_events(events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if events == null or events.is_empty():
		return out

	var formatter = GameEventLogFormatterClass.new()
	var entry_id := 0

	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var event_type := str(ev.get("type", "")).strip_edges()
		var is_stage_event := (
			event_type == EventBus.EventType.PHASE_CHANGED
			or event_type == EventBus.EventType.SUB_PHASE_CHANGED
			or event_type == EventBus.EventType.ROUND_STARTED
			or event_type == EventBus.EventType.ROUND_ENDED
			or event_type == EventBus.EventType.PLAYER_TURN_STARTED
			or event_type == EventBus.EventType.PLAYER_TURN_ENDED
			or event_type.ends_with("_report")
		)
		var cmd_index := int(ev.get("command_index", -1))
		var step_index := int(ev.get("step_index", cmd_index))
		var phase_segment := str(ev.get("phase_segment", "")).strip_edges()
		var event_seq := int(ev.get("sequence", entry_id))

		var formatted: Array = formatter.format(ev) if (formatter != null and is_instance_valid(formatter) and formatter.has_method("format")) else []
		for f_val in formatted:
			if not (f_val is Dictionary):
				continue
			var f: Dictionary = f_val
			var log_type := int(f.get("type", GameLogPanel.LogType.DEBUG))
			var msg := str(f.get("message", ""))
			var details_val = f.get("details", {})
			var details: Dictionary = details_val if (details_val is Dictionary) else {}
			if not details.has("command_index"):
				details["command_index"] = cmd_index
			if not details.has("step_index"):
				details["step_index"] = step_index
			if not phase_segment.is_empty() and not details.has("phase_segment"):
				details["phase_segment"] = phase_segment
			if not event_type.is_empty() and not details.has("event_type"):
				details["event_type"] = event_type
			if not details.has("is_stage_event"):
				details["is_stage_event"] = is_stage_event

			out.append({
				"type": log_type,
				"message": msg,
				"timestamp": str(event_seq),
				"details": details,
				"command_index": cmd_index,
				"step_index": step_index,
				"phase_segment": phase_segment,
				"event_seq": event_seq,
				"event_type": event_type,
				"is_stage_event": is_stage_event,
			})
			entry_id += 1

	return out

func _on_log_entry_clicked(entry_id: int) -> void:
	if game_engine == null:
		return
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return
	if not game_log_panel.has_method("get_entry_timeline_index"):
		return
	var idx := int(game_log_panel.call("get_entry_timeline_index", entry_id))
	if idx < -1:
		return
	_on_replay_bar_seek_requested(idx)

func _on_timeline_seek_requested(timeline_index: int) -> void:
	_on_replay_bar_seek_requested(int(timeline_index))

func _on_replay_bar_seek_requested(target_index: int) -> void:
	if game_engine == null:
		return

	# M4.2：回放模式采用 step_index（阶段切分点）seek，直接用快照覆盖 game_engine.state（只读）。
	if _replay_mode_active and _replay_step_timeline.has("steps"):
		_seek_to_replay_step(int(target_index))
		return

	# 复盘（非回放）：当 step 时间线激活时，seek 参数为 step_index。
	if _history_step_timeline_active and _history_step_timeline.has("steps"):
		_seek_to_history_step(int(target_index))
		return

	var head_index := game_engine.command_history.size() - 1
	var target := clampi(int(target_index), -1, head_index)
	if target == int(game_engine.current_command_index):
		# 若已经通过其它路径回退到历史命令（cursor<head），也允许“原地切换”为 step 时间线，
		# 以便把该命令链路中的 auto-advance 大阶段拆分成可步进点（避免看起来仍被打包在一个位置）。
		if not _history_step_timeline_active and target < head_index:
			var step_target2 := _enter_history_step_timeline_for_command(target)
			if step_target2 >= -1:
				_seek_to_history_step(step_target2)
				return
		_update_ui()
		return

	# 首次进入复盘：从命令时间线切换到 step 时间线（用于大阶段切分）。
	if target < head_index:
		var step_target := _enter_history_step_timeline_for_command(target)
		if step_target >= -1:
			_seek_to_history_step(step_target)
			return

	var r := game_engine.rewind_to_command(target)
	if not r.ok:
		GameLog.warn("Game", "时间线 seek 失败: %s" % r.error)
		return

	_update_ui()

func _enter_history_step_timeline_for_command(target_command_index: int) -> int:
	if _history_step_timeline_active and _history_step_timeline.has("steps"):
		return _history_command_index_to_step_index(int(target_command_index))
	if game_engine == null:
		return -999
	if not is_instance_valid(game_log_panel):
		return -999

	var build_r: Result = StepTimelineBuildClass.build_full(game_engine)
	if not build_r.ok:
		GameLog.warn("Game", "构建 step 时间线失败（复盘模式将回退到命令时间线）: %s" % build_r.error)
		return -999
	if not (build_r.value is Dictionary):
		GameLog.warn("Game", "构建 step 时间线失败（返回类型错误）")
		return -999

	_history_step_timeline = Dictionary(build_r.value).duplicate(true)
	_history_step_timeline_active = true

	var events_val = _history_step_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := _build_log_entries_from_timeline_events(events)
	if game_log_panel.has_method("load_step_timeline"):
		game_log_panel.load_step_timeline(_history_step_timeline, entries, false)
	else:
		game_log_panel.load_entries(entries)

	var steps_val = _history_step_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	_history_head_step_index = steps.size() - 1
	_history_cursor_step_index = _history_head_step_index

	game_log_panel.set_timeline_head(_history_head_step_index)
	game_log_panel.set_timeline_cursor(_history_cursor_step_index)
	_set_replay_bar_state(_history_head_step_index, _history_cursor_step_index, false)
	_show_game_log_panel_in_right_panel()

	return _history_command_index_to_step_index(int(target_command_index))

func _history_command_index_to_step_index(command_index: int) -> int:
	if not _history_step_timeline.has("steps"):
		return -999
	var steps_val = _history_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return -999
	var steps: Array = steps_val
	var cmd := int(command_index)
	if cmd < 0:
		return -1
	for idx in range(steps.size()):
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if str(s.get("kind", "")).strip_edges() != "command":
			continue
		if int(s.get("anchor_command_index", -999)) == cmd:
			return idx
	return -999

func _seek_to_history_step(target_step_index: int) -> void:
	if game_engine == null:
		return
	if not _history_step_timeline.has("steps"):
		return

	var steps_val = _history_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return
	var steps: Array = steps_val

	_history_head_step_index = steps.size() - 1
	var target := clampi(int(target_step_index), -1, _history_head_step_index)
	if target == _history_cursor_step_index:
		_update_ui()
		return

	var state_dict: Dictionary = {}
	var anchor_cmd := -1
	if target < 0:
		var init_val = _history_step_timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			state_dict = Dictionary(init_val)
	else:
		if target >= steps.size():
			return
		var step_val = steps[target]
		if step_val is Dictionary:
			var step: Dictionary = step_val
			anchor_cmd = int(step.get("anchor_command_index", -1))
			var sd_val = step.get("state_dict", null)
			if sd_val is Dictionary:
				state_dict = Dictionary(sd_val)

	if state_dict.is_empty():
		GameLog.warn("Game", "复盘 step seek 失败：缺少 state 快照: step=%d" % target)
		return

	var restore_r := GameState.from_dict(state_dict)
	if not restore_r.ok:
		GameLog.warn("Game", "复盘 step seek 失败：恢复 state 失败: %s" % restore_r.error)
		return
	var restored: GameState = restore_r.value
	if restored == null:
		GameLog.warn("Game", "复盘 step seek 失败：恢复 state 为空")
		return

	# 复盘态：允许用 step 快照覆盖 state；动作面板仍保持禁用，避免产生新分支。
	game_engine.state = restored
	game_engine.current_command_index = anchor_cmd
	_history_cursor_step_index = target

	_update_ui()

func _exit_history_step_timeline() -> void:
	# M4.3：正常对局也使用 step 时间线视图；“退出复盘”仅意味着跳回最新 step。
	if not _history_step_timeline_active or not _history_step_timeline.has("steps"):
		_on_replay_bar_seek_requested(game_engine.command_history.size() - 1)
		return
	_seek_to_history_step(_history_head_step_index)

func _seek_to_replay_step(target_step_index: int) -> void:
	if game_engine == null:
		return
	if not _replay_step_timeline.has("steps"):
		return

	var steps_val = _replay_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return
	var steps: Array = steps_val

	_replay_head_step_index = steps.size() - 1
	var target := clampi(int(target_step_index), -1, _replay_head_step_index)
	if target == _replay_cursor_step_index:
		_update_ui()
		return

	var state_dict: Dictionary = {}
	var anchor_cmd := -1
	if target < 0:
		var init_val = _replay_step_timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			state_dict = Dictionary(init_val)
	else:
		if target >= steps.size():
			return
		var step_val = steps[target]
		if step_val is Dictionary:
			var step: Dictionary = step_val
			anchor_cmd = int(step.get("anchor_command_index", -1))
			var sd_val = step.get("state_dict", null)
			if sd_val is Dictionary:
				state_dict = Dictionary(sd_val)

	if state_dict.is_empty():
		GameLog.warn("Game", "回放 step seek 失败：缺少 state 快照: step=%d" % target)
		return

	var restore_r := GameState.from_dict(state_dict)
	if not restore_r.ok:
		GameLog.warn("Game", "回放 step seek 失败：恢复 state 失败: %s" % restore_r.error)
		return
	var restored: GameState = restore_r.value
	if restored == null:
		GameLog.warn("Game", "回放 step seek 失败：恢复 state 为空")
		return

	# 只读回放：允许直接覆盖 state（不改写 command_history/checkpoints）。
	game_engine.state = restored
	game_engine.current_command_index = anchor_cmd
	_replay_cursor_step_index = target

	_update_ui()

func _on_replay_bar_return_latest_requested() -> void:
	if game_engine == null:
		return
	if _replay_mode_active and _replay_step_timeline.has("steps"):
		_on_replay_bar_seek_requested(_replay_head_step_index)
		return
	if _history_step_timeline_active and _history_step_timeline.has("steps"):
		_exit_history_step_timeline()
		return
	_on_replay_bar_seek_requested(game_engine.command_history.size() - 1)

func _on_replay_bar_load_requested() -> void:
	_ensure_save_load_dialog()
	_save_load_context = "replay"
	_save_load_dialog.open_for_replay()

func _on_replay_bar_close_requested() -> void:
	if _startup_replay_from_main_menu:
		Globals.reset_game_config()
		SceneManager.goto_main_menu()
		return

	# 对局内“查看历史”态：关闭等价于“返回最新”。
	if not _replay_mode_active:
		_on_replay_bar_return_latest_requested()
		return

	_hide_replay_bar()
	_exit_replay_mode()

	# 恢复对局内进入回放前的日志（避免依赖已被回放覆盖的 EventBus.history）。
	if not _replay_original_log_entries.is_empty() and is_instance_valid(game_log_panel):
		game_log_panel.load_entries(_replay_original_log_entries)
	_replay_original_log_entries.clear()

	if game_engine != null and is_instance_valid(game_log_panel):
		var head_index := game_engine.command_history.size() - 1
		var cursor_index := int(game_engine.current_command_index)
		game_log_panel.set_timeline_head(head_index)
		game_log_panel.set_timeline_cursor(cursor_index)

func show_replay_player(file_path: String) -> void:
	# Debug-only 工具：覆盖式 ReplayPlayer（旧入口）
	# 说明：主流程已切换为日志面板顶部的 ReplayBar；保留该面板用于开发期排查/对照。
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
		if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		_show_confirm("回放加载失败", load_result.error, Callable(), Callable())
		return

	var replay_engine: GameEngine = _replay_player.get_game_engine()
	if replay_engine == null:
		GameLog.error("Game", "回放加载失败: GameEngine 为空")
		if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		_show_confirm("回放加载失败", "内部错误: GameEngine 为空", Callable(), Callable())
		return

	if _startup_replay_from_main_menu and Globals != null and Globals.has_method("sync_runtime_config_from_engine"):
		Globals.sync_runtime_config_from_engine(replay_engine)

	_enter_replay_mode(replay_engine)
	if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
		SceneManager.hide_loading()
	if _startup_replay_from_main_menu and _event_log_controller != null and _event_log_controller.has_method("rebuild_from_history"):
		_event_log_controller.rebuild_from_history()
	if _startup_replay_from_main_menu:
		call_deferred("_start_background_ui_warmup")

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
	_replay_step_timeline.clear()
	_replay_head_step_index = -1
	_replay_cursor_step_index = -1

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

	# 回放 seek 会重建 EventBus.history（record_event，不会通知订阅者），
	# 因此 UI 日志需显式从 history 重建，避免残留旧时间线日志。
	if _event_log_controller != null and _event_log_controller.has_method("rebuild_from_history"):
		_event_log_controller.rebuild_from_history()

func _on_replay_error(message: String) -> void:
	GameLog.warn("ReplayPlayer", message)

func _on_replay_close_requested() -> void:
	if _startup_replay_from_main_menu:
		Globals.reset_game_config()
		SceneManager.goto_main_menu()
		return
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
		_apply_live_log_timeline_from_engine()

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
