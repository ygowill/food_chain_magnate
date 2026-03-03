# Game scene：覆盖层/工具 UI 控制器（P2）
# 负责：
# - 帮助提示/动画管理器/缩放控制初始化
# - 距离覆盖层、营销范围覆盖层、采购路线覆盖层、需求指示器、晚餐时间覆盖层
# - SettingsDialog / GameLogPanel 入口方法
class_name GameOverlayController
extends RefCounted

const SettingsDialogScene = preload("res://ui/dialogs/settings_dialog.tscn")
const HelpTooltipManagerScene = preload("res://ui/components/help_tooltip/help_tooltip_manager.tscn")
const EmployeeCardPreviewManagerScene = preload("res://ui/components/employee_card_preview/employee_card_preview_manager.tscn")
const UIAnimationManagerScene = preload("res://ui/visual/ui_animation_manager.tscn")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ZoomControllerClass = preload("res://ui/scenes/game/overlay/zoom.gd")
const DistanceOverlayControllerClass = preload("res://ui/scenes/game/overlay/distance.gd")
const MarketingRangeOverlayControllerClass = preload("res://ui/scenes/game/overlay/marketing_range.gd")
const ProcurementRouteOverlayControllerClass = preload("res://ui/scenes/game/overlay/procurement_route.gd")
const DemandIndicatorControllerClass = preload("res://ui/scenes/game/overlay/demand_indicator.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const DinnertimeAnimControllerClass = preload("res://ui/scenes/game/dinnertime/controller.gd")
const CommandClass = preload("res://core/types/command.gd")

const TOAST_DESIRED_WIDTH := 520.0
const TOAST_MIN_MARGIN := 12.0
const TOAST_OFFSET_TOP := 16.0
const TOAST_HEIGHT := 62.0
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

var _scene = null
var _map_view = null
var _map_canvas = null
var _game_log_panel = null
var _bank_break_panel = null

# Compatibility aliases (older code may read these directly)
var distance_overlay = null
var marketing_range_overlay = null
var procurement_route_overlay = null
var demand_indicator = null
var zoom_control = null
var settings_dialog = null
var help_tooltip_manager = null
var employee_card_preview_manager = null
var ui_animation_manager = null

var _zoom_controller = null
var _distance_overlay_controller = null
var _marketing_range_controller = null
var _procurement_route_controller = null
var _demand_indicator_controller = null
var _help_tooltips_initialized: bool = false
var _milestone_toast_initialized: bool = false
var _toast_queue: Array[String] = []
var _toast_showing: bool = false
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _deferred_milestone_toasts: Array[Dictionary] = []
var _eventbus_source: String = ""
var _execute_command: Callable = Callable()
var _dinnertime_anim_controller = null  # DinnertimeAnimationController
var _ui_sync_controller = null  # GameUiSyncController (for bank_label)
var _player_panel = null  # PlayerPanel
var _dinnertime_confirm_in_flight: bool = false
var _dinnertime_confirm_in_flight_round: int = -1
var _dinnertime_confirm_in_flight_local_pid: int = -1
var _dinnertime_confirm_in_flight_request_id: String = ""
var _dinnertime_confirm_in_flight_since_ms: int = -1

func _init(scene, map_view, map_canvas, game_log_panel) -> void:
	_scene = scene
	_map_view = map_view
	_map_canvas = map_canvas
	_game_log_panel = game_log_panel
	_eventbus_source = "GameOverlay:%s" % str(get_instance_id())

	_zoom_controller = ZoomControllerClass.new(_scene, _map_view)
	_distance_overlay_controller = DistanceOverlayControllerClass.new(_scene, _map_canvas)
	_marketing_range_controller = MarketingRangeOverlayControllerClass.new(_scene, _map_canvas)
	_procurement_route_controller = ProcurementRouteOverlayControllerClass.new(_scene, _map_canvas)
	_demand_indicator_controller = DemandIndicatorControllerClass.new(_scene, _map_canvas)

func set_execute_command(callable: Callable) -> void:
	_execute_command = callable

func set_ui_sync_controller(ctrl) -> void:
	_ui_sync_controller = ctrl

func set_player_panel(panel) -> void:
	_player_panel = panel

func set_bank_break_panel(panel) -> void:
	_bank_break_panel = panel
	if _demand_indicator_controller != null:
		_demand_indicator_controller.set_bank_break_panel(panel)

func initialize() -> void:
	# 初始化帮助提示管理器
	if help_tooltip_manager == null:
		help_tooltip_manager = HelpTooltipManagerScene.instantiate()
		_scene.add_child(help_tooltip_manager)
	_setup_help_tooltips()

	# 初始化员工卡片预览管理器（统一悬停/点击预览）
	if employee_card_preview_manager == null:
		employee_card_preview_manager = EmployeeCardPreviewManagerScene.instantiate()
		_scene.add_child(employee_card_preview_manager)

	# 初始化动画管理器
	if ui_animation_manager == null:
		ui_animation_manager = UIAnimationManagerScene.instantiate()
		_scene.add_child(ui_animation_manager)
	if ui_animation_manager != null and ui_animation_manager.has_method("set_animation_speed"):
		ui_animation_manager.set_animation_speed(float(Globals.animation_speed))

	# 初始化游戏日志面板（但不显示）
	if is_instance_valid(_game_log_panel):
		_game_log_panel.visible = false

	_setup_milestone_toasts()

	# 初始化缩放控制
	if _zoom_controller != null:
		_zoom_controller.initialize()
		zoom_control = _zoom_controller.zoom_control

# === 覆盖层入口（P2）===

func show_distance_overlay(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	if _distance_overlay_controller != null:
		_distance_overlay_controller.show_distance_overlay(from_position, to_positions)
		distance_overlay = _distance_overlay_controller.distance_overlay

func show_distance_overlay_pair(
	house_position: Vector2i,
	restaurant_position: Vector2i,
	path_points: Array[Vector2i],
	distance: int
) -> void:
	if _distance_overlay_controller != null:
		_distance_overlay_controller.show_distance_overlay_pair(house_position, restaurant_position, path_points, distance)
		distance_overlay = _distance_overlay_controller.distance_overlay

func hide_distance_overlay() -> void:
	if _distance_overlay_controller != null:
		_distance_overlay_controller.hide_distance_overlay()

func show_marketing_range_overlay(campaigns: Array[Dictionary]) -> void:
	if _marketing_range_controller != null:
		_marketing_range_controller.show_marketing_range_overlay(campaigns)
		marketing_range_overlay = _marketing_range_controller.marketing_range_overlay

func hide_marketing_range_overlay() -> void:
	if _marketing_range_controller != null:
		_marketing_range_controller.hide_marketing_range_overlay()

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String, extra: Dictionary = {}) -> void:
	if _marketing_range_controller != null:
		_marketing_range_controller.preview_marketing_range(position, range_val, marketing_type, extra)
		marketing_range_overlay = _marketing_range_controller.marketing_range_overlay

func show_procurement_route_overlay(entrance_pos: Vector2i, route: Array[Vector2i], picked_sources: Array[Vector2i] = [], options: Dictionary = {}) -> void:
	if _procurement_route_controller != null:
		_procurement_route_controller.show_procurement_route_overlay(entrance_pos, route, picked_sources, options)
		procurement_route_overlay = _procurement_route_controller.procurement_route_overlay

func hide_procurement_route_overlay() -> void:
	if _procurement_route_controller != null:
		_procurement_route_controller.hide_procurement_route_overlay()

func toggle_game_log() -> void:
	if is_instance_valid(_game_log_panel):
		_game_log_panel.visible = not _game_log_panel.visible

func show_settings_dialog() -> void:
	if _scene == null:
		return
	if settings_dialog == null:
		settings_dialog = SettingsDialogScene.instantiate()
		_scene.add_child(settings_dialog)
		UiSignalHelpersClass.safe_connect(settings_dialog, "settings_changed", _on_settings_changed)

	if settings_dialog.has_method("show_dialog"):
		settings_dialog.show_dialog()
	else:
		settings_dialog.show()

func get_ui_animation_manager():
	return ui_animation_manager

func get_help_tooltip_manager():
	if help_tooltip_manager == null or not is_instance_valid(help_tooltip_manager):
		return null
	return help_tooltip_manager

func _on_settings_changed(settings: Dictionary) -> void:
	# 仅处理“运行时需要立即生效”的设置项
	if settings == null:
		return

	if ui_animation_manager != null and ui_animation_manager.has_method("set_animation_speed"):
		ui_animation_manager.set_animation_speed(float(settings.get("animation_speed", Globals.animation_speed)))

	Globals.confirm_actions = bool(settings.get("confirm_actions", Globals.confirm_actions))
	Globals.show_hints = bool(settings.get("show_hints", Globals.show_hints))
	Globals.replay_load_playable = bool(settings.get("replay_load_playable", Globals.replay_load_playable))
	Globals.animation_speed = float(settings.get("animation_speed", Globals.animation_speed))

	# 字体倍率：允许在运行时立即生效（主要用于调试可读性）。
	if settings.has("font_scale") and Globals != null:
		Globals.font_scale = clampf(float(settings.get("font_scale", Globals.font_scale)), 0.5, 2.0)
		if Globals.has_method("apply_font_scale"):
			Globals.apply_font_scale()
		if settings.has("log_font_scale") and Globals != null:
			Globals.log_font_scale = clampf(float(settings.get("log_font_scale", Globals.log_font_scale)), 0.5, 3.0)
		if is_instance_valid(_game_log_panel) and _game_log_panel.has_method("apply_font_settings"):
			_game_log_panel.apply_font_settings()
		if _scene != null and is_instance_valid(_scene):
			var player_panel = _scene.get("player_panel")
			if is_instance_valid(player_panel) and player_panel.has_method("apply_font_settings"):
				player_panel.apply_font_settings()
			var inventory_panel = _scene.get("inventory_panel")
			if is_instance_valid(inventory_panel) and inventory_panel.has_method("apply_font_settings"):
				inventory_panel.apply_font_settings()
			var left_panel = _scene.get("left_panel")
			if is_instance_valid(left_panel) and left_panel.has_method("apply_font_settings"):
				left_panel.apply_font_settings()
		if _scene != null and is_instance_valid(_scene) and _scene.has_method("_apply_responsive_layout"):
			_scene.call_deferred("_apply_responsive_layout")

func _setup_help_tooltips() -> void:
	if _help_tooltips_initialized:
		return
	_help_tooltips_initialized = true

	if help_tooltip_manager == null or not is_instance_valid(help_tooltip_manager):
		return
	if _scene == null:
		return
	if not help_tooltip_manager.has_method("register_control"):
		return

	# 静态 UI 元素：直接绑定固定 key
	var action_panel = _scene.get("action_panel")
	if is_instance_valid(action_panel) and action_panel is Control:
		help_tooltip_manager.register_control(action_panel, "ui_action_panel")

	var player_panel = _scene.get("player_panel")
	if is_instance_valid(player_panel) and player_panel is Control:
		help_tooltip_manager.register_control(player_panel, "ui_player_panel")

	var inventory_panel = _scene.get("inventory_panel")
	if is_instance_valid(inventory_panel) and inventory_panel is Control:
		help_tooltip_manager.register_control(inventory_panel, "ui_inventory")

	var turn_order_track = _scene.get("turn_order_track")
	if is_instance_valid(turn_order_track) and turn_order_track is Control:
		help_tooltip_manager.register_control(turn_order_track, "mechanic_turn_order")

	var bank_label = _scene.get("bank_label")
	if is_instance_valid(bank_label) and bank_label is Control:
		bank_label.mouse_filter = Control.MOUSE_FILTER_STOP
		bank_label.mouse_default_cursor_shape = Control.CURSOR_HELP
		help_tooltip_manager.register_control(bank_label, "mechanic_bank")

	var btn_log = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/LogButton")
	if btn_log is Control:
		var c1: Control = btn_log
		c1.mouse_default_cursor_shape = Control.CURSOR_HELP
		help_tooltip_manager.register_control(c1, "ui_topbar_log")

	var btn_milestones = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/MilestonesButton")
	if btn_milestones is Control:
		var c2: Control = btn_milestones
		c2.mouse_default_cursor_shape = Control.CURSOR_HELP
		help_tooltip_manager.register_control(c2, "ui_topbar_milestones")

	var btn_distance = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/DistanceToolButton")
	if btn_distance is Control:
		var c3: Control = btn_distance
		c3.mouse_default_cursor_shape = Control.CURSOR_HELP
		help_tooltip_manager.register_control(c3, "ui_topbar_distance_tool")

	var btn_settings = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/SettingsButton")
	if btn_settings is Control:
		var c4: Control = btn_settings
		c4.mouse_default_cursor_shape = Control.CURSOR_HELP
		help_tooltip_manager.register_control(c4, "ui_topbar_settings")

	# 动态：PhaseTrack 根据悬停阶段显示不同帮助
	var phase_track = _scene.get("phase_track")
	if is_instance_valid(phase_track) and phase_track is Control:
		phase_track.mouse_filter = Control.MOUSE_FILTER_STOP
		phase_track.mouse_default_cursor_shape = Control.CURSOR_HELP
		var hover_changed_cb := Callable(self, "_on_phase_track_hover_changed")
		var hover_exited_cb := Callable(self, "_on_phase_track_hover_exited")
		if phase_track.has_signal("phase_hover_changed") and phase_track.has_signal("phase_hover_exited"):
			if not phase_track.is_connected("phase_hover_changed", hover_changed_cb):
				phase_track.connect("phase_hover_changed", hover_changed_cb)
			if not phase_track.is_connected("phase_hover_exited", hover_exited_cb):
				phase_track.connect("phase_hover_exited", hover_exited_cb)
		else:
			# 兼容旧版 PhaseTrack（仅能显示当前阶段提示）
			if not phase_track.mouse_entered.is_connected(_on_phase_label_mouse_entered):
				phase_track.mouse_entered.connect(_on_phase_label_mouse_entered)
			if not phase_track.mouse_exited.is_connected(_on_phase_label_mouse_exited):
				phase_track.mouse_exited.connect(_on_phase_label_mouse_exited)

func _on_phase_track_hover_changed(phase_key: String, hover_global_pos: Vector2) -> void:
	if help_tooltip_manager == null or not is_instance_valid(help_tooltip_manager):
		return
	if not help_tooltip_manager.has_method("show_immediate"):
		return

	var key := _get_phase_help_key(str(phase_key))
	if key.is_empty():
		if help_tooltip_manager.has_method("hide_tooltip"):
			help_tooltip_manager.hide_tooltip()
		return
	help_tooltip_manager.show_immediate(key, hover_global_pos)

func _on_phase_track_hover_exited() -> void:
	if help_tooltip_manager != null and is_instance_valid(help_tooltip_manager):
		if help_tooltip_manager.has_method("hide_tooltip"):
			help_tooltip_manager.hide_tooltip()

func _on_phase_label_mouse_entered() -> void:
	if help_tooltip_manager == null or not is_instance_valid(help_tooltip_manager):
		return
	if _scene == null:
		return
	if not help_tooltip_manager.has_method("show_immediate"):
		return

	var phase_track = _scene.get("phase_track")
	if not is_instance_valid(phase_track) or not (phase_track is Control):
		return

	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return
	var state: GameState = engine.get_state()
	if state == null:
		return

	var key := _get_phase_help_key(str(state.phase))
	if key.is_empty():
		return

	var phase_ctrl: Control = phase_track
	var pos: Vector2 = phase_ctrl.get_global_rect().position + (phase_ctrl.size / 2.0)
	help_tooltip_manager.show_immediate(key, pos)

func _on_phase_label_mouse_exited() -> void:
	if help_tooltip_manager != null and is_instance_valid(help_tooltip_manager):
		if help_tooltip_manager.has_method("hide_tooltip"):
			help_tooltip_manager.hide_tooltip()

func _get_phase_help_key(phase: String) -> String:
	match phase:
		DefsClass.PHASE_SETUP:
			return "phase_setup"
		DefsClass.PHASE_RESTRUCTURING:
			return "phase_restructuring"
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			return "phase_order_of_business"
		DefsClass.PHASE_WORKING:
			return "phase_working"
		DefsClass.PHASE_DINNERTIME:
			return "phase_dinner_time"
		DefsClass.PHASE_PAYDAY:
			return "phase_payday"
		DefsClass.PHASE_MARKETING:
			return "phase_marketing"
		DefsClass.PHASE_CLEANUP:
			return "phase_cleanup"
		DefsClass.PHASE_GAME_OVER:
			return "phase_game_over"
	return ""

func hide_all_overlays() -> void:
	hide_distance_overlay()
	hide_marketing_range_overlay()
	hide_procurement_route_overlay()

func dispose() -> void:
	if not _eventbus_source.is_empty():
		EventBus.unsubscribe_all_from_source(_eventbus_source)
	_eventbus_source = ""

	if is_instance_valid(_toast_tween):
		_toast_tween.kill()
	_toast_tween = null

	if is_instance_valid(_toast_panel):
		_toast_panel.queue_free()
	_toast_panel = null
	_toast_label = null
	_toast_queue.clear()
	_deferred_milestone_toasts.clear()
	_toast_showing = false

	_zoom_controller = null
	_distance_overlay_controller = null
	_marketing_range_controller = null
	_procurement_route_controller = null
	_disable_dinnertime_overlay()
	_demand_indicator_controller = null

	_scene = null
	_map_view = null
	_map_canvas = null
	_game_log_panel = null
	_bank_break_panel = null

	# Compatibility aliases
	distance_overlay = null
	marketing_range_overlay = null
	procurement_route_overlay = null
	demand_indicator = null
	zoom_control = null
	settings_dialog = null
	help_tooltip_manager = null
	ui_animation_manager = null

func _setup_milestone_toasts() -> void:
	if _milestone_toast_initialized:
		return
	_milestone_toast_initialized = true
	EventBus.subscribe(EventBus.EventType.MILESTONE_ACHIEVED, Callable(self, "_on_milestone_achieved"), 120, _eventbus_source)

func _on_milestone_achieved(event: Dictionary) -> void:
	if OS.has_feature("headless"):
		return
	if not (event is Dictionary) or event.is_empty():
		return
	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return
	var data: Dictionary = data_val

	var milestone_id := str(data.get("milestone_id", "")).strip_edges()
	var player_id := int(data.get("player_id", -1))
	if milestone_id.is_empty():
		return

	if _should_defer_milestone_toast():
		_deferred_milestone_toasts.append({
			"player_id": player_id,
			"milestone_id": milestone_id,
		})
		return
	show_milestone_toast(player_id, milestone_id)

func show_milestone_toast(player_id: int, milestone_id: String) -> void:
	if OS.has_feature("headless"):
		return
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return

	# 去重：若该 toast 已在 Dinnertime 期间被 EventBus 暂存，则消费并避免结算结束后重复弹出。
	for i in range(_deferred_milestone_toasts.size() - 1, -1, -1):
		var item_val = _deferred_milestone_toasts[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("player_id", -999)) != player_id:
			continue
		if str(item.get("milestone_id", "")).strip_edges() != mid:
			continue
		_deferred_milestone_toasts.remove_at(i)

	var msg := _build_milestone_toast_message(player_id, mid)
	if msg.is_empty():
		return
	_enqueue_toast(msg)

func _build_milestone_toast_message(player_id: int, milestone_id: String) -> String:
	var who := "玩家%d" % (player_id + 1) if player_id >= 0 else "未知玩家"
	if Globals != null and player_id >= 0 and Globals.has_method("get_player_name"):
		who = str(Globals.get_player_name(player_id))

	var name := milestone_id
	if MilestoneRegistryClass.is_loaded() and not milestone_id.is_empty():
		var def_val = MilestoneRegistryClass.get_def(milestone_id)
		if def_val != null and def_val is MilestoneDef:
			name = str((def_val as MilestoneDef).name)
			name = _strip_milestone_id_suffix(name, milestone_id)

	return "%s 获得里程碑：%s" % [who, name]

func _should_defer_milestone_toast() -> bool:
	# Dinnertime 的结算动画是“演示已结算的结果”，但事件本身会在命令执行结束后立刻发射。
	# 为避免“刚进晚餐就弹里程碑”，在晚餐待确认/动画期间暂存提示；
	# 动画过程中会按 timeline 在“本笔支付完成后”主动弹出里程碑，因此这里的暂存仅作为兜底与去重来源。
	if _dinnertime_anim_controller != null:
		return true
	var live_state := _read_live_game_state()
	if live_state == null:
		return false
	if str(live_state.phase) != DefsClass.PHASE_DINNERTIME:
		return false
	return _is_confirm_dinnertime_pending(live_state)

func _flush_deferred_milestone_toasts() -> void:
	if _deferred_milestone_toasts.is_empty():
		return
	var queued := _deferred_milestone_toasts.duplicate(true)
	_deferred_milestone_toasts.clear()
	for item_val in queued:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		show_milestone_toast(int(item.get("player_id", -1)), str(item.get("milestone_id", "")))

func _strip_milestone_id_suffix(raw_name: String, milestone_id: String) -> String:
	var s := str(raw_name).strip_edges()
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return s

	var suffixes: Array[String] = [
		" (" + mid + ")",
		"(" + mid + ")",
		" （" + mid + "）",
		"（" + mid + "）",
	]
	for suffix in suffixes:
		if s.ends_with(suffix):
			return s.substr(0, s.length() - suffix.length()).strip_edges()
	return s

func show_toast(message: String) -> void:
	if OS.has_feature("headless"):
		return
	_enqueue_toast(message)

func _enqueue_toast(message: String) -> void:
	var msg := message.strip_edges()
	if msg.is_empty():
		return
	_toast_queue.append(msg)
	_try_show_next_toast()

func _try_show_next_toast() -> void:
	if _toast_showing:
		return
	if _toast_queue.is_empty():
		return
	_toast_showing = true
	var msg: String = str(_toast_queue.pop_front())
	_show_toast(msg)

func _ensure_toast_panel() -> void:
	if _scene == null:
		return
	if is_instance_valid(_toast_panel):
		return
	var toast_host: Node = _scene
	var game_area = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/GameArea")
	if game_area is Control:
		toast_host = game_area

	_toast_panel = PanelContainer.new()
	_toast_panel.name = "MilestoneToast"
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 需要高于 GameOver 等终局遮罩（GameOverPanel.z_index=1400），保证提示可见。
	UiZClass.apply_absolute(_toast_panel, UiZClass.TOAST)

	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 0.0
	_toast_panel.anchor_bottom = 0.0
	_apply_toast_panel_layout()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.86, 0.95)
	style.border_color = Color(0.4, 0.7, 0.9, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_toast_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	_toast_panel.add_child(margin)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast_label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_toast_label)

	_toast_panel.visible = false
	toast_host.add_child(_toast_panel)

