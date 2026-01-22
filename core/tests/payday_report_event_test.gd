# Payday report event test
# 目的：确保离开 Payday 时会发射 PAYDAY_REPORT（用于日志显示/回放恢复）。
class_name PaydayReportEventTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	if EventBus == null:
		return Result.failure("EventBus is not available")

	_clear_event_history()

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine, "Payday", 200)
	if not to_payday.ok:
		return to_payday

	var before_count := EventBus.get_history_by_type(EventBus.EventType.PAYDAY_REPORT).size()

	# 让测试局面具备足够现金，避免 PaydaySettlement 因缺钱导致无法离开 Payday。
	# 用 bank overdraft（broke_count>=2）允许从银行转出任意金额，但仍保持现金守恒不变量成立。
	var state := engine.get_state()
	if state.bank is Dictionary:
		state.bank["broke_count"] = maxi(2, int(state.bank.get("broke_count", 0)))
	for pid in range(player_count):
		var give := StateUpdaterClass.player_receive_from_bank(state, pid, 1000)
		if not give.ok:
			return Result.failure("为玩家 %d 注入现金失败: %s" % [pid, give.error])

	# 通过“全员确认结束(skip)”离开 Payday（模拟真实流程）。
	var phase_before := str(engine.get_state().phase)
	for _i in range(player_count + 2):
		if str(engine.get_state().phase) != phase_before:
			break
		var actor := engine.get_state().get_current_player_id()
		var sk := engine.execute_command(Command.create("skip", actor))
		if not sk.ok:
			return Result.failure("离开 Payday 失败（skip）: %s" % sk.error)

	if str(engine.get_state().phase) == phase_before:
		return Result.failure("离开 Payday 失败：阶段未变化")

	var events: Array = EventBus.get_history_by_type(EventBus.EventType.PAYDAY_REPORT)
	if events.size() != before_count + 1:
		return Result.failure("应新增 1 条 PAYDAY_REPORT 事件，实际新增: %d" % (events.size() - before_count))

	var last_val = events[events.size() - 1]
	if not (last_val is Dictionary):
		return Result.failure("PAYDAY_REPORT 事件格式错误")
	var last: Dictionary = last_val
	var data_val = last.get("data", null)
	if not (data_val is Dictionary):
		return Result.failure("PAYDAY_REPORT.data 格式错误")
	var data: Dictionary = data_val

	var report_val = data.get("report", null)
	if not (report_val is Dictionary):
		return Result.failure("PAYDAY_REPORT.report 缺失或类型错误")
	var report: Dictionary = report_val

	var details_val = report.get("details", null)
	if not (details_val is Array):
		return Result.failure("PAYDAY_REPORT.report.details 缺失或类型错误")
	var details: Array = details_val
	if details.size() != player_count:
		return Result.failure("PAYDAY_REPORT.report.details 长度错误: %d（期望 %d）" % [details.size(), player_count])

	# 避免污染后续测试
	_clear_event_history()

	return Result.success({})

static func _clear_event_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

