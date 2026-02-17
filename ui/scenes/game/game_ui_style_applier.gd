# Game scene：UI 样式集中应用（避免主脚本堆积样式细节）
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

static func apply_all(game) -> void:
	if game == null:
		return
	_apply_menu_dialog_styles(game)
	_apply_topbar_button_styles(game)
	_disable_removed_panel_toggles(game)
	_apply_status_bar_styles(game)

static func _apply_menu_dialog_styles(game) -> void:
	if is_instance_valid(game.menu_dialog):
		game.menu_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
		game.menu_dialog.z_index = 1200
	if is_instance_valid(game.menu_dialog_overlay):
		game.menu_dialog_overlay.color = Color(0.05, 0.04, 0.03, 0.75)
		game.menu_dialog_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStylesClass.apply_dialog_surface(game.menu_dialog_background_panel)
	UiStylesClass.apply_button_primary(game.menu_resume_button)
	UiStylesClass.apply_button_primary(game.menu_save_button)
	UiStylesClass.apply_button_primary(game.menu_rules_button)
	UiStylesClass.apply_button_primary(game.menu_settings_button)
	UiStylesClass.apply_button_primary(game.toggle_bottom_panel_button)
	UiStylesClass.apply_button_primary(game.menu_quit_to_menu_button)

static func _apply_topbar_button_styles(game) -> void:
	var button_paths := [
		"UIRoot/TopBar/AdvancePhaseButton",
		"UIRoot/TopBar/AdvanceSubPhaseButton",
		"UIRoot/TopBar/ToggleLeftPanelButton",
		"UIRoot/TopBar/ToggleRightPanelButton",
		"UIRoot/TopBar/MenuButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/EmployeeTreeButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/LogButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/MilestonesButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/ReserveAreaButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/DistanceToolButton",
		"UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/SettingsButton",
	]
	for path in button_paths:
		var btn = game.get_node_or_null(path)
		if btn is Button:
			UiStylesClass.apply_button_secondary(btn)

static func _disable_removed_panel_toggles(game) -> void:
	# 改造：不允许隐藏信息/隐藏操作，也不允许关闭右侧动作区（只允许通过“跳过”推进动作流）。
	for btn in [game.toggle_left_panel_button, game.toggle_right_panel_button, game.right_panel_back_button, game.right_panel_close_button]:
		if btn == null or not is_instance_valid(btn):
			continue
		btn.visible = false
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _apply_status_bar_styles(game) -> void:
	UiStylesClass.apply_status_panel(game.status_bar)
	UiStylesClass.apply_break_tag(game.bank_break_tag)
	# Icon labels - accent colors
	var icon_styles: Array[Array] = [
		["UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankIconLabel", Color(0.72, 0.62, 0.25)],
		["UIRoot/TopBar/StatusBar/StatusContent/RoundSection/RoundIconLabel", Color(0.35, 0.55, 0.75)],
	]
	for entry in icon_styles:
		var lbl = game.get_node_or_null(str(entry[0]))
		if lbl is Label:
			(lbl as Label).add_theme_color_override("font_color", entry[1] as Color)
			(lbl as Label).add_theme_font_size_override("font_size", 17)
	# Bank title label - same size as value labels
	var title_lbl = game.get_node_or_null("UIRoot/TopBar/StatusBar/StatusContent/BankSection/BankTitleLabel")
	if title_lbl is Label:
		UiStylesClass.apply_label_dark(title_lbl)
		(title_lbl as Label).add_theme_font_size_override("font_size", 17)
	# Value labels - primary, larger
	for lbl in [game.round_label, game.bank_label]:
		if lbl is Label:
			UiStylesClass.apply_label_dark(lbl)
			(lbl as Label).add_theme_font_size_override("font_size", 17)
	# Phase track - 自定义绘制，初始字号
	if is_instance_valid(game.phase_track) and game.phase_track.has_method("set_font_size"):
		game.phase_track.set_font_size(16)

