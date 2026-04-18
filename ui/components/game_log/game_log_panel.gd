# 游戏日志面板组件
# 显示游戏事件历史记录
class_name GameLogPanel
extends Control

signal close_requested()
signal log_entry_clicked(entry_id: int)
signal timeline_seek_requested(timeline_index: int)
signal log_added(entry: Dictionary)
signal log_entry_hovered(entry_id: int, hovering: bool)
signal replay_toggle_changed(active: bool)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TopRow/TitleLabel
@onready var options_row: Control = $MarginContainer/VBoxContainer/TitleRow/OptionsRow
@onready var show_phase_events_check: CheckBox = $MarginContainer/VBoxContainer/TitleRow/OptionsRow/ShowPhaseEventsCheck
@onready var fold_details_check: CheckBox = $MarginContainer/VBoxContainer/TitleRow/OptionsRow/FoldDetailsCheck
@onready var close_btn: Button = $MarginContainer/VBoxContainer/TitleRow/TopRow/CloseButton
@onready var replay_toggle_button: Button = $MarginContainer/VBoxContainer/TitleRow/TopRow/ReplayToggleButton
@onready var replay_bar: Control = $MarginContainer/VBoxContainer/TitleRow/ReplayBar
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var log_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LogContainer
@onready var auto_scroll_check: CheckBox = $MarginContainer/VBoxContainer/BottomRow/AutoScrollCheck
@onready var entry_count_label: Label = $MarginContainer/VBoxContainer/BottomRow/EntryCountLabel

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const GameLogEntryUtilsClass = preload("res://ui/components/game_log/game_log_entry_utils.gd")
const GameLogDetailsWindowControllerClass = preload("res://ui/components/game_log/game_log_details_window_controller.gd")
const GameLogUnifiedTimelineBuilderClass = preload("res://ui/components/game_log/game_log_unified_timeline_builder.gd")
const GameLogTimelineBackgroundWorkerClass = preload("res://ui/components/game_log/game_log_timeline_background_worker.gd")
const GameLogItemClass = preload("res://ui/components/game_log/game_log_item.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

const _POOL_KIND_FLAT_ENTRY := "flat_entry"
const _BACKGROUND_TIMELINE_MIN_STEPS := 96
const _BACKGROUND_TIMELINE_MIN_ENTRIES := 192
const _DESCRIPTOR_COMMIT_REBUILD_SLICE_SIZE := 24
const _DESCRIPTOR_COMMIT_APPEND_SLICE_SIZE := 32

# 日志类型
enum LogType {
	SYSTEM,      # 系统消息
	PHASE,       # 阶段变更
	PLAYER,      # 玩家操作
	GAME_EVENT,  # 游戏事件（银行破产等）
	DEBUG,       # 调试信息
}

const LOG_TYPE_NAMES: Dictionary = {
	LogType.SYSTEM: "系统",
	LogType.PHASE: "阶段",
	LogType.PLAYER: "玩家",
	LogType.GAME_EVENT: "事件",
	LogType.DEBUG: "调试",
}

const LOG_TYPE_COLORS: Dictionary = {
	LogType.SYSTEM: Color(0.6, 0.6, 0.6, 1),
	LogType.PHASE: Color(0.5, 0.7, 0.9, 1),
	LogType.PLAYER: Color(0.9, 0.9, 0.9, 1),
	LogType.GAME_EVENT: Color(0.9, 0.7, 0.4, 1),
	LogType.DEBUG: Color(0.5, 0.8, 0.5, 1),
}

const PHASE_DISPLAY_NAMES: Dictionary = {
	DefsClass.PHASE_WORKING: "工作时间",
	DefsClass.PHASE_DINNERTIME: "晚餐结算",
	DefsClass.PHASE_SETUP: "开局设置",
	DefsClass.PHASE_PAYDAY: "发薪日",
	DefsClass.PHASE_MARKETING: "广告行动",
	DefsClass.PHASE_CLEANUP: "清理阶段",
	DefsClass.PHASE_RESTRUCTURING: "重组结构",
	DefsClass.PHASE_ORDER_OF_BUSINESS: "商业秩序",
	DefsClass.PHASE_GAME_OVER: "游戏结束",
}

var _step_timeline: Dictionary = {} # {initial_state_dict, steps[], events[]}
var _timeline_entries: Array[Dictionary] = [] # timeline events formatted as entries
var _extra_entries: Array[Dictionary] = [] # UI-only logs (e.g. failed action)
var _entries_all: Array[Dictionary] = []  # merged entries for details lookup
var _entry_id_counter: int = 0
var _log_items: Array[Control] = [] # GameLogItem / GameLogRoundHeaderItem / GameLogPhaseHeaderItem / GameLogActionGroupHeaderItem / GameLogEventItem
var _log_item_pool: Dictionary = {} # kind -> Array[Control]
var _auto_scroll: bool = true
var _scroll_to_bottom_requested: bool = false
var _max_entries: int = 0 # 0 表示不截断（完整时间线需要保留未来日志）
var _player_count: int = 0
var _show_phase_events: bool = false
var _fold_details_enabled: bool = false
var _expanded_action_groups: Dictionary = {} # step_index -> true（当启用折叠时仅展开少量动作组）

# 时间线（回放/查看历史）预留：在 M1 引入“完整日志”前仅存储指针，不改变渲染。
var _timeline_head_index: int = -1
var _timeline_cursor_index: int = -1

var _details_controller = null
var _blank_display_warned: bool = false
var _replay_toggle_available: bool = true
var _replay_toggle_inactive_text: String = "进入回放"
var _replay_toggle_disabled_reason: String = ""
var _last_step_timeline_update_mode: String = ""
var _timeline_background_worker = null
var _timeline_background_thread: Thread = null
var _timeline_background_running_job: Dictionary = {}
var _timeline_background_pending_job: Dictionary = {}
var _timeline_background_main_thread_scheduled: bool = false
var _timeline_background_generation: int = 0
var _visible_entry_count_cached: int = -1
var _timeline_exact_items_by_index: Dictionary = {} # timeline index -> Array[Control]
var _timeline_first_item_by_index: Dictionary = {} # timeline index -> first visible Control
var _timeline_phase_header_items: Array[Control] = []
var _timeline_round_header_items: Array[Control] = []
var _descriptor_commit_active: bool = false
var _descriptor_commit_mode: String = ""
var _descriptor_commit_descriptors: Array = []
var _descriptor_commit_next_index: int = 0
var _descriptor_commit_patch_end_step_index: int = -999
var _descriptor_commit_added_item_count: int = 0
var _descriptor_commit_slice_count: int = 0
var _descriptor_commit_span = null

func _ready() -> void:
	set_process(false)
	_timeline_background_worker = GameLogTimelineBackgroundWorkerClass.new()
	if auto_scroll_check != null:
		auto_scroll_check.toggled.connect(_on_auto_scroll_toggled)
		auto_scroll_check.button_pressed = _auto_scroll

	if replay_toggle_button != null:
		replay_toggle_button.toggled.connect(_on_replay_toggle_toggled)

	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)

	if show_phase_events_check != null:
		show_phase_events_check.toggled.connect(_on_show_phase_events_toggled)
		show_phase_events_check.button_pressed = _show_phase_events

	if fold_details_check != null:
		fold_details_check.toggled.connect(_on_fold_details_toggled)
		fold_details_check.button_pressed = _fold_details_enabled

	if options_row != null:
		options_row.visible = false
	if show_phase_events_check != null:
		show_phase_events_check.visible = false
	if fold_details_check != null:
		fold_details_check.visible = false

	if title_label != null:
		UiStylesClass.apply_label_dark(title_label)
	if show_phase_events_check != null:
		UiStylesClass.apply_check_box_field(show_phase_events_check)
	if fold_details_check != null:
		UiStylesClass.apply_check_box_field(fold_details_check)
	if auto_scroll_check != null:
		UiStylesClass.apply_check_box_field(auto_scroll_check)
	if entry_count_label != null:
		UiStylesClass.apply_label_hint_dark(entry_count_label)

	UiStylesClass.apply_button_secondary(close_btn)
	UiStylesClass.apply_button_secondary(replay_toggle_button)
	_sync_replay_toggle_button_state()

	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _exit_tree() -> void:
	_shutdown_background_timeline_worker()

func _process(_delta: float) -> void:
	_poll_background_timeline_worker()
	_poll_descriptor_commit()

func add_log(log_type: LogType, message: String, details: Dictionary = {}) -> int:
	var entry_id := _entry_id_counter
	_entry_id_counter += 1

	var entry: Dictionary = {
		"id": entry_id,
		"type": log_type,
		"message": message,
		"timestamp": Time.get_datetime_string_from_system(),
		"details": details,
	}

	if _is_step_timeline_loaded():
		_invalidate_background_timeline_jobs()
		# UI-only 日志：默认挂到当前 cursor step（回放/复盘时仍可定位到该 step）
		_attach_entry_to_current_step(entry)
		_extra_entries.append(entry)
		_rebuild_entries_all()
		log_added.emit(entry)
		_rebuild_display()
		_request_scroll_to_bottom()
		_update_entry_count()
		return entry_id

	_entries_all.append(entry)
	log_added.emit(entry)

	# 限制最大条目数
	_enforce_max_entries()

	_add_log_item(entry)
	_update_entry_count()

	return entry_id

func _enforce_max_entries() -> void:
	if _max_entries <= 0:
		return
	while _entries_all.size() > _max_entries:
		_entries_all.pop_front()

