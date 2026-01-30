# 轻量 UI 样式工具：通过 local override 统一弹窗/按钮的基础视觉。
# - 不依赖全局 Theme，避免影响游戏内其它复杂组件。
# - 适用于 Window 弹窗、菜单面板、动态创建的按钮等。
class_name UiStyles
extends RefCounted

const _DIALOG_SURFACE: StyleBox = preload("res://ui/themes/dialog_surface.tres")

const _BTN_PRIMARY_NORMAL: StyleBox = preload("res://ui/themes/button_primary_normal.tres")
const _BTN_PRIMARY_HOVER: StyleBox = preload("res://ui/themes/button_primary_hover.tres")
const _BTN_PRIMARY_PRESSED: StyleBox = preload("res://ui/themes/button_primary_pressed.tres")
const _BTN_PRIMARY_DISABLED: StyleBox = preload("res://ui/themes/button_primary_disabled.tres")

const _BTN_SECONDARY_NORMAL: StyleBox = preload("res://ui/themes/button_secondary_normal.tres")
const _BTN_SECONDARY_HOVER: StyleBox = preload("res://ui/themes/button_secondary_hover.tres")
const _BTN_SECONDARY_PRESSED: StyleBox = preload("res://ui/themes/button_secondary_pressed.tres")
const _BTN_SECONDARY_DISABLED: StyleBox = preload("res://ui/themes/button_secondary_disabled.tres")

static func apply_dialog_surface(panel: Control) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _DIALOG_SURFACE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func apply_button_primary(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _BTN_PRIMARY_NORMAL)
	button.add_theme_stylebox_override("hover", _BTN_PRIMARY_HOVER)
	button.add_theme_stylebox_override("pressed", _BTN_PRIMARY_PRESSED)
	button.add_theme_stylebox_override("disabled", _BTN_PRIMARY_DISABLED)
	button.add_theme_color_override("font_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))

static func apply_button_secondary(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _BTN_SECONDARY_NORMAL)
	button.add_theme_stylebox_override("hover", _BTN_SECONDARY_HOVER)
	button.add_theme_stylebox_override("pressed", _BTN_SECONDARY_PRESSED)
	button.add_theme_stylebox_override("disabled", _BTN_SECONDARY_DISABLED)
	button.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 0.98, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.95, 0.96, 0.98))
	button.add_theme_color_override("font_disabled_color", Color(0.95, 0.96, 0.98, 0.5))