func _apply_toast_panel_layout() -> void:
	if not is_instance_valid(_toast_panel):
		return
	if _scene == null:
		return

	var viewport_w := 0.0
	var host = _toast_panel.get_parent()
	if host is Control:
		viewport_w = float((host as Control).size.x)
	elif _scene is Control:
		viewport_w = float((_scene as Control).get_viewport_rect().size.x)
	elif _scene.has_method("get_viewport_rect"):
		viewport_w = float(_scene.get_viewport_rect().size.x)

	var target_w := TOAST_DESIRED_WIDTH
	if viewport_w > 0.0:
		target_w = minf(TOAST_DESIRED_WIDTH, maxf(0.0, viewport_w - TOAST_MIN_MARGIN * 2.0))
		if target_w <= 0.0:
			target_w = viewport_w

	_toast_panel.offset_left = -target_w * 0.5
	_toast_panel.offset_right = target_w * 0.5
	_toast_panel.offset_top = TOAST_OFFSET_TOP
	_toast_panel.offset_bottom = TOAST_OFFSET_TOP + TOAST_HEIGHT

func _show_toast(message: String) -> void:
	_ensure_toast_panel()
	if not is_instance_valid(_toast_panel) or _toast_label == null:
		_toast_showing = false
		return

	_apply_toast_panel_layout()
	_toast_label.text = message
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0

	if _toast_tween != null and is_instance_valid(_toast_tween):
		_toast_tween.kill()
		_toast_tween = null

	_toast_tween = _toast_panel.create_tween()
	_toast_tween.set_ease(Tween.EASE_OUT)
	_toast_tween.set_trans(Tween.TRANS_QUAD)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.2)
	_toast_tween.finished.connect(func():
		if is_instance_valid(_toast_panel):
			_toast_panel.visible = false
			_toast_panel.modulate.a = 1.0
		_toast_showing = false
		_try_show_next_toast()
	)

