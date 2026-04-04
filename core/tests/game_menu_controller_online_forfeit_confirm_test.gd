# Game 菜单：联机返回主菜单前应明确提示将会认输并退出
class_name GameMenuControllerOnlineForfeitConfirmTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/menu/controller.gd")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")


class _MockMenuDebugController:
	extends RefCounted

	var close_menu_count: int = 0
	var will_forfeit_on_quit: bool = false

	func close_menu() -> void:
		close_menu_count += 1

	func will_forfeit_online_match_on_quit() -> bool:
		return bool(will_forfeit_on_quit)


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
