class_name PhaseActionUiModalRegistrationTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	])
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	if engine.ruleset_v2 == null or not engine.ruleset_v2.has_method("get_phase_action_ui_modal_scene_path"):
		return Result.failure("ruleset_v2 缺少 phase action UI modal 查询接口")

	var path: String = str(engine.ruleset_v2.get_phase_action_ui_modal_scene_path(DefsClass.PHASE_CLEANUP, "kimchi")).strip_edges()
	if path.is_empty():
		return Result.failure("kimchi phase action UI modal 未注册")

	var res = load(path)
	if not (res is PackedScene):
		return Result.failure("phase action UI modal 类型错误（期望 PackedScene）: %s" % path)

	var inst = (res as PackedScene).instantiate()
	if inst == null or not is_instance_valid(inst):
		return Result.failure("phase action UI modal 无法实例化: %s" % path)

	if not inst.has_method("setup"):
		inst.queue_free()
		return Result.failure("phase action UI modal 缺少 setup(state, current_player_id): %s" % path)
	if not inst.has_signal("completed"):
		inst.queue_free()
		return Result.failure("phase action UI modal 缺少 completed 信号: %s" % path)

	inst.queue_free()
	return Result.success({"path": path})

