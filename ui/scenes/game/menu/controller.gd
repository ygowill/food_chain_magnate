# Game scene：菜单/确认弹窗控制器
# 负责：菜单按钮行为、保存/回放入口、返回主菜单确认弹窗（复用 ConfirmDialog）。
class_name GameMenuController
extends RefCounted

const UiZClass = preload("res://ui/utils/ui_z.gd")

var _host: Node = null

var _menu_debug_controller: Object = null
var _menu_dialog: Control = null
var _save_load_controller: Object = null

var _confirm_dialog_scene: PackedScene = null
var _confirm_dialog: ConfirmDialog = null
var _confirm_dialog_on_confirm: Callable = Callable()
var _confirm_dialog_on_cancel: Callable = Callable()

var _get_game_engine: Callable = Callable()
var _show_settings_dialog: Callable = Callable()
var _show_rules_dialog: Callable = Callable()
var _toggle_game_log: Callable = Callable()
var _show_milestone_panel: Callable = Callable()
var _toggle_distance_tool: Callable = Callable()
var _can_open_menu: Callable = Callable()

func _init(
	host: Node,
	menu_debug_controller: Object,
	menu_dialog: Control,
	confirm_dialog_scene: PackedScene,
	save_load_controller: Object,
	get_game_engine: Callable,
	show_settings_dialog: Callable,
	show_rules_dialog: Callable,
	toggle_game_log: Callable,
	show_milestone_panel: Callable,
	toggle_distance_tool: Callable,
	can_open_menu: Callable = Callable()
) -> void:
	_host = host
	_menu_debug_controller = menu_debug_controller
	_menu_dialog = menu_dialog
	_confirm_dialog_scene = confirm_dialog_scene
	_save_load_controller = save_load_controller
	_get_game_engine = get_game_engine
	_show_settings_dialog = show_settings_dialog
	_show_rules_dialog = show_rules_dialog
	_toggle_game_log = toggle_game_log
	_show_milestone_panel = show_milestone_panel
	_toggle_distance_tool = toggle_distance_tool
	_can_open_menu = can_open_menu

func dispose() -> void:
	_host = null
	_menu_debug_controller = null
	_menu_dialog = null
	_save_load_controller = null
	_confirm_dialog_scene = null
	_confirm_dialog = null
	_confirm_dialog_on_confirm = Callable()
	_confirm_dialog_on_cancel = Callable()
	_get_game_engine = Callable()
	_show_settings_dialog = Callable()
	_show_rules_dialog = Callable()
	_toggle_game_log = Callable()
	_show_milestone_panel = Callable()
	_toggle_distance_tool = Callable()
	_can_open_menu = Callable()

func is_menu_visible() -> bool:
	return is_instance_valid(_menu_dialog) and bool(_menu_dialog.visible)

func is_confirm_visible() -> bool:
	return _confirm_dialog != null and is_instance_valid(_confirm_dialog) and bool(_confirm_dialog.visible)

func handle_escape() -> bool:
	# 关闭顶层对话框
	if is_menu_visible():
		on_menu_dialog_close_requested()
		return true
	if is_confirm_visible():
		if _confirm_dialog.has_method("_on_cancel_pressed"):
			_confirm_dialog.call("_on_cancel_pressed")
		else:
			_confirm_dialog.hide()
		return true
	return false

func on_menu_pressed() -> void:
	if _can_open_menu.is_valid():
		var can_open_val = _can_open_menu.call()
		if can_open_val is bool and not bool(can_open_val):
			return
	if is_instance_valid(_menu_debug_controller) and _menu_debug_controller.has_method("open_menu"):
		_menu_debug_controller.call("open_menu")
	elif is_instance_valid(_menu_dialog):
		_menu_dialog.show()

func on_menu_dialog_close_requested() -> void:
	if is_instance_valid(_menu_debug_controller) and _menu_debug_controller.has_method("close_menu"):
		_menu_debug_controller.call("close_menu")
	elif is_instance_valid(_menu_dialog):
		_menu_dialog.hide()

func on_resume_pressed() -> void:
	if is_instance_valid(_menu_debug_controller) and _menu_debug_controller.has_method("resume"):
		_menu_debug_controller.call("resume")
	elif is_instance_valid(_menu_dialog):
		_menu_dialog.hide()

