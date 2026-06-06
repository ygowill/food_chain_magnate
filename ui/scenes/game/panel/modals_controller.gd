# Game scene：Modal UI 控制器
# 负责：回合顺序/储备卡/冰箱保留等 modal 的创建、显示/隐藏与命令分发。
class_name GamePanelModalsController
extends RefCounted

const TurnOrderSelectionModalScene = preload("res://ui/components/modal_panel/turn_order_selection_modal.tscn")
const ReserveCardSelectionModalScene = preload("res://ui/components/modal_panel/reserve_card_selection_modal.tscn")

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const ModuleUiMetadataClass = preload("res://gameplay/module_ui_metadata.gd")
const PhaseActionUiRegistryClass = preload("res://ui/scenes/game/panel/phase_action_ui_registry.gd")

var _scene = null
var _execute_command: Callable = Callable()
var _refresh_ui: Callable = Callable()

var _turn_order_modal = null
var _reserve_card_modal = null
var _phase_action_modals_by_key: Dictionary = {} # "%s|%s" % [phase_name, kind] -> modal instance
var _phase_action_active_kind_by_phase: Dictionary = {} # phase_name -> kind

var _pending_reserve_card_open_player_id: int = -1
var _pending_reserve_card_open_interactive: bool = true
var _pending_reserve_card_open_attempts: int = 0
var _reserve_card_open_routine_running: bool = false
var _reserve_card_modal_dismissed: bool = false
var _reserve_card_modal_dismissed_player_id: int = -1
var _reserve_card_modal_dismissed_interactive: bool = true

func _init(scene, execute_command: Callable, refresh_ui: Callable = Callable()) -> void:
	_scene = scene
	_execute_command = execute_command
	_refresh_ui = refresh_ui

func dispose() -> void:
	_execute_command = Callable()
	_refresh_ui = Callable()

	if is_instance_valid(_turn_order_modal):
		_turn_order_modal.queue_free()
	_turn_order_modal = null

	if is_instance_valid(_reserve_card_modal):
		_reserve_card_modal.queue_free()
	_reserve_card_modal = null

	for k in _phase_action_modals_by_key.keys():
		var inst = _phase_action_modals_by_key.get(k, null)
		if is_instance_valid(inst):
			inst.queue_free()
	_phase_action_modals_by_key.clear()
	_phase_action_active_kind_by_phase.clear()

	_clear_pending_reserve_card_open_state()
	_clear_reserve_card_dismissed_state()

	_scene = null

func _clear_pending_reserve_card_open_state() -> void:
	_pending_reserve_card_open_player_id = -1
	_pending_reserve_card_open_interactive = true
	_pending_reserve_card_open_attempts = 0
	_reserve_card_open_routine_running = false

func _clear_reserve_card_dismissed_state() -> void:
	_reserve_card_modal_dismissed = false
	_reserve_card_modal_dismissed_player_id = -1
	_reserve_card_modal_dismissed_interactive = true

func _request_ui_refresh() -> void:
	if _refresh_ui.is_valid():
		_refresh_ui.call()

func _get_live_state() -> GameState:
	if _scene == null:
		return null
	var engine = _scene.get("game_engine")
	if engine == null or not is_instance_valid(engine):
		return null
	if not engine.has_method("get_state"):
		return null
	var state = engine.get_state()
	return state if state is GameState else null

func _is_reserve_card_selection_state(state: GameState) -> bool:
	return state != null and str(state.phase) == DefsClass.PHASE_SETUP and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS

func _compute_reserve_card_interactive(state: GameState, current_player_id: int) -> bool:
	if state == null or current_player_id < 0:
		return false
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return true
	var local_player_id := int(NetContext.local_player_id)
	return local_player_id >= 0 \
		and current_player_id == local_player_id \
		and OnlinePhaseInteractionClass.can_player_act_in_online_reserve_cards(state, local_player_id)

func _resolve_reserve_card_modal_player_id(state: GameState, fallback_player_id: int) -> int:
	if state == null:
		return -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_player_id := int(NetContext.local_player_id)
		if local_player_id >= 0 and OnlinePhaseInteractionClass.can_player_act_in_online_reserve_cards(state, local_player_id):
			return local_player_id
		var pending := _read_reserve_card_pending_players(state)
		if not pending.is_empty():
			return int(pending[0])
	return fallback_player_id

