# 公司结构测试（M3）
# 验证：CEO 卡槽容量限制、唯一员工约束
class_name CompanyStructureTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	# 重置 EmployeeRegistry 缓存，确保测试隔离
	EmployeeRegistryClass.reset()

	# 1) 初始化游戏
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var state := engine.get_state()

	# 2) 推进到 Working 阶段的 Recruit 子阶段
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	state = engine.get_state()
	if state.phase != "Working" or state.sub_phase != "Recruit":
		return Result.failure("应该在 Working/Recruit，实际: %s/%s" % [state.phase, state.sub_phase])

	# 3) 获取当前玩家 ID
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return Result.failure("无法获取当前玩家 ID")

	# 注意：本测试既包含“纯 validator”验证，也包含“recruit 动作集成”验证。
	# 为避免直接修改 engine.state 破坏新增的不变量（员工供应池守恒），
	# 纯 validator 部分在 state 的深拷贝上执行。
	var validator_state: GameState = state.duplicate_state()

	# === 直接测试 CompanyStructureValidator ===

	var validator = CompanyStructureValidatorClass.new()

	# 确保 CEO 卡槽足够大，避免在唯一员工测试时触发卡槽满错误
	validator_state.players[current_player_id]["company_structure"] = {"ceo_slots": 10}

	# 4) 测试唯一员工约束 - 给玩家添加 cfo 后再次校验
	validator_state.players[current_player_id]["employees"].append("cfo")

	var unique_result: Result = validator.validate(validator_state, current_player_id, {"employee_id": "cfo", "to_reserve": false})
	if unique_result.ok:
		return Result.failure("已拥有 cfo 时，validator 应该拒绝再次添加")

	if not unique_result.error.contains("唯一员工"):
		return Result.failure("错误消息应该包含'唯一员工'，实际: %s" % unique_result.error)

	# 4.1) 唯一员工在预备区也应阻止重复获取
	validator_state.players[current_player_id]["employees"] = []
	validator_state.players[current_player_id]["reserve_employees"] = ["cfo"]
	validator_state.players[current_player_id]["busy_marketers"] = []
	var unique_reserve_result: Result = validator.validate(validator_state, current_player_id, {"employee_id": "cfo", "to_reserve": false})
	if unique_reserve_result.ok:
		return Result.failure("cfo 在预备区时，validator 应该拒绝再次添加")

	# 4.2) 唯一员工在忙碌区也应阻止重复获取（营销员不占卡槽，但仍属于“拥有该员工”）
	validator_state.players[current_player_id]["reserve_employees"] = []
	validator_state.players[current_player_id]["busy_marketers"] = ["cfo"]
	var unique_busy_result: Result = validator.validate(validator_state, current_player_id, {"employee_id": "cfo", "to_reserve": false})
	if unique_busy_result.ok:
		return Result.failure("cfo 在忙碌区时，validator 应该拒绝再次添加")

	# 5) 非唯一员工应该可以重复添加
	validator_state.players[current_player_id]["employees"].append("recruiter")
	var non_unique_result: Result = validator.validate(validator_state, current_player_id, {"employee_id": "recruiter", "to_reserve": false})
	if not non_unique_result.ok:
		return Result.failure("非唯一员工应该可以重复添加: %s" % non_unique_result.error)

	# === 测试 CEO 卡槽容量 ===

	# 6) 设置 CEO 卡槽为 3，当前员工数 = 2 (cfo, recruiter)
	validator_state.players[current_player_id]["company_structure"] = {"ceo_slots": 3}
	validator_state.players[current_player_id]["employees"] = ["recruiter", "recruiter", "recruiter"]

	# 7) 尝试添加第 4 个员工（应该失败 - 公司结构卡槽已满）
	# 备注：这里选用一个非“经理卡槽提供者”的员工，避免新增经理导致总卡槽数增加而误判。
	var slot_full_result: Result = validator.validate(validator_state, current_player_id, {"employee_id": "brand_manager", "to_reserve": false})
	if slot_full_result.ok:
		return Result.failure("公司结构卡槽已满时，validator 应该拒绝添加")

	if not slot_full_result.error.contains("卡槽已满"):
		return Result.failure("错误消息应该包含'卡槽已满'，实际: %s" % slot_full_result.error)

	# 8) 减少员工数量，应该可以添加
	validator_state.players[current_player_id]["employees"] = ["recruiter", "recruiter"]
	var slot_ok_result: Result = validator.validate(validator_state, current_player_id, {"employee_id": "management_trainee", "to_reserve": false})
	if not slot_ok_result.ok:
		return Result.failure("卡槽有空位时，validator 应该允许添加: %s" % slot_ok_result.error)

	# === 测试集成到 recruit 动作 ===

	# 9) 测试正常招聘（entry-level 员工）- 使用 trainer 而不是 management_trainee
	# 使用初始化状态（只含 CEO），确保不变量与供应池一致性。
	var recruit_cmd := Command.create("recruit", current_player_id, {"employee_type": "trainer"})
	var recruit_result := engine.execute_command(recruit_cmd)
	if not recruit_result.ok:
		return Result.failure("应该可以招聘 trainer: %s" % recruit_result.error)

	# 10) 验证员工已添加到预备区
	state = engine.get_state()
	assert(state.players[current_player_id].has("reserve_employees"), "player.reserve_employees 缺失")
	var reserve: Array = state.players[current_player_id]["reserve_employees"]
	if not reserve.has("trainer"):
		return Result.failure("招聘后 trainer 应该在预备区")

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"unique_constraint_tested": true,
		"ceo_slots_tested": true,
		"recruit_integration_tested": true
	})
