# Game scene：UI 同步控制器
# 负责：顶栏信息刷新、地图/面板/覆盖层同步、提示 toast（联机轮到你/阶段切换）、调试命令后的 UI 重建触发。
class_name GameUiSyncController
extends RefCounted

const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _get_game_engine: Callable = Callable()
var _refresh_ui: Callable = Callable()
var _sync_right_panel_docked_view: Callable = Callable()

var _round_label: Label = null
var _phase_label: Label = null
var _bank_label: Label = null
var _current_player_label: Label = null

var _game_log_panel: Control = null
var _map_view: Control = null

var _panel_controller: Object = null
var _overlay_controller: Object = null
var _timeline_controller: Object = null
var _online_resync_controller: Object = null

var _debug_panel: Window = null

var _online_turn_toast_last_player_id: int = -999
var _phase_toast_last_phase: String = ""

func _init(
	get_game_engine: Callable,
	refresh_ui: Callable,
	sync_right_panel_docked_view: Callable,
	round_label: Label,
	phase_label: Label,
	bank_label: Label,
	current_player_label: Label,
	game_log_panel: Control,
	map_view: Control,
	panel_controller: Object,
	overlay_controller: Object,
	timeline_controller: Object
) -> void:
	_get_game_engine = get_game_engine
	_refresh_ui = refresh_ui
	_sync_right_panel_docked_view = sync_right_panel_docked_view
	_round_label = round_label
	_phase_label = phase_label
	_bank_label = bank_label
	_current_player_label = current_player_label
	_game_log_panel = game_log_panel
	_map_view = map_view
	_panel_controller = panel_controller
	_overlay_controller = overlay_controller
	_timeline_controller = timeline_controller

func dispose() -> void:
	_get_game_engine = Callable()
	_refresh_ui = Callable()
	_sync_right_panel_docked_view = Callable()
	_round_label = null
	_phase_label = null
	_bank_label = null
	_current_player_label = null
	_game_log_panel = null
	_map_view = null
	_panel_controller = null
	_overlay_controller = null
	_timeline_controller = null
	_online_resync_controller = null
	_debug_panel = null

func set_online_resync_controller(controller: Object) -> void:
	_online_resync_controller = controller

func set_debug_panel(panel: Window) -> void:
	_debug_panel = panel

func update_ui(do_profile: bool) -> void:
	if not _get_game_engine.is_valid():
		return
	var engine_val = _get_game_engine.call()
	var game_engine: GameEngine = engine_val if engine_val is GameEngine else null
	if game_engine == null:
		return
	var state: GameState = game_engine.get_state()
	if state == null:
		return

	if is_instance_valid(_round_label):
		if str(state.phase) == DefsClass.PHASE_SETUP:
			_round_label.text = "准备阶段"
		else:
			_round_label.text = "回合: %d" % int(state.round_number)
	if is_instance_valid(_phase_label):
		_phase_label.text = "阶段: %s%s" % [
			state.phase,
			(" / %s" % state.sub_phase) if not str(state.sub_phase).is_empty() else ""
		]

	var pid := int(state.get_current_player_id())
	var current_name := Globals.get_player_name(pid) if pid >= 0 else "-"
	var view_id := pid
	if is_instance_valid(_panel_controller) and _panel_controller.has_method("get_view_player_id"):
		var v := int(_panel_controller.call("get_view_player_id"))
		if v >= 0:
			view_id = v
	var view_name := Globals.get_player_name(view_id) if view_id >= 0 else "-"

	var head_index := int(game_engine.command_history.size() - 1)
	var cursor_index := int(game_engine.current_command_index)
	var replay_suffix := ""
	if is_instance_valid(_timeline_controller):
		var hc = _timeline_controller.call("get_ui_head_cursor", game_engine)
		if hc is Vector2i:
			head_index = int(hc.x)
			cursor_index = int(hc.y)
		replay_suffix = str(_timeline_controller.call("get_ui_replay_suffix", game_engine, head_index, cursor_index))

	if is_instance_valid(_current_player_label):
		if str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
			var submitted_count := 0
			var total := int(state.players.size())
			if state.round_state is Dictionary:
				var r_val = state.round_state.get("restructuring", null)
				if r_val is Dictionary:
					var r: Dictionary = r_val
					var submitted_val = r.get("submitted", null)
					if submitted_val is Dictionary:
						var submitted: Dictionary = submitted_val
						for pid2 in range(total):
							var v2 = submitted.get(pid2, null)
							if v2 == null and submitted.has(str(pid2)):
								v2 = submitted.get(str(pid2), null)
							if bool(v2):
								submitted_count += 1

			_current_player_label.text = "重组（同时）%s｜提交: %d/%d" % [
				replay_suffix,
				submitted_count,
				total
			]
		else:
			_current_player_label.text = "行动%s: %s" % [
				replay_suffix,
				current_name
			]

	if is_instance_valid(_bank_label):
		_bank_label.text = "银行: $%d" % int(state.bank.get("total", 0))

	if is_instance_valid(_game_log_panel) and _game_log_panel.has_method("set_player_count"):
		_game_log_panel.call("set_player_count", int(state.players.size()))

	# 地图渲染
	if is_instance_valid(_map_view) and _map_view.has_method("set_game_state"):
		var span_map := PerfTraceClass.begin_span("ui:map_view.set_game_state") if do_profile else -1
		_map_view.call("set_game_state", state)
		if do_profile:
			PerfTraceClass.end_span(span_map)

	# 面板/覆盖层同步
	if is_instance_valid(_panel_controller) and _panel_controller.has_method("sync"):
		var span_panels := PerfTraceClass.begin_span("ui:panel_controller.sync") if do_profile else -1
		var force_refresh := false
		if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("consume_force_full_panel_sync_next_update"):
			force_refresh = bool(_timeline_controller.call("consume_force_full_panel_sync_next_update"))
		_panel_controller.call("sync", state, force_refresh)
		if _sync_right_panel_docked_view.is_valid():
			_sync_right_panel_docked_view.call()
		if do_profile:
			PerfTraceClass.end_span(span_panels)

	if is_instance_valid(_overlay_controller):
		var span_overlays := PerfTraceClass.begin_span("ui:overlay_controller.sync") if do_profile else -1
		if _overlay_controller.has_method("sync_demand_indicator"):
			_overlay_controller.call("sync_demand_indicator", state)
		if do_profile:
			PerfTraceClass.end_span(span_overlays)

	# 回放/复盘：日志时间线指针 + ReplayBar 显示 + ActionPanel 禁用
	if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("sync_timeline_ui"):
		_timeline_controller.call("sync_timeline_ui", head_index, cursor_index, state)

	_maybe_show_online_turn_toast(head_index, cursor_index, state)
	_maybe_show_phase_change_toast(head_index, cursor_index, state)

	# 同步调试面板
	if _debug_panel != null and is_instance_valid(_debug_panel) and _debug_panel.visible and _debug_panel.has_method("refresh_state"):
		_debug_panel.call("refresh_state")