func _read_reserve_card_pending_players(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state == null or not (state.round_state is Dictionary):
		return out
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val is Dictionary:
		var list_val = Dictionary(ppa_val).get(DefsClass.PHASE_SETUP, null)
		if list_val is Array:
			for item_val in Array(list_val):
				var pid := _read_integral_player_id(item_val)
				if pid >= 0 and pid < state.players.size():
					out.append(pid)
			return out
	for pid_val in Array(state.turn_order):
		var pid2 := _read_integral_player_id(pid_val)
		if pid2 < 0 or pid2 >= state.players.size() or out.has(pid2):
			continue
		if not _has_player_selected_reserve_card(state, pid2):
			out.append(pid2)
	for pid3 in range(state.players.size()):
		if out.has(pid3):
			continue
		if not _has_player_selected_reserve_card(state, pid3):
			out.append(pid3)
	return out

func _read_integral_player_id(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return -1

func _has_player_selected_reserve_card(state: GameState, player_id: int) -> bool:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return false
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return false
	var player: Dictionary = p_val
	var v = player.get("reserve_card_selected", -1)
	if v is int:
		return int(v) >= 0
	if v is float:
		var f: float = float(v)
		return f == floor(f) and int(f) >= 0
	return false

func has_open_modal_ui() -> bool:
	if _reserve_card_open_routine_running or _pending_reserve_card_open_player_id >= 0:
		return true
	if is_instance_valid(_turn_order_modal) and _turn_order_modal.visible:
		return true
	if is_instance_valid(_reserve_card_modal) and _reserve_card_modal.visible:
		return true
	for k in _phase_action_modals_by_key.keys():
		var inst = _phase_action_modals_by_key.get(k, null)
		if not is_instance_valid(inst):
			continue
		if inst is Control and (inst as Control).visible:
			return true
	return false

func has_menu_blocking_modal_ui() -> bool:
	return false

func has_dismissed_reserve_card_modal() -> bool:
	if not _reserve_card_modal_dismissed:
		return false
	var state := _get_live_state()
	if not _is_reserve_card_selection_state(state):
		return false
	return true

func reopen_reserve_card_modal_for_current_state() -> void:
	var state := _get_live_state()
	if not _is_reserve_card_selection_state(state):
		_clear_reserve_card_dismissed_state()
		return
	_clear_reserve_card_dismissed_state()
	var current_player_id := state.get_current_player_id()
	current_player_id = _resolve_reserve_card_modal_player_id(state, current_player_id)
	if current_player_id < 0:
		return
	var interactive := _compute_reserve_card_interactive(state, current_player_id)
	show_reserve_card_modal(state, current_player_id, get_modal_cover_rect(), interactive)

func hide() -> void:
	hide_turn_order_modal()
	hide_reserve_card_modal()
	hide_phase_action_ui_modals_for_phase("")

func get_turn_order_modal():
	return _turn_order_modal

func sync_for_state(state: GameState, covered: Rect2) -> void:
	if state == null:
		return

	if _scene != null and _scene.has_method("_is_startup_intro_running"):
		var intro_val = _scene.call("_is_startup_intro_running")
		if intro_val is bool and bool(intro_val):
			hide()
			return

	var current_player_id := state.get_current_player_id()
	var is_online := false
	var local_player_id := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_player_id = int(NetContext.local_player_id)
	var is_local_turn := (not is_online) or (local_player_id >= 0 and current_player_id == local_player_id)

	# 储备卡选择（Setup/ReserveCards）
	if _is_reserve_card_selection_state(state) and current_player_id >= 0:
		var reserve_player_id := _resolve_reserve_card_modal_player_id(state, current_player_id)
		var interactive := _compute_reserve_card_interactive(state, reserve_player_id)
		if _reserve_card_modal_dismissed:
			if _reserve_card_modal_dismissed_player_id != reserve_player_id or _reserve_card_modal_dismissed_interactive != interactive:
				_clear_reserve_card_dismissed_state()
		if _reserve_card_modal_dismissed:
			hide_reserve_card_modal()
		else:
			show_reserve_card_modal(state, reserve_player_id, covered, interactive)
	else:
		_clear_reserve_card_dismissed_state()
		hide_reserve_card_modal()

	# pending phase actions（Cleanup）：由 registry 路由到对应 modal（避免在 controller 内硬编码 kind）
	PhaseActionUiRegistryClass.sync_cleanup_pending_modals(self, state, current_player_id, covered, is_local_turn)

	# 顺序选择（OrderOfBusiness）
	var selections := {}
	if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS and (state.round_state is Dictionary):
		var rs2: Dictionary = state.round_state
		var oob_val = rs2.get("order_of_business", null)
		if oob_val is Dictionary:
			var oob: Dictionary = oob_val
			var picks_val = oob.get("picks", null)
			if picks_val is Array:
				var picks: Array = picks_val
				for pos in range(min(picks.size(), state.players.size())):
					var pid: int = int(picks[pos])
					if pid >= 0:
						selections[pos] = pid
	else:
		for i in range(state.turn_order.size()):
			if i < state.players.size():
				selections[i] = state.turn_order[i]

	var should_show_turn_order := false
	var turn_order_interactive := true
	if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS and current_player_id >= 0:
		# 联机：即使不是自己回合，也显示“顺位选择进度”，但只有当前玩家可交互。
		should_show_turn_order = not selections.values().has(current_player_id)
		if is_online:
			turn_order_interactive = is_local_turn

	if should_show_turn_order:
		show_turn_order_modal(state, current_player_id, selections, covered, turn_order_interactive, local_player_id)
	else:
		hide_turn_order_modal()

func get_modal_cover_rect() -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var map_rect := _get_scene_rect_from_path("UIRoot/MainContent/CenterSplit/GameArea")
	if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
		return map_rect

	var center_split_rect := _get_scene_rect_from_path("UIRoot/MainContent/CenterSplit")
	if center_split_rect.size.x > 1.0 and center_split_rect.size.y > 1.0:
		return center_split_rect

	return Rect2(Vector2.ZERO, _scene.get_viewport_rect().size)

func _get_scene_rect_from_path(node_path: String) -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var n = _scene.get_node_or_null(node_path)
	if not (n is Control):
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var c: Control = n
	var gr := c.get_global_rect()
	var scene_global := Vector2.ZERO
	if _scene is Control:
		scene_global = (_scene as Control).global_position
	return Rect2(gr.position - scene_global, gr.size)

func _initialize_modal(modal_ref, scene: PackedScene, signal_map: Dictionary):
	if _scene == null:
		return modal_ref
	if is_instance_valid(modal_ref):
		return modal_ref

	var inst = scene.instantiate()
	if not is_instance_valid(inst):
		return inst

	_scene.add_child(inst)
	if inst is Control:
		UiZClass.apply_absolute((inst as Control), UiZClass.MODAL)

	for sig_name in signal_map.keys():
		var cb = signal_map.get(sig_name, null)
		if cb is Callable:
			UiSignalHelpersClass.safe_connect(inst, sig_name, cb)

	return inst

func _load_phase_action_ui_modal_scene(phase_name: String, kind: String) -> PackedScene:
	if _scene == null:
		return null
	var scene_path: String = str(ModuleUiMetadataClass.get_phase_action_ui_modal_scene_path(phase_name, kind)).strip_edges()
	if scene_path.is_empty():
		GameLog.warn("GamePanelModalsController", "未注册 phase action UI modal: %s:%s" % [phase_name, kind])
		return null
	var res = load(scene_path)
	if res is PackedScene:
		return res
	GameLog.warn("GamePanelModalsController", "phase action UI modal 类型错误（期望 PackedScene）: %s" % scene_path)
	return null

func show_turn_order_modal_for_state(state: GameState) -> void:
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	var selections := {}
	var is_online := false
	var local_player_id := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_player_id = int(NetContext.local_player_id)

	if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS and (state.round_state is Dictionary):
		var rs: Dictionary = state.round_state
		var oob_val = rs.get("order_of_business", null)
		if oob_val is Dictionary:
			var oob: Dictionary = oob_val
			var picks_val = oob.get("picks", null)
			if picks_val is Array:
				var picks: Array = picks_val
				for pos in range(min(picks.size(), state.players.size())):
					var pid: int = int(picks[pos])
					if pid >= 0:
						selections[pos] = pid
	else:
		for i in range(state.turn_order.size()):
			if i < state.players.size():
				selections[i] = state.turn_order[i]

	var interactive := true
	if is_online:
		interactive = (local_player_id >= 0 and local_player_id == current_player_id)
	show_turn_order_modal(state, current_player_id, selections, get_modal_cover_rect(), interactive, local_player_id)

func show_turn_order_modal(state: GameState, current_player_id: int, selections: Dictionary, covered: Rect2, interactive: bool, local_player_id: int) -> void:
	if _scene == null:
		return
	if state == null:
		return

	_turn_order_modal = _initialize_modal(_turn_order_modal, TurnOrderSelectionModalScene, {
		"completed": _on_turn_order_modal_completed,
		"cancelled": _on_turn_order_modal_cancelled,
	})

	if not is_instance_valid(_turn_order_modal):
		return

	if _turn_order_modal is Control:
		UiZClass.apply_absolute((_turn_order_modal as Control), UiZClass.MODAL)

	if _turn_order_modal.has_method("setup"):
		_turn_order_modal.call("setup", state, current_player_id, selections, bool(interactive), int(local_player_id))
	if _turn_order_modal.has_method("open"):
		_turn_order_modal.call("open", covered)
	elif _turn_order_modal is Control:
		var c: Control = _turn_order_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func hide_turn_order_modal() -> void:
	if not is_instance_valid(_turn_order_modal):
		return
	if _turn_order_modal.has_method("close"):
		_turn_order_modal.call("close")
	elif _turn_order_modal is Control:
		(_turn_order_modal as Control).visible = false

func _on_turn_order_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_turn_order_modal):
		return
	if not _execute_command.is_valid():
		return

	var pos_val = result.get("position", null)
	var position := -1
	if pos_val is int:
		position = int(pos_val)
	elif pos_val is float:
		var f: float = float(pos_val)
		if f == floor(f):
			position = int(f)
	if position < 0:
		return

	if _turn_order_modal.has_method("set_confirm_enabled"):
		_turn_order_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var actor_id := state.get_current_player_id()
	if actor_id < 0:
		return

	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)

	_execute_command.call(Command.create("choose_turn_order", actor_id, {"position": position}))

