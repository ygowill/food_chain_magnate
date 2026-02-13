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
	button.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09))
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.06))
	button.add_theme_color_override("font_pressed_color", Color(0.17, 0.13, 0.09))
	button.add_theme_color_override("font_disabled_color", Color(0.17, 0.13, 0.09, 0.5))

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
	label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09))

static func apply_label_hint_dark(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))

static func _load_first_valid_texture(paths: PackedStringArray) -> Texture2D:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var tex = load(path)
		if tex is Texture2D:
			return tex
	return null
