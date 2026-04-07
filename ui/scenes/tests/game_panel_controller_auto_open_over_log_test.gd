class_name GamePanelControllerAutoOpenOverLogTest
extends RefCounted

const GamePanelControllerClass = preload("res://ui/scenes/game/panel/controller.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

class _ActionPanelSpy:
	extends RefCounted

	func get_guided_action_id() -> String:
		return "fire"

	func is_globally_disabled() -> bool:
		return false

class _EndPanelsSpy:
	extends RefCounted

	var show_payday_panel_count: int = 0

	func show_payday_panel() -> void:
		show_payday_panel_count += 1

class _FakeScene:
	extends Node

	var action_panel = null
	var action_flow_controls = null
	var game_log_panel = null

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载测试节点）")

	var scene := _FakeScene.new()
	scene.action_panel = _ActionPanelSpy.new()
	host.add_child(scene)

	var ui_root := Node.new()
	ui_root.name = "UIRoot"
	scene.add_child(ui_root)
	var main_content := Node.new()
	main_content.name = "MainContent"
	ui_root.add_child(main_content)
	var center_split := Node.new()
	center_split.name = "CenterSplit"
	main_content.add_child(center_split)
	var right_panel := Node.new()
	right_panel.name = "RightPanel"
	center_split.add_child(right_panel)
	var dock_host := Control.new()
	dock_host.name = "DockHost"
	right_panel.add_child(dock_host)

	scene.game_log_panel = Control.new()
	scene.game_log_panel.name = "GameLogPanel"
	scene.game_log_panel.visible = true
	dock_host.add_child(scene.game_log_panel)

	var controller = GamePanelControllerClass.new(scene, null, null, Callable(), Callable())
	var end_panels := _EndPanelsSpy.new()
	controller._end_panels = end_panels

	controller._auto_open_guided_action_ui(GameStateClass.new())
	if end_panels.show_payday_panel_count != 1:
		if controller != null and controller.has_method("dispose"):
			controller.dispose()
		_cleanup([scene])
		return Result.failure("日志面板不应阻塞 Payday 自动打开，实际 show_count=%d" % end_panels.show_payday_panel_count)

	if controller != null and controller.has_method("dispose"):
		controller.dispose()
	_cleanup([scene])
	return Result.success()

static func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()
