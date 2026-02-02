# Game scene：Working 阶段面板（Recruit/Train/Price/Production/Milestone）
extends RefCounted

const RecruitControllerClass = preload("res://ui/scenes/game/game_panel_working_recruit_controller.gd")
const PriceControllerClass = preload("res://ui/scenes/game/game_panel_working_price_controller.gd")
const MilestoneControllerClass = preload("res://ui/scenes/game/game_panel_working_milestone_controller.gd")
const TrainControllerClass = preload("res://ui/scenes/game/game_panel_working_train_controller.gd")
const ProductionControllerClass = preload("res://ui/scenes/game/game_panel_working_production_controller.gd")

var _scene = null
var _map_controller = null
var _execute_command: Callable
var _hide_all: Callable
var _center_popup: Callable
var _overlay_controller = null
var _recruit_controller = null
var _price_controller = null
var _milestone_controller = null
var _train_controller = null
var _production_controller = null

var recruit_panel = null
var train_panel = null
var price_panel = null
var production_panel = null
var milestone_panel = null

func _init(scene, map_controller, execute_command: Callable, hide_all: Callable, center_popup: Callable, overlay_controller = null) -> void:
	_scene = scene
	_map_controller = map_controller
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup
	_overlay_controller = overlay_controller
	_recruit_controller = RecruitControllerClass.new(_scene, _execute_command, _hide_all, _center_popup)
	_price_controller = PriceControllerClass.new(_scene, _execute_command, _hide_all, _center_popup)
	_milestone_controller = MilestoneControllerClass.new(_scene, _hide_all, _center_popup)
	_train_controller = TrainControllerClass.new(_scene, _execute_command, _hide_all, _center_popup)
	_production_controller = ProductionControllerClass.new(_scene, _map_controller, _overlay_controller, _execute_command, _hide_all, _center_popup)

func hide() -> void:
	if is_instance_valid(recruit_panel):
		recruit_panel.visible = false
	if is_instance_valid(train_panel):
		train_panel.visible = false
	if is_instance_valid(price_panel):
		price_panel.visible = false
	if is_instance_valid(production_panel):
		production_panel.visible = false
	if is_instance_valid(milestone_panel):
		milestone_panel.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	_sync_recruit_panel(state, force_full_refresh)
	_sync_train_panel(state, force_full_refresh)
	_sync_production_panel(state, force_full_refresh)
	_sync_price_panel(state, force_full_refresh)
	_sync_milestone_panel(state, force_full_refresh)

func show_recruit_panel() -> void:
	if _recruit_controller == null:
		return
	_recruit_controller.show()
	recruit_panel = _recruit_controller.recruit_panel

func _sync_recruit_panel(state: GameState, force_full_refresh: bool = false) -> void:
	if _recruit_controller != null:
		_recruit_controller.sync(state, force_full_refresh)

func show_train_panel() -> void:
	if _train_controller == null:
		return
	_train_controller.show()
	train_panel = _train_controller.train_panel

func _sync_train_panel(state: GameState, force_full_refresh: bool = false) -> void:
	if _train_controller != null:
		_train_controller.sync(state, force_full_refresh)

func show_price_panel(action_id: String) -> void:
	if _price_controller == null:
		return
	_price_controller.show(action_id)
	price_panel = _price_controller.price_panel

func _sync_price_panel(state: GameState, force_full_refresh: bool = false) -> void:
	if _price_controller != null:
		_price_controller.sync(state, force_full_refresh)

func show_production_panel(production_type: String) -> void:
	if _production_controller == null:
		return
	_production_controller.show(production_type)
	production_panel = _production_controller.production_panel

func _sync_production_panel(state: GameState, force_full_refresh: bool = false) -> void:
	if _production_controller != null:
		_production_controller.sync(state, force_full_refresh)

func _sync_milestone_panel(state: GameState, force_full_refresh: bool = false) -> void:
	if _milestone_controller != null:
		_milestone_controller.sync(state, force_full_refresh)

func show_milestone_panel() -> void:
	if _milestone_controller == null:
		return
	_milestone_controller.show()
	milestone_panel = _milestone_controller.milestone_panel
