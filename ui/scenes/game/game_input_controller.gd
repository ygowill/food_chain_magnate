# Game scene：输入/快捷键控制器
# 负责：ESC/Enter/D/R 等快捷键，与菜单/弹窗/右侧 footer/地图放置旋转等交互的分发。
class_name GameInputController
extends RefCounted

var _menu_controller: Object = null
var _overlay_controller: Object = null
var _panel_controller: Object = null
var _map_controller: Object = null
var _right_panel_dock_controller: Object = null

var _right_panel_footer_row: Control = null
var _right_panel_footer_secondary_button: Button = null
var _right_panel_footer_primary_button: Button = null

func _init(
	menu_controller: Object,
	overlay_controller: Object,
	panel_controller: Object,
	map_controller: Object,
	right_panel_dock_controller: Object,
	right_panel_footer_row: Control,
	right_panel_footer_secondary_button: Button,
	right_panel_footer_primary_button: Button
) -> void:
	_menu_controller = menu_controller
	_overlay_controller = overlay_controller
	_panel_controller = panel_controller
	_map_controller = map_controller
	_right_panel_dock_controller = right_panel_dock_controller
	_right_panel_footer_row = right_panel_footer_row
	_right_panel_footer_secondary_button = right_panel_footer_secondary_button
	_right_panel_footer_primary_button = right_panel_footer_primary_button

func dispose() -> void:
	_menu_controller = null
	_overlay_controller = null
	_panel_controller = null
	_map_controller = null
	_right_panel_dock_controller = null
	_right_panel_footer_row = null
	_right_panel_footer_secondary_button = null
	_right_panel_footer_primary_button = null