# === Dinnertime 可视化（只读）===

func _reset_dinnertime_confirm_in_flight() -> void:
	_dinnertime_confirm_in_flight = false
	_dinnertime_confirm_in_flight_round = -1
	_dinnertime_confirm_in_flight_local_pid = -1
	_dinnertime_confirm_in_flight_request_id = ""
	_dinnertime_confirm_in_flight_since_ms = -1

func _set_dinnertime_confirm_in_flight(state: GameState, request_id: String) -> void:
	if state == null:
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var local_pid := int(NetContext.local_player_id)
	if local_pid < 0:
		return
	_dinnertime_confirm_in_flight = true
	_dinnertime_confirm_in_flight_round = int(state.round_number)
	_dinnertime_confirm_in_flight_local_pid = local_pid
	_dinnertime_confirm_in_flight_request_id = str(request_id)
	_dinnertime_confirm_in_flight_since_ms = int(Time.get_ticks_msec())

func _is_dinnertime_confirm_in_flight_for_state(state: GameState) -> bool:
	if not _dinnertime_confirm_in_flight:
		return false
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if state == null:
		return false
	if int(state.round_number) != _dinnertime_confirm_in_flight_round:
		return false
	var local_pid := int(NetContext.local_player_id)
	if local_pid < 0:
		return false
	return local_pid == _dinnertime_confirm_in_flight_local_pid

