extends RefCounted

# 手工复核存档（员工/里程碑）场景清单
#
# 约定：
# - 每个员工/里程碑至少 1 个 case；每个 case 会生成同名 JSON+MD。
# - steps/expected 允许偏“操作指引”，详细测试点请对照 `docs/plans/manual_test_saves_plan.md`。
#
# 说明：原先单文件过长，现将清单按主题拆分到 tools/manual_test_saves/*.gd 中；
# 该文件仅做聚合，保持对外接口 `get_cases()` 不变。

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

const ExamplesManifest = preload("res://tools/manual_test_saves/manifest_examples.gd")
const MilestonesManifest = preload("res://tools/manual_test_saves/manifest_milestones.gd")
const EmployeesManifest = preload("res://tools/manual_test_saves/manifest_employees.gd")
const LogsManifest = preload("res://tools/manual_test_saves/manifest_logs.gd")
const MarketingManifest = preload("res://tools/manual_test_saves/manifest_marketing.gd")

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	cases.append_array(ExamplesManifest.get_cases())
	cases.append_array(MilestonesManifest.get_cases())
	cases.append_array(EmployeesManifest.get_cases())
	cases.append_array(LogsManifest.get_cases())
	cases.append_array(MarketingManifest.get_cases())
	return cases