func _on_turn_order_modal_cancelled() -> void:
	hide_turn_order_modal()

func show_reserve_card_modal(state: GameState, current_player_id: int, covered: Rect2, interactive: bool) -> void:
	if _scene == null:
		return
	if state == null:
		return

	_reserve_card_modal = _initialize_modal(_reserve_card_modal, ReserveCardSelectionModalScene, {
		"completed": _on_reserve_card_modal_completed,
		"cancelled": _on_reserve_card_modal_cancelled,
	})

	if not is_instance_valid(_reserve_card_modal):
		return

	if interactive:
		if _reserve_card_modal.has_method("setup"):
			_reserve_card_modal.call("setup", state, current_player_id)
	else:
		# Waiting mode must never reveal reserve card details.
		if _reserve_card_modal.has_method("setup_waiting"):
			_reserve_card_modal.call("setup_waiting", current_player_id)
		else:
			hide_reserve_card_modal()
			return
	if _reserve_card_modal.has_method("open"):
		# 首次打开时 UI 布局可能尚未完成，CenterSplit 的 rect 会错误导致遮罩落在左上角；
		# 延迟一帧再重新计算覆盖区域并打开，确保首位玩家显示正常。
		if not _reserve_card_modal.visible:
			if _pending_reserve_card_open_player_id != current_player_id or _pending_reserve_card_open_interactive != interactive:
				_pending_reserve_card_open_player_id = current_player_id
				_pending_reserve_card_open_interactive = interactive
				_pending_reserve_card_open_attempts = 0
			if not _reserve_card_open_routine_running:
				_reserve_card_open_routine_running = true
				call_deferred("_deferred_open_reserve_card_modal")
			return

		_reserve_card_modal.call("open", covered)
	elif _reserve_card_modal is Control:
		var c: Control = _reserve_card_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func _deferred_open_reserve_card_modal() -> void:
	# 注意：call_deferred 只保证“当前调用栈之后”，不保证已完成容器布局；
	# 因此这里按帧等待并重算覆盖区域，避免首位玩家第一次弹窗落在左上角。
	while true:
		var expected_player_id := _pending_reserve_card_open_player_id
		var expected_interactive := _pending_reserve_card_open_interactive
		if expected_player_id < 0:
			_clear_pending_reserve_card_open_state()
			return
		if _reserve_card_modal_dismissed:
			_clear_pending_reserve_card_open_state()
			return
		if _scene == null or _scene.game_engine == null:
			_clear_pending_reserve_card_open_state()
			return
		if not is_instance_valid(_reserve_card_modal):
			_clear_pending_reserve_card_open_state()
			return

		# 等待至少一帧，让 VBox/SplitContainer 等容器完成布局（位置/尺寸）。
		await _scene.get_tree().process_frame

		# 过程中可能发生状态变化，重新校验
		if _pending_reserve_card_open_player_id != expected_player_id or _pending_reserve_card_open_interactive != expected_interactive:
			_pending_reserve_card_open_attempts = 0
			continue

		var state: GameState = _scene.game_engine.get_state()
		if state == null:
			_clear_pending_reserve_card_open_state()
			return
		if str(state.phase) != DefsClass.PHASE_SETUP or str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
			_clear_pending_reserve_card_open_state()
			return

		var current_player_id := state.get_current_player_id()
		current_player_id = _resolve_reserve_card_modal_player_id(state, current_player_id)
		if current_player_id != expected_player_id:
			_clear_pending_reserve_card_open_state()
			return

		var covered := get_modal_cover_rect()

		# UI 布局刚完成前的一两帧，覆盖区域可能异常偏小（但非 0），导致遮罩落在左上角；
		# 这里最多等待几帧，直到覆盖区域达到可用尺寸后再打开。
		var should_retry := covered.size.x <= 1.0 or covered.size.y <= 1.0
		if not should_retry and (covered.size.x < 160.0 or covered.size.y < 120.0):
			should_retry = true

		if should_retry and _pending_reserve_card_open_attempts < 8:
			_pending_reserve_card_open_attempts += 1
			continue

		_clear_pending_reserve_card_open_state()

		# 进入储备卡选择时再隐藏加载遮罩，避免“先闪一帧游戏 UI 再弹窗”的体验。
		if SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()

		if expected_interactive:
			if _reserve_card_modal.has_method("setup"):
				_reserve_card_modal.call("setup", state, current_player_id)
		else:
			if _reserve_card_modal.has_method("setup_waiting"):
				_reserve_card_modal.call("setup_waiting", current_player_id)
		if _reserve_card_modal.has_method("open"):
			_reserve_card_modal.call("open", covered)
		elif _reserve_card_modal is Control:
			var c: Control = _reserve_card_modal
			c.position = covered.position
			c.size = covered.size
			c.visible = true
		return

