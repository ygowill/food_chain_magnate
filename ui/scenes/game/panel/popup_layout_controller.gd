# GamePanelController：弹窗布局/定位（居中 / 右侧抽屉式）
extends RefCounted

const POPUP_LAYOUT_META_KEY := "popup_layout"
const POPUP_LAYOUT_DOCK_RIGHT := "dock_right"

var _scene = null

func _init(scene) -> void:
	_scene = scene

func dispose() -> void:
	_scene = null

func center_popup(panel: Control) -> void:
	if panel == null:
		return
	if _scene == null:
		return
	var layout := ""
	if panel.has_meta(POPUP_LAYOUT_META_KEY):
		layout = str(panel.get_meta(POPUP_LAYOUT_META_KEY))

	panel.z_index = 500

	if layout == POPUP_LAYOUT_DOCK_RIGHT:
		_dock_popup_right(panel)
	else:
		await _scene.get_tree().process_frame
		_center_popup_in_viewport(panel)

	# P2：弹窗动画（避免 headless 影响测试/资源回收）
	if OS.has_feature("headless"):
		return
	if not (_scene.has_method("get_ui_animation_manager")):
		return
	var anim_manager = _scene.call("get_ui_animation_manager")
	if anim_manager == null:
		return

	if layout != POPUP_LAYOUT_DOCK_RIGHT and anim_manager.has_method("animate_scale_bounce"):
		anim_manager.call("animate_scale_bounce", panel)

func _center_popup_in_viewport(panel: Control) -> void:
	if panel == null or _scene == null:
		return
	var safe_rect := _get_map_area_rect_in_scene()
	var panel_size := _get_panel_size(panel)

	var x := safe_rect.position.x + (safe_rect.size.x - panel_size.x) / 2.0
	var y := safe_rect.position.y + (safe_rect.size.y - panel_size.y) / 2.0

	var margin := 8.0
	var min_x := safe_rect.position.x + margin
	var max_x := safe_rect.position.x + safe_rect.size.x - panel_size.x - margin
	if max_x < min_x:
		max_x = min_x
	var min_y := safe_rect.position.y + margin
	var max_y := safe_rect.position.y + safe_rect.size.y - panel_size.y - margin
	if max_y < min_y:
		max_y = min_y

	panel.position = Vector2(
		clampf(x, min_x, max_x),
		clampf(y, min_y, max_y)
	)

func _dock_popup_right(panel: Control) -> void:
	if panel == null or _scene == null:
		return

	# v2：优先嵌入到 RightPanel（抽屉式），而不是覆盖在视口右侧
	if _scene.has_method("dock_popup_into_right_panel"):
		var r = _scene.call("dock_popup_into_right_panel", panel)
		if r is bool and bool(r):
			return

	var safe := _get_popup_safe_rect()
	var panel_size := _get_panel_size(panel)

	var margin := 12.0
	var x := safe.position.x + safe.size.x - panel_size.x - margin
	var y := safe.position.y + (safe.size.y - panel_size.y) / 2.0

	# Clamp
	x = maxf(margin, x)
	var min_y := safe.position.y + margin
	var max_y := safe.position.y + safe.size.y - panel_size.y - margin
	if max_y < min_y:
		max_y = min_y
	y = clampf(y, min_y, max_y)

	panel.position = Vector2(x, y)

func _get_panel_size(panel: Control) -> Vector2:
	var s := panel.size
	if s == Vector2.ZERO:
		s = panel.get_combined_minimum_size()
	if s == Vector2.ZERO:
		s = panel.custom_minimum_size
	if s == Vector2.ZERO:
		s = Vector2(420, 260)
	return s

func _get_map_area_rect_in_scene() -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var map_area = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/GameArea")
	if map_area is Control:
		var c: Control = map_area
		var gr := c.get_global_rect()
		var scene_global := Vector2.ZERO
		if _scene is Control:
			scene_global = (_scene as Control).global_position
		var rect := Rect2(gr.position - scene_global, gr.size)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			return rect

	return Rect2(Vector2.ZERO, _scene.get_viewport_rect().size)

func _get_popup_safe_rect() -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var viewport_size: Vector2 = _scene.get_viewport_rect().size
	var top := 0.0
	var bottom := viewport_size.y

	var top_bar = _scene.get_node_or_null("UIRoot/TopBar")
	if top_bar is Control:
		var c: Control = top_bar
		top = maxf(top, c.position.y + c.size.y)

	var bottom_panel = _scene.get_node_or_null("UIRoot/BottomPanel")
	if bottom_panel is Control:
		var c2: Control = bottom_panel
		bottom = minf(bottom, c2.position.y)

	# 预留一点间距（避免贴边）
	top += 5.0
	bottom -= 5.0

	if bottom < top:
		bottom = top

	return Rect2(Vector2(0, top), Vector2(viewport_size.x, bottom - top))

