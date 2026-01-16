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
@onready var state_hash_label: Label = $DebugDialog/VBoxContainer/StatusRow/StateHashLabel
@onready var command_count_label: Label = $DebugDialog/VBoxContainer/StatusRow/CommandCountLabel
@onready var toggle_bottom_panel_button: Button = $MenuDialog/VBoxContainer/ToggleBottomPanelButton
@onready var menu_dialog: Window = $MenuDialog
@onready var debug_dialog: Window = $DebugDialog
@onready var debug_text: TextEdit = $DebugDialog/VBoxContainer/DebugText
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

var _left_area_visible: bool = true
var _main_content_default_split_offset: int = 360
var _left_area_user_resized: bool = false
const LEFT_AREA_MIN_WIDTH := 200
const LEFT_AREA_MAX_WIDTH := 400

var _bottom_panel_visible: bool = true
var _right_panel_visible: bool = true
var _center_split_default_split_offset: int = -340

var _responsive_mode: String = ""
var _right_panel_footer_source: Object = null

func _ready() -> void:
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

	var should_restore_log_history := false
	if Globals.current_game_engine != null and Globals.current_game_engine is GameEngine:
		var existing_engine: GameEngine = Globals.current_game_engine
		should_restore_log_history = existing_engine.get_state() != null

	if not should_restore_log_history and EventBus != null:
		EventBus.clear_history()

	_apply_ui_layout()
	_init_left_panel_toggle()
	_init_right_panel_toggle()
	_init_right_panel_header()
	_init_right_panel_footer()

	_overlay_controller = GameOverlayControllerClass.new(self, map_view, map_canvas, game_log_panel)
	_overlay_controller.initialize()

	_map_controller = GameMapInteractionControllerClass.new(self, map_canvas, _overlay_controller)
	_map_controller.connect_signals()
	if _map_controller.has_signal("mode_changed") and not _map_controller.mode_changed.is_connected(_on_map_mode_changed):
		_map_controller.mode_changed.connect(_on_map_mode_changed)

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
	_event_log_controller.setup(game_log_panel, should_restore_log_history)

	_initialize_game()
	if game_engine != null:
		_panel_controller.reset_bank_break_tracking(game_engine.get_state())

	# 初始化调试面板
	_setup_debug_panel()
	DebugFlags.debug_panel_toggled.connect(_on_debug_panel_toggled)
	_on_debug_panel_toggled(DebugFlags.show_console)

	_init_bottom_panel_toggle()
	_init_left_area_resize()
	_apply_responsive_layout()
	if is_instance_valid(self) and has_signal("resized"):
		if not resized.is_connected(_on_root_resized):
			resized.connect(_on_root_resized)
	_update_ui()
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
	var clamped := clampi(int(offset), LEFT_AREA_MIN_WIDTH, LEFT_AREA_MAX_WIDTH)
	_main_content_default_split_offset = clamped
	if is_instance_valid(main_content):
		main_content.split_offset = clamped
	if is_instance_valid(left_area):
		left_area.custom_minimum_size.x = clamped

func _init_left_panel_toggle() -> void:
	if is_instance_valid(main_content):
		_main_content_default_split_offset = clampi(int(main_content.split_offset), LEFT_AREA_MIN_WIDTH, LEFT_AREA_MAX_WIDTH)
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
	var version := int(Globals.ui_layout_version) if Globals != null else 2

	if version == 2:
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
	else:
		if is_instance_valid(player_panel):
			player_panel.visible = true
		if is_instance_valid(inventory_panel):
			inventory_panel.visible = true
		if is_instance_valid(left_panel):
			left_panel.visible = false
		if is_instance_valid(game_log_panel):
			game_log_panel.visible = true

		if is_instance_valid(bottom_panel):
			bottom_panel.visible = _bottom_panel_visible
		if is_instance_valid(toggle_bottom_panel_button):
			toggle_bottom_panel_button.visible = true
			_update_bottom_panel_toggle_button()

