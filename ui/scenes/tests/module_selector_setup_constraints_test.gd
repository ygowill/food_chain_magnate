# Setup/RoomConfig 约束：模块选择器应从 module.json 的 setup_constraints 推导强制模块，避免 core UI 写死 module_id。
class_name ModuleSelectorSetupConstraintsTest
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleSelectorClass = preload("res://ui/components/module_selector/module_selector.gd")

static func run(seed_val: int = 12345) -> Result:
	var selector = ModuleSelectorClass.new()

	if selector.has_method("set_setup_player_count"):
		selector.call("set_setup_player_count", 6)

	var base_dir := str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	var load_r: Result = selector.set_modules_base_dir(base_dir)
	if not load_r.ok:
		return Result.failure("ModuleSelector 加载模块列表失败: %s" % load_r.error)

	selector.set_initial_enabled_modules_v2(GameDefaultsClass.build_default_enabled_modules_v2())

	if selector.has_method("set_setup_player_count"):
		selector.call("set_setup_player_count", 6)

	var required: Dictionary = {}
	if selector.has_method("get_required_optional_modules_for_player_count"):
		var req_val = selector.call("get_required_optional_modules_for_player_count", 6)
		if req_val is Dictionary:
			required = req_val

	if required.is_empty():
		return Result.failure("6 人局未配置必需模块（setup_constraints）")

	var enabled: Array[String] = selector.get_enabled_modules_v2()
	for mid_val in required.keys():
		var mid := str(mid_val).strip_edges()
		if mid.is_empty():
			continue
		if not enabled.has(mid):
			return Result.failure("ModuleSelector 未启用必需模块: %s" % mid)

	var engine := GameEngine.new()
	var init := engine.initialize(6, seed_val, enabled)
	if not init.ok:
		return Result.failure("6 人局用 ModuleSelector 生成的模块列表初始化失败: %s" % init.error)

	return Result.success({
		"required_modules": required.keys().size(),
	})