func append_entry(entry: Dictionary) -> void:
	if entry == null or entry.is_empty():
		return

	var d: Dictionary = entry.duplicate(true)
	if _is_step_timeline_loaded():
		_invalidate_background_timeline_jobs()
		d["id"] = _entry_id_counter
		_entry_id_counter += 1
		if not d.has("step_index"):
			_attach_entry_to_current_step(d)
		_extra_entries.append(d)
		_rebuild_entries_all()
		_rebuild_display()
		_request_scroll_to_bottom()
		_update_entry_count()
		return

	_entries_all.append(d)
	_enforce_max_entries()
	_add_log_item(d)
	_update_entry_count()

func get_entries() -> Array[Dictionary]:
	return _entries_all.duplicate(true)

func get_step_timeline_entries() -> Array[Dictionary]:
	return _timeline_entries.duplicate(true)

func get_last_step_timeline_update_mode() -> String:
	return _last_step_timeline_update_mode

func has_step_timeline_loaded() -> bool:
	return _is_step_timeline_loaded()

func has_pending_descriptor_commit() -> bool:
	return _descriptor_commit_active

func _duplicate_entry_array(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_val in entries:
		if entry_val is Dictionary:
			out.append(Dictionary(entry_val).duplicate(true))
	return out

func _duplicate_entry_array_with_fresh_ids(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_val in entries:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_val).duplicate(true)
		entry["id"] = _entry_id_counter
		_entry_id_counter += 1
		out.append(entry)
	return out

func _adopt_entry_array_preserving_ids(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var next_entry_id := int(_entry_id_counter)
	for entry_val in entries:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_val).duplicate(false)
		var has_valid_id := false
		var id_val = entry.get("id", null)
		if id_val is int:
			next_entry_id = maxi(next_entry_id, int(id_val) + 1)
			has_valid_id = true
		elif id_val is float:
			var id_float := float(id_val)
			if id_float == floor(id_float):
				next_entry_id = maxi(next_entry_id, int(id_float) + 1)
				has_valid_id = true
		if not has_valid_id:
			entry["id"] = next_entry_id
			next_entry_id += 1
		out.append(entry)
	_entry_id_counter = maxi(int(_entry_id_counter), int(next_entry_id))
	return out

func _build_entries_all_for_state(timeline_entries: Array[Dictionary], extra_entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in timeline_entries:
		if entry is Dictionary:
			out.append(Dictionary(entry).duplicate(true))
	for extra in extra_entries:
		if extra is Dictionary:
			out.append(Dictionary(extra).duplicate(true))
	return out

func _get_initial_round_number_for_timeline(timeline: Dictionary) -> int:
	if timeline == null or not (timeline is Dictionary):
		return -1
	var init_val = timeline.get("initial_state_dict", null)
	if not (init_val is Dictionary):
		return -1
	var init: Dictionary = init_val
	var r_val = init.get("round_number", null)
	if r_val is int:
		return int(r_val)
	if r_val is float:
		var f: float = float(r_val)
		if f == floor(f):
			return int(f)
	return -1

func _get_initial_phase_segment_for_timeline(timeline: Dictionary) -> String:
	if timeline == null or not (timeline is Dictionary):
		return ""
	var init_val = timeline.get("initial_state_dict", null)
	if not (init_val is Dictionary):
		return ""
	return str(Dictionary(init_val).get("phase", "")).strip_edges()

func _should_use_background_timeline_job(timeline: Dictionary, entries_all: Array[Dictionary]) -> bool:
	return _should_use_background_timeline_job_for_count(timeline, entries_all.size())

func _should_use_background_timeline_job_for_count(timeline: Dictionary, entry_count: int) -> bool:
	return _get_step_count(timeline) >= _BACKGROUND_TIMELINE_MIN_STEPS or int(entry_count) >= _BACKGROUND_TIMELINE_MIN_ENTRIES

func _invalidate_background_timeline_jobs() -> void:
	_timeline_background_generation += 1
	_timeline_background_pending_job.clear()
	_cancel_pending_descriptor_commit()

func _queue_background_timeline_job(job: Dictionary) -> void:
	_timeline_background_generation += 1
	var next_job: Dictionary = job.duplicate(false)
	next_job["generation"] = int(_timeline_background_generation)
	if _should_run_background_timeline_job_on_main_thread():
		_timeline_background_pending_job = next_job
		if not _timeline_background_main_thread_scheduled:
			_timeline_background_main_thread_scheduled = true
			call_deferred("_flush_main_thread_timeline_job")
		return
	if _timeline_background_thread != null:
		_timeline_background_pending_job = next_job
		return
	_start_background_timeline_job(next_job)

func _start_background_timeline_job(job: Dictionary) -> void:
	if job == null or job.is_empty():
		return
	if _timeline_background_worker == null:
		_timeline_background_worker = GameLogTimelineBackgroundWorkerClass.new()

	var thread := Thread.new()
	var err := thread.start(Callable(_timeline_background_worker, "execute").bind(job))
	if err != OK:
		_apply_background_timeline_job_fallback(job)
		return

	_timeline_background_running_job = job
	_timeline_background_thread = thread
	_update_process_state()

func _should_run_background_timeline_job_on_main_thread() -> bool:
	return OS.has_feature("web")

func _flush_main_thread_timeline_job() -> void:
	_timeline_background_main_thread_scheduled = false
	if _timeline_background_pending_job.is_empty():
		return
	var job := _timeline_background_pending_job
	_timeline_background_pending_job = {}
	var result = _timeline_background_worker.execute(job)
	var finished_generation := int(job.get("generation", -1))
	if finished_generation != int(_timeline_background_generation):
		if not _timeline_background_pending_job.is_empty() and not _timeline_background_main_thread_scheduled:
			_timeline_background_main_thread_scheduled = true
			call_deferred("_flush_main_thread_timeline_job")
		return
	if result is Dictionary:
		_apply_background_timeline_result(job, Dictionary(result))
	else:
		_apply_background_timeline_job_fallback(job)
	if not _timeline_background_pending_job.is_empty() and not _timeline_background_main_thread_scheduled:
		_timeline_background_main_thread_scheduled = true
		call_deferred("_flush_main_thread_timeline_job")

func _poll_background_timeline_worker() -> void:
	if _timeline_background_thread == null:
		if _timeline_background_pending_job.is_empty():
			_update_process_state()
		elif _timeline_background_running_job.is_empty():
			var queued_job := _timeline_background_pending_job
			_timeline_background_pending_job = {}
			_start_background_timeline_job(queued_job)
		return
	if _timeline_background_thread.is_alive():
		return
	var finished_job := _timeline_background_running_job
	var result = _timeline_background_thread.wait_to_finish()
	_timeline_background_thread = null
	_timeline_background_running_job = {}
	var has_newer_job := not _timeline_background_pending_job.is_empty()
	var finished_generation := int(finished_job.get("generation", -1))
	var should_apply := (not has_newer_job) and finished_generation == int(_timeline_background_generation)

	if should_apply and result is Dictionary:
		_apply_background_timeline_result(finished_job, Dictionary(result))
	elif should_apply:
		_apply_background_timeline_job_fallback(finished_job)

	if has_newer_job:
		var queued_job := _timeline_background_pending_job
		_timeline_background_pending_job = {}
		_start_background_timeline_job(queued_job)
	elif _timeline_background_thread == null:
		_update_process_state()

func _apply_background_timeline_result(job: Dictionary, result: Dictionary) -> void:
	var descriptor_info_val = result.get("descriptor_info", {})
	if not (descriptor_info_val is Dictionary):
		_apply_background_timeline_job_fallback(job)
		return
	var descriptor_info: Dictionary = descriptor_info_val
	var descriptors_val = descriptor_info.get("items", [])
	if not (descriptors_val is Array):
		_apply_background_timeline_job_fallback(job)
		return

	var mode := str(job.get("mode", "")).strip_edges()
	_apply_background_job_state(job)
	_update_visible_entry_count_cache_from_background_result(job, descriptor_info)

	match mode:
		"append":
			_start_descriptor_commit(
				"append",
				descriptors_val,
				int(descriptor_info.get("patch_existing_last_phase_header_end_step_index", -999))
			)
		_:
			_start_descriptor_commit("rebuild", descriptors_val)

func _apply_background_timeline_job_fallback(job: Dictionary) -> void:
	_cancel_pending_descriptor_commit()
	var mode := str(job.get("mode", "")).strip_edges()
	_apply_background_job_state(job)
	_visible_entry_count_cached = -1
	_rebuild_display()
	_last_step_timeline_update_mode = "append" if mode == "append" else "rebuild"
	_request_scroll_to_bottom()
	_update_entry_count()

func _apply_committed_step_timeline_state(timeline: Dictionary, timeline_entries: Array[Dictionary], extra_entries: Array[Dictionary]) -> void:
	_step_timeline = timeline.duplicate(true) if (timeline is Dictionary) else {}
	_timeline_entries = _duplicate_entry_array(timeline_entries)
	_extra_entries = _duplicate_entry_array(extra_entries)
	_rebuild_entries_all()

func _apply_background_job_state(job: Dictionary) -> void:
	var mode := str(job.get("mode", "")).strip_edges()
	if mode == "append":
		var append_state := _build_append_committed_state_from_job(job)
		var append_timeline_val = append_state.get("timeline", {})
		var append_timeline: Dictionary = append_timeline_val if (append_timeline_val is Dictionary) else {}
		var append_timeline_entries_val = append_state.get("timeline_entries", [])
		var append_timeline_entries: Array = append_timeline_entries_val if (append_timeline_entries_val is Array) else []
		var append_extra_entries_val = append_state.get("extra_entries", [])
		var append_extra_entries: Array = append_extra_entries_val if (append_extra_entries_val is Array) else []
		_apply_committed_step_timeline_state_owned(
			append_timeline,
			append_timeline_entries,
			append_extra_entries
		)
		return

	var timeline_val = job.get("timeline", {})
	var timeline: Dictionary = timeline_val if (timeline_val is Dictionary) else {}
	var timeline_entries_val = job.get("timeline_entries", [])
	var timeline_entries: Array = timeline_entries_val if (timeline_entries_val is Array) else []
	var extra_entries_val = job.get("extra_entries", [])
	var extra_entries: Array = extra_entries_val if (extra_entries_val is Array) else []
	_apply_committed_step_timeline_state_owned(timeline, timeline_entries, extra_entries)

func _apply_committed_step_timeline_state_owned(timeline: Dictionary, timeline_entries: Array, extra_entries: Array) -> void:
	_step_timeline = timeline.duplicate(false) if (timeline is Dictionary) else {}

	var committed_timeline_entries: Array[Dictionary] = []
	if timeline_entries is Array:
		for entry_val in timeline_entries:
			if entry_val is Dictionary:
				committed_timeline_entries.append(entry_val)
	_timeline_entries = committed_timeline_entries

	var committed_extra_entries: Array[Dictionary] = []
	if extra_entries is Array:
		for entry_val in extra_entries:
			if entry_val is Dictionary:
				committed_extra_entries.append(entry_val)
	_extra_entries = committed_extra_entries

	_rebuild_entries_all()

func _build_append_committed_state_from_job(job: Dictionary) -> Dictionary:
	var timeline_val = job.get("timeline", {})
	var timeline: Dictionary = timeline_val if (timeline_val is Dictionary) else {}
	var base_timeline_entry_count := int(job.get("base_timeline_entry_count", -1))
	var base_extra_entry_count := int(job.get("base_extra_entry_count", -1))
	if OnlinePerfTraceClass.enabled():
		var timeline_count_mismatch := base_timeline_entry_count >= 0 and base_timeline_entry_count != _timeline_entries.size()
		var extra_count_mismatch := base_extra_entry_count >= 0 and base_extra_entry_count != _extra_entries.size()
		if timeline_count_mismatch or extra_count_mismatch:
			OnlinePerfTraceClass.emit_event("ui.game_log.append_background_state_mismatch", {
				"expected_timeline_entry_count": int(base_timeline_entry_count),
				"actual_timeline_entry_count": int(_timeline_entries.size()),
				"expected_extra_entry_count": int(base_extra_entry_count),
				"actual_extra_entry_count": int(_extra_entries.size()),
			})

	var next_timeline_entries: Array = _timeline_entries.duplicate(false)
	var appended_entries_val = job.get("appended_timeline_entries", [])
	if appended_entries_val is Array:
		for entry_val in appended_entries_val:
			if entry_val is Dictionary:
				next_timeline_entries.append(entry_val)

	return {
		"timeline": timeline,
		"timeline_entries": next_timeline_entries,
		"extra_entries": _extra_entries.duplicate(false),
	}

func _update_visible_entry_count_cache_from_background_result(job: Dictionary, descriptor_info: Dictionary) -> void:
	var mode := str(job.get("mode", "")).strip_edges()
	if mode == "append":
		var base_visible_entry_count := int(job.get("base_visible_entry_count", -1))
		var visible_entry_count_delta := int(descriptor_info.get("visible_entry_count_delta", -1))
		if base_visible_entry_count >= 0 and visible_entry_count_delta >= 0:
			_visible_entry_count_cached = base_visible_entry_count + visible_entry_count_delta
		else:
			_visible_entry_count_cached = -1
		return

	_visible_entry_count_cached = int(descriptor_info.get("visible_entry_count", -1))

func _apply_descriptor_rebuild_result(descriptors: Array) -> void:
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.apply_descriptor_rebuild", {
		"descriptor_count": int(descriptors.size()),
	})
	_clear_display()
	var items: Array[Control] = []
	GameLogUnifiedTimelineBuilderClass.append_descriptor_slice(
		items,
		log_container,
		descriptors,
		0,
		descriptors.size(),
		_timeline_cursor_index,
		_timeline_head_index,
		Callable(self, "_on_timeline_header_clicked"),
		Callable(self, "_on_entry_clicked"),
		Callable(self, "_on_entry_double_clicked"),
		Callable(self, "_on_action_group_fold_toggled"),
		Callable(self, "_acquire_log_item")
	)
	_log_items = items
	for item in _log_items:
		if item is Control:
			_connect_item_hover_signals(item)
	_rebuild_timeline_item_indexes()
	OnlinePerfTraceClass.end_span(span, {
		"descriptor_count": int(descriptors.size()),
		"log_item_count": int(_log_items.size()),
	})

