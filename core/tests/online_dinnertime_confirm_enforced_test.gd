# Online：晚餐阶段必须由显式 rules marker 驱动玩家确认，不能隐式依赖 NetContext.mode。
class_name OnlineDinnertimeConfirmEnforcedTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var strict_guard_r := _test_auto_advance_fails_on_missing_confirm_pending(player_count, seed_val)
	if not strict_guard_r.ok:
		_reset_net_context()
		return strict_guard_r

	var strict_prepare_r := _test_prepare_resume_fails_on_missing_confirm_pending(player_count, seed_val)
	if not strict_prepare_r.ok:
		_reset_net_context()
		return strict_prepare_r

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		_reset_net_context()
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	if state == null:
		_reset_net_context()
		return Result.failure("state 为空")
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		_reset_net_context()
		return Result.failure("prepare_engine_for_online_resume 失败: %s" % prepare_r.error)
	if not (state.rules is Dictionary) or int(state.rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, 0)) != 1:
		_reset_net_context()
		return Result.failure("prepare_engine_for_online_resume 未写入晚餐确认 marker")

	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		_reset_net_context()
		return setup_r
	var restruct_r := TestPhaseUtilsClass.complete_restructuring(engine)
	if not restruct_r.ok:
		_reset_net_context()
		return restruct_r
	var oob_r := TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		_reset_net_context()
		return oob_r
	var working_r := TestPhaseUtilsClass.complete_working_phase(engine)
	if not working_r.ok:
		_reset_net_context()
		return working_r

	var after_work: GameState = engine.get_state()
	if after_work == null:
		_reset_net_context()
		return Result.failure("Working 完成后 state 为空")
	if str(after_work.phase) != DefsClass.PHASE_DINNERTIME:
		_reset_net_context()
		return Result.failure("在线模式下应停留在 Dinnertime 等待确认，实际: %s" % str(after_work.phase))

	var pending_read := _read_dinnertime_pending_list(after_work)
	if not pending_read.ok:
		_reset_net_context()
		return pending_read
	var pending: Array = pending_read.value
	var assert_pending := _assert_per_player_confirm_pending(pending, player_count)
	if not assert_pending.ok:
		_reset_net_context()
		return assert_pending

	# 两位玩家依次确认，之后应进入 Payday
	var c0 := engine.execute_command(Command.create(KIND_CONFIRM_DINNERTIME, 0, {}))
	if not c0.ok:
		_reset_net_context()
		return Result.failure("confirm_dinnertime(0) 失败: %s" % c0.error)
	if str(engine.get_state().phase) != DefsClass.PHASE_DINNERTIME:
		_reset_net_context()
		return Result.failure("confirm_dinnertime(0) 后应仍停留在 Dinnertime，实际: %s" % str(engine.get_state().phase))

	var c1 := engine.execute_command(Command.create(KIND_CONFIRM_DINNERTIME, 1, {}))
	if not c1.ok:
		_reset_net_context()
		return Result.failure("confirm_dinnertime(1) 失败: %s" % c1.error)
	if str(engine.get_state().phase) != DefsClass.PHASE_PAYDAY:
		_reset_net_context()
		return Result.failure("双方确认后应进入 Payday，实际: %s" % str(engine.get_state().phase))

	_reset_net_context()
	return Result.success()

