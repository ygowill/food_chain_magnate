class_name PhaseActionUiModalRegistrationTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ModuleUiMetadataClass = preload("res://gameplay/module_ui_metadata.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")

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
	var ui_metadata_apply := ModuleUiMetadataBootstrapClass.apply(engine)
	if not ui_metadata_apply.ok:
		return Result.failure("UI metadata 装配失败: %s" % ui_metadata_apply.error)

	if not ModuleUiMetadataClass.is_loaded():
		return Result.failure("ModuleUiMetadata 未加载")

	var path: String = str(ModuleUiMetadataClass.get_phase_action_ui_modal_scene_path(DefsClass.PHASE_CLEANUP, "kimchi")).strip_edges()
	if path.is_empty():
		return Result.failure("kimchi phase action UI modal 未注册")

	var base_path: String = str(ModuleUiMetadataClass.get_phase_action_ui_modal_scene_path(DefsClass.PHASE_CLEANUP, "fridge_keep")).strip_edges()
	if base_path.is_empty():
		return Result.failure("fridge_keep phase action UI modal 未注册")

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

	var base_res = load(base_path)
	if not (base_res is PackedScene):
		return Result.failure("base phase action UI modal 类型错误（期望 PackedScene）: %s" % base_path)

	var base_inst = (base_res as PackedScene).instantiate()
	if base_inst == null or not is_instance_valid(base_inst):
		return Result.failure("base phase action UI modal 无法实例化: %s" % base_path)

	if not base_inst.has_method("setup"):
		base_inst.queue_free()
		return Result.failure("base phase action UI modal 缺少 setup(state, current_player_id): %s" % base_path)
	if not base_inst.has_signal("completed"):
		base_inst.queue_free()
		return Result.failure("base phase action UI modal 缺少 completed 信号: %s" % base_path)

	base_inst.queue_free()
	return Result.success({"path": path, "base_path": base_path})