func handle_unhandled_input(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	var e: InputEventKey = event
	if not e.pressed or e.echo:
		return false

	match e.keycode:
		KEY_ESCAPE:
			if _handle_escape():
				return true
			if is_instance_valid(_menu_controller) and _menu_controller.has_method("on_menu_pressed"):
				_menu_controller.call("on_menu_pressed")
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if e.shift_pressed:
				return _try_trigger_right_panel_footer_secondary()
			return _try_trigger_right_panel_footer_primary()
		KEY_1, KEY_KP_1:
			return _try_select_procure_drinks_start_restaurant_by_index(1)
		KEY_2, KEY_KP_2:
			return _try_select_procure_drinks_start_restaurant_by_index(2)
		KEY_3, KEY_KP_3:
			return _try_select_procure_drinks_start_restaurant_by_index(3)
		KEY_4, KEY_KP_4:
			return _try_select_procure_drinks_start_restaurant_by_index(4)
		KEY_5, KEY_KP_5:
			return _try_select_procure_drinks_start_restaurant_by_index(5)
		KEY_6, KEY_KP_6:
			return _try_select_procure_drinks_start_restaurant_by_index(6)
		KEY_7, KEY_KP_7:
			return _try_select_procure_drinks_start_restaurant_by_index(7)
		KEY_8, KEY_KP_8:
			return _try_select_procure_drinks_start_restaurant_by_index(8)
		KEY_9, KEY_KP_9:
			return _try_select_procure_drinks_start_restaurant_by_index(9)
		KEY_D:
			if is_instance_valid(_map_controller) and _map_controller.has_method("toggle_distance_tool"):
				_map_controller.call("toggle_distance_tool")
				return true
		KEY_R:
			return _try_rotate_placement()
		_:
			return false

	return false

func _try_select_procure_drinks_start_restaurant_by_index(index: int) -> bool:
	# 若有顶层对话框，优先不处理
	if is_instance_valid(_menu_controller):
		if _menu_controller.has_method("is_menu_visible") and bool(_menu_controller.call("is_menu_visible")):
			return false
		if _menu_controller.has_method("is_confirm_visible") and bool(_menu_controller.call("is_confirm_visible")):
			return false

	if is_instance_valid(_overlay_controller):
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
			return false

	if not is_instance_valid(_map_controller):
		return false
	if not _map_controller.has_method("try_select_procure_drinks_start_restaurant_by_index"):
		return false
	var handled = _map_controller.call("try_select_procure_drinks_start_restaurant_by_index", int(index))
	return handled is bool and bool(handled)

func _try_trigger_right_panel_footer_primary() -> bool:
	if not is_instance_valid(_right_panel_footer_row) or not _right_panel_footer_row.visible:
		return false
	if not is_instance_valid(_right_panel_footer_primary_button) or not _right_panel_footer_primary_button.visible:
		return false
	if _right_panel_footer_primary_button.disabled:
		return false
	if is_instance_valid(_right_panel_dock_controller) and _right_panel_dock_controller.has_method("on_footer_primary_pressed"):
		_right_panel_dock_controller.call("on_footer_primary_pressed")
		return true
	return false

func _try_trigger_right_panel_footer_secondary() -> bool:
	if not is_instance_valid(_right_panel_footer_row) or not _right_panel_footer_row.visible:
		return false
	if not is_instance_valid(_right_panel_footer_secondary_button) or not _right_panel_footer_secondary_button.visible:
		return false
	if _right_panel_footer_secondary_button.disabled:
		return false
	if is_instance_valid(_right_panel_dock_controller) and _right_panel_dock_controller.has_method("on_footer_secondary_pressed"):
		_right_panel_dock_controller.call("on_footer_secondary_pressed")
		return true
	return false

func _handle_escape() -> bool:
	# 关闭顶层对话框（菜单/确认）
	if is_instance_valid(_menu_controller) and _menu_controller.has_method("handle_escape"):
		var closed_val = _menu_controller.call("handle_escape")
		if closed_val is bool and bool(closed_val):
			return true

	# 关闭设置窗口
	if is_instance_valid(_overlay_controller):
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
			if dlg.has_method("_on_close_pressed"):
				dlg.call("_on_close_pressed")
			else:
				dlg.hide()
			return true

	# 关闭全屏浏览视图（例如里程碑/保留区），避免影响底层面板/选中状态。
	if is_instance_valid(_panel_controller) and _panel_controller.has_method("hide_top_overlays_if_open"):
		var closed = _panel_controller.call("hide_top_overlays_if_open")
		if closed is bool and bool(closed):
			return true

	# 关闭阶段面板/取消地图模式
	if not is_instance_valid(_panel_controller):
		return false

	var map_mode_active := false
	if is_instance_valid(_map_controller) and _map_controller.has_method("get_mode"):
		map_mode_active = not str(_map_controller.call("get_mode")).is_empty()

	if map_mode_active:
		if _panel_controller.has_method("hide_all"):
			_panel_controller.call("hide_all")
		return true

	if _panel_controller.has_method("has_open_phase_ui") and bool(_panel_controller.call("has_open_phase_ui")):
		if _panel_controller.has_method("hide_all_keep_selection"):
			_panel_controller.call("hide_all_keep_selection")
		elif _panel_controller.has_method("hide_all"):
			_panel_controller.call("hide_all")
		return true

	return false

func _try_rotate_placement() -> bool:
	# 若有顶层对话框，优先不处理
	if is_instance_valid(_menu_controller):
		if _menu_controller.has_method("is_menu_visible") and bool(_menu_controller.call("is_menu_visible")):
			return false
		if _menu_controller.has_method("is_confirm_visible") and bool(_menu_controller.call("is_confirm_visible")):
			return false

	if is_instance_valid(_overlay_controller):
		var dlg = _overlay_controller.settings_dialog
		if is_instance_valid(dlg) and dlg.visible:
			return false

	if not is_instance_valid(_map_controller) or not _map_controller.has_method("get_mode"):
		return false
	var mode := str(_map_controller.call("get_mode"))

	if mode == "restaurant_placement":
		var ov = _map_controller.restaurant_placement_overlay
		if is_instance_valid(ov) and ov.visible and ov.has_method("rotate_cw"):
			ov.rotate_cw()
			return true
	if mode == "house_placement":
		var ov2 = _map_controller.house_placement_overlay
		if is_instance_valid(ov2) and ov2.visible and ov2.has_method("rotate_cw"):
			ov2.rotate_cw()
			return true

	return false
