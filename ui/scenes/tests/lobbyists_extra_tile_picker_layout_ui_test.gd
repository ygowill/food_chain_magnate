class_name LobbyistsExtraTilePickerLayoutUiTest
extends RefCounted

const OverlayScene: PackedScene = preload("res://modules/lobbyists/ui/components/lobbyists_extra_tile/lobbyists_extra_tile_overlay.tscn")

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 overlay）")

	var overlay = OverlayScene.instantiate()
	if overlay == null or not is_instance_valid(overlay):
		return Result.failure("实例化 LobbyistsExtraTileOverlay 失败")
	host.add_child(overlay)
	overlay.visible = true

	var tiles: Array[String] = ["t01", "t02", "t03", "t04"]
	if overlay.has_method("set_available_tiles"):
		overlay.call("set_available_tiles", tiles)
	if overlay.has_method("show_picker"):
		overlay.call("show_picker")

	# Wait a few frames so containers can settle sizing and apply the matrix layout.
	for _i in range(5):
		await st.process_frame

	var tiles_scroll = overlay.get_node_or_null("Center/HintMargin/HintPanel/VBox/TilesRow/TilesScroll")
	var tiles_stage = overlay.get_node_or_null("Center/HintMargin/HintPanel/VBox/TilesRow/TilesScroll/TilesStage")
	var tiles_flow = overlay.get_node_or_null("Center/HintMargin/HintPanel/VBox/TilesRow/TilesScroll/TilesStage/TilesFlow")
	if tiles_scroll == null or tiles_stage == null or tiles_flow == null:
		await _cleanup_overlay(overlay)
		return Result.failure("overlay 节点结构变更：找不到 TilesScroll/TilesStage/TilesFlow")

	if tiles_flow.get_child_count() != tiles.size():
		await _cleanup_overlay(overlay)
		return Result.failure("tile 按钮数量不匹配：expected=%d actual=%d" % [tiles.size(), tiles_flow.get_child_count()])

	var tile_w := 160.0
	if tiles_flow.get_child_count() > 0:
		var c0 = tiles_flow.get_child(0)
		if c0 is Control and is_instance_valid(c0):
			var ms := (c0 as Control).get_combined_minimum_size()
			if ms.x > 4.0:
				tile_w = float(ms.x)
	var h_sep := float(tiles_flow.get_theme_constant("h_separation"))
	if h_sep <= 0.0:
		h_sep = 12.0

	# Should be at least 2 columns for 4 tiles (avoid single-column regressions).
	var min_two_cols_w := tile_w * 2.0 + h_sep
	if float(tiles_flow.custom_minimum_size.x) < min_two_cols_w - 0.5:
		await _cleanup_overlay(overlay)
		return Result.failure("TilesFlow 过窄（疑似回归为单列）：min_size=%s expected>=%s" % [str(tiles_flow.custom_minimum_size), str(Vector2(min_two_cols_w, 0))])

	# When content height is smaller than the scroll viewport, the matrix should not stick to the top.
	var stage_h := float((tiles_stage as Control).size.y)
	var flow_h := float((tiles_flow as Control).size.y)
	if stage_h > flow_h + 32.0:
		var y := float((tiles_flow as Control).position.y)
		if y < 16.0:
			await _cleanup_overlay(overlay)
			return Result.failure("TilesFlow 未垂直居中：stage_h=%.1f flow_h=%.1f flow_y=%.1f" % [stage_h, flow_h, y])

	await _cleanup_overlay(overlay)
	return Result.success({})

static func _cleanup_overlay(overlay: Node) -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		await (tree as SceneTree).process_frame
