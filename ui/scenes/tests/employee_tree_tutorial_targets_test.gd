class_name EmployeeTreeTutorialTargetsTest
extends RefCounted

const EmployeeTreeScene: PackedScene = preload("res://ui/components/employee_tree/employee_tree.tscn")

const REQUIRED_TARGET_KINDS: Array[String] = [
	"card",
	"header",
	"remaining_badge",
	"entry_marker",
	"one_x_marker",
	"manager_header",
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
		control.position = Vector2(80, 50)
		control.custom_minimum_size = Vector2(1120, 620)
		control.size = Vector2(1120, 620)
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

	var tutorial_viewport = panel.call("get_tutorial_viewport")
	if not (tutorial_viewport is Control):
		_safe_free(host)
		await tree.process_frame
		if engine.has_method("dispose"):
			engine.dispose()
		return Result.failure("EmployeeTree 缺少 tutorial viewport")
	var viewport_control: Control = tutorial_viewport
	var viewport_rect := viewport_control.get_global_rect()

	for target_kind in REQUIRED_TARGET_KINDS:
		if panel.has_method("prepare_tutorial_focus"):
			panel.call("prepare_tutorial_focus", target_kind)
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
		var visible_rect := _get_visible_global_rect(control_target, viewport_control)
		if visible_rect.size.x <= 0.0 or visible_rect.size.y <= 0.0:
			_safe_free(host)
			await tree.process_frame
			if engine.has_method("dispose"):
				engine.dispose()
			return Result.failure("EmployeeTree 教学 target 未落在可见视口内: %s" % target_kind)
		var target_rect := control_target.get_global_rect()
		if target_rect.position.distance_to(visible_rect.position) > 1.0 or target_rect.size.distance_to(visible_rect.size) > 1.0:
			_safe_free(host)
			await tree.process_frame
			if engine.has_method("dispose"):
				engine.dispose()
			return Result.failure("EmployeeTree 教学 target 被裁切或超出视口: %s (viewport=%s, target=%s, visible=%s)" % [target_kind, viewport_rect, target_rect, visible_rect])

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

static func _get_visible_global_rect(target: Control, viewport_control: Control) -> Rect2:
	if target == null or not is_instance_valid(target):
		return Rect2()
	var rect := target.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	if viewport_control != null and is_instance_valid(viewport_control):
		rect = rect.intersection(viewport_control.get_global_rect())
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return Rect2()
	var parent_node: Node = target.get_parent()
	while parent_node != null:
		if parent_node is Control:
			var parent_control := parent_node as Control
			if parent_control.clip_contents:
				rect = rect.intersection(parent_control.get_global_rect())
				if rect.size.x <= 0.0 or rect.size.y <= 0.0:
					return Rect2()
			if parent_control == viewport_control:
				break
		parent_node = parent_node.get_parent()
	return rect
