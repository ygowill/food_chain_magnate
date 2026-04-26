# Game scene：命令执行/阶段推进控制器
# 负责：本地/联机命令执行、回退到回合开始、SKIP 前强制动作自动补完、发薪日拦截提示。
class_name GameCommandController
extends RefCounted

const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")

const AUTO_MANDATORY_ACTION_IDS := {
	ActionIdsClass.SET_PRICE: true,
	ActionIdsClass.SET_DISCOUNT: true,
	ActionIdsClass.SET_LUXURY_PRICE: true,
}

var _get_game_engine: Callable = Callable()
var _update_ui: Callable = Callable()
var _show_confirm: Callable = Callable()

var _timeline_controller: Object = null
var _panel_controller: Object = null
var _online_resync_controller: Object = null
var _game_log_panel: Control = null
var _tutorial_match_runtime = null

func _init(
	get_game_engine: Callable,
	update_ui: Callable,
	show_confirm: Callable,
	timeline_controller: Object,
	panel_controller: Object,
	game_log_panel: Control,
	tutorial_match_runtime = null
) -> void:
	_get_game_engine = get_game_engine
	_update_ui = update_ui
	_show_confirm = show_confirm
	_timeline_controller = timeline_controller
	_panel_controller = panel_controller
	_game_log_panel = game_log_panel
	_tutorial_match_runtime = tutorial_match_runtime

func dispose() -> void:
	_get_game_engine = Callable()
	_update_ui = Callable()
	_show_confirm = Callable()
	_timeline_controller = null
	_panel_controller = null
	_online_resync_controller = null
	_game_log_panel = null
	if _tutorial_match_runtime != null and _tutorial_match_runtime.has_method("dispose"):
		_tutorial_match_runtime.dispose()
	_tutorial_match_runtime = null

func set_online_resync_controller(controller: Object) -> void:
	_online_resync_controller = controller

func rewind_to_turn_start() -> void:
	var game_engine: GameEngine = _get_engine()
	if game_engine == null:
		return
	if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
		GameLog.warn("Game", "回放模式下无法回退回合")
		return

	var state := game_engine.get_state()
	if state == null:
		return
	var pid := int(state.get_current_player_id())
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		pid = int(OnlinePhaseInteractionClass.get_online_local_player_id(state, pid))
		if not OnlinePhaseInteractionClass.can_player_request_rewind_in_online_phase(state, pid):
			GameLog.warn("Game", "联机模式下当前玩家不能发起回退（player=%d）" % pid)
			return

	var idx_r: Result = game_engine.find_current_player_turn_start_command_index(pid)
	if not idx_r.ok:
		GameLog.warn("Game", "计算回合开始索引失败: %s" % idx_r.error)
		return

	var target_index := int(idx_r.value)
	var current_index := int(game_engine.current_command_index)
	if target_index >= current_index:
		return

	var phase_name := str(state.phase)
	var steps := current_index - target_index

	if _show_confirm.is_valid():
		_show_confirm.call(
			"回退到回合开始",
			"确定要回退到当前玩家（P%d）的回合开始吗？\n将撤销从该回合开始以来的 %d 步操作。\n（阶段：%s）" % [pid + 1, steps, phase_name],
			Callable(self, "_confirm_rewind_to_turn_start").bind(target_index),
			Callable(),
			"回退",
			"取消"
		)

func _confirm_rewind_to_turn_start(target_index: int) -> void:
	var game_engine: GameEngine = _get_engine()
	if game_engine == null:
		return

	# 联机：回退必须由 server 执行并广播（否则会导致各客户端状态不一致）。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		if _online_resync_controller == null or not is_instance_valid(_online_resync_controller):
			GameLog.warn("Game", "联机模式下回退失败：控制器未就绪")
			return
		# 避免重复触发（例如用户连续点击）
		if _online_resync_controller.has_method("is_resync_in_progress") and bool(_online_resync_controller.call("is_resync_in_progress")):
			return
		if _online_resync_controller.has_method("begin_rewind_to_turn_start_request"):
			_online_resync_controller.call("begin_rewind_to_turn_start_request")
		return

	var result := game_engine.rewind_to_command(target_index)
	if not result.ok:
		GameLog.warn("Game", "回退到回合开始失败: %s" % result.error)
	else:
		if is_instance_valid(_timeline_controller):
			if _timeline_controller.has_method("set_timeline_edit_mode_active"):
				_timeline_controller.call("set_timeline_edit_mode_active", true)
			if _timeline_controller.has_method("request_force_full_panel_sync_next_update"):
				_timeline_controller.call("request_force_full_panel_sync_next_update")
			if _timeline_controller.has_method("apply_live_log_timeline_from_engine"):
				_timeline_controller.call("apply_live_log_timeline_from_engine", true)
	_request_ui_refresh()

