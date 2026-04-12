# Game scene：Working/Milestone 面板控制器
# 负责：MilestonePanel 的生命周期与同步（全局视图）。
class_name GamePanelWorkingMilestoneController
extends RefCounted

const MilestonePanelScene = preload("res://ui/components/milestone_panel/milestone_panel.tscn")

var _scene = null
var _hide_all: Callable = Callable()
var _center_popup: Callable = Callable()

var milestone_panel = null

func _init(scene, hide_all: Callable, center_popup: Callable) -> void:
	_scene = scene
	_hide_all = hide_all
	_center_popup = center_popup

func hide() -> void:
	if is_instance_valid(milestone_panel):
		milestone_panel.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(milestone_panel) or not milestone_panel.visible:
		return

	# 右侧里程碑面板在可见时允许继续执行其它操作；
	# 若这里只在 force_full_refresh 才同步，会导致“里程碑池/玩家已获得里程碑”停留在旧状态。
	if milestone_panel.has_method("set_milestone_pool"):
		milestone_panel.set_milestone_pool(state.milestone_pool)
	if milestone_panel.has_method("set_players"):
		milestone_panel.set_players(state.players)
	if milestone_panel.has_method("set_global_view"):
		milestone_panel.set_global_view(true)
	if force_full_refresh and milestone_panel.has_method("set_rules"):
		milestone_panel.set_rules(state.rules)

func show() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if milestone_panel == null:
		milestone_panel = MilestonePanelScene.instantiate()
		milestone_panel.visible = false
		milestone_panel.set_meta("popup_layout", "dock_right")
		milestone_panel.set_meta("popup_title", "里程碑")
		if milestone_panel.has_signal("cancelled"):
			milestone_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(milestone_panel)

	var state = _scene.game_engine.get_state()

	if milestone_panel.has_method("set_milestone_pool"):
		milestone_panel.set_milestone_pool(state.milestone_pool)
	if milestone_panel.has_method("set_players"):
		milestone_panel.set_players(state.players)
	if milestone_panel.has_method("set_global_view"):
		milestone_panel.set_global_view(true)
	if milestone_panel.has_method("set_rules"):
		milestone_panel.set_rules(state.rules)

	if _center_popup.is_valid():
		_center_popup.call(milestone_panel)
	milestone_panel.visible = true

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
