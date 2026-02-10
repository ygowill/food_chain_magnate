class_name KimchiStorageModalUiTest
extends RefCounted

const ModalScene: PackedScene = preload("res://modules/kimchi/ui/components/modal_panel/kimchi_storage_modal.tscn")

static func run(seed_val: int = 12345) -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 modal）")

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

	var state := engine.get_state()
	state.phase = "Cleanup"
	state.sub_phase = ""
	state.round_number = 1
	state.turn_order = [0, 1]
	state.current_player_index = 0
	if not (state.round_state is Dictionary):
		state.round_state = {}

	state.players[0]["inventory"]["kimchi"] = 3

	# Case A：点击“存泡菜”
	var modal_a = ModalScene.instantiate()
	if modal_a == null or not is_instance_valid(modal_a):
		return Result.failure("实例化 KimchiStorageModal 失败(caseA)")
	host.add_child(modal_a)
	(modal_a as Control).visible = true

	# 等待一帧，确保 onready 节点已就绪
	await st.process_frame

	if modal_a.has_method("setup"):
		modal_a.call("setup", state, 0)

	var results_a: Array[Dictionary] = []
	if modal_a.has_signal("completed"):
		modal_a.completed.connect(func(r: Dictionary) -> void: results_a.append(r))

	if modal_a.has_method("_on_confirm_pressed"):
		modal_a.call("_on_confirm_pressed")

	if results_a.size() != 1 or not bool(results_a[0].get("store", false)):
		await _cleanup_modal(modal_a)
		return Result.failure("caseA 应 emit store=true，实际: %s" % str(results_a))

	if modal_a is ModalPanelBase:
		var mb: ModalPanelBase = modal_a
		if is_instance_valid(mb.confirm_button) and not mb.confirm_button.disabled:
			await _cleanup_modal(modal_a)
			return Result.failure("caseA confirm_button 应被禁用")
		if is_instance_valid(mb.cancel_button) and not mb.cancel_button.disabled:
			await _cleanup_modal(modal_a)
			return Result.failure("caseA cancel_button 应被禁用")

	await _cleanup_modal(modal_a)

	# Case B：点击“不存泡菜”
	var modal_b = ModalScene.instantiate()
	if modal_b == null or not is_instance_valid(modal_b):
		return Result.failure("实例化 KimchiStorageModal 失败(caseB)")
	host.add_child(modal_b)
	(modal_b as Control).visible = true
	await st.process_frame

	if modal_b.has_method("setup"):
		modal_b.call("setup", state, 0)

	var results_b: Array[Dictionary] = []
	if modal_b.has_signal("completed"):
		modal_b.completed.connect(func(r: Dictionary) -> void: results_b.append(r))

	if modal_b.has_method("_on_cancel_pressed"):
		modal_b.call("_on_cancel_pressed")

	if results_b.size() != 1 or bool(results_b[0].get("store", true)):
		await _cleanup_modal(modal_b)
		return Result.failure("caseB 应 emit store=false，实际: %s" % str(results_b))

	await _cleanup_modal(modal_b)
	return Result.success({})

static func _cleanup_modal(modal: Node) -> void:
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		await (tree as SceneTree).process_frame
