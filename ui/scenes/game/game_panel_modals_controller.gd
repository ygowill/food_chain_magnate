# Game scene：Modal UI 控制器
# 负责：回合顺序/储备卡/冰箱保留等 modal 的创建、显示/隐藏与命令分发。
class_name GamePanelModalsController
extends RefCounted

const TurnOrderSelectionModalScene = preload("res://ui/components/modal_panel/turn_order_selection_modal.tscn")
const ReserveCardSelectionModalScene = preload("res://ui/components/modal_panel/reserve_card_selection_modal.tscn")
const FridgeKeepModalScene = preload("res://ui/components/modal_panel/fridge_keep_modal.tscn")

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _scene = null
var _execute_command: Callable = Callable()

var _turn_order_modal = null
var _reserve_card_modal = null
var _fridge_keep_modal = null

var _pending_reserve_card_open_player_id: int = -1
var _pending_reserve_card_open_interactive: bool = true
var _pending_reserve_card_open_attempts: int = 0
var _reserve_card_open_routine_running: bool = false

func _init(scene, execute_command: Callable) -> void:
	_scene = scene
	_execute_command = execute_command

func dispose() -> void:
	_execute_command = Callable()

	if is_instance_valid(_turn_order_modal):
		_turn_order_modal.queue_free()
	_turn_order_modal = null

	if is_instance_valid(_reserve_card_modal):
		_reserve_card_modal.queue_free()
	_reserve_card_modal = null

	if is_instance_valid(_fridge_keep_modal):
		_fridge_keep_modal.queue_free()
	_fridge_keep_modal = null

	_pending_reserve_card_open_player_id = -1
	_pending_reserve_card_open_interactive = true
	_pending_reserve_card_open_attempts = 0
	_reserve_card_open_routine_running = false

	_scene = null

func has_open_modal_ui() -> bool:
	if is_instance_valid(_turn_order_modal) and _turn_order_modal.visible:
		return true
	if is_instance_valid(_reserve_card_modal) and _reserve_card_modal.visible:
		return true
	if is_instance_valid(_fridge_keep_modal) and _fridge_keep_modal.visible:
		return true
	return false

func hide() -> void:
	hide_turn_order_modal()
	hide_reserve_card_modal()
	hide_fridge_keep_modal()

