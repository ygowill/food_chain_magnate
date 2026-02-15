# Game scene：Payday / BankBreak / GameOver 面板
extends RefCounted

const PaydayPanelScene = preload("res://ui/components/payday_panel/payday_panel.tscn")
const GameOverPanelScene = preload("res://ui/components/game_over/game_over_panel.tscn")
const BankBreakPanelScene = preload("res://ui/components/bank_break/bank_break_panel.tscn")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

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

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	_sync_payday_panel(state, force_full_refresh)

	var is_timeline_read_only := false
	if _scene != null and _scene.has_method("is_timeline_read_only_active"):
		var v = _scene.call("is_timeline_read_only_active")
		if v is bool:
			is_timeline_read_only = bool(v)
	elif _scene != null and _scene.has_method("is_replay_mode_active"):
		# Backwards-compat fallback.
		var v2 = _scene.call("is_replay_mode_active")
		if v2 is bool:
			is_timeline_read_only = bool(v2)

	# 回放/复盘（只读时间线）：不要弹出 BankBreak/GameOver 这类“强提示”面板，避免阻塞时间线回放；
	# 但仍保持 tracking 同步，防止返回最新后错误触发弹窗。
	if is_timeline_read_only:
		if state != null and (state.bank is Dictionary):
			var bank: Dictionary = state.bank
			_last_bank_total = int(bank.get("total", 0))
			_last_bank_broke_count = int(bank.get("broke_count", 0))

		if is_instance_valid(bank_break_panel):
			bank_break_panel.visible = false
		if is_instance_valid(game_over_panel):
			game_over_panel.visible = false
		return

	# 时间线变化：清掉这类“事件型强提示”面板（它们不完全可由 state 推导），并重置 tracking，
	# 避免回退/跳转后残留旧弹窗或错误触发。
	if force_full_refresh:
		reset_bank_break_tracking(state)
		if is_instance_valid(bank_break_panel):
			bank_break_panel.visible = false
		if is_instance_valid(game_over_panel) and state != null and state.phase != DefsClass.PHASE_GAME_OVER:
			game_over_panel.visible = false

	_check_bank_break(state)
	if state != null and state.phase == DefsClass.PHASE_GAME_OVER:
		_show_game_over()
	elif is_instance_valid(game_over_panel):
		game_over_panel.visible = false

func _sync_payday_panel(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(payday_panel) or not payday_panel.visible:
		return
	if state.phase != DefsClass.PHASE_PAYDAY:
		payday_panel.visible = false
		return

	if not force_full_refresh:
		return

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

	if payday_panel.has_method("set_discount") and (state.round_state is Dictionary):
		var round_state: Dictionary = state.round_state
		var discount: int = int(round_state.get("salary_discount", 0))
		payday_panel.set_discount(discount)

	# 薪资为 0：直接跳过，不展示面板。
	if payday_panel.has_method("calculate_total"):
		if int(payday_panel.calculate_total()) <= 0:
			payday_panel.visible = false
			_on_pay_confirmed()
			return

func show_payday_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if payday_panel == null:
		payday_panel = PaydayPanelScene.instantiate()
		payday_panel.visible = false
		payday_panel.set_meta("popup_layout", "dock_right")
		payday_panel.set_meta("popup_title", "发薪日")
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

	# 薪资为 0：直接跳过，不展示面板。
	if payday_panel != null and is_instance_valid(payday_panel) and payday_panel.has_method("calculate_total"):
		if int(payday_panel.calculate_total()) <= 0:
			_on_pay_confirmed()
			return

	if _center_popup.is_valid():
		_center_popup.call(payday_panel)
	payday_panel.visible = true

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
	_execute_command.call(Command.create_system(ActionIdsClass.ADVANCE_PHASE))

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
