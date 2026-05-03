class_name OnlineLiveCommandLogPerfTest
extends Control

const GameLogPanelScene: PackedScene = preload("res://ui/components/game_log/game_log_panel.tscn")
const PREFIX := "[OnlineLiveCommandLogPerf]"
const DEFAULT_HISTORY_SIZES: Array[int] = [200, 500, 1000]

static func run(tree: SceneTree, history_sizes: Array[int] = DEFAULT_HISTORY_SIZES) -> Result:
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if GameLogPanelScene == null:
		return Result.failure("GameLogPanelScene preload 失败")

	var rows: Array[Dictionary] = []
	for history_size in history_sizes:
		var case_r: Result = await _run_case(tree, int(history_size))
		if not case_r.ok:
			return case_r
		if case_r.value is Dictionary:
			rows.append(case_r.value)

	return Result.success({
		"cases": rows,
	})

func _ready() -> void:
	if not _should_autorun():
		return
	await get_tree().process_frame
	print("%s START sizes=%s" % [PREFIX, str(DEFAULT_HISTORY_SIZES)])
	var result: Result = await run(get_tree(), DEFAULT_HISTORY_SIZES)
	if result.ok:
		print("%s PASS %s" % [PREFIX, JSON.stringify(result.value)])
		get_tree().quit(0)
		return
	push_error("%s FAIL %s" % [PREFIX, str(result.error)])
	print("%s FAIL %s" % [PREFIX, str(result.error)])
	get_tree().quit(1)

static func _run_case(tree: SceneTree, history_size: int) -> Result:
	var panel = GameLogPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("perf case %d: GameLogPanel 实例化失败" % history_size)
	tree.root.add_child(panel)
	await tree.process_frame

	var log_container = panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/LogContainer")
	if log_container == null or not is_instance_valid(log_container):
		return await _finish_with_panel(Result.failure("perf case %d: 未找到 LogContainer" % history_size), panel, tree)

	var timeline := _build_linear_timeline(history_size)
	var entries := _build_linear_entries(history_size)
	var load_start_usec := Time.get_ticks_usec()
	panel.call("load_step_timeline", timeline, entries)
	var loaded := await _wait_until(func() -> bool:
		var current_entries = panel.call("get_step_timeline_entries")
		return current_entries is Array \
			and current_entries.size() == history_size \
			and not bool(panel.call("has_pending_descriptor_commit"))
	, tree, 900)
	var load_ms := _elapsed_ms(load_start_usec)
	if not loaded:
		return await _finish_with_panel(Result.failure("perf case %d: 初始 history 加载超时" % history_size), panel, tree)

	var next_timeline := _build_linear_timeline(history_size + 1)
	var next_entries := _build_linear_entries(history_size + 1)
	var append_start_usec := Time.get_ticks_usec()
	panel.call("load_step_timeline", next_timeline, next_entries)
	var appended := await _wait_until(func() -> bool:
		var current_entries = panel.call("get_step_timeline_entries")
		var update_mode := str(panel.call("get_last_step_timeline_update_mode"))
		return current_entries is Array \
			and current_entries.size() == history_size + 1 \
			and not bool(panel.call("has_pending_descriptor_commit")) \
			and _is_append_update_mode(update_mode)
	, tree, 240)
	var append_ms := _elapsed_ms(append_start_usec)
	if not appended:
		return await _finish_with_panel(Result.failure("perf case %d: 追加 1 条 command 未走 append/append_window/append_virtual" % history_size), panel, tree)

	var display_window = panel.call("get_step_timeline_display_window")
	var display_window_dict: Dictionary = display_window if (display_window is Dictionary) else {}
	var row := {
		"history_size": int(history_size),
		"loaded_entries": int(history_size),
		"appended_entries": 1,
		"load_ms": load_ms,
		"append_ms": append_ms,
		"log_control_count": int(log_container.get_child_count()),
		"update_mode": str(panel.call("get_last_step_timeline_update_mode")),
		"display_window": display_window_dict,
	}
	if (str(row.get("update_mode", "")) == "append_window" or str(row.get("update_mode", "")) == "append_virtual") and int(row.get("log_control_count", 0)) > 320:
		return await _finish_with_panel(Result.failure("perf case %d: %s 后 Control 数量过高: %d" % [history_size, str(row.get("update_mode", "")), int(row.get("log_control_count", 0))]), panel, tree)
	print("%s CASE %s" % [PREFIX, JSON.stringify(row)])
	return await _finish_with_panel(Result.success(row), panel, tree)

static func _build_linear_timeline(step_count: int) -> Dictionary:
	var steps: Array[Dictionary] = []
	for idx in range(step_count):
		steps.append({
			"round": 1 + int(idx / 20),
			"phase": "Working",
			"kind": "command",
			"action_id": "recruit" if idx % 2 == 0 else "train",
			"action_display_name": "招募" if idx % 2 == 0 else "培训",
			"actor": 0,
			"anchor_command_index": idx,
		})
	return {
		"initial_state_dict": {
			"round_number": 0,
			"phase": "Setup",
		},
		"_build_meta": {
			"processed_command_count": int(step_count),
			"last_event_sequence": int(step_count),
		},
		"steps": steps,
		"events": [],
	}

static func _build_linear_entries(step_count: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for idx in range(step_count):
		entries.append({
			"type": 2,
			"message": "玩家1: %s %d" % [("招募" if idx % 2 == 0 else "培训"), idx],
			"details": {"command_index": idx},
			"step_index": idx,
			"command_index": idx,
			"event_seq": idx + 1,
		})
	return entries

static func _wait_until(predicate: Callable, tree: SceneTree, max_frames: int) -> bool:
	for _i in range(maxi(1, int(max_frames))):
		if predicate.is_valid() and bool(predicate.call()):
			return true
		await tree.process_frame
	return predicate.is_valid() and bool(predicate.call())

static func _elapsed_ms(start_usec: int) -> float:
	return float(maxi(0, Time.get_ticks_usec() - int(start_usec))) / 1000.0

static func _is_append_update_mode(mode: String) -> bool:
	var m := str(mode).strip_edges()
	return m == "append" or m == "append_window" or m == "append_virtual"

static func _finish_with_panel(result: Result, panel: Node, tree: SceneTree) -> Result:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
		await tree.process_frame
	return result

func _should_autorun() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var args := OS.get_cmdline_user_args()
	return args.has("autorun") or args.has("--autorun")