func on_save_pressed() -> void:
	if is_instance_valid(_save_load_controller) and _save_load_controller.has_method("open_for_save"):
		var engine = null
		if _get_game_engine.is_valid():
			var engine_val = _get_game_engine.call()
			engine = engine_val if engine_val is GameEngine else null
		_save_load_controller.call("open_for_save", engine)
	on_menu_dialog_close_requested()

func on_settings_pressed() -> void:
	if _show_settings_dialog.is_valid():
		_show_settings_dialog.call()
	on_menu_dialog_close_requested()

func on_rules_pressed() -> void:
	if _show_rules_dialog.is_valid():
		_show_rules_dialog.call()
	on_menu_dialog_close_requested()

func on_toggle_log_pressed() -> void:
	if _toggle_game_log.is_valid():
		_toggle_game_log.call()
	on_menu_dialog_close_requested()

func on_milestones_pressed() -> void:
	if _show_milestone_panel.is_valid():
		_show_milestone_panel.call()
	on_menu_dialog_close_requested()

func on_distance_tool_pressed() -> void:
	if _toggle_distance_tool.is_valid():
		_toggle_distance_tool.call()
	on_menu_dialog_close_requested()

func on_replay_pressed() -> void:
	GameLog.info("Game", "游戏内载入已禁用（仅主菜单可载入）")
	on_menu_dialog_close_requested()

func on_quit_to_menu_pressed() -> void:
	on_menu_dialog_close_requested()
	show_confirm(
		"返回主菜单",
		"确定要返回主菜单吗？\n未保存的进度将丢失。",
		Callable(self, "_confirm_quit_to_menu"),
		Callable(self, "_cancel_quit_to_menu")
	)

func show_confirm(title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable(), confirm_text: String = "确认", cancel_text: String = "取消") -> void:
	if _confirm_dialog_scene == null:
		return

	if _confirm_dialog == null or not is_instance_valid(_confirm_dialog):
		_confirm_dialog = _confirm_dialog_scene.instantiate()
		if is_instance_valid(_host) and _host.has_method("add_child"):
			_host.add_child(_confirm_dialog)
		if _confirm_dialog is Control:
			UiZClass.apply_absolute((_confirm_dialog as Control), UiZClass.CONFIRM_DIALOG)

		var confirmed_cb := Callable(self, "_on_confirm_dialog_confirmed")
		var cancelled_cb := Callable(self, "_on_confirm_dialog_cancelled")

		if _confirm_dialog.has_signal("confirmed"):
			var sig1 := Signal(_confirm_dialog, &"confirmed")
			if not sig1.is_connected(confirmed_cb):
				sig1.connect(confirmed_cb)
		if _confirm_dialog.has_signal("cancelled"):
			var sig2 := Signal(_confirm_dialog, &"cancelled")
			if not sig2.is_connected(cancelled_cb):
				sig2.connect(cancelled_cb)

	_confirm_dialog_on_confirm = on_confirm
	_confirm_dialog_on_cancel = on_cancel
	if _confirm_dialog.has_method("setup"):
		_confirm_dialog.call("setup", title, message, confirm_text, cancel_text)
	if _confirm_dialog.has_method("show_dialog"):
		_confirm_dialog.call("show_dialog")
	else:
		_confirm_dialog.show()

func _on_confirm_dialog_confirmed() -> void:
	var cb := _confirm_dialog_on_confirm
	_confirm_dialog_on_confirm = Callable()
	_confirm_dialog_on_cancel = Callable()
	if cb.is_valid():
		cb.call()

func _on_confirm_dialog_cancelled() -> void:
	var cb := _confirm_dialog_on_cancel
	_confirm_dialog_on_confirm = Callable()
	_confirm_dialog_on_cancel = Callable()
	if cb.is_valid():
		cb.call()

func _confirm_quit_to_menu() -> void:
	if is_instance_valid(_menu_debug_controller) and _menu_debug_controller.has_method("quit_to_menu"):
		_menu_debug_controller.call("quit_to_menu")
	else:
		Globals.reset_game_config()
		SceneManager.goto_main_menu()

func _cancel_quit_to_menu() -> void:
	if is_instance_valid(_menu_debug_controller) and _menu_debug_controller.has_method("open_menu"):
		_menu_debug_controller.call("open_menu")
	elif is_instance_valid(_menu_dialog):
		_menu_dialog.show()
