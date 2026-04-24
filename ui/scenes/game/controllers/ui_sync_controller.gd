# Game scene：UI 同步控制器
# 负责：顶栏信息刷新、地图/面板/覆盖层同步、提示 toast（联机轮到你/阶段切换）、调试命令后的 UI 重建触发。
class_name GameUiSyncController
extends RefCounted

const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

# 阶段英文 → 中文映射（用于 toast 等）
const PHASE_DISPLAY_NAMES: Dictionary = {
	"Setup": "设置阶段",
	"Restructuring": "重组结构",
	"OrderOfBusiness": "商业秩序",
	"Working": "工作时间",
	"Dinnertime": "晚餐时间",
	"Payday": "发薪日",
	"Marketing": "营销结算",
	"Cleanup": "清理阶段",
	"GameOver": "游戏结束",
}

var _get_game_engine: Callable = Callable()
var _refresh_ui: Callable = Callable()
var _sync_right_panel_docked_view: Callable = Callable()

var _round_label: Label = null
var _phase_track: Control = null
var _bank_label: Label = null
var _skip_bank_sync: bool = false

func get_bank_label() -> Label:
	return _bank_label

func set_skip_bank_sync(skip: bool) -> void:
	_skip_bank_sync = skip
var _bank_break_tag: Label = null

var _game_log_panel: Control = null
var _map_view: Control = null

var _panel_controller: Object = null
var _overlay_controller: Object = null
var _timeline_controller: Object = null
var _online_resync_controller: Object = null

var _debug_panel: Window = null

var _online_turn_toast_last_player_id: int = -999
var _phase_toast_last_phase: String = ""
var _last_can_peek_all_reserve_cards_by_player: Array[bool] = []
var _pending_first_have_20_overview_player_id: int = -1