func sync_dinnertime_overlay(state: GameState, is_live: bool = true) -> void:
	# 非 DINNERTIME 阶段 或 回放模式 → 隐藏
	if str(state.phase) != DefsClass.PHASE_DINNERTIME or not is_live:
		_reset_dinnertime_confirm_in_flight()
		_disable_dinnertime_overlay()
		return

	# 检查是否还有“本地玩家待确认”的晚餐结算 pending（避免与其它模块注入的 Dinnertime pending 冲突）
	if not _is_confirm_dinnertime_pending_for_local(state):
		_reset_dinnertime_confirm_in_flight()
		_disable_dinnertime_overlay()
		return

	# 联机模式：晚餐确认已发出但本地状态仍未更新时，避免重复播放/重复确认。
	if _is_dinnertime_confirm_in_flight_for_state(state):
		return

	# 提取结算数据
	var dt_data := _get_dinnertime_report(state)
	if dt_data.is_empty():
		_disable_dinnertime_overlay()
		return

	# 动画控制器已在运行则跳过
	if _dinnertime_anim_controller != null:
		return

	_start_dinnertime_animation(dt_data, state)

# === 需求指示器 ===

func sync_demand_indicator(state: GameState) -> void:
	if _demand_indicator_controller == null:
		return
	# 晚餐结算面板是一个“模态”覆盖层：显示时不应继续在地图上渲染需求指示器，
	# 否则会出现巨大图标/矩形块，干扰结算阅读。
	if _is_confirm_dinnertime_pending(state) or _dinnertime_anim_controller != null:
		_demand_indicator_controller.hide()
		demand_indicator = _demand_indicator_controller.demand_indicator
		return

	_demand_indicator_controller.sync_demand_indicator(state)
	demand_indicator = _demand_indicator_controller.demand_indicator

