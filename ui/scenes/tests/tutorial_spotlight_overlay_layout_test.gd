class_name TutorialSpotlightOverlayLayoutTest
extends RefCounted

const TutorialSpotlightOverlayScene: PackedScene = preload("res://ui/components/tutorial/tutorial_spotlight_overlay.tscn")

static func run() -> Result:
	var tree := _get_tree()
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")
	if TutorialSpotlightOverlayScene == null:
		return Result.failure("TutorialSpotlightOverlayScene preload 失败")

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)

	var layout_target := ColorRect.new()
	layout_target.position = Vector2(180, 160)
	layout_target.size = Vector2(220, 180)
	host.add_child(layout_target)

	var target_a := ColorRect.new()
	target_a.position = layout_target.position + Vector2(18, 16)
	target_a.size = Vector2(44, 28)
	host.add_child(target_a)

	var target_b := ColorRect.new()
	target_b.position = layout_target.position + Vector2(150, 126)
	target_b.size = Vector2(40, 26)
	host.add_child(target_b)

	var overlay = TutorialSpotlightOverlayScene.instantiate()
	if overlay == null or not is_instance_valid(overlay):
		_safe_free(host)
		await tree.process_frame
		return Result.failure("实例化 TutorialSpotlightOverlay 失败")
	host.add_child(overlay)

	overlay.call(
		"start_tour",
		[
			{
				"target_key": "target_a",
				"layout_target_key": "layout_card",
				"preferred_card_side": "right",
				"title": "步骤一",
				"body": "步骤一正文",
			},
			{
				"target_key": "target_b",
				"layout_target_key": "layout_card",
				"preferred_card_side": "right",
				"title": "步骤二",
				"body": "步骤二正文",
			},
		],
		func(_target_key: String = "") -> Dictionary:
			return {
				"target_a": target_a,
				"target_b": target_b,
				"layout_card": layout_target,
			}
	)

	for _i in range(4):
		await tree.process_frame

	var card_panel := overlay.get_node_or_null("CardPanel") as Control
	if card_panel == null or not is_instance_valid(card_panel):
		_safe_free(host)
		await tree.process_frame
		return Result.failure("TutorialSpotlightOverlay 缺少说明面板节点")

	var panel_pos_step1 := card_panel.position
	if panel_pos_step1.x <= layout_target.position.x + layout_target.size.x:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("说明面板未优先布局在 layout target 右侧")

	var expected_y := layout_target.position.y + (layout_target.size.y - card_panel.size.y) * 0.5
	if abs(panel_pos_step1.y - expected_y) > 1.0:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("说明面板未按 layout target 垂直居中布局")

	var next_button := overlay.get_node_or_null("CardPanel/MarginContainer/VBoxContainer/ButtonRow/NextButton") as Button
	if next_button == null:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("TutorialSpotlightOverlay 缺少 NextButton")
	next_button.emit_signal("pressed")

	for _i in range(4):
		await tree.process_frame

	var panel_pos_step2 := card_panel.position
	if panel_pos_step2.distance_to(panel_pos_step1) > 1.0:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("同一 layout target 下，说明面板位置不应在步骤切换时明显跳动")

	_safe_free(host)
	await tree.process_frame
	await tree.process_frame
	return Result.success({})

static func _get_tree() -> SceneTree:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return loop as SceneTree
	return null

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
