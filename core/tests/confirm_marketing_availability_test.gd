# confirm_marketing 可用阶段回归测试
class_name ConfirmMarketingAvailabilityTest
extends RefCounted

const ActionAvailabilityRegistryClass = preload("res://core/actions/action_availability_registry.gd")
const ConfirmMarketingActionClass = preload("res://gameplay/actions/confirm_marketing_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	var registry := ActionAvailabilityRegistryClass.new()
	var action := ConfirmMarketingActionClass.new()

	var build_r: Result = registry.build_defaults_from_executors([action])
	if not build_r.ok:
		return Result.failure("build_defaults_from_executors 失败: %s" % build_r.error)

	var compile_r: Result = registry.compile_with_validation(["confirm_marketing"])
	if not compile_r.ok:
		return Result.failure("compile_with_validation 失败: %s" % compile_r.error)

	if registry.is_action_available("confirm_marketing", DefsClass.PHASE_SETUP, ""):
		return Result.failure("confirm_marketing 不应在 Setup 阶段可用")

	if registry.is_action_available("confirm_marketing", DefsClass.PHASE_WORKING, DefsClass.SUB_PHASE_RECRUIT):
		return Result.failure("confirm_marketing 不应在 Working/Recruit 阶段可用")

	if not registry.is_action_available("confirm_marketing", DefsClass.PHASE_MARKETING, ""):
		return Result.failure("confirm_marketing 应在 Marketing 阶段可用")

	return Result.success({})
