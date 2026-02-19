# Game scene：控制器构建器（从 game.gd 抽取）
# 目的：减少 game.gd 体积与合并冲突，将“控制器 new + 信号连接”集中管理。
class_name GameControllersBuilder
extends RefCounted

const GameMenuDebugControllerClass = preload("res://ui/scenes/game/menu/debug_controller.gd")
const GameMenuControllerClass = preload("res://ui/scenes/game/menu/controller.gd")
const GameSaveLoadControllerClass = preload("res://ui/scenes/game/game_save_load_controller.gd")
const GameLayoutControllerClass = preload("res://ui/scenes/game/game_layout_controller.gd")
const GameRightPanelDockControllerClass = preload("res://ui/scenes/game/game_right_panel_dock_controller.gd")
const GameUiSyncControllerClass = preload("res://ui/scenes/game/game_ui_sync_controller.gd")
const GameCommandControllerClass = preload("res://ui/scenes/game/game_command_controller.gd")
const GameInputControllerClass = preload("res://ui/scenes/game/game_input_controller.gd")
const GameLogDockControllerClass = preload("res://ui/scenes/game/game_log_dock_controller.gd")
const GameBackgroundWarmupControllerClass = preload("res://ui/scenes/game/game_background_warmup_controller.gd")
const GameDebugPanelControllerClass = preload("res://ui/scenes/game/game_debug_panel_controller.gd")
const GameOverlayControllerClass = preload("res://ui/scenes/game/overlay/controller.gd")
const GameMapInteractionControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")
const GameMapModeBarControllerClass = preload("res://ui/scenes/game/map_interaction/mode_bar_controller.gd")
const GamePanelControllerClass = preload("res://ui/scenes/game/panel/controller.gd")
const GameTimelineControllerClass = preload("res://ui/scenes/game/timeline/controller.gd")
const GameProcurementLogPreviewControllerClass = preload("res://ui/scenes/game/panel/procurement/log_preview_controller.gd")

const DebugPanelScene = preload("res://ui/scenes/debug/debug_panel.tscn")
const ConfirmDialogScene = preload("res://ui/dialogs/confirm_dialog.tscn")
const SaveLoadDialogScript = preload("res://ui/dialogs/save_load_dialog.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")

