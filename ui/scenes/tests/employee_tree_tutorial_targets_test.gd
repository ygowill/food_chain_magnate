class_name EmployeeTreeTutorialTargetsTest
extends RefCounted

const EmployeeTreeScene: PackedScene = preload("res://ui/components/employee_tree/employee_tree.tscn")

const REQUIRED_TARGET_KINDS: Array[String] = [
	"card",
	"header",
	"remaining_badge",
	"entry_marker",
	"range_marker",
	"salary_marker",
	"description",
]

static func run() -> Result:
	var tree := _get_tree()
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if EmployeeTreeScene == null:
		return Result.failure("EmployeeTreeScene preload 失败")

	var engine := GameEngine.new()
	var init_r := engine.initialize(2, 12345)
	if not init_r.ok:
		return Result.failure("GameEngine.initialize 失败: %s" % init_r.error)

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)

	var panel = EmployeeTreeScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		_safe_free(host)
		await tree.process_frame
		if engine.has_method("dispose"):
			engine.dispose()
		return Result.failure("实例化 EmployeeTree 失败")
	host.add_child(panel)

	if panel is Control:
		var control: Control = panel
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
		control.visible = true

	var state: GameState = engine.get_state()
	if state != null and panel.has_method("set_employee_pool"):
		panel.call("set_employee_pool", state.employee_pool)
	if panel.has_method("open"):
		panel.call("open")
	await tree.process_frame
	if panel.has_method("prepare_tutorial_layout"):
		panel.call("prepare_tutorial_layout")

	var layout_ready := false
	for _i in range(120):
		if panel.has_method("is_tutorial_layout_ready") and bool(panel.call("is_tutorial_layout_ready")):
			layout_ready = true
			break
		await tree.process_frame
	if not layout_ready:
		_safe_free(host)
		await tree.process_frame
		if engine.has_method("dispose"):
			engine.dispose()
		return Result.failure("EmployeeTree 教学布局未在预期帧数内准备完成")

	for target_kind in REQUIRED_TARGET_KINDS:
		if not panel.has_method("get_tutorial_sample_card_target"):
			_safe_free(host)
			await tree.process_frame
			if engine.has_method("dispose"):
				engine.dispose()
			return Result.failure("EmployeeTree 缺少 get_tutorial_sample_card_target")
		var target = panel.call("get_tutorial_sample_card_target", target_kind)
		if not (target is Control):
			_safe_free(host)
			await tree.process_frame
			if engine.has_method("dispose"):
				engine.dispose()
			return Result.failure("EmployeeTree 教学 target 不是 Control: %s" % target_kind)
		var control_target: Control = target
		if not is_instance_valid(control_target) or not control_target.is_visible_in_tree():
			_safe_free(host)
			await tree.process_frame
			if engine.has_method("dispose"):
				engine.dispose()
			return Result.failure("EmployeeTree 教学 target 缺失或不可见: %s" % target_kind)

	_safe_free(host)
	await tree.process_frame
	await tree.process_frame
	if engine.has_method("dispose"):
		engine.dispose()
	return Result.success({
		"target_kinds": REQUIRED_TARGET_KINDS.size(),
	})

static func _get_tree() -> SceneTree:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return loop as SceneTree
	return null

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