func _is_confirm_dinnertime_pending(state: GameState) -> bool:
	var list := _read_dinnertime_pending_list(state)
	if list.is_empty():
		return false
	if _is_legacy_confirm_dinnertime_pending(list):
		return true
	if not _is_only_player_confirm_dinnertime_pending(list):
		return false
	return true

func _is_confirm_dinnertime_pending_for_local(state: GameState) -> bool:
	var list := _read_dinnertime_pending_list(state)
	if list.is_empty():
		return false
	if _is_legacy_confirm_dinnertime_pending(list):
		return true
	if not _is_only_player_confirm_dinnertime_pending(list):
		return false
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		if local_pid < 0:
			return false
		return _list_has_player_confirm_dinnertime_pending(list, local_pid)
	return true

func _read_dinnertime_pending_list(state: GameState) -> Array:
	if state == null:
		return []
	if not (state.round_state is Dictionary):
		return []
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return []
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if not (list_val is Array):
		return []
	return Array(list_val)

func _is_legacy_confirm_dinnertime_pending(list: Array) -> bool:
	return list.size() == 1 and (list[0] is String) and str(list[0]) == KIND_CONFIRM_DINNERTIME

func _is_only_player_confirm_dinnertime_pending(list: Array) -> bool:
	if list.is_empty():
		return false
	for item_val in list:
		if not (item_val is Dictionary):
			return false
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			return false
		var pid_val = item.get("player_id", null)
		if not (pid_val is int):
			if not (pid_val is float and float(pid_val) == floor(float(pid_val))):
				return false
	return true