func execute_command(command: Command) -> Result:
	var game_engine: GameEngine = _get_engine()
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")
	if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
		return Result.failure("回放模式下无法执行命令")

	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		if _online_resync_controller == null or not is_instance_valid(_online_resync_controller):
			return Result.failure("联机同步未就绪")
		if _online_resync_controller.has_method("try_send_online_action"):
			var r_val = _online_resync_controller.call("try_send_online_action", command)
			if r_val is Result:
				return r_val
		return Result.failure("联机同步未就绪")

	var head_index := int(game_engine.command_history.size() - 1)
	var was_in_history := int(game_engine.current_command_index) < head_index
	var can_edit_timeline := (is_instance_valid(_timeline_controller) and _timeline_controller.has_method("is_timeline_edit_mode_active") and bool(_timeline_controller.call("is_timeline_edit_mode_active")))
	if was_in_history and not can_edit_timeline:
		return Result.failure("查看历史中无法执行命令（请先返回最新）")

	var state: GameState = game_engine.get_state()
	if _tutorial_match_runtime != null and _tutorial_match_runtime.has_method("validate_command"):
		var tutorial_gate = _tutorial_match_runtime.validate_command(command, state, game_engine)
		if tutorial_gate is Result and not tutorial_gate.ok:
			GameLog.warn("Game", "教学局步骤限制: %s" % tutorial_gate.error)
			_request_ui_refresh()
			return tutorial_gate

	var auto := _maybe_auto_complete_mandatory_actions_before_skip(command, game_engine)
	if auto is Result and not auto.ok:
		GameLog.warn("Game", "自动完成强制动作失败: %s" % auto.error)
		_request_ui_refresh()
		return auto

	var result := game_engine.execute_command(command)
	if not result.ok:
		GameLog.warn("Game", "命令执行失败: %s" % result.error)
		_maybe_show_payday_blocker_prompt(command, result, game_engine)
	else:
		GameLog.info("Game", "命令执行成功: %s" % command.action_id)
		# 时间线被回退过时，执行新命令会截断未来时间线并生成新分支：需要重建 step_timeline 视图，避免 UI 仍引用旧 head。
		# 其它情况下：仅标记 dirty，并在日志面板可见时合帧刷新，降低每步全量回放开销。
		if is_instance_valid(_timeline_controller):
			if was_in_history:
				if _timeline_controller.has_method("apply_live_log_timeline_from_engine"):
					_timeline_controller.call("apply_live_log_timeline_from_engine", true)
			elif _timeline_controller.has_method("request_live_log_timeline_refresh_deferred"):
				_timeline_controller.call("request_live_log_timeline_refresh_deferred")
			elif _timeline_controller.has_method("request_live_log_timeline_refresh"):
				_timeline_controller.call("request_live_log_timeline_refresh")
			elif _timeline_controller.has_method("mark_live_log_timeline_dirty"):
				_timeline_controller.call("mark_live_log_timeline_dirty")
		if was_in_history and is_instance_valid(_timeline_controller) and _timeline_controller.has_method("set_timeline_edit_mode_active"):
			_timeline_controller.call("set_timeline_edit_mode_active", false)
		if _tutorial_match_runtime != null and _tutorial_match_runtime.has_method("on_command_executed"):
			_tutorial_match_runtime.on_command_executed(command, game_engine.get_state(), result)

	_request_ui_refresh()
	return result

func on_advance_phase_pressed() -> void:
	execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))

func on_advance_sub_phase_pressed() -> void:
	execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"}))

func on_skip_pressed() -> void:
	var game_engine: GameEngine = _get_engine()
	if game_engine == null:
		return
	if bool(Globals.confirm_actions) and _show_confirm.is_valid():
		_show_confirm.call(
			"确认结束",
			"确定要结束当前阶段/子阶段吗？",
			Callable(self, "_confirm_skip")
		)
		return
	_confirm_skip()

