# Game scene：Working/Price 面板控制器
# 负责：PriceSettingPanel 的生命周期、同步与命令分发。
class_name GamePanelWorkingPriceController
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PricePanelScene = preload("res://ui/components/price_panel/price_setting_panel.tscn")

var _scene = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()
var _center_popup: Callable = Callable()

var price_panel = null

func _init(scene, execute_command: Callable, hide_all: Callable, center_popup: Callable) -> void:
	_scene = scene
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup

func hide() -> void:
	if is_instance_valid(price_panel):
		price_panel.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(price_panel) or not price_panel.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING:
		price_panel.visible = false
		return

	# 时间线变化：若面板保持打开，刷新当前价格，避免残留旧输入/显示。
	if force_full_refresh and price_panel.has_method("set_current_prices"):
		var current_player: Dictionary = state.get_current_player()
		var prices: Dictionary = current_player.get("prices", {})
		price_panel.set_current_prices(prices)

func show(action_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if price_panel == null:
		price_panel = PricePanelScene.instantiate()
		price_panel.visible = false
		price_panel.set_meta("popup_layout", "dock_right")
		if price_panel.has_signal("price_confirmed"):
			price_panel.price_confirmed.connect(_on_price_confirmed)
		if price_panel.has_signal("cancelled"):
			price_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(price_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if price_panel.has_method("set_mode"):
		match action_id:
			"set_price":
				price_panel.set_meta("popup_title", "定价")
				price_panel.set_mode("price")
			"set_luxury_price":
				price_panel.set_meta("popup_title", "奢侈品定价")
				price_panel.set_mode("luxury")
			"set_discount":
				price_panel.set_meta("popup_title", "折扣")
				price_panel.set_mode("discount")

	if price_panel.has_method("set_current_prices"):
		var prices: Dictionary = current_player.get("prices", {})
		price_panel.set_current_prices(prices)

	if _center_popup.is_valid():
		_center_popup.call(price_panel)
	price_panel.visible = true

func _on_price_confirmed(action_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	if action_id.is_empty():
		return
	var result: Result = _execute_command.call(Command.create(action_id, current_player_id))

	if result.ok and _hide_all.is_valid():
		_hide_all.call()

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()