func _apply_descriptor_append_result(descriptors: Array, patch_end_step_index: int) -> void:
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.apply_descriptor_append", {
		"descriptor_count": int(descriptors.size()),
		"patch_end_step_index": int(patch_end_step_index),
	})
	if int(patch_end_step_index) > -999:
		_patch_last_phase_header_end_step_index(int(patch_end_step_index))
	var added_items: Array[Control] = []
	GameLogUnifiedTimelineBuilderClass.append_descriptor_slice(
		added_items,
		log_container,
		descriptors,
		0,
		descriptors.size(),
		_timeline_cursor_index,
		_timeline_head_index,
		Callable(self, "_on_timeline_header_clicked"),
		Callable(self, "_on_entry_clicked"),
		Callable(self, "_on_entry_double_clicked"),
		Callable(self, "_on_action_group_fold_toggled"),
		Callable(self, "_acquire_log_item")
	)
	for item in added_items:
		if item is Control:
			var ctrl: Control = item
			_log_items.append(ctrl)
			_index_log_item(ctrl)
			_connect_item_hover_signals(ctrl)
	OnlinePerfTraceClass.end_span(span, {
		"descriptor_count": int(descriptors.size()),
		"added_item_count": int(added_items.size()),
		"log_item_count": int(_log_items.size()),
	})

func _start_descriptor_commit(mode: String, descriptors: Array, patch_end_step_index: int = -999) -> void:
	_cancel_pending_descriptor_commit()
	_descriptor_commit_mode = "append" if str(mode) == "append" else "rebuild"
	_descriptor_commit_descriptors = descriptors if descriptors is Array else []
	_descriptor_commit_next_index = 0
	_descriptor_commit_patch_end_step_index = int(patch_end_step_index)
	_descriptor_commit_added_item_count = 0
	_descriptor_commit_slice_count = 0
	_descriptor_commit_active = true

	var span_name := "ui.game_log.apply_descriptor_append" if _descriptor_commit_mode == "append" else "ui.game_log.apply_descriptor_rebuild"
	var span_fields := {
		"descriptor_count": int(_descriptor_commit_descriptors.size()),
		"chunked": true,
	}
	if _descriptor_commit_mode == "append":
		span_fields["patch_end_step_index"] = int(_descriptor_commit_patch_end_step_index)
	_descriptor_commit_span = OnlinePerfTraceClass.begin_span(span_name, span_fields)

	if _descriptor_commit_mode == "rebuild":
		_clear_display()
	elif _descriptor_commit_patch_end_step_index > -999:
		_patch_last_phase_header_end_step_index(_descriptor_commit_patch_end_step_index)

	if _descriptor_commit_descriptors.is_empty():
		_finish_descriptor_commit()
		return
	_update_process_state()

func _poll_descriptor_commit() -> void:
	if not _descriptor_commit_active:
		return
	if log_container == null or not is_instance_valid(log_container):
		_finish_descriptor_commit()
		return
	if _descriptor_commit_next_index >= _descriptor_commit_descriptors.size():
		_finish_descriptor_commit()
		return

	var slice_size := _DESCRIPTOR_COMMIT_APPEND_SLICE_SIZE if _descriptor_commit_mode == "append" else _DESCRIPTOR_COMMIT_REBUILD_SLICE_SIZE
	var from_idx := int(_descriptor_commit_next_index)
	var to_idx := mini(from_idx + slice_size, _descriptor_commit_descriptors.size())
	var added_items: Array[Control] = []
	GameLogUnifiedTimelineBuilderClass.append_descriptor_slice(
		added_items,
		log_container,
		_descriptor_commit_descriptors,
		from_idx,
		to_idx,
		_timeline_cursor_index,
		_timeline_head_index,
		Callable(self, "_on_timeline_header_clicked"),
		Callable(self, "_on_entry_clicked"),
		Callable(self, "_on_entry_double_clicked"),
		Callable(self, "_on_action_group_fold_toggled"),
		Callable(self, "_acquire_log_item")
	)
	for item in added_items:
		if item is Control:
			var ctrl: Control = item
			_log_items.append(ctrl)
			_index_log_item(ctrl)
			_connect_item_hover_signals(ctrl)

	_descriptor_commit_next_index = int(to_idx)
	_descriptor_commit_added_item_count += int(added_items.size())
	_descriptor_commit_slice_count += 1

	if _descriptor_commit_next_index >= _descriptor_commit_descriptors.size():
		_finish_descriptor_commit()