static func _test_prepare_resume_fails_on_missing_confirm_pending(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("strict prepare 初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("strict prepare state 为空")
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("strict prepare 初始 prepare_engine_for_online_resume 失败: %s" % prepare_r.error)
	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("strict prepare complete_setup 失败: %s" % setup_r.error)
	var restruct_r := TestPhaseUtilsClass.complete_restructuring(engine)
	if not restruct_r.ok:
		return Result.failure("strict prepare complete_restructuring 失败: %s" % restruct_r.error)
	var oob_r := TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("strict prepare complete_order_of_business 失败: %s" % oob_r.error)
	var working_r := TestPhaseUtilsClass.complete_working_phase(engine)
	if not working_r.ok:
		return Result.failure("strict prepare complete_working_phase 失败: %s" % working_r.error)

	var after_work: GameState = engine.get_state()
	if after_work == null:
		return Result.failure("strict prepare Working 完成后 state 为空")
	if str(after_work.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("strict prepare 应停留在 Dinnertime，实际: %s" % str(after_work.phase))
	if not (after_work.round_state is Dictionary):
		return Result.failure("strict prepare round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = after_work.round_state
	var ppa: Dictionary = {}
	if rs.get("pending_phase_actions", null) is Dictionary:
		ppa = Dictionary(rs.get("pending_phase_actions", {})).duplicate(true)
	ppa.erase(DefsClass.PHASE_DINNERTIME)
	rs["pending_phase_actions"] = ppa

	var prepare_again: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if prepare_again.ok:
		return Result.failure("prepare_engine_for_online_resume 不应修复缺失的 Dinnertime pending 后继续")
	if str(prepare_again.error).find("pending_phase_actions[Dinnertime]") < 0:
		return Result.failure("strict prepare 错误信息应包含 pending_phase_actions[Dinnertime]，实际: %s" % prepare_again.error)
	var ppa_after_val = rs.get("pending_phase_actions", null)
	if ppa_after_val is Dictionary and Dictionary(ppa_after_val).has(DefsClass.PHASE_DINNERTIME):
		return Result.failure("strict prepare 失败时不应重建 pending_phase_actions[Dinnertime]")
	return Result.success()

static func _test_auto_advance_fails_on_missing_confirm_pending(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("strict guard 初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("strict guard state 为空")
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		return Result.failure("strict guard prepare_engine_for_online_resume 失败: %s" % prepare_r.error)
	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("strict guard complete_setup 失败: %s" % setup_r.error)
	var restruct_r := TestPhaseUtilsClass.complete_restructuring(engine)
	if not restruct_r.ok:
		return Result.failure("strict guard complete_restructuring 失败: %s" % restruct_r.error)
	var oob_r := TestPhaseUtilsClass.complete_order_of_business(engine)
	if not oob_r.ok:
		return Result.failure("strict guard complete_order_of_business 失败: %s" % oob_r.error)
	var working_r := TestPhaseUtilsClass.complete_working_phase(engine)
	if not working_r.ok:
		return Result.failure("strict guard complete_working_phase 失败: %s" % working_r.error)

	var after_work: GameState = engine.get_state()
	if after_work == null:
		return Result.failure("strict guard Working 完成后 state 为空")
	if str(after_work.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("strict guard 应停留在 Dinnertime，实际: %s" % str(after_work.phase))
	if not (after_work.round_state is Dictionary):
		return Result.failure("strict guard round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = after_work.round_state
	var confirmed_before := str(rs.get("online_dinnertime_confirmed_players", null))
	if not rs.has("online_dinnertime_confirmed_players"):
		return Result.failure("strict guard 缺少 online_dinnertime_confirmed_players")
	var ppa: Dictionary = {}
	if rs.get("pending_phase_actions", null) is Dictionary:
		ppa = Dictionary(rs.get("pending_phase_actions", {})).duplicate(true)
	ppa.erase(DefsClass.PHASE_DINNERTIME)
	rs["pending_phase_actions"] = ppa

	var auto_r: Result = AutoAdvanceClass.try_advance_one(after_work, engine.phase_manager, engine.action_registry)
	if auto_r.ok:
		return Result.failure("Dinnertime confirm pending 缺失时 auto_advance 应失败，不应修复后继续")
	if str(auto_r.error).find("pending_phase_actions[Dinnertime]") < 0:
		return Result.failure("strict guard 错误信息应包含 pending_phase_actions[Dinnertime]，实际: %s" % auto_r.error)
	if str(rs.get("online_dinnertime_confirmed_players", null)) != confirmed_before:
		return Result.failure("strict guard 失败时不应改写 online_dinnertime_confirmed_players")
	var ppa_after_val = rs.get("pending_phase_actions", null)
	if ppa_after_val is Dictionary and Dictionary(ppa_after_val).has(DefsClass.PHASE_DINNERTIME):
		return Result.failure("strict guard 失败时不应重建 pending_phase_actions[Dinnertime]")
	return Result.success()

static func _read_dinnertime_pending_list(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions 缺失或类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if not (list_val is Array):
		return Result.failure("pending_phase_actions[Dinnertime] 缺失或类型错误（期望 Array）")
	return Result.success(Array(list_val))

static func _assert_per_player_confirm_pending(list: Array, player_count: int) -> Result:
	if list.size() != player_count:
		return Result.failure("Dinnertime pending 数量错误（期望 %d，实际 %d）" % [player_count, list.size()])

	var seen := {}
	for item_val in list:
		if not (item_val is Dictionary):
			return Result.failure("Dinnertime pending 项类型错误（期望 Dictionary），实际: %s" % str(typeof(item_val)))
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			return Result.failure("Dinnertime pending.kind 错误: %s" % str(item.get("kind", null)))
		var pid_val = item.get("player_id", null)
		var pid := -1
		if pid_val is int:
			pid = int(pid_val)
		elif pid_val is float and float(pid_val) == floor(float(pid_val)):
			pid = int(pid_val)
		else:
			return Result.failure("Dinnertime pending.player_id 类型错误（期望 int/float），实际: %s" % str(typeof(pid_val)))
		if pid < 0 or pid >= player_count:
			return Result.failure("Dinnertime pending.player_id 越界: %d" % pid)
		seen[pid] = true

	for pid2 in range(player_count):
		if not seen.has(pid2):
			return Result.failure("Dinnertime pending 缺少 player_id=%d" % pid2)

	return Result.success()

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
