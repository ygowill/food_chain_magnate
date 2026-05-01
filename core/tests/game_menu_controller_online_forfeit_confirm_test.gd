# Game 菜单：联机返回主菜单前应明确提示将会认输并退出
class_name GameMenuControllerOnlineForfeitConfirmTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/menu/controller.gd")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const UiZClass = preload("res://ui/utils/ui_z.gd")


class _MockMenuDebugController:
	extends RefCounted

	var close_menu_count: int = 0
	var open_menu_count: int = 0
	var will_forfeit_on_quit: bool = false
	var online_game_over_return_to_lobby: bool = false
	var game_over: bool = false

	func open_menu() -> void:
		open_menu_count += 1

	func close_menu() -> void:
		close_menu_count += 1

	func will_forfeit_online_match_on_quit() -> bool:
		return bool(will_forfeit_on_quit)

	func is_online_game_over_return_to_lobby() -> bool:
		return bool(online_game_over_return_to_lobby)

	func is_game_over() -> bool:
		return bool(game_over)


static func run() -> Result:
	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")

	var host := Control.new()
	tree.root.add_child(host)
	var menu_dialog := Control.new()
	host.add_child(menu_dialog)

	var mock_debug := _MockMenuDebugController.new()
	mock_debug.will_forfeit_on_quit = true

	var controller = ControllerClass.new(
		host,
		mock_debug,
		menu_dialog,
		ConfirmDialogScene,
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable()
	)

	controller.on_quit_to_menu_pressed()
	await tree.process_frame

	if mock_debug.close_menu_count != 1:
		return await _cleanup_and_fail(tree, host, controller, "打开确认框前应先关闭菜单")

	var dialog = controller._confirm_dialog
	if dialog == null or not is_instance_valid(dialog):
		return await _cleanup_and_fail(tree, host, controller, "未弹出返回主菜单确认框")
	if dialog.message_label == null or dialog.message_label.text.find("认输并退出") < 0:
		return await _cleanup_and_fail(tree, host, controller, "联机确认框未提示将会认输并退出: %s" % str(dialog.message_label.text if dialog.message_label != null else ""))
	if dialog.confirm_btn == null or str(dialog.confirm_btn.text) != "认输并退出":
		return await _cleanup_and_fail(tree, host, controller, "联机确认按钮文案错误: %s" % str(dialog.confirm_btn.text if dialog.confirm_btn != null else ""))

	await _cleanup(tree, host, controller)
	var game_over_confirm_result := await _run_online_game_over_return_confirm(tree)
	if not game_over_confirm_result.ok:
		return game_over_confirm_result
	return Result.success()


static func _run_online_game_over_return_confirm(tree: SceneTree) -> Result:
	var host := Control.new()
	tree.root.add_child(host)
	var menu_dialog := Control.new()
	host.add_child(menu_dialog)
	var phase_modal := Control.new()
	host.add_child(phase_modal)
	var box := VBoxContainer.new()
	box.name = "VBoxContainer"
	menu_dialog.add_child(box)
	var quit_btn := Button.new()
	quit_btn.name = "QuitToMenuButton"
	quit_btn.text = "返回主菜单"
	box.add_child(quit_btn)

	var mock_debug := _MockMenuDebugController.new()
	mock_debug.online_game_over_return_to_lobby = true
	mock_debug.game_over = true

	var controller = ControllerClass.new(
		host,
		mock_debug,
		menu_dialog,
		ConfirmDialogScene,
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable()
	)

	controller.on_menu_pressed()
	if str(quit_btn.text) != "返回房间列表":
		return await _cleanup_and_fail(tree, host, controller, "GameOver 联机菜单按钮应显示返回房间列表，实际: %s" % str(quit_btn.text))
	if mock_debug.open_menu_count != 1:
		return await _cleanup_and_fail(tree, host, controller, "打开菜单应委托 menu_debug_controller.open_menu")
	if menu_dialog.get_index() <= phase_modal.get_index():
		return await _cleanup_and_fail(tree, host, controller, "打开菜单时 MenuDialog 应移到阶段弹窗之后以接收点击")
	if menu_dialog.z_as_relative or menu_dialog.z_index < UiZClass.MENU:
		return await _cleanup_and_fail(tree, host, controller, "打开菜单时 MenuDialog 应使用最高菜单层级")

	controller.on_quit_to_menu_pressed()
	await tree.process_frame

	if mock_debug.close_menu_count != 1:
		return await _cleanup_and_fail(tree, host, controller, "打开 GameOver 返回确认框前应先关闭菜单")

	var dialog = controller._confirm_dialog
	if dialog == null or not is_instance_valid(dialog):
		return await _cleanup_and_fail(tree, host, controller, "未弹出返回房间列表确认框")
	if dialog.title_label == null or str(dialog.title_label.text) != "返回房间列表":
		return await _cleanup_and_fail(tree, host, controller, "GameOver 联机确认框标题错误: %s" % str(dialog.title_label.text if dialog.title_label != null else ""))
	if dialog.message_label == null or dialog.message_label.text.find("返回房间列表") < 0:
		return await _cleanup_and_fail(tree, host, controller, "GameOver 联机确认框未提示返回房间列表: %s" % str(dialog.message_label.text if dialog.message_label != null else ""))
	if dialog.message_label != null and dialog.message_label.text.find("认输") >= 0:
		return await _cleanup_and_fail(tree, host, controller, "GameOver 联机确认框不应提示认输: %s" % str(dialog.message_label.text))
	if dialog.confirm_btn == null or str(dialog.confirm_btn.text) != "返回房间列表":
		return await _cleanup_and_fail(tree, host, controller, "GameOver 联机确认按钮文案错误: %s" % str(dialog.confirm_btn.text if dialog.confirm_btn != null else ""))

	await _cleanup(tree, host, controller)
	return Result.success()


static func _cleanup(tree: SceneTree, host: Node, controller) -> void:
	if controller != null and controller.has_method("dispose"):
		controller.dispose()
	if host != null and is_instance_valid(host):
		host.queue_free()
	if tree != null:
		await tree.process_frame


static func _cleanup_and_fail(tree: SceneTree, host: Node, controller, message: String) -> Result:
	await _cleanup(tree, host, controller)
	return Result.failure(message)