func _finish_descriptor_commit() -> void:
	if not _descriptor_commit_active:
		_update_process_state()
		return

	var mode := _descriptor_commit_mode
	var descriptor_count := int(_descriptor_commit_descriptors.size())
	var added_item_count := int(_descriptor_commit_added_item_count)
	var slice_count := int(_descriptor_commit_slice_count)
	var span = _descriptor_commit_span

	_descriptor_commit_active = false
	_descriptor_commit_mode = ""
	_descriptor_commit_descriptors = []
	_descriptor_commit_next_index = 0
	_descriptor_commit_patch_end_step_index = -999
	_descriptor_commit_added_item_count = 0
	_descriptor_commit_slice_count = 0
	_descriptor_commit_span = null

	_blank_display_warned = false
	_prune_expanded_action_groups()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled
	_last_step_timeline_update_mode = mode if not mode.is_empty() else "rebuild"
	_apply_timeline_state_to_items()
	_request_scroll_to_bottom()
	_update_entry_count()
	_update_process_state()

	var span_fields := {
		"descriptor_count": int(descriptor_count),
		"log_item_count": int(_log_items.size()),
		"slice_count": int(slice_count),
		"chunked": true,
	}
	if mode == "append":
		span_fields["added_item_count"] = int(added_item_count)
	OnlinePerfTraceClass.end_span(span, span_fields)

func _cancel_pending_descriptor_commit() -> void:
	_descriptor_commit_active = false
	_descriptor_commit_mode = ""
	_descriptor_commit_descriptors = []
	_descriptor_commit_next_index = 0
	_descriptor_commit_patch_end_step_index = -999
	_descriptor_commit_added_item_count = 0
	_descriptor_commit_slice_count = 0
	_descriptor_commit_span = null
	_update_process_state()

func _update_process_state() -> void:
	set_process(_timeline_background_thread != null or _descriptor_commit_active)

func _patch_last_phase_header_end_step_index(end_step_index: int) -> void:
	for idx in range(_timeline_phase_header_items.size() - 1, -1, -1):
		var item_val = _timeline_phase_header_items[idx]
		if not (item_val is Control):
			continue
		var item: Control = item_val
		if not is_instance_valid(item):
			continue
		item.end_step_index = int(end_step_index)
		return

func _shutdown_background_timeline_worker() -> void:
	_timeline_background_pending_job.clear()
	_timeline_background_main_thread_scheduled = false
	_cancel_pending_descriptor_commit()
	if _timeline_background_thread != null:
		_timeline_background_thread.wait_to_finish()
		_timeline_background_thread = null
	_timeline_background_running_job.clear()
	_update_process_state()

func load_entries(entries: Array[Dictionary]) -> void:
	# Flat list mode (legacy/tests). This intentionally clears step timeline view state.
	_invalidate_background_timeline_jobs()
	_step_timeline.clear()
	_timeline_entries.clear()
	_extra_entries.clear()
	_entries_all.clear()
	_visible_entry_count_cached = -1
	_blank_display_warned = false
	_entry_id_counter = 0
	_fold_details_enabled = false
	_expanded_action_groups.clear()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled

	for e in entries:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		_entries_all.append(d.duplicate(true))
		var id_val = d.get("id", null)
		if id_val is int:
			_entry_id_counter = maxi(_entry_id_counter, int(id_val) + 1)
		elif id_val is float:
			var f: float = float(id_val)
			if f == floor(f):
				_entry_id_counter = maxi(_entry_id_counter, int(f) + 1)

	_rebuild_display()
	_request_scroll_to_bottom()
	_update_entry_count()
	_last_step_timeline_update_mode = "flat"

func load_step_timeline(timeline: Dictionary, entries: Array[Dictionary], reset_extra_entries: bool = false) -> void:
	# Unified timeline view (M4.3): structure comes from steps, contents come from formatted entries.
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.load_step_timeline", {
		"incoming_entries": int(entries.size()),
		"current_entries": int(_entries_all.size()),
		"reset_extra_entries": bool(reset_extra_entries),
		"timeline_loaded": bool(_is_step_timeline_loaded()),
	})
	var next_timeline: Dictionary = timeline.duplicate(true) if (timeline is Dictionary) else {}
	if _can_append_step_timeline(next_timeline, entries, bool(reset_extra_entries)):
		var appended_entries := _build_appended_timeline_entries(entries)
		if append_step_timeline(next_timeline, appended_entries, bool(reset_extra_entries)):
			OnlinePerfTraceClass.end_span(span, {
				"mode": "append",
				"entry_count": int(_entries_all.size()),
				"timeline_step_count": int(_get_step_count(_step_timeline)),
			})
			return

	next_timeline = timeline.duplicate(true) if (timeline is Dictionary) else {}
	var next_timeline_entries: Array[Dictionary] = []
	if not _is_step_timeline_loaded() and _timeline_entries.is_empty() and _extra_entries.is_empty():
		next_timeline_entries = _adopt_entry_array_preserving_ids(entries)
	else:
		next_timeline_entries = _duplicate_entry_array_with_fresh_ids(entries)

	var next_extra_entries: Array[Dictionary] = []
	if not bool(reset_extra_entries):
		next_extra_entries = _duplicate_entry_array(_extra_entries)
	var next_entries_count := next_timeline_entries.size() + next_extra_entries.size()
	if _should_use_background_timeline_job_for_count(next_timeline, next_entries_count):
		var next_entries_all := _build_entries_all_for_state(next_timeline_entries, next_extra_entries)
		_queue_background_timeline_job({
			"mode": "rebuild",
			"timeline": next_timeline,
			"timeline_entries": next_timeline_entries,
			"extra_entries": next_extra_entries,
			"entries_all": next_entries_all,
			"show_phase_events": _show_phase_events,
			"fold_details_enabled": _fold_details_enabled,
			"expanded_action_groups": _expanded_action_groups.duplicate(true),
			"initial_round_number": _get_initial_round_number_for_timeline(next_timeline),
			"initial_phase_segment": _get_initial_phase_segment_for_timeline(next_timeline),
		})
		OnlinePerfTraceClass.end_span(span, {
			"mode": "rebuild_async",
			"background": true,
			"entry_count": int(next_entries_count),
			"timeline_step_count": int(_get_step_count(next_timeline)),
		})
		return

	_apply_committed_step_timeline_state(next_timeline, next_timeline_entries, next_extra_entries)
	_blank_display_warned = false
	_prune_expanded_action_groups()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled

	_rebuild_display()
	_request_scroll_to_bottom()
	_update_entry_count()
	_last_step_timeline_update_mode = "rebuild"
	OnlinePerfTraceClass.end_span(span, {
		"mode": "rebuild",
		"entry_count": int(_entries_all.size()),
		"timeline_step_count": int(_get_step_count(_step_timeline)),
	})

func append_step_timeline(timeline: Dictionary, appended_entries: Array[Dictionary], reset_extra_entries: bool = false) -> bool:
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.append_step_timeline", {
		"appended_entries": int(appended_entries.size()),
		"current_entries": int(_entries_all.size()),
		"timeline_loaded": bool(_is_step_timeline_loaded()),
		"reset_extra_entries": bool(reset_extra_entries),
	})
	if bool(reset_extra_entries):
		OnlinePerfTraceClass.end_span(span, {"ok": false, "reason": "reset_extra_entries"})
		return false
	if not _is_step_timeline_loaded():
		OnlinePerfTraceClass.end_span(span, {"ok": false, "reason": "timeline_not_loaded"})
		return false
	if log_container == null or not is_instance_valid(log_container):
		OnlinePerfTraceClass.end_span(span, {"ok": false, "reason": "log_container_missing"})
		return false
	if _log_items.is_empty():
		OnlinePerfTraceClass.end_span(span, {"ok": false, "reason": "log_items_empty"})
		return false
	if timeline == null or not (timeline is Dictionary) or timeline.is_empty():
		OnlinePerfTraceClass.end_span(span, {"ok": false, "reason": "timeline_invalid"})
		return false

	var next_timeline: Dictionary = timeline.duplicate(false)
	var normalized_appended_entries := _duplicate_entry_array_with_fresh_ids(appended_entries)
	var next_entries_count := _timeline_entries.size() + normalized_appended_entries.size() + _extra_entries.size()
	if _should_use_background_timeline_job_for_count(next_timeline, next_entries_count):
		_queue_background_timeline_job({
			"mode": "append",
			"timeline": next_timeline,
			"appended_timeline_entries": normalized_appended_entries,
			"base_timeline_entry_count": int(_timeline_entries.size()),
			"base_extra_entry_count": int(_extra_entries.size()),
			"show_phase_events": _show_phase_events,
			"fold_details_enabled": _fold_details_enabled,
			"expanded_action_groups": _expanded_action_groups.duplicate(true),
			"initial_round_number": _get_initial_round_number_for_timeline(next_timeline),
			"initial_phase_segment": _get_initial_phase_segment_for_timeline(next_timeline),
			"start_step_index": _get_step_count(_step_timeline),
			"base_visible_entry_count": int(_visible_entry_count_cached),
		})
		OnlinePerfTraceClass.end_span(span, {
			"ok": true,
			"background": true,
			"mode": "append_async",
			"entry_count": int(next_entries_count),
			"timeline_step_count": int(_get_step_count(next_timeline)),
		})
		return true

	var next_timeline_entries := _duplicate_entry_array(_timeline_entries)
	for appended in normalized_appended_entries:
		next_timeline_entries.append(appended)
	var next_extra_entries := _duplicate_entry_array(_extra_entries)
	if not _append_step_timeline_display(next_timeline, normalized_appended_entries):
		OnlinePerfTraceClass.end_span(span, {"ok": false, "reason": "append_display_failed"})
		return false

	_apply_committed_step_timeline_state(next_timeline, next_timeline_entries, next_extra_entries)
	_blank_display_warned = false
	_prune_expanded_action_groups()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled
	_last_step_timeline_update_mode = "append"
	_apply_timeline_state_to_items()
	_request_scroll_to_bottom()
	_update_entry_count()
	OnlinePerfTraceClass.end_span(span, {
		"ok": true,
		"entry_count": int(_entries_all.size()),
		"timeline_step_count": int(_get_step_count(_step_timeline)),
	})
	return true