func _init(
	get_game_engine: Callable,
	refresh_ui: Callable,
	sync_right_panel_docked_view: Callable,
	round_label: Label,
	phase_track: Control,
	bank_label: Label,
	bank_break_tag: Label,
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
	_phase_track = phase_track
	_bank_label = bank_label
	_bank_break_tag = bank_break_tag
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
	_phase_track = null
	_bank_label = null
	_bank_break_tag = null
	_game_log_panel = null
	_map_view = null
	_panel_controller = null
	_overlay_controller = null
	_timeline_controller = null
	_online_resync_controller = null
	_debug_panel = null
	_last_can_peek_all_reserve_cards_by_player.clear()
	_pending_first_have_20_overview_player_id = -1

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
	var online_span_total := OnlinePerfTraceClass.begin_span("ui.online_sync.total", {
		"phase": str(state.phase),
		"round": int(state.round_number),
		"history_size": int(game_engine.command_history.size()),
		"cursor_command_index": int(game_engine.current_command_index),
	})

	if is_instance_valid(_round_label):
		if str(state.phase) == DefsClass.PHASE_SETUP:
			_round_label.text = "准备阶段"
		else:
			_round_label.text = "第 %d 回合" % int(state.round_number)
	if is_instance_valid(_phase_track) and _phase_track.has_method("set_current_phase"):
		_phase_track.set_current_phase(str(state.phase).strip_edges())

	if is_instance_valid(_bank_label) and not _skip_bank_sync:
		_bank_label.text = "$%d" % int(state.bank.get("total", 0))
	if is_instance_valid(_bank_break_tag):
		var broke_count := int(state.bank.get("broke_count", 0))
		_bank_break_tag.visible = broke_count >= 1

	var head_index := int(game_engine.command_history.size() - 1)
	var cursor_index := int(game_engine.current_command_index)
	if is_instance_valid(_timeline_controller):
		var hc = _timeline_controller.call("get_ui_head_cursor", game_engine)
		if hc is Vector2i:
			head_index = int(hc.x)
			cursor_index = int(hc.y)

	if is_instance_valid(_game_log_panel) and _game_log_panel.has_method("set_player_count"):
		_game_log_panel.call("set_player_count", int(state.players.size()))

	# 回放/复盘/联机等待：先同步“是否可操作”的状态，再同步面板。
	# 否则会出现“本帧先刷新出可点击面板，下一步才被禁用”的短暂交互窗口。
	if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("sync_timeline_ui"):
		var online_span_timeline := OnlinePerfTraceClass.begin_span("ui.online_sync.timeline_ui", {
			"phase": str(state.phase),
			"round": int(state.round_number),
			"head_index": int(head_index),
			"cursor_index": int(cursor_index),
		})
		_timeline_controller.call("sync_timeline_ui", head_index, cursor_index, state)
		OnlinePerfTraceClass.end_span(online_span_timeline, {
			"phase": str(state.phase),
			"round": int(state.round_number),
			"head_index": int(head_index),
			"cursor_index": int(cursor_index),
		})

	# 地图渲染
	if is_instance_valid(_map_view) and _map_view.has_method("set_game_state"):
		var span_map := PerfTraceClass.begin_span("ui:map_view.set_game_state") if do_profile else -1
		var online_span_map := OnlinePerfTraceClass.begin_span("ui.online_sync.map_view", {
			"phase": str(state.phase),
			"round": int(state.round_number),
		})
		_map_view.call("set_game_state", state)
		if do_profile:
			PerfTraceClass.end_span(span_map)
		OnlinePerfTraceClass.end_span(online_span_map, {
			"phase": str(state.phase),
			"round": int(state.round_number),
		})

	# 面板/覆盖层同步
	if is_instance_valid(_panel_controller) and _panel_controller.has_method("sync"):
		var span_panels := PerfTraceClass.begin_span("ui:panel_controller.sync") if do_profile else -1
		var force_refresh := false
		if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("consume_force_full_panel_sync_next_update"):
			force_refresh = bool(_timeline_controller.call("consume_force_full_panel_sync_next_update"))
		var online_span_panels := OnlinePerfTraceClass.begin_span("ui.online_sync.panel_controller", {
			"phase": str(state.phase),
			"round": int(state.round_number),
			"force_refresh": bool(force_refresh),
		})
		_panel_controller.call("sync", state, force_refresh)
		if _sync_right_panel_docked_view.is_valid():
			_sync_right_panel_docked_view.call()
		if do_profile:
			PerfTraceClass.end_span(span_panels)
		OnlinePerfTraceClass.end_span(online_span_panels, {
			"phase": str(state.phase),
			"round": int(state.round_number),
			"force_refresh": bool(force_refresh),
		})

	if is_instance_valid(_overlay_controller):
		var span_overlays := PerfTraceClass.begin_span("ui:overlay_controller.sync") if do_profile else -1
		var online_span_overlays := OnlinePerfTraceClass.begin_span("ui.online_sync.overlay_controller", {
			"phase": str(state.phase),
			"round": int(state.round_number),
			"timeline_at_head": bool(head_index == cursor_index),
		})
		if _overlay_controller.has_method("sync_demand_indicator"):
			_overlay_controller.call("sync_demand_indicator", state)
		if _overlay_controller.has_method("sync_dinnertime_overlay"):
			_overlay_controller.call("sync_dinnertime_overlay", state, head_index == cursor_index)
		if _overlay_controller.has_method("sync_marketing_overlay"):
			_overlay_controller.call("sync_marketing_overlay", state, head_index == cursor_index)
		if do_profile:
			PerfTraceClass.end_span(span_overlays)
		OnlinePerfTraceClass.end_span(online_span_overlays, {
			"phase": str(state.phase),
			"round": int(state.round_number),
			"timeline_at_head": bool(head_index == cursor_index),
		})

	_maybe_show_online_turn_toast(head_index, cursor_index, state)
	_maybe_show_phase_change_toast(head_index, cursor_index, state)
	_maybe_open_first_have_20_overview(game_engine, state)

	# 同步调试面板
	if _debug_panel != null and is_instance_valid(_debug_panel) and _debug_panel.visible and _debug_panel.has_method("refresh_state"):
		var online_span_debug_panel := OnlinePerfTraceClass.begin_span("ui.online_sync.debug_panel", {
			"phase": str(state.phase),
			"round": int(state.round_number),
		})
		_debug_panel.call("refresh_state")
		OnlinePerfTraceClass.end_span(online_span_debug_panel, {
			"phase": str(state.phase),
			"round": int(state.round_number),
		})
	OnlinePerfTraceClass.end_span(online_span_total, {
		"phase": str(state.phase),
		"round": int(state.round_number),
		"history_size": int(game_engine.command_history.size()),
		"cursor_command_index": int(game_engine.current_command_index),
	})

func _maybe_open_first_have_20_overview(game_engine: GameEngine, state: GameState) -> void:
	if state == null or not (state.players is Array):
		_last_can_peek_all_reserve_cards_by_player.clear()
		_pending_first_have_20_overview_player_id = -1
		return
	if _is_timeline_read_only(game_engine):
		_last_can_peek_all_reserve_cards_by_player = _read_can_peek_flags(state)
		return

	var current_flags := _read_can_peek_flags(state)
	if _pending_first_have_20_overview_player_id >= 0:
		if str(state.phase) != DefsClass.PHASE_DINNERTIME and not _is_reserve_cards_overview_visible():
			if _should_auto_open_first_have_20_for_player(_pending_first_have_20_overview_player_id):
				if is_instance_valid(_panel_controller) and _panel_controller.has_method("show_reserve_cards_overview"):
					_panel_controller.call("show_reserve_cards_overview", _pending_first_have_20_overview_player_id)
			_pending_first_have_20_overview_player_id = -1
	if _last_can_peek_all_reserve_cards_by_player.size() != current_flags.size():
		_last_can_peek_all_reserve_cards_by_player = current_flags
		return

	for pid in range(current_flags.size()):
		var had_before := bool(_last_can_peek_all_reserve_cards_by_player[pid])
		var has_now := bool(current_flags[pid])
		if had_before or not has_now:
			continue
		if not _should_auto_open_first_have_20_for_player(pid):
			continue
		if str(state.phase) == DefsClass.PHASE_DINNERTIME:
			_pending_first_have_20_overview_player_id = pid
			break
		if _is_reserve_cards_overview_visible():
			break
		if is_instance_valid(_panel_controller) and _panel_controller.has_method("show_reserve_cards_overview"):
			_panel_controller.call("show_reserve_cards_overview", pid)
		break

	_last_can_peek_all_reserve_cards_by_player = current_flags

func _read_can_peek_flags(state: GameState) -> Array[bool]:
	var out: Array[bool] = []
	if state == null or not (state.players is Array):
		return out
	for player_val in state.players:
		if not (player_val is Dictionary):
			out.append(false)
			continue
		var player: Dictionary = player_val
		out.append(bool(player.get("can_peek_all_reserve_cards", false)))
	return out

func _should_auto_open_first_have_20_for_player(player_id: int) -> bool:
	if player_id < 0:
		return false
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		return int(NetContext.local_player_id) == player_id
	return true

func _is_reserve_cards_overview_visible() -> bool:
	if not is_instance_valid(_panel_controller) or not _panel_controller.has_method("get_reserve_cards_full_screen_view"):
		return false
	var view = _panel_controller.call("get_reserve_cards_full_screen_view")
	return view != null and is_instance_valid(view) and bool(view.visible)

func _is_timeline_read_only(game_engine: GameEngine) -> bool:
	if not is_instance_valid(_timeline_controller):
		return false
	if _timeline_controller.has_method("is_timeline_read_only_active"):
		var ro = _timeline_controller.call("is_timeline_read_only_active", game_engine)
		if ro is bool:
			return bool(ro)
	if _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
		return true
	return false

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
			_timeline_controller.call("apply_live_log_timeline_from_engine", true)
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
