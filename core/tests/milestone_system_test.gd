# 里程碑系统测试（M5 起步）
# 覆盖：同回合多名可获得（Cleanup 统一移除供给）+ 若干关键触发点（Train/LowerPrice/Produce/DemandMarked）
class_name MilestoneSystemTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

const TriggersTestClass = preload("res://core/tests/milestone_system/milestone_system_triggers_test.gd")
const TrainRulesTestClass = preload("res://core/tests/milestone_system/milestone_system_train_rules_test.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	EmployeeRegistryClass.reset()
	MilestoneRegistryClass.reset()

	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1: Result = TriggersTestClass.run(seed_val)
	if not r1.ok:
		return r1

	var r2: Result = TrainRulesTestClass.run(seed_val)
	if not r2.ok:
		return r2

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"cases": 16,
	})