func set_expand_enabled(_enabled: bool) -> void:
	# 保留接口兼容 FullLogWindow，当前日志面板已移除“全屏”按钮。
	pass

func set_timeline_head(head_index: int, update_visible_items: bool = true) -> void:
	var h := int(head_index)
	if h == _timeline_head_index:
		return
	var previous_cursor_index := int(_timeline_cursor_index)
	var previous_head_index := int(_timeline_head_index)
	_timeline_head_index = h
	if bool(update_visible_items):
		_apply_timeline_state_delta(previous_cursor_index, previous_head_index)

func set_timeline_cursor(cursor_index: int, update_visible_items: bool = true) -> void:
	var c := int(cursor_index)
	if c == _timeline_cursor_index:
		if bool(update_visible_items) and _timeline_cursor_index >= _timeline_head_index:
			_request_scroll_to_bottom()
		return
	var previous_cursor_index := int(_timeline_cursor_index)
	var previous_head_index := int(_timeline_head_index)
	_timeline_cursor_index = c
	var should_scroll_to_cursor := _timeline_cursor_index < _timeline_head_index
	if bool(update_visible_items):
		_apply_timeline_state_delta(previous_cursor_index, previous_head_index, should_scroll_to_cursor)
	if bool(update_visible_items) and not should_scroll_to_cursor:
		_request_scroll_to_bottom()

func set_timeline_head_cursor(head_index: int, cursor_index: int, update_visible_items: bool = true) -> void:
	var h := int(head_index)
	var c := int(cursor_index)
	if h == _timeline_head_index and c == _timeline_cursor_index:
		if bool(update_visible_items) and c >= h:
			_request_scroll_to_bottom()
		return
	var previous_cursor_index := int(_timeline_cursor_index)
	var previous_head_index := int(_timeline_head_index)
	_timeline_head_index = h
	_timeline_cursor_index = c
	var should_scroll_to_cursor := c < h
	if bool(update_visible_items):
		_apply_timeline_state_delta(previous_cursor_index, previous_head_index, should_scroll_to_cursor)
	if bool(update_visible_items) and not should_scroll_to_cursor:
		_request_scroll_to_bottom()

func set_entry_command_index(entry_id: int, command_index: int) -> void:
	var cmd := int(command_index)
	for i in range(_entries_all.size()):
		var e_val = _entries_all[i]
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if int(e.get("id", -1)) != int(entry_id):
			continue

		e["command_index"] = cmd
		var details_val = e.get("details", {})
		var details: Dictionary = details_val if (details_val is Dictionary) else {}
		details["command_index"] = cmd
		e["details"] = details
		_entries_all[i] = e
		break

func add_system_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.SYSTEM, message, details)

func add_phase_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.PHASE, message, details)

func add_player_log(player_id: int, message: String, details: Dictionary = {}) -> int:
	var prefix := "玩家%d" % (player_id + 1)
	if Globals != null:
		if Globals.has_method("get_player_name_compact"):
			var s := str(Globals.get_player_name_compact(player_id)).strip_edges()
			if not s.is_empty():
				prefix = s
		elif Globals.has_method("get_player_name"):
			var s2 := str(Globals.get_player_name(player_id)).strip_edges()
			if not s2.is_empty():
				prefix = s2

	var d: Dictionary = details if (details is Dictionary) else {}
	if not d.has("player_id"):
		d = d.duplicate(true)
		d["player_id"] = player_id

	var full_message := "%s: %s" % [prefix, message]
	return add_log(LogType.PLAYER, full_message, d)

func add_event_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.GAME_EVENT, message, details)

func add_debug_log(message: String, details: Dictionary = {}) -> int:
	return add_log(LogType.DEBUG, message, details)

func clear_logs() -> void:
	_invalidate_background_timeline_jobs()
	_step_timeline.clear()
	_timeline_entries.clear()
	_extra_entries.clear()
	_entries_all.clear()
	_visible_entry_count_cached = -1
	_blank_display_warned = false
	_fold_details_enabled = false
	_expanded_action_groups.clear()
	if fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled
	_clear_display()
	_update_entry_count()

func get_replay_bar() -> Control:
	return replay_bar

func apply_font_settings() -> void:
	# 允许 SettingsDialog 在运行时调整日志可读性（例如字体倍率）。
	for item in _log_items:
		if is_instance_valid(item) and item.has_method("apply_font_settings"):
			item.apply_font_settings()
	for pool_val in _log_item_pool.values():
		if not (pool_val is Array):
			continue
		for pooled_item in pool_val:
			if pooled_item is Control and is_instance_valid(pooled_item) and pooled_item.has_method("apply_font_settings"):
				pooled_item.apply_font_settings()

func set_player_count(count: int) -> void:
	_player_count = maxi(0, count)

func ensure_display_ready() -> void:
	if not is_inside_tree():
		return
	if log_container == null or not is_instance_valid(log_container):
		return
	if _descriptor_commit_active:
		return

	# 没有日志数据：不强行塞占位符，保持空面板（但仍显示 EntryCountLabel）。
	var has_data := (not _entries_all.is_empty()) or _is_step_timeline_loaded()
	if not has_data:
		return

	# UI 已有子节点：无需重复 rebuild。
	if log_container.get_child_count() > 0:
		_blank_display_warned = false
		return

	var span := OnlinePerfTraceClass.begin_span("ui.game_log.ensure_display_ready", {
		"entry_count": int(_entries_all.size()),
		"timeline_loaded": bool(_is_step_timeline_loaded()),
		"child_count_before": int(log_container.get_child_count()),
	})
	_rebuild_display()
	_request_scroll_to_bottom()
	_update_entry_count()
	OnlinePerfTraceClass.end_span(span, {
		"entry_count": int(_entries_all.size()),
		"timeline_loaded": bool(_is_step_timeline_loaded()),
		"child_count_after": int(log_container.get_child_count()),
	})

	# 若数据存在但仍构建为空：打一次 warning（便于用户反馈时定位）。
	if log_container.get_child_count() <= 0 and not _entries_all.is_empty() and not _blank_display_warned:
		_blank_display_warned = true
		var steps_val = _step_timeline.get("steps", [])
		var steps_count := int(steps_val.size()) if (steps_val is Array) else 0
		var events_val = _step_timeline.get("events", [])
		var events_count := int(events_val.size()) if (events_val is Array) else 0
		GameLog.warn(
			"GameLogPanel",
			"日志面板构建为空（可能是初始化/布局时序问题）：entries=%d steps=%d events=%d visible_in_tree=%s" % [
				_entries_all.size(),
				steps_count,
				events_count,
				str(is_visible_in_tree()),
			]
		)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	# 延后一帧：避免 dock/reparent 后 Container 尚未完成 layout 导致的“短暂空白”。
	call_deferred("ensure_display_ready")
	if _scroll_to_bottom_requested or _should_keep_scroll_at_bottom():
		_scroll_to_bottom_requested = true
		call_deferred("_apply_scroll_to_bottom")

func _on_resized() -> void:
	if not _should_keep_scroll_at_bottom():
		return
	_scroll_to_bottom_requested = true
	call_deferred("_apply_scroll_to_bottom")

func _should_keep_scroll_at_bottom() -> bool:
	return _auto_scroll and _timeline_cursor_index >= _timeline_head_index

func _scroll_scroll_container_to_bottom() -> void:
	if scroll_container == null:
		return
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _is_step_timeline_loaded() -> bool:
	if _step_timeline == null or _step_timeline.is_empty():
		return false
	var steps_val = _step_timeline.get("steps", null)
	return (steps_val is Array)

func _is_action_group_expanded(step_index: int) -> bool:
	if not _fold_details_enabled:
		return true
	return bool(_expanded_action_groups.get(int(step_index), false))

func _prune_expanded_action_groups() -> void:
	if _expanded_action_groups == null or _expanded_action_groups.is_empty():
		return

	var max_step := int(_timeline_head_index)
	var steps_val = _step_timeline.get("steps", null)
	if steps_val is Array:
		max_step = (steps_val as Array).size() - 1

	for k in _expanded_action_groups.keys():
		if not (k is int or k is float):
			_expanded_action_groups.erase(k)
			continue
		var idx := int(k)
		if idx < -1 or idx > max_step:
			_expanded_action_groups.erase(k)

func _rebuild_entries_all() -> void:
	_entries_all.clear()
	for e in _timeline_entries:
		if e is Dictionary:
			_entries_all.append(Dictionary(e))
	for e2 in _extra_entries:
		if e2 is Dictionary:
			_entries_all.append(Dictionary(e2))

func _get_initial_state_dict() -> Dictionary:
	var init_val = _step_timeline.get("initial_state_dict", null)
	return Dictionary(init_val) if (init_val is Dictionary) else {}