func sync_for_state(state: GameState, covered: Rect2) -> void:
	if state == null:
		return

	var current_player_id := state.get_current_player_id()
	var is_online := false
	var local_player_id := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_player_id = int(NetContext.local_player_id)
	var is_local_turn := (not is_online) or (local_player_id >= 0 and current_player_id == local_player_id)

	# 储备卡选择（Setup/ReserveCards）
	if state.phase == DefsClass.PHASE_SETUP and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS and current_player_id >= 0:
		var interactive := true
		if is_online:
			interactive = is_local_turn
		show_reserve_card_modal(state, current_player_id, covered, interactive)
	else:
		hide_reserve_card_modal()

	# 冰箱保留选择（Cleanup）
	var should_show_fridge_keep := false
	if state.phase == DefsClass.PHASE_CLEANUP and (state.round_state is Dictionary) and current_player_id >= 0:
		var rs: Dictionary = state.round_state
		var ppa_val = rs.get("pending_phase_actions", null)
		if ppa_val is Dictionary:
			var ppa: Dictionary = ppa_val
			var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
			if list_val is Array:
				var list: Array = list_val
				if not list.is_empty() and int(list[0]) == current_player_id:
					should_show_fridge_keep = true

	if should_show_fridge_keep and is_local_turn:
		show_fridge_keep_modal(state, current_player_id, covered)
	else:
		hide_fridge_keep_modal()

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

	var center_split = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit")
	if center_split is Control:
		var c: Control = center_split
		var gr := c.get_global_rect()
		var scene_global := Vector2.ZERO
		if _scene is Control:
			scene_global = (_scene as Control).global_position
		return Rect2(gr.position - scene_global, gr.size)

	return Rect2(Vector2.ZERO, _scene.get_viewport_rect().size)

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
		(inst as Control).z_index = 900

	for sig_name in signal_map.keys():
		var cb = signal_map.get(sig_name, null)
		if cb is Callable:
			UiSignalHelpersClass.safe_connect(inst, sig_name, cb)

	return inst

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
			_reserve_card_open_routine_running = false
			return
		if _scene == null or _scene.game_engine == null:
			_reserve_card_open_routine_running = false
			return
		if not is_instance_valid(_reserve_card_modal):
			_reserve_card_open_routine_running = false
			return

		# 等待至少一帧，让 VBox/SplitContainer 等容器完成布局（位置/尺寸）。
		await _scene.get_tree().process_frame

		# 过程中可能发生状态变化，重新校验
		if _pending_reserve_card_open_player_id != expected_player_id or _pending_reserve_card_open_interactive != expected_interactive:
			_pending_reserve_card_open_attempts = 0
			continue

		var state: GameState = _scene.game_engine.get_state()
		if state == null:
			_reserve_card_open_routine_running = false
			return
		if str(state.phase) != DefsClass.PHASE_SETUP or str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
			_pending_reserve_card_open_player_id = -1
			_pending_reserve_card_open_attempts = 0
			_reserve_card_open_routine_running = false
			return

		var current_player_id := state.get_current_player_id()
		if current_player_id != expected_player_id:
			_reserve_card_open_routine_running = false
			return

		var covered := get_modal_cover_rect()

		# UI 布局刚完成前的一两帧，CenterSplit 的 rect 可能异常偏小（但非 0），导致遮罩落在左上角；
		# 这里最多等待几帧，直到覆盖区域尺寸接近 viewport（再打开）。
		var viewport_size = _scene.get_viewport_rect().size
		var should_retry := false
		if viewport_size.x > 1.0 and viewport_size.y > 1.0:
			if covered.size.x < viewport_size.x * 0.4 or covered.size.y < viewport_size.y * 0.4:
				should_retry = true
		else:
			should_retry = covered.size.x <= 1.0 or covered.size.y <= 1.0

		if should_retry and _pending_reserve_card_open_attempts < 8:
			_pending_reserve_card_open_attempts += 1
			continue

		_pending_reserve_card_open_player_id = -1
		_pending_reserve_card_open_interactive = true
		_pending_reserve_card_open_attempts = 0
		_reserve_card_open_routine_running = false

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
	_pending_reserve_card_open_player_id = -1
	_pending_reserve_card_open_interactive = true
	_pending_reserve_card_open_attempts = 0
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

	if _reserve_card_modal.has_method("set_confirm_enabled"):
		_reserve_card_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		if local_pid < 0 or current_player_id != local_pid:
			return

	_execute_command.call(Command.create("select_reserve_card", current_player_id, {"selected_index": selected_index}))

func show_fridge_keep_modal(state: GameState, current_player_id: int, covered: Rect2) -> void:
	if _scene == null:
		return
	if state == null:
		return

	_fridge_keep_modal = _initialize_modal(_fridge_keep_modal, FridgeKeepModalScene, {
		"completed": _on_fridge_keep_modal_completed,
	})
	if not is_instance_valid(_fridge_keep_modal):
		return

	if _fridge_keep_modal.has_method("setup"):
		_fridge_keep_modal.call("setup", state, current_player_id)
	if _fridge_keep_modal.has_method("open"):
		_fridge_keep_modal.call("open", covered)
	elif _fridge_keep_modal is Control:
		var c: Control = _fridge_keep_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func hide_fridge_keep_modal() -> void:
	if not is_instance_valid(_fridge_keep_modal):
		return
	if _fridge_keep_modal.has_method("close"):
		_fridge_keep_modal.call("close")
	elif _fridge_keep_modal is Control:
		(_fridge_keep_modal as Control).visible = false

func _on_fridge_keep_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_fridge_keep_modal):
		return
	if not _execute_command.is_valid():
		return

	var keep_val = result.get("keep", {})
	var keep: Dictionary = keep_val if keep_val is Dictionary else {}

	if _fridge_keep_modal.has_method("set_confirm_enabled"):
		_fridge_keep_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return

	_execute_command.call(Command.create("choose_fridge_keep", current_player_id, {"keep": keep}))