func on_debug_command_executed(command: String) -> void:
	# undo/redo/restore/load 会“改写时间线”；
	# M4.3：日志面板统一使用 step_timeline，因此时间线变化后需要重建 step_timeline 视图。
	var cmd := str(command).strip_edges()
	var head := cmd.split(" ", false, 1)[0] if not cmd.is_empty() else ""
	var is_timeline_change := (head == "undo" or head == "redo" or head == "restore" or head == "load")

	# 避免时间线变化后仍停留在旧面板/选点上下文导致“看起来没回退”；
	# 不再强制 hide：保持面板打开，但下一帧强制从 state 全量同步，避免残留旧 UI 缓存。
	if is_timeline_change and is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("request_force_full_panel_sync_next_update"):
			_timeline_controller.call("request_force_full_panel_sync_next_update")
		if _timeline_controller.has_method("apply_live_log_timeline_from_engine"):
			_timeline_controller.call("apply_live_log_timeline_from_engine")
		# 调试面板的 undo/redo 需要进入“时间线编辑模式”，否则 undo 后 UI 会处于只读态导致无法继续操作。
		if head == "undo" or head == "redo":
			if _timeline_controller.has_method("set_timeline_edit_mode_active"):
				_timeline_controller.call("set_timeline_edit_mode_active", true)

	if _refresh_ui.is_valid():
		_refresh_ui.call()

func _maybe_show_online_turn_toast(head_index: int, cursor_index: int, state: GameState) -> void:
	if OS.has_feature("headless"):
		return
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		_online_turn_toast_last_player_id = -999
		return
	if is_instance_valid(_online_resync_controller) and _online_resync_controller.has_method("is_resync_in_progress"):
		if bool(_online_resync_controller.call("is_resync_in_progress")):
			return
	if state == null:
		return
	if is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
			return
		if _timeline_controller.has_method("is_history_step_timeline_active") and bool(_timeline_controller.call("is_history_step_timeline_active")):
			return
	if cursor_index < head_index:
		return
	if str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
		return

	var local_pid := int(NetContext.local_player_id)
	if local_pid < 0:
		return
	var current_pid := int(state.get_current_player_id())
	if current_pid < 0:
		return
	if current_pid == _online_turn_toast_last_player_id:
		return
	_online_turn_toast_last_player_id = current_pid

	if current_pid != local_pid:
		return

	if is_instance_valid(_overlay_controller) and _overlay_controller.has_method("show_toast"):
		_overlay_controller.call("show_toast", "轮到你行动")

	var sm := SoundManager.get_instance()
	if sm != null and is_instance_valid(sm):
		# 占位：若资源缺失则静默；后续补齐 res://ui/audio/sfx/event_turn_start.(wav/ogg/mp3)
		sm.play(SoundManager.SOUND_TURN_START)

func _maybe_show_phase_change_toast(head_index: int, cursor_index: int, state: GameState) -> void:
	if OS.has_feature("headless"):
		return
	if state == null:
		return

	# 回放/复盘/时间线回退时会频繁切换阶段：避免刷屏，仅在“实时头部”显示。
	if is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
			_phase_toast_last_phase = ""
			return
		if _timeline_controller.has_method("is_history_step_timeline_active") and bool(_timeline_controller.call("is_history_step_timeline_active")):
			_phase_toast_last_phase = ""
			return
	if cursor_index < head_index:
		return

	var phase := str(state.phase).strip_edges()
	if phase.is_empty():
		return
	if _phase_toast_last_phase.is_empty():
		_phase_toast_last_phase = phase
		return
	if phase == _phase_toast_last_phase:
		return
	_phase_toast_last_phase = phase

	# 只提示大阶段；Working 内子阶段不提示（sub_phase 忽略）。
	var display_name = GameLogPanel.PHASE_DISPLAY_NAMES.get(phase, phase)
	var msg := "进入阶段：%s" % str(display_name)
	if is_instance_valid(_overlay_controller) and _overlay_controller.has_method("show_toast"):
		_overlay_controller.call("show_toast", msg)