func _get_initial_round_number() -> int:
	var init := _get_initial_state_dict()
	var r_val = init.get("round_number", null)
	if r_val is int:
		return int(r_val)
	if r_val is float:
		var f: float = float(r_val)
		if f == floor(f):
			return int(f)
	return -1

func _get_initial_phase_segment() -> String:
	var init := _get_initial_state_dict()
	return str(init.get("phase", "")).strip_edges()

func _get_step_count(timeline: Dictionary) -> int:
	if timeline == null or timeline.is_empty():
		return 0
	var steps_val = timeline.get("steps", null)
	return int((steps_val as Array).size()) if (steps_val is Array) else 0

func _entry_equals_ignoring_id(lhs: Dictionary, rhs: Dictionary) -> bool:
	var a := lhs.duplicate(true) if (lhs is Dictionary) else {}
	var b := rhs.duplicate(true) if (rhs is Dictionary) else {}
	if a.has("id"):
		a.erase("id")
	if b.has("id"):
		b.erase("id")
	return a == b

func _can_append_step_timeline(timeline: Dictionary, entries: Array, reset_extra_entries: bool) -> bool:
	if bool(reset_extra_entries):
		return false
	if not _is_step_timeline_loaded():
		return false
	if log_container == null or not is_instance_valid(log_container):
		return false
	if _log_items.is_empty():
		return false

	var old_steps_val = _step_timeline.get("steps", null)
	var new_steps_val = timeline.get("steps", null)
	if not (old_steps_val is Array) or not (new_steps_val is Array):
		return false
	var old_steps: Array = old_steps_val
	var new_steps: Array = new_steps_val
	if new_steps.size() <= old_steps.size():
		return false

	var old_init := Dictionary(_step_timeline.get("initial_state_dict", {}))
	var new_init := Dictionary(timeline.get("initial_state_dict", {}))
	if old_init != new_init:
		return false

	for idx in range(old_steps.size()):
		var old_step_val = old_steps[idx]
		var new_step_val = new_steps[idx]
		if not (old_step_val is Dictionary) or not (new_step_val is Dictionary):
			return false
		if Dictionary(old_step_val) != Dictionary(new_step_val):
			return false

	if not (entries is Array):
		return false
	if entries.size() < _timeline_entries.size():
		return false
	for idx in range(_timeline_entries.size()):
		var old_entry_val = _timeline_entries[idx]
		var new_entry_val = entries[idx]
		if not (old_entry_val is Dictionary) or not (new_entry_val is Dictionary):
			return false
		if not _entry_equals_ignoring_id(Dictionary(old_entry_val), Dictionary(new_entry_val)):
			return false

	return true

func _build_appended_timeline_entries(entries: Array) -> Array[Dictionary]:
	var raw_entries: Array[Dictionary] = []
	var start_idx := _timeline_entries.size()
	for idx in range(start_idx, entries.size()):
		var entry_val = entries[idx]
		if not (entry_val is Dictionary):
			continue
		raw_entries.append(Dictionary(entry_val).duplicate(true))
	return raw_entries

func _append_step_timeline_display(next_timeline: Dictionary, appended_entries: Array[Dictionary]) -> bool:
	var start_step_index := _get_step_count(_step_timeline)
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.append_step_range", {
		"start_step_index": int(start_step_index),
		"appended_entry_count": int(appended_entries.size()),
	})
	var append_info_val = GameLogUnifiedTimelineBuilderClass.append_step_range(
		_log_items,
		log_container,
		next_timeline,
		appended_entries,
		start_step_index,
		_show_phase_events,
		_fold_details_enabled,
		Callable(self, "_is_action_group_expanded"),
		_timeline_cursor_index,
		_timeline_head_index,
		Callable(self, "_on_timeline_header_clicked"),
		Callable(self, "_on_entry_clicked"),
		Callable(self, "_on_entry_double_clicked"),
		Callable(self, "_on_action_group_fold_toggled"),
		_get_initial_round_number(),
		_get_initial_phase_segment(),
		Callable(self, "_acquire_log_item")
	)
	if not (append_info_val is Dictionary):
		OnlinePerfTraceClass.end_span(span, {
			"ok": false,
			"reason": "append_info_invalid",
		})
		return false
	var append_info: Dictionary = append_info_val
	var added_items_val = append_info.get("items", [])
	if not (added_items_val is Array):
		OnlinePerfTraceClass.end_span(span, {
			"ok": false,
			"reason": "append_items_invalid",
		})
		return false
	var added_items: Array = added_items_val
	for item in added_items:
		if not (item is Control):
			continue
		var ctrl: Control = item
		_log_items.append(ctrl)
		_connect_item_hover_signals(ctrl)
	var visible_entry_count_delta := int(append_info.get("visible_entry_count", -1))
	if visible_entry_count_delta >= 0 and _visible_entry_count_cached >= 0:
		_visible_entry_count_cached += visible_entry_count_delta
	else:
		_visible_entry_count_cached = -1
	OnlinePerfTraceClass.end_span(span, {
		"ok": true,
		"added_item_count": int(added_items.size()),
		"visible_entry_count_delta": int(visible_entry_count_delta),
		"log_item_count": int(_log_items.size()),
	})
	return true

func _get_anchor_command_index_for_step(step_index: int) -> int:
	var idx := int(step_index)
	if idx < 0:
		return -1
	var steps_val = _step_timeline.get("steps", null)
	if not (steps_val is Array):
		return -1
	var steps: Array = steps_val
	if idx >= steps.size():
		return -1
	var step_val = steps[idx]
	if not (step_val is Dictionary):
		return -1
	return int(Dictionary(step_val).get("anchor_command_index", -1))

func _get_phase_for_step(step_index: int) -> String:
	var idx := int(step_index)
	if idx < 0:
		return _get_initial_phase_segment()
	var steps_val = _step_timeline.get("steps", null)
	if not (steps_val is Array):
		return ""
	var steps: Array = steps_val
	if idx >= steps.size():
		return ""
	var step_val = steps[idx]
	if not (step_val is Dictionary):
		return ""
	return str(Dictionary(step_val).get("phase", "")).strip_edges()

func _attach_entry_to_current_step(entry: Dictionary) -> void:
	if entry == null or entry.is_empty():
		return
	var step_idx := int(_timeline_cursor_index)
	if step_idx < -1:
		step_idx = int(_timeline_head_index)
	if int(_timeline_head_index) >= -1:
		step_idx = clampi(step_idx, -1, int(_timeline_head_index))

	var cmd_idx := _get_anchor_command_index_for_step(step_idx)
	var phase_seg := _get_phase_for_step(step_idx)

	entry["step_index"] = step_idx
	entry["command_index"] = cmd_idx
	if not phase_seg.is_empty():
		entry["phase_segment"] = phase_seg
	entry["is_stage_event"] = false
	entry["source"] = "ui"

	var details_val = entry.get("details", {})
	var details: Dictionary = details_val.duplicate(true) if (details_val is Dictionary) else {}
	details["step_index"] = step_idx
	details["command_index"] = cmd_idx
	if not phase_seg.is_empty():
		details["phase_segment"] = phase_seg
	entry["details"] = details

func _add_log_item(entry: Dictionary) -> void:
	if log_container == null:
		return

	var item = _acquire_log_item(_POOL_KIND_FLAT_ENTRY)
	if item == null:
		item = GameLogItemClass.new()
	item.set_meta("_log_pool_kind", _POOL_KIND_FLAT_ENTRY)
	item.set_meta("log_entry_id", int(entry.get("id", -1)))
	log_container.add_child(item)
	if item.has_method("configure_entry"):
		item.configure_entry(entry, int(entry.get("type", 0)))
	else:
		item.entry_data = entry
		item.log_type = entry.type
	if not item.entry_clicked.is_connected(_on_entry_clicked):
		item.entry_clicked.connect(_on_entry_clicked)
	if not item.entry_double_clicked.is_connected(_on_entry_double_clicked):
		item.entry_double_clicked.connect(_on_entry_double_clicked)
	_connect_item_hover_signals(item)
	_log_items.append(item)
	_index_log_item(item)
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)

	_request_scroll_to_bottom()

func _clear_timeline_item_indexes() -> void:
	_timeline_exact_items_by_index.clear()
	_timeline_first_item_by_index.clear()
	_timeline_phase_header_items.clear()
	_timeline_round_header_items.clear()

func _rebuild_timeline_item_indexes() -> void:
	_clear_timeline_item_indexes()
	for item_val in _log_items:
		if item_val is Control:
			_index_log_item(item_val)

