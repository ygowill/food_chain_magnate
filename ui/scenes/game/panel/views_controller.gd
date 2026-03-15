# Game scene：顶层浏览视图控制器
# 负责：EmployeeTree / MilestoneFullScreenView / ReserveCardsFullScreenView / ReserveAreaFullScreenView 的创建、显示/隐藏与生命周期管理。
class_name GamePanelViewsController
extends RefCounted

const EmployeeTreeScene = preload("res://ui/components/employee_tree/employee_tree.tscn")
const MilestoneFullScreenViewScene = preload("res://ui/components/milestone_panel/milestone_full_screen_view.tscn")
const ReserveCardsFullScreenViewScene = preload("res://ui/components/reserve_cards/reserve_cards_full_screen_view.tscn")
const ReserveAreaFullScreenViewScene = preload("res://ui/components/reserve_area/reserve_area_full_screen_view.tscn")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")

var _scene = null

var _employee_tree_panel = null
var _milestone_full_screen_view = null
var _reserve_cards_full_screen_view = null
var _reserve_area_full_screen_view = null

func _init(scene) -> void:
	_scene = scene

func dispose() -> void:
	if is_instance_valid(_employee_tree_panel):
		_employee_tree_panel.queue_free()
	_employee_tree_panel = null

	if is_instance_valid(_milestone_full_screen_view):
		_milestone_full_screen_view.queue_free()
	_milestone_full_screen_view = null

	if is_instance_valid(_reserve_cards_full_screen_view):
		_reserve_cards_full_screen_view.queue_free()
	_reserve_cards_full_screen_view = null

	if is_instance_valid(_reserve_area_full_screen_view):
		_reserve_area_full_screen_view.queue_free()
	_reserve_area_full_screen_view = null

	_scene = null

func has_open_view_ui() -> bool:
	if is_instance_valid(_employee_tree_panel) and _employee_tree_panel.visible:
		return true
	if is_instance_valid(_milestone_full_screen_view) and _milestone_full_screen_view.visible:
		return true
	if is_instance_valid(_reserve_cards_full_screen_view) and _reserve_cards_full_screen_view.visible:
		return true
	if is_instance_valid(_reserve_area_full_screen_view) and _reserve_area_full_screen_view.visible:
		return true
	return false

func hide() -> void:
	hide_employee_tree()
	hide_milestone_full_screen_view()
	hide_reserve_cards_full_screen_view()
	hide_reserve_area_full_screen_view()

func hide_top_overlays_if_open() -> bool:
	if is_instance_valid(_reserve_cards_full_screen_view) and _reserve_cards_full_screen_view.visible:
		hide_reserve_cards_full_screen_view()
		return true
	if is_instance_valid(_reserve_area_full_screen_view) and _reserve_area_full_screen_view.visible:
		hide_reserve_area_full_screen_view()
		return true
	if is_instance_valid(_milestone_full_screen_view) and _milestone_full_screen_view.visible:
		hide_milestone_full_screen_view()
		return true
	return false

func is_employee_tree_visible() -> bool:
	return is_instance_valid(_employee_tree_panel) and bool(_employee_tree_panel.visible)

func show_employee_tree() -> void:
	if _scene == null:
		return
	_ensure_employee_tree_panel()
	if not is_instance_valid(_employee_tree_panel):
		return

	if _employee_tree_panel.has_method("open"):
		_employee_tree_panel.call("open")

	# 覆盖全屏（不使用居中弹窗布局）
	if _employee_tree_panel is Control:
		var p: Control = _employee_tree_panel
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.offset_left = 0.0
		p.offset_top = 0.0
		p.offset_right = 0.0
		p.offset_bottom = 0.0
		p.position = Vector2.ZERO
		p.size = _scene.get_viewport_rect().size
	_employee_tree_panel.visible = true

func hide_employee_tree() -> void:
	var was_visible := false
	if is_instance_valid(_employee_tree_panel):
		was_visible = bool(_employee_tree_panel.visible)
		_employee_tree_panel.visible = false
	# 仅当确实从“可见 -> 隐藏”时才刷新 UI；否则会在 hide_all/终局面板等流程中形成无限刷新循环。
	if was_visible and _scene != null and is_instance_valid(_scene) and _scene.has_method("_update_ui"):
		_scene.call_deferred("_update_ui")

func get_employee_tree_panel():
	_ensure_employee_tree_panel()
	return _employee_tree_panel

func show_milestone_full_screen_view(state: GameState, map_skin) -> void:
	if state == null:
		return
	_ensure_milestone_full_screen_view()
	if not is_instance_valid(_milestone_full_screen_view):
		return
	if _milestone_full_screen_view.has_method("open_with_state"):
		_milestone_full_screen_view.call("open_with_state", state, map_skin)

	# 覆盖全屏（不使用居中弹窗布局）
	if _scene != null and _milestone_full_screen_view is Control:
		_apply_full_rect(_milestone_full_screen_view as Control)
	_milestone_full_screen_view.visible = true

func hide_milestone_full_screen_view() -> void:
	if is_instance_valid(_milestone_full_screen_view):
		_milestone_full_screen_view.visible = false

