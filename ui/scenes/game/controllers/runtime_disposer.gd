# Game scene：集中释放 RefCounted 控制器（用于 headless 测试退出时降低泄漏噪声）
extends RefCounted

static func dispose_runtime(game) -> void:
	if game == null:
		return

	# 释放 RefCounted 控制器（避免 headless 测试退出时资源泄漏）
	if game._panel_controller != null and game._panel_controller.has_method("dispose"):
		game._panel_controller.dispose()
	game._panel_controller = null

	if game._map_controller != null and game._map_controller.has_method("dispose"):
		game._map_controller.dispose()
	game._map_controller = null

	if game._overlay_controller != null and game._overlay_controller.has_method("dispose"):
		game._overlay_controller.dispose()
	game._overlay_controller = null

	if game._input_controller != null and game._input_controller.has_method("dispose"):
		game._input_controller.dispose()
	game._input_controller = null

	if game._map_mode_bar_controller != null and game._map_mode_bar_controller.has_method("dispose"):
		game._map_mode_bar_controller.dispose()
	game._map_mode_bar_controller = null

	if game._menu_controller != null and game._menu_controller.has_method("dispose"):
		game._menu_controller.dispose()
	game._menu_controller = null

	if game._log_dock_controller != null and game._log_dock_controller.has_method("dispose"):
		game._log_dock_controller.dispose()
	game._log_dock_controller = null

	if game._procurement_log_preview_controller != null and game._procurement_log_preview_controller.has_method("dispose"):
		game._procurement_log_preview_controller.dispose()
	game._procurement_log_preview_controller = null

	if game._warmup_controller != null and game._warmup_controller.has_method("dispose"):
		game._warmup_controller.dispose()
	game._warmup_controller = null

	if game._menu_debug_controller != null and game._menu_debug_controller.has_method("dispose"):
		game._menu_debug_controller.dispose()
	game._menu_debug_controller = null

	if game._save_load_controller != null and game._save_load_controller.has_method("dispose"):
		game._save_load_controller.dispose()
	game._save_load_controller = null

	if game._layout_controller != null and game._layout_controller.has_method("dispose"):
		game._layout_controller.dispose()
	game._layout_controller = null

	if game._right_panel_dock_controller != null and game._right_panel_dock_controller.has_method("dispose"):
		game._right_panel_dock_controller.dispose()
	game._right_panel_dock_controller = null

	if game._online_resync_controller != null and game._online_resync_controller.has_method("dispose"):
		game._online_resync_controller.dispose()
	game._online_resync_controller = null

	if game._startup_online_resume_controller != null and game._startup_online_resume_controller.has_method("dispose"):
		game._startup_online_resume_controller.dispose()
	game._startup_online_resume_controller = null

	if game._timeline_controller != null and game._timeline_controller.has_method("dispose"):
		game._timeline_controller.dispose()
	game._timeline_controller = null

	if game._debug_panel_controller != null and game._debug_panel_controller.has_method("dispose"):
		game._debug_panel_controller.dispose()
	game._debug_panel_controller = null

	if game._ui_sync_controller != null and game._ui_sync_controller.has_method("dispose"):
		game._ui_sync_controller.dispose()
	game._ui_sync_controller = null

	if game._command_controller != null and game._command_controller.has_method("dispose"):
		game._command_controller.dispose()
	game._command_controller = null

	var engine = game.game_engine
	if engine != null and engine.has_method("dispose"):
		engine.dispose()

	if Globals != null and Globals.current_game_engine == engine:
		Globals.current_game_engine = null
	if Globals != null:
		Globals.is_game_active = false

	game.game_engine = null