func _init_bottom_panel_toggle() -> void:
	var version := int(Globals.ui_layout_version) if Globals != null else 2
	_bottom_panel_visible = false if version == 2 else (is_instance_valid(bottom_panel) and bottom_panel.visible)
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

	if mode == _responsive_mode:
		return
	_responsive_mode = mode

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
		left_width = clampi(int(_main_content_default_split_offset), LEFT_AREA_MIN_WIDTH, LEFT_AREA_MAX_WIDTH)
	else:
		left_width = clampi(int(left_width), LEFT_AREA_MIN_WIDTH, LEFT_AREA_MAX_WIDTH)

	if is_instance_valid(left_area):
		left_area.custom_minimum_size.x = left_width
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
	elif top_bar is HBoxContainer:
		(top_bar as HBoxContainer).add_theme_constant_override("separation", separation)

	if is_instance_valid(round_label):
		round_label.add_theme_font_size_override("font_size", font_size)
	if is_instance_valid(phase_label):
		phase_label.add_theme_font_size_override("font_size", font_size)
	if is_instance_valid(bank_label):
		bank_label.add_theme_font_size_override("font_size", font_size)
	if is_instance_valid(current_player_label):
		current_player_label.add_theme_font_size_override("font_size", font_size)

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
	var init_result := game_engine.initialize(Globals.player_count, Globals.random_seed, Globals.enabled_modules_v2, Globals.modules_v2_base_dir, [])
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
	var current_name := Globals.get_player_name(pid) if pid >= 0 else "-"
	var view_id := pid
	if _panel_controller != null and _panel_controller.has_method("get_view_player_id"):
		var v := int(_panel_controller.call("get_view_player_id"))
		if v >= 0:
			view_id = v
	var view_name := Globals.get_player_name(view_id) if view_id >= 0 else "-"

	var replay_suffix := "（回放）" if _replay_mode_active else ""

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

	# 计算状态哈希（截断显示）
	var full_hash := state.compute_hash()
	state_hash_label.text = "Hash: %s..." % full_hash.substr(0, 8)

	# 命令计数
	command_count_label.text = "命令: %d" % game_engine.get_command_history().size()

	if is_instance_valid(game_log_panel) and game_log_panel.has_method("set_player_count"):
		game_log_panel.set_player_count(state.players.size())

	# 地图渲染（M2 接入）
	if is_instance_valid(map_view) and map_view.has_method("set_game_state"):
		map_view.call("set_game_state", state)

	# UI 同步（面板/覆盖层）
	if _panel_controller != null:
		_panel_controller.sync(state)
		_sync_right_panel_docked_view()
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
		_maybe_show_payday_blocker_prompt(command, result)
	else:
		GameLog.info("Game", "命令执行成功: %s" % command.action_id)

	_update_ui()
	return result

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
	if is_instance_valid(debug_dialog) and debug_dialog.visible:
		_on_debug_dialog_close_requested()
		return true
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog) and _confirm_dialog.visible:
		_confirm_dialog.hide()
		return true

	if _overlay_controller != null:
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
			dlg.hide()
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
	if is_instance_valid(debug_dialog) and debug_dialog.visible:
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
			map_mode_bar.show_mode("📏 距离工具", "点击起点，再点击终点｜再次点起点重置｜D/ESC 关闭")
		_:
			map_mode_bar.show_mode("模式：%s" % m, "ESC 取消")

func _on_log_button_pressed() -> void:
	toggle_game_log()

func _on_left_panel_logs_requested() -> void:
	toggle_game_log()

func _on_milestones_button_pressed() -> void:
	show_milestone_panel()

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

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String, extra: Dictionary = {}) -> void:
	if _overlay_controller != null:
		_overlay_controller.preview_marketing_range(position, range_val, marketing_type, extra)

func show_milestone_panel() -> void:
	if _panel_controller != null:
		_panel_controller.show_milestone_panel()

func toggle_game_log() -> void:
	var layout_version := int(Globals.ui_layout_version) if Globals != null else 2
	if layout_version == 2 and is_instance_valid(left_panel) and is_instance_valid(game_log_panel):
		_ensure_left_area_visible()
		var show_logs := not game_log_panel.visible
		game_log_panel.visible = show_logs
		left_panel.visible = not show_logs
		return
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
