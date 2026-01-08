# Game scene：Payday / BankBreak / GameOver 面板
extends RefCounted

const PaydayPanelScene = preload("res://ui/components/payday_panel/payday_panel.tscn")
const GameOverPanelScene = preload("res://ui/components/game_over/game_over_panel.tscn")
const BankBreakPanelScene = preload("res://ui/components/bank_break/bank_break_panel.tscn")

var _scene = null
var _overlay_controller = null
var _execute_command: Callable
var _hide_all: Callable
var _center_popup: Callable
var _refresh_ui: Callable

var _last_bank_total: int = 0
var _last_bank_broke_count: int = 0

var payday_panel = null
var game_over_panel = null
var bank_break_panel = null

func _init(scene, overlay_controller, execute_command: Callable, hide_all: Callable, center_popup: Callable, refresh_ui: Callable) -> void:
	_scene = scene
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup
	_refresh_ui = refresh_ui

func hide() -> void:
	if is_instance_valid(payday_panel):
		payday_panel.visible = false
	if is_instance_valid(bank_break_panel):
		bank_break_panel.visible = false

func reset_bank_break_tracking(state: GameState) -> void:
	if state == null:
		_last_bank_total = 0
		_last_bank_broke_count = 0
		return
	_last_bank_total = int(state.bank.get("total", 0))
	_last_bank_broke_count = int(state.bank.get("broke_count", 0))

func sync(state: GameState) -> void:
	_sync_payday_panel(state)
	_check_bank_break(state)
	if state != null and state.phase == "GameOver":
		_show_game_over()

func _sync_payday_panel(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(payday_panel) or not payday_panel.visible:
		return
	if state.phase != "Payday":
		payday_panel.visible = false
		return

func show_payday_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if payday_panel == null:
		payday_panel = PaydayPanelScene.instantiate()
		payday_panel.fire_employees.connect(_on_fire_employees)
		payday_panel.pay_confirmed.connect(_on_pay_confirmed)
		_scene.add_child(payday_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if payday_panel.has_method("set_employees"):
		var employees: Array[String] = []
		var busy: Array[String] = []
		for e in Array(current_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(current_player.get("busy_marketers", [])):
			busy.append(str(e))
		payday_panel.set_employees(employees, busy)

	if payday_panel.has_method("set_player_cash"):
		payday_panel.set_player_cash(int(current_player.get("cash", 0)))

	if payday_panel.has_method("set_discount"):
		var round_state: Dictionary = state.round_state
		var discount: int = int(round_state.get("salary_discount", 0))
		payday_panel.set_discount(discount)

	payday_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(payday_panel)

func _check_bank_break(state: GameState) -> void:
	if state == null:
		return
	if not (state.bank is Dictionary):
		return

	var bank: Dictionary = state.bank
	var broke_count := int(bank.get("broke_count", 0))
	var bank_total := int(bank.get("total", 0))

	if broke_count > _last_bank_broke_count:
		_show_bank_break_panel(broke_count, _last_bank_total, bank_total)

	_last_bank_broke_count = broke_count
	_last_bank_total = bank_total

func _show_bank_break_panel(broke_count: int, bank_before: int, bank_after: int) -> void:
	if _scene == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if bank_break_panel == null:
		bank_break_panel = BankBreakPanelScene.instantiate()
		if bank_break_panel.has_signal("bankruptcy_acknowledged"):
			bank_break_panel.bankruptcy_acknowledged.connect(_on_bank_break_acknowledged)
		if bank_break_panel.has_signal("game_end_triggered"):
			bank_break_panel.game_end_triggered.connect(_on_bank_break_game_end_triggered)
		_scene.add_child(bank_break_panel)
		if _overlay_controller != null:
			_overlay_controller.set_bank_break_panel(bank_break_panel)

	if bank_break_panel.has_method("set_bankruptcy_info"):
		bank_break_panel.set_bankruptcy_info(broke_count, bank_before, bank_after)

	if bank_break_panel.has_method("show_with_animation"):
		bank_break_panel.show_with_animation()
	else:
		bank_break_panel.visible = true

	if _center_popup.is_valid():
		_center_popup.call(bank_break_panel)

func _show_game_over() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if game_over_panel == null:
		game_over_panel = GameOverPanelScene.instantiate()
		game_over_panel.return_to_menu_requested.connect(_on_game_over_return)
		game_over_panel.play_again_requested.connect(_on_game_over_play_again)
		_scene.add_child(game_over_panel)

	if game_over_panel.has_method("set_final_state"):
		game_over_panel.set_final_state(_scene.game_engine.get_state())

	if game_over_panel.has_method("show_with_animation"):
		game_over_panel.show_with_animation()
	else:
		game_over_panel.visible = true

func _on_fire_employees(employee_ids: Array[String]) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()

	for emp_id in employee_ids:
		_execute_command.call(Command.create("fire", current_player_id, {"employee_id": emp_id}))

	if is_instance_valid(payday_panel):
		show_payday_panel()

func _on_pay_confirmed() -> void:
	if not _execute_command.is_valid():
		return
	if _hide_all.is_valid():
		_hide_all.call()
	_execute_command.call(Command.create_system("advance_phase"))

func _on_game_over_return() -> void:
	Globals.reset_game_config()
	SceneManager.goto_main_menu()

func _on_game_over_play_again() -> void:
	SceneManager.goto_game()

func _on_bank_break_acknowledged() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
	if _refresh_ui.is_valid():
		_refresh_ui.call()

func _on_bank_break_game_end_triggered() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
	if _refresh_ui.is_valid():
		_refresh_ui.call()
