# GameEngine：动作注册（内建 actions）
# 负责：构建 ActionRegistry 并注册所有内建 ActionExecutor。
extends RefCounted

const PROVIDER_PATH_SETTING = "fcm/action_setup_provider_path"

static var provider_path_override: String = ""

static func set_provider_path(path: String) -> void:
	provider_path_override = str(path).strip_edges()

static func _resolve_provider_path() -> String:
	if not provider_path_override.is_empty():
		return provider_path_override
	if not ProjectSettings.has_setting(PROVIDER_PATH_SETTING):
		return ""
	var v = ProjectSettings.get_setting(PROVIDER_PATH_SETTING)
	if not (v is String):
		return ""
	var p := str(v).strip_edges()
	return p

static func build_registry(phase_manager: PhaseManager, piece_registry: Dictionary = {}) -> ActionRegistry:
	assert(phase_manager != null, "phase_manager 不能为空")

	var provider_path := _resolve_provider_path()
	if provider_path.is_empty():
		GameLog.error("ActionSetup", "未配置动作注册 provider（override 或 ProjectSettings.%s）" % PROVIDER_PATH_SETTING)
		return ActionRegistry.new()
	var provider = load(provider_path)
	if provider == null:
		GameLog.error("ActionSetup", "缺少动作注册 provider: %s" % provider_path)
		return ActionRegistry.new()
	if provider.has_method("build_registry"):
		return provider.build_registry(phase_manager, piece_registry)
	GameLog.error("ActionSetup", "动作注册 provider 缺少 build_registry: %s" % provider_path)
	return ActionRegistry.new()
