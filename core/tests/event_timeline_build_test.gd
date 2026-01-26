# 完整事件时间线构建测试
# - build_full() 应返回非空事件数组
# - 每条事件应包含 command_index，且单调不减
# - 应覆盖所有命令索引（0..last）
class_name EventTimelineBuildTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const EventTimelineBuildClass = preload("res://gameplay/replay/event_timeline_build.gd")

static func run(player_count: int = 2, seed_val: int = 12345, min_commands: int = 20) -> Result:
	if EventBus != null:
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		else:
			EventBus.clear_history()

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 让用例生成一段可重放的命令历史（含 Setup/放置餐厅等），再补一些 end_turn。
	var setup := TestPhaseUtilsClass.complete_setup(engine)
	if not setup.ok:
		return Result.failure("complete_setup 失败: %s" % setup.error)

	var safety := 0
	while engine.command_history.size() < min_commands:
		safety += 1
		if safety > min_commands * 3:
			return Result.failure("生成命令超出安全上限: %d" % safety)
		var pid := engine.get_state().get_current_player_id()
		var r := engine.execute_command(Command.create("end_turn", pid))
		if not r.ok:
			return Result.failure("end_turn 失败: %s" % r.error)

	var last_index := engine.command_history.size() - 1
	if last_index < 0:
		return Result.failure("命令数量不足: %d" % engine.command_history.size())

	var build_r: Result = EventTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full 失败: %s" % build_r.error)

	var events_val = build_r.value
	if not (events_val is Array):
		return Result.failure("build_full.value 类型错误（期望 Array）")
	var events: Array = events_val
	if events.is_empty():
		return Result.failure("build_full 事件为空")

	var prev_ci := -999999
	var seen := {}
	var has_game_started := false

	for ev_val in events:
		if not (ev_val is Dictionary):
			return Result.failure("事件类型错误（期望 Dictionary）: %s" % str(ev_val))
		var ev: Dictionary = ev_val
		if not ev.has("command_index"):
			return Result.failure("事件缺少 command_index: %s" % str(ev))
		var ci := int(ev.get("command_index", -999999))
		if ci < prev_ci:
			return Result.failure("command_index 非单调不减: prev=%d cur=%d" % [prev_ci, ci])
		prev_ci = ci

		var t := str(ev.get("type", "")).strip_edges()
		if t == EventBus.EventType.GAME_STARTED and ci == -1:
			has_game_started = true

		if ci >= 0:
			seen[ci] = true

			# 命令事件应把 command_index 写入 data（便于 UI 读取/筛选）
			var d_val = ev.get("data", null)
			if not (d_val is Dictionary):
				return Result.failure("事件 data 类型错误（期望 Dictionary）: %s" % str(ev))
			var d: Dictionary = d_val
			if int(d.get("command_index", -999999)) != ci:
				return Result.failure("事件 data.command_index 不一致: ci=%d data=%s" % [ci, str(d.get("command_index", null))])

	if not has_game_started:
		return Result.failure("缺少 GAME_STARTED 初始化事件（command_index=-1）")

	# 应覆盖每个命令索引（0..last_index）
	for i in range(last_index + 1):
		if not seen.has(i):
			return Result.failure("缺少命令索引对应事件: %d (last=%d)" % [i, last_index])

	return Result.success({
		"commands": last_index + 1,
		"events": events.size(),
	})
