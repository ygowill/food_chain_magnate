class_name RightPanelDockControllerReplaceVisiblePanelTest
extends RefCounted

const GameRightPanelDockControllerClass = preload("res://ui/scenes/game/controllers/right_panel_dock_controller.gd")

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载测试节点）")

	var dock_host := Control.new()
	host.add_child(dock_host)
	var default_stack := Control.new()
	host.add_child(default_stack)
	var header_row := Control.new()
	host.add_child(header_row)
	var back_button := Button.new()
	host.add_child(back_button)
	var title_label := Label.new()
	host.add_child(title_label)
	var footer_row := Control.new()
	host.add_child(footer_row)
	var cancel_button := Button.new()
	host.add_child(cancel_button)
	var secondary_button := Button.new()
	host.add_child(secondary_button)
	var primary_button := Button.new()
	host.add_child(primary_button)

	var log_panel := Control.new()
	log_panel.name = "GameLogPanel"
	log_panel.visible = true
	dock_host.add_child(log_panel)

	var controller = GameRightPanelDockControllerClass.new(
		Callable(),
		Callable(),
		Callable(),
		log_panel,
		default_stack,
		dock_host,
		header_row,
		back_button,
		title_label,
		footer_row,
		cancel_button,
		secondary_button,
		primary_button,
		Callable(),
		func() -> Dictionary: return {}
	)

	var payday_panel := Control.new()
	payday_panel.name = "PaydayPanel"
	host.add_child(payday_panel)

	var ok := controller.dock_popup(payday_panel)
	if not ok:
		_cleanup([payday_panel, log_panel, primary_button, secondary_button, cancel_button, footer_row, title_label, back_button, header_row, default_stack, dock_host])
		return Result.failure("dock_popup 应成功")
	if log_panel.visible:
		_cleanup([payday_panel, log_panel, primary_button, secondary_button, cancel_button, footer_row, title_label, back_button, header_row, default_stack, dock_host])
		return Result.failure("新的 dock panel 打开后应隐藏旧日志面板")
	if payday_panel.get_parent() != dock_host or not payday_panel.visible:
		_cleanup([payday_panel, log_panel, primary_button, secondary_button, cancel_button, footer_row, title_label, back_button, header_row, default_stack, dock_host])
		return Result.failure("新的 dock panel 未正确显示在 DockHost 中")

	_cleanup([payday_panel, log_panel, primary_button, secondary_button, cancel_button, footer_row, title_label, back_button, header_row, default_stack, dock_host])
	return Result.success()

static func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()
