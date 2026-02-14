# Setup/RoomConfig 约束：模块选择器应从 module.json 的 setup_constraints 推导强制模块，避免 core UI 写死 module_id。
class_name ModuleSelectorSetupConstraintsTest
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleSelectorClass = preload("res://ui/components/module_selector/module_selector.gd")

static func run(seed_val: int = 12345) -> Result:
	var selector = ModuleSelectorClass.new()
	var selector2 = null
	var engine = null
	var engine2 = null

	if selector.has_method("set_setup_player_count"):
		selector.call("set_setup_player_count", 6)

	var base_dir := str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	var load_r: Result = selector.set_modules_base_dir(base_dir)
	if not load_r.ok:
		return _finish(Result.failure("ModuleSelector 加载模块列表失败: %s" % load_r.error), selector, selector2, engine, engine2)

	selector.set_initial_enabled_modules_v2(GameDefaultsClass.build_default_enabled_modules_v2())

	if selector.has_method("set_setup_player_count"):
		selector.call("set_setup_player_count", 6)

	var required: Dictionary = {}
	if selector.has_method("get_required_optional_modules_for_player_count"):
		var req_val = selector.call("get_required_optional_modules_for_player_count", 6)
		if req_val is Dictionary:
			required = req_val

	if required.is_empty():
		return _finish(Result.failure("6 人局未配置必需模块（setup_constraints）"), selector, selector2, engine, engine2)

	var enabled: Array[String] = selector.get_enabled_modules_v2()
	for mid_val in required.keys():
		var mid := str(mid_val).strip_edges()
		if mid.is_empty():
			continue
		if not enabled.has(mid):
			return _finish(Result.failure("ModuleSelector 未启用必需模块: %s" % mid), selector, selector2, engine, engine2)

	engine = GameEngine.new()
	var init: Result = engine.initialize(6, seed_val, enabled)
	if not init.ok:
		return _finish(Result.failure("6 人局用 ModuleSelector 生成的模块列表初始化失败: %s" % init.error), selector, selector2, engine, engine2)

	# 规则书：5/6 人局启用 Lobbyists 时需要使用扩展的新地图板块（New Districts）。
	selector2 = ModuleSelectorClass.new()
	if selector2.has_method("set_setup_player_count"):
		selector2.call("set_setup_player_count", 5)

	var base_dir2 := str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR)
	var load_r2: Result = selector2.set_modules_base_dir(base_dir2)
	if not load_r2.ok:
		return _finish(Result.failure("ModuleSelector(5p) 加载模块列表失败: %s" % load_r2.error), selector, selector2, engine, engine2)

	var enabled2_init: Array[String] = GameDefaultsClass.build_default_enabled_modules_v2()
	enabled2_init.append("lobbyists")
	selector2.set_initial_enabled_modules_v2(enabled2_init)

	if selector2.has_method("set_setup_player_count"):
		selector2.call("set_setup_player_count", 5)

	var required2: Dictionary = {}
	if selector2.has_method("get_required_optional_modules_for_player_count"):
		var req_val2 = selector2.call("get_required_optional_modules_for_player_count", 5)
		if req_val2 is Dictionary:
			required2 = req_val2
	if not required2.has("new_districts"):
		return _finish(Result.failure("5 人局启用 Lobbyists 时未强制启用 New Districts（setup_constraints.requires_optional_modules）"), selector, selector2, engine, engine2)

	var enabled2: Array[String] = selector2.get_enabled_modules_v2()
	if not enabled2.has("new_districts"):
		return _finish(Result.failure("5 人局启用 Lobbyists 时 ModuleSelector 未启用 New Districts"), selector, selector2, engine, engine2)

	engine2 = GameEngine.new()
	var init2: Result = engine2.initialize(5, seed_val, enabled2)
	if not init2.ok:
		return _finish(Result.failure("5 人局（Lobbyists+NewDistricts）初始化失败: %s" % init2.error), selector, selector2, engine, engine2)

	return _finish(Result.success({
		"required_modules_6p": required.keys().size(),
		"required_modules_5p_lobbyists": required2.keys().size(),
	}), selector, selector2, engine, engine2)

static func _finish(result: Result, selector, selector2, engine, engine2) -> Result:
	_safe_dispose_engine(engine)
	_safe_dispose_engine(engine2)
	_safe_free_node(selector)
	_safe_free_node(selector2)
	return result

static func _safe_dispose_engine(engine) -> void:
	if engine == null:
		return
	if engine.has_method("dispose"):
		engine.dispose()

static func _safe_free_node(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
