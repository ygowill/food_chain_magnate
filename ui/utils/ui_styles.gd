# 轻量 UI 样式工具：通过 local override 统一弹窗/按钮的基础视觉。
# - 不依赖全局 Theme，避免影响游戏内其它复杂组件。
# - 适用于 Window 弹窗、菜单面板、动态创建的按钮等。
class_name UiStyles
extends RefCounted

const _DIALOG_SURFACE: StyleBox = preload("res://ui/themes/dialog_surface.tres")
const _POSTER_INNER_BORDER: StyleBox = preload("res://ui/themes/poster_inner_border.tres")
const _PANEL_POSTER: StyleBox = preload("res://ui/themes/panel_poster.tres")
const _PANEL_POSTER_ALT: StyleBox = preload("res://ui/themes/panel_poster_alt.tres")
const _OVERLAY_DIM: StyleBox = preload("res://ui/themes/overlay_dim.tres")

const _BTN_PRIMARY_NORMAL: StyleBox = preload("res://ui/themes/button_primary_normal.tres")
const _BTN_PRIMARY_HOVER: StyleBox = preload("res://ui/themes/button_primary_hover.tres")
const _BTN_PRIMARY_PRESSED: StyleBox = preload("res://ui/themes/button_primary_pressed.tres")
const _BTN_PRIMARY_DISABLED: StyleBox = preload("res://ui/themes/button_primary_disabled.tres")

const _BTN_SECONDARY_NORMAL: StyleBox = preload("res://ui/themes/button_secondary_normal.tres")
const _BTN_SECONDARY_HOVER: StyleBox = preload("res://ui/themes/button_secondary_hover.tres")
const _BTN_SECONDARY_PRESSED: StyleBox = preload("res://ui/themes/button_secondary_pressed.tres")
const _BTN_SECONDARY_DISABLED: StyleBox = preload("res://ui/themes/button_secondary_disabled.tres")

const _TILED_TEXTURE_SHADER: Shader = preload("res://ui/shaders/tiled_texture.gdshader")
const _VIGNETTE_SHADER: Shader = preload("res://ui/shaders/vignette.gdshader")

const WALL_TEXTURE_PATHS: PackedStringArray = [
	"res://assets/textures/wall_texture.png",
	"res://assets/textures/wall_bg.png",
]
const PAPER_TEXTURE_PATHS: PackedStringArray = [
	"res://assets/textures/paper_texture.png",
	"res://assets/textures/old_paper.png",
]

const COLOR_TEXT_PRIMARY := Color(0.17, 0.13, 0.09, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.45, 0.35, 1.0)
const COLOR_TEXT_HINT := Color(0.73, 0.23, 0.18, 0.85)
const COLOR_TEXT_ERROR := Color(0.73, 0.23, 0.18, 1.0)
const COLOR_TEXT_SUCCESS := Color(0.28, 0.55, 0.22, 1.0)
const COLOR_FIELD_BG := Color(0.95, 0.91, 0.82, 0.9)
const COLOR_FIELD_BG_DISABLED := Color(0.92, 0.88, 0.78, 0.7)
const COLOR_FIELD_BORDER := Color(0.17, 0.13, 0.09, 0.26)
const COLOR_FIELD_BORDER_FOCUS := Color(0.73, 0.23, 0.18, 0.72)

static func apply_dialog_surface(panel: Control) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _DIALOG_SURFACE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func apply_poster_inner_border(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _POSTER_INNER_BORDER)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func apply_tiled_texture(node: Control, texture_paths: PackedStringArray, tile_scale: float = 3.0, tint: Color = Color(0.93, 0.88, 0.75, 1.0)) -> void:
	if node == null:
		return
	var tex: Texture2D = _load_first_valid_texture(texture_paths)
	var mat := ShaderMaterial.new()
	mat.shader = _TILED_TEXTURE_SHADER
	if tex != null:
		mat.set_shader_parameter("pattern_tex", tex)
	mat.set_shader_parameter("tile_scale", tile_scale)
	mat.set_shader_parameter("tint_color", tint)
	node.material = mat
	if tex == null:
		# Fallback: 没有纹理贴图时使用纯色
		if node is ColorRect:
			node.color = tint
		elif node is TextureRect:
			node.self_modulate = tint

static func apply_vignette(node: ColorRect, intensity: float = 0.45, smoothness: float = 0.5) -> void:
	if node == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _VIGNETTE_SHADER
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("smoothness", smoothness)
	node.material = mat
	node.color = Color(0, 0, 0, 0)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func apply_button_primary(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _BTN_PRIMARY_NORMAL)
	button.add_theme_stylebox_override("hover", _BTN_PRIMARY_HOVER)
	button.add_theme_stylebox_override("pressed", _BTN_PRIMARY_PRESSED)
	button.add_theme_stylebox_override("disabled", _BTN_PRIMARY_DISABLED)
	button.add_theme_color_override("font_color", Color(0.97, 0.93, 0.82))
	button.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.86))
	button.add_theme_color_override("font_pressed_color", Color(0.97, 0.93, 0.82))
	button.add_theme_color_override("font_disabled_color", Color(0.97, 0.93, 0.82, 0.55))

static func apply_button_secondary(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _BTN_SECONDARY_NORMAL)
	button.add_theme_stylebox_override("hover", _BTN_SECONDARY_HOVER)
	button.add_theme_stylebox_override("pressed", _BTN_SECONDARY_PRESSED)
	button.add_theme_stylebox_override("disabled", _BTN_SECONDARY_DISABLED)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.06))
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Color(COLOR_TEXT_PRIMARY.r, COLOR_TEXT_PRIMARY.g, COLOR_TEXT_PRIMARY.b, 0.5))