func _confirm_skip() -> void:
	var game_engine: GameEngine = _get_engine()
	if game_engine == null:
		return
	var state: GameState = game_engine.get_state()
	if state == null:
		return
	var actor_id := int(state.get_current_player_id())
	actor_id = int(OnlinePhaseInteractionClass.get_online_local_player_id(state, actor_id))
	execute_command(Command.create(ActionIdsClass.SKIP, actor_id))

func _get_engine() -> GameEngine:
	if not _get_game_engine.is_valid():
		return null
	var engine_val = _get_game_engine.call()
	return engine_val if engine_val is GameEngine else null

func _request_ui_refresh() -> void:
	if _update_ui.is_valid():
		_update_ui.call()

func _get_last_working_sub_phase_name(game_engine: GameEngine) -> String:
	var last_sub_phase := DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if game_engine != null and game_engine.phase_manager != null and game_engine.phase_manager.has_method("get_working_sub_phase_order_names"):
		var order = game_engine.phase_manager.get_working_sub_phase_order_names()
		if order is Array and not order.is_empty():
			last_sub_phase = str(order[order.size() - 1])
	return last_sub_phase

func _maybe_auto_complete_mandatory_actions_before_skip(command: Command, game_engine: GameEngine) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if str(command.action_id).strip_edges() != ActionIdsClass.SKIP:
		return Result.success()
	if game_engine == null:
		return Result.failure("游戏引擎未初始化")

	var state: GameState = game_engine.get_state()
	if state == null:
		return Result.failure("游戏状态为空")
	if str(state.phase) != DefsClass.PHASE_WORKING:
		return Result.success()
	if str(state.sub_phase) != _get_last_working_sub_phase_name(game_engine):
		return Result.success()

	var current_player_id := int(state.get_current_player_id())
	if int(command.actor) != current_player_id:
		return Result.success()

	var player := state.get_player(current_player_id)
	var required := MandatoryActionsRulesClass.get_required_mandatory_actions(player)
	if required.is_empty():
		return Result.success()

	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has("mandatory_actions_completed"):
		return Result.failure("round_state.mandatory_actions_completed 缺失")
	var mac_val = state.round_state["mandatory_actions_completed"]
	if not (mac_val is Dictionary):
		return Result.failure("round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mac: Dictionary = mac_val
	if not mac.has(current_player_id):
		return Result.failure("mandatory_actions_completed 缺少玩家 key: %d" % current_player_id)
	var completed_val = mac[current_player_id]
	if not (completed_val is Array):
		return Result.failure("mandatory_actions_completed[%d] 类型错误（期望 Array）" % current_player_id)
	var completed: Array = completed_val

	var missing: Array[String] = []
	for action_id in required:
		var aid := str(action_id).strip_edges()
		if aid.is_empty():
			continue
		if not AUTO_MANDATORY_ACTION_IDS.has(aid):
			continue
		if completed.has(aid):
			continue
		missing.append(aid)

	for aid2 in missing:
		var cmd := Command.create(str(aid2), current_player_id, {"auto": true})
		var r := game_engine.execute_command(cmd)
		if not r.ok:
			return Result.failure("自动执行强制动作失败(%s): %s" % [aid2, r.error])

	return Result.success()

func _maybe_show_payday_blocker_prompt(_command: Command, result: Result, game_engine: GameEngine) -> void:
	if result == null or result.ok:
		return
	if OS.has_feature("headless"):
		return
	if game_engine == null:
		return

	var state := game_engine.get_state()
	if state == null:
		return
	if str(state.phase) != DefsClass.PHASE_PAYDAY:
		return

	var err := str(result.error).strip_edges()
	if err.is_empty():
		return
	if err.find("薪水不足") == -1:
		return

	if is_instance_valid(_panel_controller) and _panel_controller.has_method("show_payday_panel"):
		_panel_controller.call("show_payday_panel")

	if _show_confirm.is_valid():
		_show_confirm.call(
			"无法结束发薪日",
			"%s\n\n请在发薪日解雇员工以支付薪资，然后再确认结束。" % err,
			Callable(self, "_open_payday_panel_from_prompt"),
			Callable(),
			"打开发薪日",
			"知道了"
		)

func _open_payday_panel_from_prompt() -> void:
	if is_instance_valid(_panel_controller) and _panel_controller.has_method("show_payday_panel"):
		_panel_controller.call("show_payday_panel")
