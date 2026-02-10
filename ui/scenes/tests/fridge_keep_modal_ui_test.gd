class_name FridgeKeepModalUiTest
extends RefCounted

const ModalScene: PackedScene = preload("res://modules/base_rules/ui/components/modal_panel/fridge_keep_modal.tscn")

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

	# 通过 base_milestones 的 first_throw_away 获得冰箱（gain_fridge=10）
	state.players[0]["milestones"] = ["first_throw_away"]
	state.players[0]["inventory"] = {
		"burger": 5,
		"lemonade": 8,
	}

	var modal = ModalScene.instantiate()
	if modal == null or not is_instance_valid(modal):
		return Result.failure("实例化 FridgeKeepModal 失败")
	host.add_child(modal)
	(modal as Control).visible = true

	# 等待一帧，确保 onready 节点已就绪
	await st.process_frame

	if modal.has_method("setup"):
		modal.call("setup", state, 0)

	if modal is ModalPanelBase:
		var mb_ready: ModalPanelBase = modal
		if is_instance_valid(mb_ready.confirm_button) and mb_ready.confirm_button.disabled:
			await _cleanup_modal(modal)
			return Result.failure("setup 后 confirm_button 应可用（默认选择应满足容量）")

	var results: Array[Dictionary] = []
	if modal.has_signal("completed"):
		modal.completed.connect(func(r: Dictionary) -> void: results.append(r))

	if modal.has_method("_on_confirm_pressed"):
		modal.call("_on_confirm_pressed")
	else:
		await _cleanup_modal(modal)
		return Result.failure("FridgeKeepModal 缺少 _on_confirm_pressed（无法完成测试）")

	if results.size() != 1:
		await _cleanup_modal(modal)
		return Result.failure("应 emit completed 一次，实际: %s" % str(results))

	var keep_val = results[0].get("keep", null)
	if not (keep_val is Dictionary):
		await _cleanup_modal(modal)
		return Result.failure("completed.keep 类型错误（期望 Dictionary），实际: %s" % str(keep_val))
	var keep: Dictionary = keep_val

	# 默认策略：按产品 id 顺序尽量填满 cap=10，因此 burger=5, lemonade=5
	if int(keep.get("burger", 0)) != 5:
		await _cleanup_modal(modal)
		return Result.failure("默认 keep.burger 应为 5，实际: %s" % str(keep.get("burger", null)))
	if int(keep.get("lemonade", 0)) != 5:
		await _cleanup_modal(modal)
		return Result.failure("默认 keep.lemonade 应为 5，实际: %s" % str(keep.get("lemonade", null)))

	if modal is ModalPanelBase:
		var mb_done: ModalPanelBase = modal
		if is_instance_valid(mb_done.confirm_button) and not mb_done.confirm_button.disabled:
			await _cleanup_modal(modal)
			return Result.failure("confirm 后 confirm_button 应被禁用（避免重复触发）")

	await _cleanup_modal(modal)
	return Result.success({})

static func _cleanup_modal(modal: Node) -> void:
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		await (tree as SceneTree).process_frame