static func apply_panel_poster(panel: Control) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _PANEL_POSTER)

static func apply_panel_poster_alt(panel: Control) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _PANEL_POSTER_ALT)

static func apply_overlay_dim(overlay: ColorRect) -> void:
	if overlay == null:
		return
	overlay.color = Color(0.05, 0.04, 0.03, 0.75)

static func apply_label_dark(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)

static func apply_label_hint_dark(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)

static func apply_label_error(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_ERROR)

static func apply_label_success(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_SUCCESS)

static func apply_rich_text_dark(rich_text: RichTextLabel) -> void:
	if rich_text == null:
		return
	rich_text.add_theme_color_override("default_color", COLOR_TEXT_PRIMARY)

static func apply_line_edit_field(edit: LineEdit) -> void:
	if edit == null:
		return
	edit.add_theme_stylebox_override("normal", _make_field_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER, 1))
	edit.add_theme_stylebox_override("focus", _make_field_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER_FOCUS, 2))
	edit.add_theme_stylebox_override("read_only", _make_field_style(COLOR_FIELD_BG_DISABLED, Color(COLOR_FIELD_BORDER.r, COLOR_FIELD_BORDER.g, COLOR_FIELD_BORDER.b, 0.18), 1))
	edit.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	edit.add_theme_color_override("font_placeholder_color", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.78))
	edit.add_theme_color_override("font_uneditable_color", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.9))
	edit.add_theme_color_override("caret_color", COLOR_TEXT_PRIMARY)
	edit.add_theme_color_override("selection_color", Color(0.73, 0.23, 0.18, 0.25))

static func apply_option_button_field(option: OptionButton) -> void:
	if option == null:
		return
	var normal := _make_field_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER, 1)
	var hover := _make_field_style(Color(0.97, 0.94, 0.86, 0.95), COLOR_FIELD_BORDER, 1)
	var pressed := _make_field_style(Color(0.92, 0.88, 0.78, 0.95), COLOR_FIELD_BORDER_FOCUS, 1)
	var disabled := _make_field_style(COLOR_FIELD_BG_DISABLED, Color(COLOR_FIELD_BORDER.r, COLOR_FIELD_BORDER.g, COLOR_FIELD_BORDER.b, 0.14), 1)
	option.add_theme_stylebox_override("normal", normal)
	option.add_theme_stylebox_override("hover", hover)
	option.add_theme_stylebox_override("pressed", pressed)
	option.add_theme_stylebox_override("disabled", disabled)
	option.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	option.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	option.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
	option.add_theme_color_override("font_disabled_color", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.72))

static func apply_spin_box_field(spin: SpinBox) -> void:
	if spin == null:
		return
	var line_edit := spin.get_line_edit()
	if line_edit != null and is_instance_valid(line_edit):
		apply_line_edit_field(line_edit)

static func apply_check_box_field(check: CheckBox) -> void:
	if check == null:
		return
	check.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	check.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
	check.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	check.add_theme_color_override("font_hover_pressed_color", COLOR_TEXT_PRIMARY)
	check.add_theme_color_override("font_disabled_color", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.72))

static func apply_tab_container_surface(tab_container: TabContainer) -> void:
	if tab_container == null:
		return
	tab_container.add_theme_stylebox_override("panel", _PANEL_POSTER_ALT)
	var tab_bar := tab_container.get_tab_bar()
	if tab_bar == null or not is_instance_valid(tab_bar):
		return
	tab_bar.add_theme_stylebox_override("tab_unselected", _make_field_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER, 1))
	tab_bar.add_theme_stylebox_override("tab_selected", _make_field_style(Color(0.97, 0.94, 0.86, 0.98), COLOR_FIELD_BORDER_FOCUS, 2))
	tab_bar.add_theme_stylebox_override("tab_hovered", _make_field_style(Color(0.97, 0.94, 0.86, 0.98), COLOR_FIELD_BORDER, 1))
	tab_bar.add_theme_stylebox_override("tab_disabled", _make_field_style(COLOR_FIELD_BG_DISABLED, Color(COLOR_FIELD_BORDER.r, COLOR_FIELD_BORDER.g, COLOR_FIELD_BORDER.b, 0.14), 1))
	tab_bar.add_theme_color_override("font_selected_color", COLOR_TEXT_PRIMARY)
	tab_bar.add_theme_color_override("font_unselected_color", COLOR_TEXT_MUTED)
	tab_bar.add_theme_color_override("font_hovered_color", COLOR_TEXT_PRIMARY)
	tab_bar.add_theme_color_override("font_disabled_color", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.72))

static func apply_item_list_surface(item_list: ItemList) -> void:
	if item_list == null:
		return
	item_list.add_theme_stylebox_override("panel", _make_field_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER, 1))
	item_list.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	item_list.add_theme_color_override("font_selected_color", COLOR_TEXT_PRIMARY)
	item_list.add_theme_color_override("font_hovered_color", COLOR_TEXT_PRIMARY)
	item_list.add_theme_color_override("font_disabled_color", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.72))
	item_list.add_theme_color_override("selection_color", Color(0.73, 0.23, 0.18, 0.2))

static func _load_first_valid_texture(paths: PackedStringArray) -> Texture2D:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var tex = load(path)
		if tex is Texture2D:
			return tex
	return null

static func _make_field_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(maxi(0, border_width))
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 6
	style.content_margin_top = 4
	style.content_margin_right = 6
	style.content_margin_bottom = 4
	return style
