# Game scene：覆盖层/工具 UI 控制器（P2）
# 负责：
# - 帮助提示/动画管理器/缩放控制初始化
# - 距离覆盖层、营销范围覆盖层、采购路线覆盖层、需求指示器、晚餐时间覆盖层
# - SettingsDialog / GameLogPanel 入口方法
class_name GameOverlayController
extends RefCounted

const SettingsDialogScene = preload("res://ui/dialogs/settings_dialog.tscn")
const HelpTooltipManagerScene = preload("res://ui/components/help_tooltip/help_tooltip_manager.tscn")
const UIAnimationManagerScene = preload("res://ui/visual/ui_animation_manager.tscn")
const ZoomControllerClass = preload("res://ui/scenes/game/game_overlay_zoom.gd")
const DistanceOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_distance.gd")
const MarketingRangeOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_marketing_range.gd")
const ProcurementRouteOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_procurement_route.gd")
const DinnertimeOverlayControllerClass = preload("res://ui/scenes/game/game_overlay_dinnertime.gd")
const DemandIndicatorControllerClass = preload("res://ui/scenes/game/game_overlay_demand_indicator.gd")

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
var dinner_time_overlay = null
var settings_dialog = null
var help_tooltip_manager = null
var ui_animation_manager = null

var _zoom_controller = null
var _distance_overlay_controller = null
var _marketing_range_controller = null
var _procurement_route_controller = null
var _dinnertime_overlay_controller = null
var _demand_indicator_controller = null
var _help_tooltips_initialized: bool = false

func _init(scene, map_view, map_canvas, game_log_panel) -> void:
	_scene = scene
	_map_view = map_view
	_map_canvas = map_canvas
	_game_log_panel = game_log_panel

	_zoom_controller = ZoomControllerClass.new(_scene, _map_view)
	_distance_overlay_controller = DistanceOverlayControllerClass.new(_scene, _map_canvas)
	_marketing_range_controller = MarketingRangeOverlayControllerClass.new(_scene, _map_canvas)
	_procurement_route_controller = ProcurementRouteOverlayControllerClass.new(_scene, _map_canvas)
	_dinnertime_overlay_controller = DinnertimeOverlayControllerClass.new(_scene)
	_demand_indicator_controller = DemandIndicatorControllerClass.new(_scene, _map_canvas)

func set_bank_break_panel(panel) -> void:
	_bank_break_panel = panel
	if _dinnertime_overlay_controller != null:
		_dinnertime_overlay_controller.set_bank_break_panel(panel)
	if _demand_indicator_controller != null:
		_demand_indicator_controller.set_bank_break_panel(panel)

func initialize() -> void:
	# 初始化帮助提示管理器
	if help_tooltip_manager == null:
		help_tooltip_manager = HelpTooltipManagerScene.instantiate()
		_scene.add_child(help_tooltip_manager)
	_setup_help_tooltips()

	# 初始化动画管理器
	if ui_animation_manager == null:
		ui_animation_manager = UIAnimationManagerScene.instantiate()
		_scene.add_child(ui_animation_manager)

	# 初始化游戏日志面板（但不显示）
	if is_instance_valid(_game_log_panel):
		_game_log_panel.visible = true

	# 初始化缩放控制
	if _zoom_controller != null:
		_zoom_controller.initialize()
		zoom_control = _zoom_controller.zoom_control

# === 覆盖层入口（P2）===

func show_distance_overlay(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	if _distance_overlay_controller != null:
		_distance_overlay_controller.show_distance_overlay(from_position, to_positions)
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

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String) -> void:
	if _marketing_range_controller != null:
		_marketing_range_controller.preview_marketing_range(position, range_val, marketing_type)
		marketing_range_overlay = _marketing_range_controller.marketing_range_overlay

func show_procurement_route_overlay(entrance_pos: Vector2i, route: Array[Vector2i], picked_sources: Array[Vector2i] = []) -> void:
	if _procurement_route_controller != null:
		_procurement_route_controller.show_procurement_route_overlay(entrance_pos, route, picked_sources)
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

	if settings_dialog.has_method("show_dialog"):
		settings_dialog.show_dialog()
	else:
		settings_dialog.show()

func get_ui_animation_manager():
	return ui_animation_manager

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

	# 动态：PhaseLabel 根据当前 phase 显示不同帮助
	var phase_label = _scene.get("phase_label")
	if is_instance_valid(phase_label) and phase_label is Control:
		phase_label.mouse_filter = Control.MOUSE_FILTER_STOP
		phase_label.mouse_default_cursor_shape = Control.CURSOR_HELP
		if not phase_label.mouse_entered.is_connected(_on_phase_label_mouse_entered):
			phase_label.mouse_entered.connect(_on_phase_label_mouse_entered)
		if not phase_label.mouse_exited.is_connected(_on_phase_label_mouse_exited):
			phase_label.mouse_exited.connect(_on_phase_label_mouse_exited)

func _on_phase_label_mouse_entered() -> void:
	if help_tooltip_manager == null or not is_instance_valid(help_tooltip_manager):
		return
	if _scene == null:
		return
	if not help_tooltip_manager.has_method("show_immediate"):
		return

	var phase_label = _scene.get("phase_label")
	if not is_instance_valid(phase_label) or not (phase_label is Control):
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

	var phase_ctrl: Control = phase_label
	var pos: Vector2 = phase_ctrl.get_global_rect().position + (phase_ctrl.size / 2.0)
	help_tooltip_manager.show_immediate(key, pos)

func _on_phase_label_mouse_exited() -> void:
	if help_tooltip_manager != null and is_instance_valid(help_tooltip_manager):
		if help_tooltip_manager.has_method("hide_tooltip"):
			help_tooltip_manager.hide_tooltip()

func _get_phase_help_key(phase: String) -> String:
	match phase:
		"Setup":
			return "phase_setup"
		"Restructuring":
			return "phase_restructuring"
		"OrderOfBusiness":
			return "phase_order_of_business"
		"Working":
			return "phase_working"
		"Dinnertime":
			return "phase_dinner_time"
		"Payday":
			return "phase_payday"
		"Marketing":
			return "phase_marketing"
		"Cleanup":
			return "phase_cleanup"
		"GameOver":
			return "phase_game_over"
	return ""

func hide_all_overlays() -> void:
	hide_distance_overlay()
	hide_marketing_range_overlay()
	hide_procurement_route_overlay()
	if _demand_indicator_controller != null:
		_demand_indicator_controller.hide()
	if _dinnertime_overlay_controller != null:
		_dinnertime_overlay_controller.hide()

# === Dinnertime 可视化（只读）===

func sync_dinnertime_overlay(state: GameState) -> void:
	if _dinnertime_overlay_controller != null:
		_dinnertime_overlay_controller.sync_dinnertime_overlay(state)
		dinner_time_overlay = _dinnertime_overlay_controller.dinner_time_overlay

# === 需求指示器 ===

func sync_demand_indicator(state: GameState) -> void:
	if _demand_indicator_controller != null:
		_demand_indicator_controller.sync_demand_indicator(state)
		demand_indicator = _demand_indicator_controller.demand_indicator
