# 模块系统 V2：SettlementRegistry + init fail-fast + PhaseManager 调用注册表
class_name SettlementRegistryV2Test
extends RefCounted

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var missing := _test_missing_required_settlements_fail(player_count, seed_val)
	if not missing.ok:
		return missing

	var called := _test_settlements_called_through_registry(player_count, seed_val)
	if not called.ok:
		return called

	var dup := _test_duplicate_primary_fails(player_count, seed_val)
	if not dup.ok:
		return dup

	return Result.success()

static func _test_missing_required_settlements_fail(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(
		player_count,
		seed_val,
		["alpha"],  # v2 modules（无结算注册，应 fail-fast）
		"res://core/tests/fixtures/modules_v2_valid"
	)
	if init.ok:
		return Result.failure("启用 V2 模块但缺少必需 primary settlements 时应初始化失败")
	if init.error.find("缺少必需结算器") == -1:
		return Result.failure("错误信息应包含“缺少必需结算器”，实际: %s" % init.error)
	return Result.success()

static func _test_settlements_called_through_registry(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(
		player_count,
		seed_val,
		["probe_rules"],
		"res://core/tests/fixtures/modules_v2_rules_probe"
	)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var pm = engine.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")

	# Setup -> Restructuring -> OrderOfBusiness -> Working -> Dinnertime（触发 dinnertime_enter）
	for _i in range(4):
		var step: Result = pm.advance_phase(state)
		if not step.ok:
			return Result.failure("推进阶段失败: %s" % step.error)
	if state.phase != "Dinnertime":
		return Result.failure("期望进入 Dinnertime，实际: %s" % state.phase)
	if not (state.rules is Dictionary) or not state.rules.has("probe_dinnertime_enter") or not (state.rules["probe_dinnertime_enter"] is int) or int(state.rules["probe_dinnertime_enter"]) != 1:
		return Result.failure("Dinnertime enter settlement 未被调用或计数错误: %s" % str(state.rules.get("probe_dinnertime_enter", null)))

	# Dinnertime -> Payday（不触发 probe）
	var to_payday: Result = pm.advance_phase(state)
	if not to_payday.ok:
		return Result.failure("推进到 Payday 失败: %s" % to_payday.error)
	if state.phase != "Payday":
		return Result.failure("期望进入 Payday，实际: %s" % state.phase)

	# Payday -> Marketing（触发 payday_exit + marketing_enter）
	var to_marketing: Result = pm.advance_phase(state)
	if not to_marketing.ok:
		return Result.failure("推进到 Marketing 失败: %s" % to_marketing.error)
	if state.phase != "Marketing":
		return Result.failure("期望进入 Marketing，实际: %s" % state.phase)
	if not state.rules.has("probe_payday_exit") or not (state.rules["probe_payday_exit"] is int) or int(state.rules["probe_payday_exit"]) != 1:
		return Result.failure("Payday exit settlement 未被调用或计数错误: %s" % str(state.rules.get("probe_payday_exit", null)))
	if not state.rules.has("probe_marketing_enter") or not (state.rules["probe_marketing_enter"] is int) or int(state.rules["probe_marketing_enter"]) != 1:
		return Result.failure("Marketing enter settlement 未被调用或计数错误: %s" % str(state.rules.get("probe_marketing_enter", null)))

	# Marketing -> Cleanup（触发 cleanup_enter）
	var to_cleanup: Result = pm.advance_phase(state)
	if not to_cleanup.ok:
		return Result.failure("推进到 Cleanup 失败: %s" % to_cleanup.error)
	if state.phase != "Cleanup":
		return Result.failure("期望进入 Cleanup，实际: %s" % state.phase)
	if not state.rules.has("probe_cleanup_enter") or not (state.rules["probe_cleanup_enter"] is int) or int(state.rules["probe_cleanup_enter"]) != 1:
		return Result.failure("Cleanup enter settlement 未被调用或计数错误: %s" % str(state.rules.get("probe_cleanup_enter", null)))

	return Result.success()

static func _test_duplicate_primary_fails(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(
		player_count,
		seed_val,
		["a", "b"],
		"res://core/tests/fixtures/modules_v2_rules_duplicate_primary"
	)
	if init.ok:
		return Result.failure("重复 primary settlement 注册应导致初始化失败")
	if init.error.find("重复注册") == -1:
		return Result.failure("错误信息应包含“重复注册”，实际: %s" % init.error)
	return Result.success()