func get_milestone_full_screen_view():
	_ensure_milestone_full_screen_view()
	return _milestone_full_screen_view

func show_reserve_cards_full_screen_view(state: GameState, focus_player_id: int = -1) -> void:
	if state == null:
		return
	_ensure_reserve_cards_full_screen_view()
	if not is_instance_valid(_reserve_cards_full_screen_view):
		return
	if _reserve_cards_full_screen_view.has_method("open_with_state"):
		_reserve_cards_full_screen_view.call("open_with_state", state, focus_player_id)

	if _scene != null and _reserve_cards_full_screen_view is Control:
		_apply_full_rect(_reserve_cards_full_screen_view as Control)
	_reserve_cards_full_screen_view.visible = true

func hide_reserve_cards_full_screen_view() -> void:
	if is_instance_valid(_reserve_cards_full_screen_view):
		_reserve_cards_full_screen_view.visible = false

func get_reserve_cards_full_screen_view():
	_ensure_reserve_cards_full_screen_view()
	return _reserve_cards_full_screen_view

func show_reserve_area_full_screen_view(state: GameState, map_skin) -> void:
	if state == null:
		return
	_ensure_reserve_area_full_screen_view()
	if not is_instance_valid(_reserve_area_full_screen_view):
		return
	if _reserve_area_full_screen_view.has_method("open_with_state"):
		_reserve_area_full_screen_view.call("open_with_state", state, map_skin)

	# 覆盖全屏（不使用居中弹窗布局）
	if _scene != null and _reserve_area_full_screen_view is Control:
		_apply_full_rect(_reserve_area_full_screen_view as Control)
	_reserve_area_full_screen_view.visible = true

func _apply_full_rect(ctrl: Control) -> void:
	if _scene == null:
		return
	if ctrl == null or not is_instance_valid(ctrl):
		return
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.position = Vector2.ZERO
	ctrl.size = _scene.get_viewport_rect().size

func hide_reserve_area_full_screen_view() -> void:
	if is_instance_valid(_reserve_area_full_screen_view):
		_reserve_area_full_screen_view.visible = false

func get_reserve_area_full_screen_view():
	_ensure_reserve_area_full_screen_view()
	return _reserve_area_full_screen_view

func _ensure_employee_tree_panel() -> void:
	if _scene == null:
		return
	if is_instance_valid(_employee_tree_panel):
		return

	_employee_tree_panel = EmployeeTreeScene.instantiate()
	if not is_instance_valid(_employee_tree_panel):
		return
	_employee_tree_panel.visible = false
	_scene.add_child(_employee_tree_panel)
	if _employee_tree_panel is Control:
		UiZClass.apply_absolute((_employee_tree_panel as Control), UiZClass.FULLSCREEN_VIEW)
	if _employee_tree_panel.has_signal("closed"):
		if not _employee_tree_panel.closed.is_connected(hide_employee_tree):
			_employee_tree_panel.closed.connect(hide_employee_tree)

func _ensure_milestone_full_screen_view() -> void:
	if _scene == null:
		return
	if is_instance_valid(_milestone_full_screen_view):
		return

	_milestone_full_screen_view = MilestoneFullScreenViewScene.instantiate()
	if not is_instance_valid(_milestone_full_screen_view):
		return
	_milestone_full_screen_view.visible = false
	_scene.add_child(_milestone_full_screen_view)

	if _milestone_full_screen_view is Control:
		UiZClass.apply_absolute((_milestone_full_screen_view as Control), UiZClass.FULLSCREEN_VIEW)

	UiSignalHelpersClass.safe_connect(_milestone_full_screen_view, "close_requested", hide_milestone_full_screen_view)

func _ensure_reserve_cards_full_screen_view() -> void:
	if _scene == null:
		return
	if is_instance_valid(_reserve_cards_full_screen_view):
		return

	_reserve_cards_full_screen_view = ReserveCardsFullScreenViewScene.instantiate()
	if not is_instance_valid(_reserve_cards_full_screen_view):
		return
	_reserve_cards_full_screen_view.visible = false
	_scene.add_child(_reserve_cards_full_screen_view)

	if _reserve_cards_full_screen_view is Control:
		UiZClass.apply_absolute((_reserve_cards_full_screen_view as Control), UiZClass.FULLSCREEN_VIEW)

	UiSignalHelpersClass.safe_connect(_reserve_cards_full_screen_view, "close_requested", hide_reserve_cards_full_screen_view)

func _ensure_reserve_area_full_screen_view() -> void:
	if _scene == null:
		return
	if is_instance_valid(_reserve_area_full_screen_view):
		return

	_reserve_area_full_screen_view = ReserveAreaFullScreenViewScene.instantiate()
	if not is_instance_valid(_reserve_area_full_screen_view):
		return
	_reserve_area_full_screen_view.visible = false
	_scene.add_child(_reserve_area_full_screen_view)

	if _reserve_area_full_screen_view is Control:
		UiZClass.apply_absolute((_reserve_area_full_screen_view as Control), UiZClass.FULLSCREEN_VIEW)

	UiSignalHelpersClass.safe_connect(_reserve_area_full_screen_view, "close_requested", hide_reserve_area_full_screen_view)
