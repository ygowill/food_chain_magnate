# GameEngine：动作注册（内建 actions）
# 负责：构建 ActionRegistry 并注册所有内建 ActionExecutor。
extends RefCounted

const PROVIDER_PATH_SETTING = "fcm/action_setup_provider_path"
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

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

static func _resolve_provider(provider_override = null) -> Result:
	if provider_override != null:
		if provider_override is String:
			var injected_path := str(provider_override).strip_edges()
			if injected_path.is_empty():
				return Result.failure("ActionSetup: 注入的动作注册 provider path 为空")
			var injected_provider = load(injected_path)
			if injected_provider == null:
				return Result.failure("ActionSetup: 缺少注入的动作注册 provider: %s" % injected_path)
			if not injected_provider.has_method("build_registry"):
				return Result.failure("ActionSetup: 注入的动作注册 provider 缺少 build_registry: %s" % injected_path)
			return Result.success(injected_provider)
		if provider_override.has_method("build_registry"):
			return Result.success(provider_override)
		return Result.failure("ActionSetup: 注入的动作注册 provider 类型错误（缺少 build_registry）")

	var provider_path := _resolve_provider_path()
	if provider_path.is_empty():
		return Result.failure("ActionSetup: 未配置动作注册 provider（override 或 ProjectSettings.%s）" % PROVIDER_PATH_SETTING)
	var provider = load(provider_path)
	if provider == null:
		return Result.failure("ActionSetup: 缺少动作注册 provider: %s" % provider_path)
	if provider.has_method("build_registry"):
		return Result.success(provider)
	return Result.failure("ActionSetup: 动作注册 provider 缺少 build_registry: %s" % provider_path)

static func build_registry(phase_manager: PhaseManager, piece_registry: Dictionary = {}, provider_override = null) -> Result:
	assert(phase_manager != null, "phase_manager 不能为空")

	var provider_r := _resolve_provider(provider_override)
	if not provider_r.ok:
		AutoloadAccessClass.log_error("ActionSetup", str(provider_r.error))
		return provider_r
	var provider = provider_r.value
	var registry_val = provider.build_registry(phase_manager, piece_registry)
	if not (registry_val is ActionRegistry):
		return Result.failure("ActionSetup: 动作注册 provider.build_registry 必须返回 ActionRegistry")
	return Result.success(registry_val)