func _index_log_item(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return
	var kind := str(item.get_meta("_log_pool_kind", "")).strip_edges()
	var timeline_index := -999999
	if item.has_method("get_timeline_index"):
		timeline_index = int(item.call("get_timeline_index"))
		if timeline_index >= -1 and not _timeline_first_item_by_index.has(timeline_index):
			_timeline_first_item_by_index[timeline_index] = item

	match kind:
		"phase_header":
			_timeline_phase_header_items.append(item)
		"round_header":
			_timeline_round_header_items.append(item)
		_:
			if timeline_index < -1:
				return
			var bucket_val = _timeline_exact_items_by_index.get(timeline_index, [])
			var bucket: Array = bucket_val if (bucket_val is Array) else []
			bucket.append(item)
			_timeline_exact_items_by_index[timeline_index] = bucket

func _acquire_log_item(kind: String):
	var k := str(kind).strip_edges()
	if k.is_empty():
		return null
	var pool_val = _log_item_pool.get(k, null)
	if not (pool_val is Array):
		return null
	var pool: Array = pool_val
	while not pool.is_empty():
		var item_val = pool.pop_back()
		if item_val is Control and is_instance_valid(item_val):
			_log_item_pool[k] = pool
			var item: Control = item_val
			item.visible = true
			return item
	_log_item_pool[k] = pool
	return null

func _release_log_item(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return
	var kind := str(item.get_meta("_log_pool_kind", "")).strip_edges()
	if kind.is_empty():
		kind = _POOL_KIND_FLAT_ENTRY
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	item.visible = false
	if not _log_item_pool.has(kind) or not (_log_item_pool[kind] is Array):
		_log_item_pool[kind] = []
	var pool: Array = _log_item_pool[kind]
	pool.append(item)
	_log_item_pool[kind] = pool

func _request_scroll_to_bottom() -> void:
	if not _should_keep_scroll_at_bottom():
		_scroll_to_bottom_requested = false
		return
	if _scroll_to_bottom_requested:
		return
	_scroll_to_bottom_requested = true
	call_deferred("_apply_scroll_to_bottom")

func _apply_scroll_to_bottom() -> void:
	if not _scroll_to_bottom_requested:
		return
	if not _should_keep_scroll_at_bottom():
		_scroll_to_bottom_requested = false
		return
	if scroll_container == null:
		_scroll_to_bottom_requested = false
		return
	if not is_visible_in_tree():
		return
	_scroll_scroll_container_to_bottom()
	# 某些布局/重建时序下，ScrollBar 的 max_value 会在下一帧才更新；这里补一次确保落到底部。
	call_deferred("_apply_scroll_to_bottom_final")

func _apply_scroll_to_bottom_final() -> void:
	if not _scroll_to_bottom_requested:
		return
	if not _should_keep_scroll_at_bottom():
		_scroll_to_bottom_requested = false
		return
	if scroll_container == null:
		_scroll_to_bottom_requested = false
		return
	if not is_visible_in_tree():
		return
	_scroll_scroll_container_to_bottom()
	_scroll_to_bottom_requested = false

func _clear_display() -> void:
	_clear_timeline_item_indexes()
	for item in _log_items:
		if item is Control and is_instance_valid(item):
			_release_log_item(item)
	_log_items.clear()

func _rebuild_display() -> void:
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.rebuild_display", {
		"timeline_loaded": bool(_is_step_timeline_loaded()),
		"entry_count": int(_entries_all.size()),
		"visible_in_tree": bool(is_visible_in_tree()),
	})
	_clear_display()

	if _is_step_timeline_loaded():
		_build_unified_timeline_display()
	else:
		for entry_val in _entries_all:
			if entry_val is Dictionary:
				_add_log_item(Dictionary(entry_val))

	OnlinePerfTraceClass.end_span(span, {
		"timeline_loaded": bool(_is_step_timeline_loaded()),
		"entry_count": int(_entries_all.size()),
		"child_count_after": int(log_container.get_child_count()) if log_container != null else 0,
		"log_item_count": int(_log_items.size()),
	})

func _build_unified_timeline_display() -> void:
	if log_container == null:
		return

	var span := OnlinePerfTraceClass.begin_span("ui.game_log.build_unified_timeline_display", {
		"entry_count": int(_entries_all.size()),
		"timeline_step_count": int(_get_step_count(_step_timeline)),
	})
	var build_info_val = GameLogUnifiedTimelineBuilderClass.build(
		log_container,
		_step_timeline,
		_entries_all,
		_show_phase_events,
		_fold_details_enabled,
		Callable(self, "_is_action_group_expanded"),
		_timeline_cursor_index,
		_timeline_head_index,
		Callable(self, "_on_timeline_header_clicked"),
		Callable(self, "_on_entry_clicked"),
		Callable(self, "_on_entry_double_clicked"),
		Callable(self, "_on_action_group_fold_toggled"),
		_get_initial_round_number(),
		_get_initial_phase_segment(),
		Callable(self, "_acquire_log_item")
	)
	var build_info: Dictionary = build_info_val if (build_info_val is Dictionary) else {}
	var items_val = build_info.get("items", [])
	_log_items = items_val if (items_val is Array) else []
	_visible_entry_count_cached = int(build_info.get("visible_entry_count", -1))
	for item in _log_items:
		if item is Control:
			_connect_item_hover_signals(item)
	_rebuild_timeline_item_indexes()
	OnlinePerfTraceClass.end_span(span, {
		"log_item_count": int(_log_items.size()),
		"visible_entry_count": int(_visible_entry_count_cached),
	})

func _on_timeline_header_clicked(timeline_index: int) -> void:
	timeline_seek_requested.emit(int(timeline_index))

func _on_action_group_fold_toggled(step_index: int, expanded: bool) -> void:
	if not _fold_details_enabled:
		return
	_invalidate_background_timeline_jobs()
	var idx := int(step_index)
	if idx < -1:
		return
	if expanded:
		_expanded_action_groups[idx] = true
	else:
		if _expanded_action_groups.has(idx):
			_expanded_action_groups.erase(idx)

	_rebuild_display()
	_update_entry_count()

func _update_entry_count() -> void:
	if entry_count_label == null:
		return

	var total := _entries_all.size()
	var visible := total
	if _is_step_timeline_loaded():
		if _visible_entry_count_cached >= 0:
			visible = int(_visible_entry_count_cached)
		else:
			var span := OnlinePerfTraceClass.begin_span("ui.game_log.compute_visible_entry_count", {
				"entry_count": int(_entries_all.size()),
				"timeline_step_count": int(_get_step_count(_step_timeline)),
			})
			visible = GameLogUnifiedTimelineBuilderClass.compute_visible_entry_count(
				_step_timeline,
				_entries_all,
				_show_phase_events,
				Callable(self, "_is_action_group_expanded")
			)
			_visible_entry_count_cached = int(visible)
			OnlinePerfTraceClass.end_span(span, {
				"visible_entry_count": int(visible),
			})
	entry_count_label.text = "显示 %d / %d" % [visible, total]

func _apply_timeline_state_to_items(scroll_to_cursor: bool = false) -> void:
	_apply_timeline_state_to_items_internal(true, _timeline_cursor_index, _timeline_head_index, scroll_to_cursor)

func _apply_timeline_state_delta(previous_cursor_index: int, previous_head_index: int, scroll_to_cursor: bool = false) -> void:
	_apply_timeline_state_to_items_internal(false, previous_cursor_index, previous_head_index, scroll_to_cursor)

func _apply_timeline_state_to_items_internal(
	force_full_update: bool,
	previous_cursor_index: int,
	previous_head_index: int,
	scroll_to_cursor: bool = false
) -> void:
	var old_cursor_index := int(previous_cursor_index)
	var old_head_index := int(previous_head_index)
	var new_cursor_index := int(_timeline_cursor_index)
	var new_head_index := int(_timeline_head_index)
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.apply_timeline_state", {
		"log_item_count": int(_log_items.size()),
		"scroll_to_cursor": bool(scroll_to_cursor),
		"force_full_update": bool(force_full_update),
		"old_cursor_index": int(old_cursor_index),
		"old_head_index": int(old_head_index),
		"new_cursor_index": int(new_cursor_index),
		"new_head_index": int(new_head_index),
	})
	var update_mode := "skip"
	var updated_item_count := 0
	if force_full_update or _should_force_full_timeline_state_update():
		update_mode = "full"
		updated_item_count = _apply_timeline_state_to_all_items()
	else:
		var old_future_mode := old_cursor_index < old_head_index
		var new_future_mode := new_cursor_index < new_head_index
		if old_cursor_index != new_cursor_index or old_future_mode != new_future_mode:
			update_mode = "delta"
			var dirty_range := _compute_timeline_exact_dirty_range(
				old_cursor_index,
				old_head_index,
				new_cursor_index,
				new_head_index
			)
			if bool(dirty_range.get("dirty", false)):
				updated_item_count += _apply_timeline_state_to_exact_range(
					int(dirty_range.get("start_index", 0)),
					int(dirty_range.get("end_index", -1))
				)
			updated_item_count += _apply_timeline_state_to_control_list(_timeline_phase_header_items)
			updated_item_count += _apply_timeline_state_to_control_list(_timeline_round_header_items)

	if not scroll_to_cursor:
		OnlinePerfTraceClass.end_span(span, {
			"log_item_count": int(_log_items.size()),
			"scroll_to_cursor": false,
			"update_mode": str(update_mode),
			"updated_item_count": int(updated_item_count),
		})
		return
	if OS.has_feature("headless"):
		OnlinePerfTraceClass.end_span(span, {
			"log_item_count": int(_log_items.size()),
			"scroll_to_cursor": true,
			"skipped_scroll": true,
			"reason": "headless",
			"update_mode": str(update_mode),
			"updated_item_count": int(updated_item_count),
		})
		return
	if scroll_container == null:
		OnlinePerfTraceClass.end_span(span, {
			"log_item_count": int(_log_items.size()),
			"scroll_to_cursor": true,
			"skipped_scroll": true,
			"reason": "scroll_container_missing",
			"update_mode": str(update_mode),
			"updated_item_count": int(updated_item_count),
		})
		return
	if not scroll_container.has_method("ensure_control_visible"):
		OnlinePerfTraceClass.end_span(span, {
			"log_item_count": int(_log_items.size()),
			"scroll_to_cursor": true,
			"skipped_scroll": true,
			"reason": "ensure_control_visible_missing",
			"update_mode": str(update_mode),
			"updated_item_count": int(updated_item_count),
		})
		return

	# 定位到当前 cursor 对应的第一条可见日志（过滤后可能不存在）。
	var cursor_item := _find_first_timeline_item(_timeline_cursor_index)
	if cursor_item != null and is_instance_valid(cursor_item):
		scroll_container.call("ensure_control_visible", cursor_item)
	OnlinePerfTraceClass.end_span(span, {
		"log_item_count": int(_log_items.size()),
		"scroll_to_cursor": bool(scroll_to_cursor),
		"update_mode": str(update_mode),
		"updated_item_count": int(updated_item_count),
	})