func hide_reserve_card_modal() -> void:
	_clear_pending_reserve_card_open_state()
	if not is_instance_valid(_reserve_card_modal):
		return
	if _reserve_card_modal.has_method("close"):
		_reserve_card_modal.call("close")
	elif _reserve_card_modal is Control:
		(_reserve_card_modal as Control).visible = false

func _on_reserve_card_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_reserve_card_modal):
		return
	if not _execute_command.is_valid():
		return

	var idx_val = result.get("selected_index", null)
	var selected_index := -1
	if idx_val is int:
		selected_index = int(idx_val)
	elif idx_val is float:
		var f: float = float(idx_val)
		if f == floor(f):
			selected_index = int(f)
	if selected_index < 0:
		return

	_clear_reserve_card_dismissed_state()
	if _reserve_card_modal.has_method("set_confirm_enabled"):
		_reserve_card_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var actor_id := state.get_current_player_id()
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		if local_pid < 0 or not OnlinePhaseInteractionClass.can_player_act_in_online_reserve_cards(state, local_pid):
			return
		actor_id = local_pid
	else:
		actor_id = _resolve_reserve_card_modal_player_id(state, actor_id)
	if actor_id < 0:
		return

	_execute_command.call(Command.create("select_reserve_card", actor_id, {"selected_index": selected_index}))