func _list_has_player_confirm_dinnertime_pending(list: Array, player_id: int) -> bool:
	for item_val in list:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			continue
		var pid_val = item.get("player_id", null)
		var pid := -1
		if pid_val is int:
			pid = int(pid_val)
		elif pid_val is float and float(pid_val) == floor(float(pid_val)):
			pid = int(pid_val)
		if pid == player_id:
			return true
	return false

func _get_dinnertime_report(state: GameState) -> Dictionary:
	if not (state.round_state is Dictionary):
		return {}
	var val = Dictionary(state.round_state).get("dinnertime", null)
	if val is Dictionary:
		return val
	return {}

func _start_dinnertime_animation(dt_data: Dictionary, state: GameState) -> void:
	if _scene == null:
		return

	hide_all_overlays()
	if _demand_indicator_controller != null:
		_demand_indicator_controller.hide()

	var bank_label: Label = null
	if _ui_sync_controller != null and _ui_sync_controller.has_method("get_bank_label"):
		bank_label = _ui_sync_controller.get_bank_label()

	_dinnertime_anim_controller = DinnertimeAnimControllerClass.new()
	_dinnertime_anim_controller.settlement_completed.connect(_on_dinnertime_anim_completed)
	_dinnertime_anim_controller.start(
		dt_data,
		state,
		_scene,
		_map_canvas,
		bank_label,
		_player_panel,
		_bank_break_panel,
		Callable(self, "show_milestone_toast")
	)
	if _ui_sync_controller != null and _ui_sync_controller.has_method("set_skip_bank_sync"):
		_ui_sync_controller.set_skip_bank_sync(true)

