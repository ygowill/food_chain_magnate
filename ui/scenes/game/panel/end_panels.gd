# Game scene：Payday / BankBreak / GameOver 面板
extends RefCounted

const PaydayPanelScene = preload("res://ui/components/payday_panel/payday_panel.tscn")
const GameOverPanelScene = preload("res://ui/components/game_over/game_over_panel.tscn")
const BankBreakPanelScene = preload("res://ui/components/bank_break/bank_break_panel.tscn")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const GameMenuDebugControllerClass = preload("res://ui/scenes/game/menu/debug_controller.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

const REPLAY_SAVES_DIR := "user://saves"

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

var _game_over_replay_save_path: String = ""

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

	var suppress_game_over_modal := false
	if _scene != null and _scene.has_method("should_suppress_game_over_modal"):
		var v = _scene.call("should_suppress_game_over_modal")
		if v is bool:
			suppress_game_over_modal = bool(v)

	var is_replay_mode := false
	if _scene != null and _scene.has_method("is_replay_mode_active"):
		var rm = _scene.call("is_replay_mode_active")
		if rm is bool:
			is_replay_mode = bool(rm)

	var is_timeline_read_only := false
	if _scene != null and _scene.has_method("is_timeline_read_only_active"):
		var v = _scene.call("is_timeline_read_only_active")
		if v is bool:
			is_timeline_read_only = bool(v)
	elif _scene != null and _scene.has_method("is_replay_mode_active"):
		# Backwards-compat fallback.
		is_timeline_read_only = is_replay_mode

	# 回放/复盘（只读时间线）：不要弹出 BankBreak/GameOver 这类“强提示”面板，避免阻塞时间线回放；
	# 但仍保持 tracking 同步，防止返回最新后错误触发弹窗。
	if is_timeline_read_only:
		if state != null and (state.bank is Dictionary):
			var bank: Dictionary = state.bank
			_last_bank_total = int(bank.get("total", 0))
			_last_bank_broke_count = int(bank.get("broke_count", 0))

		if is_instance_valid(bank_break_panel):
			bank_break_panel.visible = false
		# 例外：手动回放导致的“只读时间线”下，若真实对局已到 GameOver，
		# 仍应允许展示 GameOver 面板（提供返回主菜单/再来一局入口），避免软锁。
		if not suppress_game_over_modal and not is_replay_mode and state != null and str(state.phase) == DefsClass.PHASE_GAME_OVER:
			_show_game_over()
		elif is_instance_valid(game_over_panel):
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
		if suppress_game_over_modal:
			if is_instance_valid(game_over_panel):
				game_over_panel.visible = false
		else:
			_show_game_over()
	elif is_instance_valid(game_over_panel):
		game_over_panel.visible = false

func _resolve_payday_player_id(state: GameState) -> int:
	if state == null:
		return -1
	var fallback_player_id := int(state.get_current_player_id())
	return int(OnlinePhaseInteractionClass.get_online_local_player_id(state, fallback_player_id))

func _get_payday_player_snapshot(state: GameState) -> Dictionary:
	if state == null:
		return {}
	var player_id := _resolve_payday_player_id(state)
	if player_id < 0:
		return {}
	return state.get_player(player_id)

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

	var current_player_id := _resolve_payday_player_id(state)
	var current_player := _get_payday_player_snapshot(state)
	var effect_registry = null
	if _scene != null and _scene.game_engine != null and _scene.game_engine.phase_manager != null and _scene.game_engine.phase_manager.has_method("get_effect_registry"):
		effect_registry = _scene.game_engine.phase_manager.get_effect_registry()

	if payday_panel.has_method("set_context"):
		payday_panel.set_context(state, current_player_id, effect_registry)

	if payday_panel.has_method("set_employees"):
		var employees: Array[String] = []
		var reserve: Array[String] = []
		var busy: Array[String] = []
		for e in Array(current_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(current_player.get("reserve_employees", [])):
			reserve.append(str(e))
		for e in Array(current_player.get("busy_marketers", [])):
			busy.append(str(e))
		payday_panel.set_employees(employees, reserve, busy)

	if payday_panel.has_method("set_player_cash"):
		payday_panel.set_player_cash(int(current_player.get("cash", 0)))

func show_payday_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	var cur_state = _scene.game_engine.get_state()
	if cur_state == null or cur_state.phase != DefsClass.PHASE_PAYDAY:
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

	var state = cur_state
	var current_player_id := _resolve_payday_player_id(state)
	var current_player := _get_payday_player_snapshot(state)
	var effect_registry = null
	if _scene != null and _scene.game_engine != null and _scene.game_engine.phase_manager != null and _scene.game_engine.phase_manager.has_method("get_effect_registry"):
		effect_registry = _scene.game_engine.phase_manager.get_effect_registry()

	if payday_panel.has_method("set_context"):
		payday_panel.set_context(state, current_player_id, effect_registry)

	if payday_panel.has_method("set_employees"):
		var employees: Array[String] = []
		var reserve: Array[String] = []
		var busy: Array[String] = []
		for e in Array(current_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(current_player.get("reserve_employees", [])):
			reserve.append(str(e))
		for e in Array(current_player.get("busy_marketers", [])):
			busy.append(str(e))
		payday_panel.set_employees(employees, reserve, busy)

	if payday_panel.has_method("set_player_cash"):
		payday_panel.set_player_cash(int(current_player.get("cash", 0)))

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
		var latest_event := _find_latest_bankruptcy_event(state, broke_count)
		var bank_before := _last_bank_total
		var bank_after := bank_total
		if not latest_event.is_empty():
			if latest_event.has("bank_total_before"):
				bank_before = int(latest_event.get("bank_total_before", bank_before))
			if latest_event.has("bank_total_after"):
				bank_after = int(latest_event.get("bank_total_after", bank_after))
		if _should_defer_bank_break_to_dinnertime_overlay(state, latest_event):
			_ensure_bank_break_panel()
		else:
			_show_bank_break_panel(broke_count, bank_before, bank_after, latest_event)

	_last_bank_broke_count = broke_count
	_last_bank_total = bank_total

func _ensure_bank_break_panel() -> void:
	if _scene == null:
		return
	if bank_break_panel != null:
		return
	bank_break_panel = BankBreakPanelScene.instantiate()
	if bank_break_panel is Control:
		UiZClass.apply_absolute((bank_break_panel as Control), UiZClass.MODAL)
	if bank_break_panel.has_signal("bankruptcy_acknowledged"):
		bank_break_panel.bankruptcy_acknowledged.connect(_on_bank_break_acknowledged)
	if bank_break_panel.has_signal("game_end_triggered"):
		bank_break_panel.game_end_triggered.connect(_on_bank_break_game_end_triggered)
	_scene.add_child(bank_break_panel)
	if _overlay_controller != null:
		_overlay_controller.set_bank_break_panel(bank_break_panel)

func _show_bank_break_panel(broke_count: int, bank_before: int, bank_after: int, event_data: Dictionary = {}) -> void:
	if _scene == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	_ensure_bank_break_panel()

	if bank_break_panel.has_method("set_bankruptcy_info"):
		bank_break_panel.set_bankruptcy_info(broke_count, bank_before, bank_after, event_data)

	if bank_break_panel.has_method("show_with_animation"):
		bank_break_panel.show_with_animation()
	else:
		bank_break_panel.visible = true

func _find_latest_bankruptcy_event(state: GameState, broke_count: int) -> Dictionary:
	if state == null or not (state.round_state is Dictionary):
		return {}
	var bankruptcy_val = state.round_state.get("bankruptcy", null)
	if not (bankruptcy_val is Dictionary):
		return {}
	var events_val = (bankruptcy_val as Dictionary).get("events", null)
	if not (events_val is Array):
		return {}
	var events: Array = events_val
	if events.is_empty():
		return {}

	var target_kind := "first"
	if broke_count >= 2:
		target_kind = "second"
	for i in range(events.size() - 1, -1, -1):
		var evt_val = events[i]
		if not (evt_val is Dictionary):
			continue
		var evt: Dictionary = evt_val
		if str(evt.get("kind", "")).strip_edges() == target_kind:
			return evt.duplicate(true)
	var last_val = events[events.size() - 1]
	if last_val is Dictionary:
		return (last_val as Dictionary).duplicate(true)
	return {}

func _should_defer_bank_break_to_dinnertime_overlay(state: GameState, latest_event: Dictionary) -> bool:
	if state == null:
		return false
	if str(state.phase) != DefsClass.PHASE_DINNERTIME:
		return false
	if latest_event.is_empty():
		return false
	if not (state.round_state is Dictionary):
		return false

	var dt_val = state.round_state.get("dinnertime", null)
	if not (dt_val is Dictionary):
		return false
	var dt: Dictionary = dt_val
	var dt_breaks_val = dt.get("bankruptcy_events", null)
	if not (dt_breaks_val is Array):
		return false

	var pending_map_val = state.round_state.get("pending_phase_actions", null)
	if not (pending_map_val is Dictionary):
		return false
	var pending_for_phase_val = (pending_map_val as Dictionary).get(DefsClass.PHASE_DINNERTIME, null)
	if not (pending_for_phase_val is Array):
		return false
	var pending_for_phase: Array = pending_for_phase_val
	for item_val in pending_for_phase:
		if item_val is String and str(item_val) == KIND_CONFIRM_DINNERTIME:
			return true
		if item_val is Dictionary:
			var item: Dictionary = item_val
			if str(item.get("kind", "")).strip_edges() == KIND_CONFIRM_DINNERTIME:
				return true
	return false

func _show_game_over() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if game_over_panel == null:
		game_over_panel = GameOverPanelScene.instantiate()
		if game_over_panel is Control:
			UiZClass.apply_absolute((game_over_panel as Control), UiZClass.GAME_OVER)
		else:
			game_over_panel.z_index = UiZClass.GAME_OVER
		game_over_panel.return_to_menu_requested.connect(_on_game_over_return)
		game_over_panel.play_again_requested.connect(_on_game_over_play_again)
		game_over_panel.save_replay_requested.connect(_on_game_over_save_replay)
		_scene.add_child(game_over_panel)

	if game_over_panel.has_method("set_final_state"):
		game_over_panel.set_final_state(_scene.game_engine.get_state())

	if game_over_panel.has_method("show_with_animation"):
		game_over_panel.show_with_animation()
	else:
		game_over_panel.visible = true

	if _game_over_replay_save_path.is_empty():
		_game_over_replay_save_path = _build_game_over_replay_save_path()

func _on_fire_employees(items: Array) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id := _resolve_payday_player_id(_scene.game_engine.get_state())
	if current_player_id < 0:
		return

	for item in items:
		if item is Dictionary:
			var d: Dictionary = item
			var emp_id := str(d.get("employee_id", "")).strip_edges()
			if emp_id.is_empty():
				continue
			var location := str(d.get("location", "")).strip_edges()
			var params := {"employee_id": emp_id}
			if not location.is_empty():
				params["location"] = location
			_execute_command.call(Command.create("fire", current_player_id, params))
		else:
			var emp_id2 := str(item).strip_edges()
			if emp_id2.is_empty():
				continue
			_execute_command.call(Command.create("fire", current_player_id, {"employee_id": emp_id2}))

	if is_instance_valid(payday_panel):
		show_payday_panel()

func _on_pay_confirmed() -> void:
	if not _execute_command.is_valid():
		return
	if _hide_all.is_valid():
		_hide_all.call()
	if _scene == null or _scene.game_engine == null:
		return
	var state = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := _resolve_payday_player_id(state)
	if current_player_id < 0:
		return
	_execute_command.call(Command.create(ActionIdsClass.SKIP, current_player_id, {}))
	if is_instance_valid(payday_panel):
		show_payday_panel()

func _on_game_over_return() -> void:
	GameMenuDebugControllerClass.cleanup_online_state_before_quit()
	Globals.reset_game_config()
	SceneManager.goto_main_menu()

func _on_game_over_play_again() -> void:
	SceneManager.goto_game()

func _on_game_over_save_replay() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	var path := str(_game_over_replay_save_path).strip_edges()
	if path.is_empty():
		path = _build_game_over_replay_save_path()
		_game_over_replay_save_path = path

	if not _ensure_replay_saves_dir():
		_toast("回放保存失败：无法创建存档目录")
		return

	var result: Result = _scene.game_engine.save_to_file(path)
	if not result.ok:
		_toast("回放保存失败：%s" % str(result.error))
		return

	_toast("回放已保存：%s" % path.get_file())

func _build_game_over_replay_save_path() -> String:
	var ts := str(Time.get_datetime_string_from_system()).strip_edges()
	if ts.is_empty():
		ts = "game_over"
	ts = ts.replace(" ", "T")
	ts = ts.replace(":", "-")
	ts = ts.replace("/", "-")
	ts = ts.replace("\\", "-")
	ts = ts.replace("..", "_")
	return "%s/%s.json" % [REPLAY_SAVES_DIR, ts]

func _ensure_replay_saves_dir() -> bool:
	var abs_dir := ProjectSettings.globalize_path(REPLAY_SAVES_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		return true
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	return err == OK and DirAccess.dir_exists_absolute(abs_dir)

func _toast(msg: String) -> void:
	if _overlay_controller == null:
		return
	if _overlay_controller.has_method("show_toast"):
		_overlay_controller.call("show_toast", str(msg).strip_edges())

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