func _on_reserve_card_modal_cancelled() -> void:
	var state := _get_live_state()
	var current_player_id := -1
	var interactive := true
	if state != null:
		current_player_id = state.get_current_player_id()
		current_player_id = _resolve_reserve_card_modal_player_id(state, current_player_id)
		if current_player_id >= 0:
			interactive = _compute_reserve_card_interactive(state, current_player_id)
	_reserve_card_modal_dismissed = true
	_reserve_card_modal_dismissed_player_id = current_player_id
	_reserve_card_modal_dismissed_interactive = interactive
	hide_reserve_card_modal()
	_request_ui_refresh()

func show_phase_action_ui_modal(phase_name: String, kind: String, state: GameState, current_player_id: int, covered: Rect2) -> void:
	if _scene == null:
		return
	if state == null:
		return

	var phase := str(phase_name).strip_edges()
	var k := str(kind).strip_edges()
	if phase.is_empty() or k.is_empty():
		hide_phase_action_ui_modals_for_phase(phase)
		return

	var active_k := str(_phase_action_active_kind_by_phase.get(phase, "")).strip_edges()
	if not active_k.is_empty() and active_k != k:
		_hide_phase_action_ui_modal(phase, active_k)
	_phase_action_active_kind_by_phase[phase] = k

	var key := _build_phase_action_ui_modal_key(phase, k)
	var inst = _phase_action_modals_by_key.get(key, null)

	var modal_scene: PackedScene = _load_phase_action_ui_modal_scene(phase, k)
	if modal_scene == null:
		_hide_phase_action_ui_modal(phase, k)
		return

	inst = _initialize_modal(inst, modal_scene, {
		"completed": Callable(self, "_on_phase_action_ui_modal_completed").bind(phase, k),
	})
	_phase_action_modals_by_key[key] = inst
	if not is_instance_valid(inst):
		return

	if inst.has_method("setup"):
		inst.call("setup", state, current_player_id)
	if inst.has_method("open"):
		inst.call("open", covered)
	elif inst is Control:
		var c: Control = inst
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func hide_phase_action_ui_modals_for_phase(phase_name: String) -> void:
	if _scene == null:
		return

	var phase := str(phase_name).strip_edges()
	if phase.is_empty():
		for k in _phase_action_modals_by_key.keys():
			_hide_phase_action_ui_modal_by_key(str(k))
		_phase_action_active_kind_by_phase.clear()
		return

	var active_k := str(_phase_action_active_kind_by_phase.get(phase, "")).strip_edges()
	if not active_k.is_empty():
		_hide_phase_action_ui_modal(phase, active_k)
	_phase_action_active_kind_by_phase.erase(phase)

func _build_phase_action_ui_modal_key(phase_name: String, kind: String) -> String:
	return "%s|%s" % [str(phase_name).strip_edges(), str(kind).strip_edges()]

func _hide_phase_action_ui_modal(phase_name: String, kind: String) -> void:
	var key := _build_phase_action_ui_modal_key(phase_name, kind)
	_hide_phase_action_ui_modal_by_key(key)

func _hide_phase_action_ui_modal_by_key(key: String) -> void:
	var inst = _phase_action_modals_by_key.get(key, null)
	if not is_instance_valid(inst):
		return
	if inst.has_method("close"):
		inst.call("close")
	elif inst is Control:
		(inst as Control).visible = false

func _on_phase_action_ui_modal_completed(result: Dictionary, phase_name: String, kind: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return

	var cmd_id := str(result.get("command_id", "")).strip_edges()
	if cmd_id.is_empty():
		GameLog.warn("GamePanelModalsController", "phase action modal 缺少 command_id: %s:%s" % [str(phase_name), str(kind)])
		return

	var args_val = result.get("command_args", null)
	var args: Dictionary = args_val if args_val is Dictionary else {}

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return

	_execute_command.call(Command.create(cmd_id, current_player_id, args))
