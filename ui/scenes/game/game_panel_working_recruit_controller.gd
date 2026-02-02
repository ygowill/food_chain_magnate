# Game scene：Working/Recruit 面板控制器
# 负责：RecruitPanel 的生命周期、同步与命令分发。
class_name GamePanelWorkingRecruitController
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RecruitPanelScene = preload("res://ui/components/recruit_panel/recruit_panel.tscn")

var _scene = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()
var _center_popup: Callable = Callable()

var recruit_panel = null

func _init(scene, execute_command: Callable, hide_all: Callable, center_popup: Callable) -> void:
	_scene = scene
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup

func dispose() -> void:
	_execute_command = Callable()
	_hide_all = Callable()
	_center_popup = Callable()

	if is_instance_valid(recruit_panel):
		recruit_panel.queue_free()
	recruit_panel = null
	_scene = null

func hide() -> void:
	if is_instance_valid(recruit_panel):
		recruit_panel.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(recruit_panel) or not recruit_panel.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_RECRUIT:
		recruit_panel.visible = false
		return
	if force_full_refresh and recruit_panel.has_method("set_employee_pool"):
		recruit_panel.set_employee_pool(state.employee_pool)
	if recruit_panel.has_method("set_recruit_count"):
		var actor := state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

func show() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if recruit_panel == null:
		recruit_panel = RecruitPanelScene.instantiate()
		recruit_panel.visible = false
		recruit_panel.set_meta("popup_layout", "dock_right")
		recruit_panel.set_meta("popup_title", "招聘")
		recruit_panel.recruit_requested.connect(_on_recruit_requested)
		if recruit_panel.has_signal("cancelled"):
			recruit_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(recruit_panel)

	var state = _scene.game_engine.get_state()

	if recruit_panel.has_method("set_employee_pool"):
		recruit_panel.set_employee_pool(state.employee_pool)

	if recruit_panel.has_method("set_recruit_count"):
		var actor = state.get_current_player_id()
		var counts := _compute_recruit_counts(state, actor)
		recruit_panel.set_recruit_count(int(counts.remaining), int(counts.total))

	if recruit_panel.has_method("clear_selection"):
		recruit_panel.clear_selection()

	if _center_popup.is_valid():
		_center_popup.call(recruit_panel)
	recruit_panel.visible = true

func _compute_recruit_counts(state: GameState, player_id: int) -> Dictionary:
	if state == null:
		return {"remaining": 0, "total": 0}
	var total: int = EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
	var used: int = EmployeeRulesClass.get_action_count(state, player_id, "recruit")
	return {"remaining": maxi(0, total - used), "total": total}

func _on_recruit_requested(employee_type: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var result: Result = _execute_command.call(Command.create("recruit", current_player_id, {"employee_type": employee_type}))

	if result.ok:
		var state = _scene.game_engine.get_state()
		if is_instance_valid(recruit_panel) and recruit_panel.has_method("set_employee_pool"):
			recruit_panel.set_employee_pool(state.employee_pool)
		sync(state)

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()