static func build(host: Control, refs: Dictionary, callbacks: Dictionary, startup_replay_from_main_menu: bool) -> Dictionary:
	var out := {}
	if host == null or not is_instance_valid(host):
		return out

	var layout_controller = GameLayoutControllerClass.new(
		host,
		refs.get("round_label", null),
		refs.get("phase_track", null),
		refs.get("bank_label", null),
		refs.get("toggle_left_panel_button", null),
		refs.get("toggle_right_panel_button", null),
		refs.get("toggle_bottom_panel_button", null),
		refs.get("main_content", null),
		refs.get("center_split", null),
		refs.get("left_area", null),
		refs.get("left_panel", null),
		refs.get("game_log_panel", null),
		refs.get("bottom_panel", null),
		refs.get("right_panel_root", null),
		refs.get("player_panel", null),
		refs.get("inventory_panel", null)
	)
	out["layout_controller"] = layout_controller

	var game_log_panel = refs.get("game_log_panel", null)
	var map_view = refs.get("map_view", null)
	var map_canvas = refs.get("map_canvas", null)

	var overlay_controller = GameOverlayControllerClass.new(host, map_view, map_canvas, game_log_panel)
	overlay_controller.initialize()
	overlay_controller.set_execute_command(callbacks.get("execute_command", Callable()))
	out["overlay_controller"] = overlay_controller

	var map_controller = GameMapInteractionControllerClass.new(host, map_canvas, overlay_controller)
	map_controller.connect_signals()
	out["map_controller"] = map_controller

	var map_mode_bar_controller = GameMapModeBarControllerClass.new(refs.get("map_mode_bar", null))
	out["map_mode_bar_controller"] = map_mode_bar_controller
	UiSignalHelpersClass.safe_connect(map_controller, "mode_changed", Callable(map_mode_bar_controller, "on_map_mode_changed"))

	var panel_controller = GamePanelControllerClass.new(
		host,
		map_controller,
		overlay_controller,
		callbacks.get("execute_command", Callable()),
		callbacks.get("update_ui", Callable())
	)
	panel_controller.connect_signals(
		refs.get("action_panel", null),
		refs.get("action_flow_controls", null),
		refs.get("turn_order_track", null),
		refs.get("hand_area", null),
		refs.get("company_structure", null)
	)
	out["panel_controller"] = panel_controller

	var warmup_controller = GameBackgroundWarmupControllerClass.new(
		host,
		callbacks.get("get_game_engine", Callable()),
		panel_controller,
		map_canvas
	)
	out["warmup_controller"] = warmup_controller

	var menu_dialog = refs.get("menu_dialog", null)
	var menu_debug_controller = GameMenuDebugControllerClass.new(host, menu_dialog)
	out["menu_debug_controller"] = menu_debug_controller

	var save_load_controller = GameSaveLoadControllerClass.new(host, SaveLoadDialogScript, callbacks.get("start_replay_from_file", Callable()))
	out["save_load_controller"] = save_load_controller

	var menu_controller = GameMenuControllerClass.new(
		host,
		menu_debug_controller,
		menu_dialog,
		ConfirmDialogScene,
		save_load_controller,
		callbacks.get("get_game_engine", Callable()),
		callbacks.get("show_settings_dialog", Callable()),
		callbacks.get("show_rules_dialog", Callable()),
		callbacks.get("toggle_game_log", Callable()),
		callbacks.get("show_milestone_panel", Callable()),
		callbacks.get("toggle_distance_tool", Callable()),
		callbacks.get("can_open_menu", Callable())
	)
	out["menu_controller"] = menu_controller

	var right_panel_dock_controller = GameRightPanelDockControllerClass.new(
		callbacks.get("ensure_right_panel_visible", Callable()),
		callbacks.get("cancel_right_panel_docked_panel", Callable()),
		callbacks.get("toggle_game_log", Callable()),
		game_log_panel,
		refs.get("right_panel_default_stack", null),
		refs.get("right_panel_dock_host", null),
		refs.get("right_panel_header_row", null),
		refs.get("right_panel_back_button", null),
		refs.get("right_panel_title_label", null),
		refs.get("right_panel_footer_row", null),
		refs.get("right_panel_footer_cancel_button", null),
		refs.get("right_panel_footer_secondary_button", null),
		refs.get("right_panel_footer_primary_button", null),
		Callable(panel_controller, "on_action_requested"),
		Callable(refs.get("action_panel", null), "get_flow_controls_config")
	)
	out["right_panel_dock_controller"] = right_panel_dock_controller

	var input_controller = GameInputControllerClass.new(
		menu_controller,
		overlay_controller,
		panel_controller,
		map_controller,
		right_panel_dock_controller,
		refs.get("right_panel_footer_row", null),
		refs.get("right_panel_footer_secondary_button", null),
		refs.get("right_panel_footer_primary_button", null)
	)
	out["input_controller"] = input_controller

	UiSignalHelpersClass.safe_connect(game_log_panel, "close_requested", callbacks.get("toggle_game_log", Callable()))

	var timeline_controller = GameTimelineControllerClass.new(
		host,
		game_log_panel,
		refs.get("action_panel", null),
		callbacks.get("get_game_engine", Callable()),
		callbacks.get("set_active_game_engine", Callable()),
		callbacks.get("update_ui", Callable()),
		callbacks.get("show_confirm", Callable()),
		callbacks.get("show_game_log_panel_in_right_panel", Callable()),
		callbacks.get("open_replay_load_dialog", Callable()),
		callbacks.get("is_online_resync_in_progress", Callable())
	)
	timeline_controller.set_startup_replay_from_main_menu(startup_replay_from_main_menu)
	timeline_controller.initialize()
	out["timeline_controller"] = timeline_controller

	var procurement_log_preview_controller = GameProcurementLogPreviewControllerClass.new(
		callbacks.get("get_game_engine", Callable()),
		overlay_controller,
		game_log_panel,
		timeline_controller
	)
	out["procurement_log_preview_controller"] = procurement_log_preview_controller
	UiSignalHelpersClass.safe_connect(game_log_panel, "replay_toggle_changed", Callable(procurement_log_preview_controller, "on_replay_toggle_changed"))
	UiSignalHelpersClass.safe_connect(game_log_panel, "log_entry_hovered", Callable(procurement_log_preview_controller, "on_log_entry_hovered"))
	UiSignalHelpersClass.safe_connect(game_log_panel, "log_entry_clicked", Callable(procurement_log_preview_controller, "on_log_entry_clicked"))

	var log_dock_controller = GameLogDockControllerClass.new(
		callbacks.get("ensure_left_area_visible", Callable()),
		callbacks.get("ensure_right_panel_visible", Callable()),
		callbacks.get("cancel_right_panel_docked_panel", Callable()),
		callbacks.get("sync_right_panel_docked_view", Callable()),
		callbacks.get("dock_popup_into_right_panel", Callable()),
		game_log_panel,
		refs.get("right_panel_dock_host", null),
		timeline_controller
	)
	out["log_dock_controller"] = log_dock_controller

	var ui_sync_controller = GameUiSyncControllerClass.new(
		callbacks.get("get_game_engine", Callable()),
		callbacks.get("update_ui", Callable()),
		callbacks.get("sync_right_panel_docked_view", Callable()),
		refs.get("round_label", null),
		refs.get("phase_track", null),
		refs.get("bank_label", null),
		refs.get("bank_break_tag", null),
		game_log_panel,
		map_view,
		panel_controller,
		overlay_controller,
		timeline_controller
	)
	overlay_controller.set_ui_sync_controller(ui_sync_controller)
	overlay_controller.set_player_panel(refs.get("left_panel", null))
	out["ui_sync_controller"] = ui_sync_controller

	var debug_panel_controller = GameDebugPanelControllerClass.new(
		host,
		DebugPanelScene,
		callbacks.get("get_game_engine", Callable()),
		callbacks.get("on_debug_command_executed", Callable()),
		ui_sync_controller
	)
	out["debug_panel_controller"] = debug_panel_controller

	var command_controller = GameCommandControllerClass.new(
		callbacks.get("get_game_engine", Callable()),
		callbacks.get("update_ui", Callable()),
		callbacks.get("show_confirm", Callable()),
		timeline_controller,
		panel_controller,
		game_log_panel
	)
	out["command_controller"] = command_controller

	return out