func _should_force_full_timeline_state_update() -> bool:
	if _log_items.is_empty():
		return false
	return _timeline_exact_items_by_index.is_empty() \
		and _timeline_phase_header_items.is_empty() \
		and _timeline_round_header_items.is_empty()

func _compute_timeline_exact_dirty_range(
	old_cursor_index: int,
	old_head_index: int,
	new_cursor_index: int,
	new_head_index: int
) -> Dictionary:
	var old_future_mode := int(old_cursor_index) < int(old_head_index)
	var new_future_mode := int(new_cursor_index) < int(new_head_index)
	if int(old_cursor_index) == int(new_cursor_index) and old_future_mode == new_future_mode:
		return {"dirty": false}

	var start_index := mini(int(old_cursor_index), int(new_cursor_index))
	var end_index := maxi(int(old_cursor_index), int(new_cursor_index))
	if old_future_mode != new_future_mode:
		end_index = maxi(end_index, maxi(int(old_head_index), int(new_head_index)))

	return {
		"dirty": bool(end_index >= start_index),
		"start_index": int(start_index),
		"end_index": int(end_index),
	}

func _apply_timeline_state_to_all_items() -> int:
	var updated_item_count := 0
	for item_val in _log_items:
		if item_val is Control:
			updated_item_count += _apply_timeline_state_to_item(item_val)
	return updated_item_count

func _apply_timeline_state_to_control_list(items: Array[Control]) -> int:
	var updated_item_count := 0
	for item_val in items:
		updated_item_count += _apply_timeline_state_to_item(item_val)
	return updated_item_count

func _apply_timeline_state_to_exact_range(start_index: int, end_index: int) -> int:
	if int(end_index) < int(start_index):
		return 0
	var updated_item_count := 0
	for idx in range(int(start_index), int(end_index) + 1):
		updated_item_count += _apply_timeline_state_to_exact_index(int(idx))
	return updated_item_count

func _apply_timeline_state_to_exact_index(timeline_index: int) -> int:
	var bucket_val = _timeline_exact_items_by_index.get(int(timeline_index), [])
	if not (bucket_val is Array):
		return 0
	var updated_item_count := 0
	for item_val in bucket_val:
		if item_val is Control:
			updated_item_count += _apply_timeline_state_to_item(item_val)
	return updated_item_count

func _apply_timeline_state_to_item(item: Control) -> int:
	if item == null or not is_instance_valid(item):
		return 0
	if not item.has_method("apply_timeline_state"):
		return 0
	item.apply_timeline_state(_timeline_cursor_index, _timeline_head_index)
	return 1

func _find_first_timeline_item(timeline_index: int) -> Control:
	var cached_item_val = _timeline_first_item_by_index.get(int(timeline_index), null)
	if cached_item_val is Control and is_instance_valid(cached_item_val):
		return cached_item_val
	for item_val in _log_items:
		if not (item_val is Control):
			continue
		var item: Control = item_val
		if not is_instance_valid(item):
			continue
		if not item.has_method("get_timeline_index"):
			continue
		if int(item.call("get_timeline_index")) != int(timeline_index):
			continue
		return item
	return null

func _connect_item_hover_signals(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return

	var cb_enter := Callable(self, "_on_item_mouse_entered").bind(item)
	if not item.mouse_entered.is_connected(cb_enter):
		item.mouse_entered.connect(cb_enter)
	var cb_exit := Callable(self, "_on_item_mouse_exited").bind(item)
	if not item.mouse_exited.is_connected(cb_exit):
		item.mouse_exited.connect(cb_exit)

func _on_item_mouse_entered(item: Control) -> void:
	var entry_id := _get_entry_id_from_item(item)
	if entry_id < 0:
		return
	log_entry_hovered.emit(entry_id, true)

func _on_item_mouse_exited(item: Control) -> void:
	var entry_id := _get_entry_id_from_item(item)
	if entry_id < 0:
		return
	log_entry_hovered.emit(entry_id, false)

func _get_entry_id_from_item(item: Control) -> int:
	if item == null or not is_instance_valid(item):
		return -1
	if item.has_meta("log_entry_id"):
		var v = item.get_meta("log_entry_id")
		if v is int:
			return int(v)
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				return int(f)
	return -1

func _on_show_phase_events_toggled(toggled: bool) -> void:
	_invalidate_background_timeline_jobs()
	_show_phase_events = bool(toggled)
	_rebuild_display()
	_update_entry_count()

func _on_fold_details_toggled(toggled: bool) -> void:
	set_fold_details_enabled(bool(toggled), false)

func set_fold_details_enabled(enabled: bool, update_checkbox: bool = true) -> void:
	_invalidate_background_timeline_jobs()
	var en := bool(enabled)
	if en == _fold_details_enabled:
		if update_checkbox and fold_details_check != null:
			fold_details_check.button_pressed = _fold_details_enabled
		return

	_fold_details_enabled = en
	_expanded_action_groups.clear()

	# 默认只展开当前 cursor 的动作组，避免一次性展开导致列表过长。
	if _fold_details_enabled:
		var idx := int(_timeline_cursor_index)
		if idx < -1:
			idx = -1
		if _timeline_head_index >= -1:
			idx = clampi(idx, -1, int(_timeline_head_index))
		_expanded_action_groups[idx] = true

	_prune_expanded_action_groups()

	if update_checkbox and fold_details_check != null:
		fold_details_check.button_pressed = _fold_details_enabled

	_rebuild_display()
	_update_entry_count()

func _on_auto_scroll_toggled(toggled: bool) -> void:
	_auto_scroll = toggled
	if _auto_scroll:
		_request_scroll_to_bottom()
	else:
		_scroll_to_bottom_requested = false

func set_replay_toggle_active(active: bool) -> void:
	if replay_toggle_button == null:
		return
	var v := bool(active)
	if replay_toggle_button.button_pressed != v:
		replay_toggle_button.button_pressed = v
	_sync_replay_toggle_button_state()

func set_replay_toggle_availability(
	available: bool,
	inactive_text: String = "进入回放",
	disabled_reason: String = ""
) -> void:
	_replay_toggle_available = bool(available)
	var next_inactive_text := str(inactive_text).strip_edges()
	if next_inactive_text.is_empty():
		next_inactive_text = "进入回放"
	_replay_toggle_inactive_text = next_inactive_text
	_replay_toggle_disabled_reason = str(disabled_reason).strip_edges()
	_sync_replay_toggle_button_state()

func _on_replay_toggle_toggled(toggled: bool) -> void:
	_sync_replay_toggle_button_state()
	replay_toggle_changed.emit(bool(toggled))

func _on_close_pressed() -> void:
	close_requested.emit()

func _sync_replay_toggle_button_state() -> void:
	if replay_toggle_button == null:
		return
	var pressed := bool(replay_toggle_button.button_pressed)
	var should_disable := (not _replay_toggle_available) and (not pressed)
	replay_toggle_button.disabled = should_disable
	if should_disable and not _replay_toggle_disabled_reason.is_empty():
		replay_toggle_button.tooltip_text = "不可用：%s" % _replay_toggle_disabled_reason
	else:
		replay_toggle_button.tooltip_text = ""
	replay_toggle_button.text = "退出回放" if pressed else (
		_replay_toggle_inactive_text if not _replay_toggle_available else "进入回放"
	)

func _on_entry_clicked(entry_id: int) -> void:
	log_entry_clicked.emit(entry_id)

func _on_entry_double_clicked(entry_id: int) -> void:
	_open_entry_details(entry_id)

func get_entry_by_id(entry_id: int) -> Dictionary:
	var e := _find_entry_by_id(entry_id)
	return e.duplicate(true) if not e.is_empty() else {}

func get_entry_command_index(entry_id: int) -> int:
	var e := _find_entry_by_id(entry_id)
	return GameLogEntryUtilsClass.get_entry_command_index(e) if not e.is_empty() else -999

func get_entry_timeline_index(entry_id: int) -> int:
	var e := _find_entry_by_id(entry_id)
	return GameLogEntryUtilsClass.get_entry_timeline_index(e) if not e.is_empty() else -999

func _open_entry_details(entry_id: int) -> void:
	if OS.has_feature("headless"):
		return
	var entry := _find_entry_by_id(entry_id)
	if entry.is_empty():
		return

	if _details_controller == null:
		_details_controller = GameLogDetailsWindowControllerClass.new()
	var type_name: String = LOG_TYPE_NAMES.get(int(entry.get("type", 0)), "?")
	_details_controller.open(self, entry, type_name)

func _find_entry_by_id(entry_id: int) -> Dictionary:
	for e_val in _entries_all:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if int(e.get("id", -1)) == entry_id:
			return e
	return {}