func _read_live_game_state() -> GameState:
	if _scene == null or not is_instance_valid(_scene):
		return null
	if not _scene.has_method("get"):
		return null
	var engine_val = _scene.get("game_engine")
	if engine_val == null or not engine_val.has_method("get_state"):
		return null
	var state_val = engine_val.get_state()
	return state_val if state_val is GameState else null

func _should_send_dinnertime_confirm() -> bool:
	var live_state := _read_live_game_state()
	if live_state == null:
		return false
	if str(live_state.phase) != DefsClass.PHASE_DINNERTIME:
		return false
	if not _is_confirm_dinnertime_pending_for_local(live_state):
		return false
	if _is_dinnertime_confirm_in_flight_for_state(live_state):
		return false
	if _scene != null and is_instance_valid(_scene) and _scene.has_method("_is_online_resync_in_progress"):
		if bool(_scene.call("_is_online_resync_in_progress")):
			return false
	return true

func _on_dinnertime_anim_completed() -> void:
	if _ui_sync_controller != null and _ui_sync_controller.has_method("set_skip_bank_sync"):
		_ui_sync_controller.set_skip_bank_sync(false)
	if not _should_send_dinnertime_confirm():
		_disable_dinnertime_overlay()
		return
	if _execute_command.is_valid():
		var live_state := _read_live_game_state()
		var confirm_cmd = CommandClass.create_system("confirm_dinnertime")
		if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
			var local_pid := int(NetContext.local_player_id)
			if local_pid < 0:
				_disable_dinnertime_overlay()
				return
			confirm_cmd = CommandClass.create("confirm_dinnertime", local_pid, {})
		var exec_r_val = _execute_command.call(confirm_cmd)
		if exec_r_val is Result:
			if exec_r_val.ok:
				var req_id := ""
				if exec_r_val.value is Dictionary:
					req_id = str(Dictionary(exec_r_val.value).get("request_id", ""))
				_set_dinnertime_confirm_in_flight(live_state, req_id)
			else:
				var phase := str(live_state.phase) if live_state != null else "-"
				var pending := _read_dinnertime_pending_list(live_state)
				var mode := str(NetContext.mode) if NetContext != null else "NetContext:null"
				var local_pid2 := int(NetContext.local_player_id) if NetContext != null else -1
				GameLog.warn(
					"Game",
					"确认晚餐结算失败: %s phase=%s local_pid=%d mode=%s pending=%s"
						% [str(exec_r_val.error), phase, local_pid2, mode, str(pending)]
				)
	_disable_dinnertime_overlay()

func _disable_dinnertime_overlay() -> void:
	if _dinnertime_anim_controller != null:
		_dinnertime_anim_controller.dispose()
	_dinnertime_anim_controller = null
	if _ui_sync_controller != null and _ui_sync_controller.has_method("set_skip_bank_sync"):
		_ui_sync_controller.set_skip_bank_sync(false)
	_flush_deferred_milestone_toasts()
