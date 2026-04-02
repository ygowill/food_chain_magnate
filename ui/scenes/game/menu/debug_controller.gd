# Game scene：菜单/调试控制器
# 负责：菜单按钮、保存/返回主菜单
class_name GameMenuDebugController
extends RefCounted

var _scene = null
var _menu_dialog = null

func _init(scene, menu_dialog) -> void:
	_scene = scene
	_menu_dialog = menu_dialog

func open_menu() -> void:
	GameLog.info("Game", "打开游戏菜单")
	if is_instance_valid(_menu_dialog):
		_menu_dialog.show()

func close_menu() -> void:
	if is_instance_valid(_menu_dialog):
		_menu_dialog.hide()

func resume() -> void:
	GameLog.info("Game", "继续游戏")
	close_menu()

func save_game() -> void:
	GameLog.info("Game", "保存游戏")
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		GameLog.warn("Game", "游戏引擎未初始化，无法保存")
		close_menu()
		return

	var path := "user://savegame.json"
	var save_result = engine.save_to_file(path)
	if not save_result.ok:
		GameLog.error("Game", "保存失败: %s" % save_result.error)
	else:
		GameLog.info("Game", "已保存到: %s" % path)
	close_menu()

static func cleanup_online_state_before_quit() -> void:
	var should_reset := false
	if NetContext != null:
		should_reset = int(NetContext.mode) == int(NetContext.Mode.ONLINE_CLIENT)
		if not should_reset and NetContext.has_method("has_online_resume_context"):
			should_reset = bool(NetContext.has_online_resume_context())
	if not should_reset:
		return
	if NetClient != null:
		NetClient.shutdown(true)
		return
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

func quit_to_menu() -> void:
	GameLog.info("Game", "返回主菜单")
	cleanup_online_state_before_quit()
	Globals.reset_game_config()
	SceneManager.goto_main_menu()
