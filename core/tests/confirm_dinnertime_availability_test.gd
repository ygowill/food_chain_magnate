# confirm_dinnertime 可用阶段回归测试
class_name ConfirmDinnertimeAvailabilityTest
extends RefCounted

const ActionAvailabilityRegistryClass = preload("res://core/actions/action_availability_registry.gd")
const ConfirmDinnertimeActionClass = preload("res://gameplay/actions/confirm_dinnertime_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	var registry := ActionAvailabilityRegistryClass.new()
	var action := ConfirmDinnertimeActionClass.new()

	var build_r: Result = registry.build_defaults_from_executors([action])
	if not build_r.ok:
		return Result.failure("build_defaults_from_executors 失败: %s" % build_r.error)

	var compile_r: Result = registry.compile_with_validation(["confirm_dinnertime"])
	if not compile_r.ok:
		return Result.failure("compile_with_validation 失败: %s" % compile_r.error)

	if registry.is_action_available("confirm_dinnertime", DefsClass.PHASE_SETUP, ""):
		return Result.failure("confirm_dinnertime 不应在 Setup 阶段可用")

	if registry.is_action_available("confirm_dinnertime", DefsClass.PHASE_WORKING, DefsClass.SUB_PHASE_RECRUIT):
		return Result.failure("confirm_dinnertime 不应在 Working/Recurit 阶段可用")

	if not registry.is_action_available("confirm_dinnertime", DefsClass.PHASE_DINNERTIME, ""):
		return Result.failure("confirm_dinnertime 应在 Dinnertime 阶段可用")

	return Result.success({})
