# GameEngine：动作注册（内建 actions）
# 负责：构建 ActionRegistry 并注册所有内建 ActionExecutor。
extends RefCounted

const DEFAULT_PROVIDER_PATH = "res://gameplay/action_setup.gd"

static func build_registry(phase_manager: PhaseManager, piece_registry: Dictionary = {}) -> ActionRegistry:
	assert(phase_manager != null, "phase_manager 不能为空")

	var provider = load(DEFAULT_PROVIDER_PATH)
	if provider == null:
		GameLog.error("ActionSetup", "缺少动作注册 provider: %s" % DEFAULT_PROVIDER_PATH)
		return ActionRegistry.new()
	if provider.has_method("build_registry"):
		return provider.build_registry(phase_manager, piece_registry)
	GameLog.error("ActionSetup", "动作注册 provider 缺少 build_registry: %s" % DEFAULT_PROVIDER_PATH)
	return ActionRegistry.new()
