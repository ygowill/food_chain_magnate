class_name TutorialSpotlightOverlayStartTest
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

	var target := ColorRect.new()
	target.position = Vector2(180, 120)
	target.size = Vector2(220, 96)
	host.add_child(target)

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
				"target_key": "target",
				"title": "测试",
				"body": "测试正文",
			}
		],
		func() -> Dictionary:
			return {"target": target}
	)

	for _i in range(4):
		await tree.process_frame

	var overlay_mask = overlay.get_node_or_null("Overlay") as ColorRect
	if overlay_mask == null:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("TutorialSpotlightOverlay 缺少 Overlay 节点")
	if overlay_mask.visible:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("教学 spotlight 不应显示整屏遮罩 Overlay；否则会重新盖住高亮区域")

	var highlight := overlay.get_node_or_null("HighlightFrame") as Control
	var card_panel := overlay.get_node_or_null("CardPanel") as Control
	if highlight == null or card_panel == null:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("TutorialSpotlightOverlay 缺少高亮或说明面板节点")
	if not bool(overlay.call("is_tour_running")):
		_safe_free(host)
		await tree.process_frame
		return Result.failure("教学 spotlight 在首次启动后未进入运行状态")
	if not highlight.visible or highlight.size.x <= 0.0 or highlight.size.y <= 0.0:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("教学 spotlight 未生成有效高亮框")
	if not card_panel.visible:
		_safe_free(host)
		await tree.process_frame
		return Result.failure("教学 spotlight 未显示说明卡片")

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
