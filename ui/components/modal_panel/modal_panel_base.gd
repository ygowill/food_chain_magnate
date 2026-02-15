# 遮罩面板基类
# - 覆盖指定区域（通常为中央地图区）
# - ESC 取消；Space 按住窥视地图（隐藏面板并降低遮罩）
class_name ModalPanelBase
extends Control

signal completed(result: Dictionary)
signal cancelled()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@export var title: String = ""
@export var confirm_text: String = "确认"
@export var cancel_text: String = "取消"
@export var allow_cancel: bool = true
@export var allow_peek_map: bool = true

@onready var overlay: ColorRect = $Overlay
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var content_host: Control = $Panel/MarginContainer/VBoxContainer/ContentHost
@onready var confirm_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/CancelButton
@onready var hint_label: Label = $Panel/MarginContainer/VBoxContainer/HintLabel

var _peek_held: bool = false
var _overlay_alpha_normal: float = 0.75
var _overlay_alpha_peek: float = 0.25

func _ready() -> void:
	visible = false
	UiStylesClass.apply_dialog_surface(panel)
	UiStylesClass.apply_button_primary(confirm_button)
	UiStylesClass.apply_button_secondary(cancel_button)
	if is_instance_valid(title_label):
		title_label.text = title
		UiStylesClass.apply_label_dark(title_label)
	if is_instance_valid(confirm_button):
		confirm_button.text = confirm_text
		confirm_button.pressed.connect(_on_confirm_pressed)
	if is_instance_valid(cancel_button):
		cancel_button.text = cancel_text
		cancel_button.visible = allow_cancel
		if allow_cancel:
			cancel_button.pressed.connect(_on_cancel_pressed)
	_update_hint()
	if is_instance_valid(hint_label):
		UiStylesClass.apply_label_hint_dark(hint_label)
	_apply_overlay_alpha(_overlay_alpha_normal)

func set_title_text(text: String) -> void:
	title = text
	if is_instance_valid(title_label):
		title_label.text = title
		UiStylesClass.apply_label_dark(title_label)

func set_confirm_text(text: String) -> void:
	confirm_text = text
	if is_instance_valid(confirm_button):
		confirm_button.text = confirm_text

func set_cancel_text(text: String) -> void:
	cancel_text = text
	if is_instance_valid(cancel_button):
		cancel_button.text = cancel_text

func set_confirm_enabled(enabled: bool) -> void:
	if is_instance_valid(confirm_button):
		confirm_button.disabled = not enabled

func open(covered_rect: Rect2) -> void:
	# 兼容：首次进入场景时部分 UI 节点尺寸尚未布局完成，可能传入 size=0 的 rect；
	# 优先尝试从父场景解析中央地图区域，再退回 viewport 尺寸兜底。
	var rect := covered_rect
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		rect = _resolve_fallback_cover_rect_from_parent()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		rect = Rect2(Vector2.ZERO, get_viewport_rect().size)

	position = rect.position
	size = rect.size
	visible = true
	_set_peek(false)
	# 首次打开时尽量立即居中（避免“第一帧在左上角”），再用 deferred 做二次校正（确保布局完成）。
	_center_panel()
	call_deferred("_center_panel")

func _resolve_fallback_cover_rect_from_parent() -> Rect2:
	var parent_node := get_parent()
	if parent_node == null or not is_instance_valid(parent_node):
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	for path in [
		"UIRoot/MainContent/CenterSplit/GameArea",
		"UIRoot/MainContent/CenterSplit",
	]:
		var n = parent_node.get_node_or_null(path)
		if not (n is Control):
			continue
		var c: Control = n
		var gr := c.get_global_rect()
		var parent_global := Vector2.ZERO
		if parent_node is Control:
			parent_global = (parent_node as Control).global_position
		var rect := Rect2(gr.position - parent_global, gr.size)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			return rect

	return Rect2(Vector2.ZERO, Vector2.ZERO)

func close() -> void:
	_set_peek(false)
	visible = false

func _center_panel() -> void:
	var p: Control = panel
	if not is_instance_valid(p):
		var n = get_node_or_null("Panel")
		if n is Control:
			p = n
	if not is_instance_valid(p):
		return

	var panel_size := p.size
	if panel_size == Vector2.ZERO:
		panel_size = p.get_combined_minimum_size()
	if panel_size == Vector2.ZERO:
		panel_size = p.custom_minimum_size
	if panel_size == Vector2.ZERO:
		panel_size = Vector2(720, 520)

	# 面板比覆盖区域更大时，缩小到可见范围内（保留四周 12px 边距）
	var max_w := maxf(0.0, size.x - 24.0)
	var max_h := maxf(0.0, size.y - 24.0)
	if max_w > 0.0 and max_h > 0.0:
		var clamped := Vector2(min(panel_size.x, max_w), min(panel_size.y, max_h))
		if clamped != panel_size:
			panel_size = clamped
			p.size = panel_size

	var x := (size.x - panel_size.x) / 2.0
	var y := (size.y - panel_size.y) / 2.0
	x = clampf(x, 12.0, maxf(12.0, size.x - panel_size.x - 12.0))
	y = clampf(y, 12.0, maxf(12.0, size.y - panel_size.y - 12.0))
	p.position = Vector2(x, y)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var e: InputEventKey = event
	if e.echo:
		return

	match e.keycode:
		KEY_ESCAPE:
			if not e.pressed:
				return
			# 强制弹窗（allow_cancel=false）也应吞掉 ESC，避免穿透到上层触发其它 UI（例如菜单）。
			get_viewport().set_input_as_handled()
			if allow_cancel:
				_on_cancel_pressed()
		KEY_ENTER, KEY_KP_ENTER:
			if e.pressed and is_instance_valid(confirm_button) and not confirm_button.disabled:
				get_viewport().set_input_as_handled()
				_on_confirm_pressed()
		KEY_SPACE:
			if not allow_peek_map:
				return
			get_viewport().set_input_as_handled()
			_set_peek(e.pressed)

func _set_peek(enabled: bool) -> void:
	if _peek_held == enabled:
		return
	_peek_held = enabled

	mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP

	if is_instance_valid(panel):
		panel.visible = not enabled

	if is_instance_valid(overlay):
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		_apply_overlay_alpha(_overlay_alpha_peek if enabled else _overlay_alpha_normal)

func _apply_overlay_alpha(alpha: float) -> void:
	if not is_instance_valid(overlay):
		return
	var c := overlay.color
	c.a = clampf(alpha, 0.0, 1.0)
	overlay.color = c

func _update_hint() -> void:
	if not is_instance_valid(hint_label):
		return
	var parts: Array[String] = []
	if allow_cancel:
		parts.append("ESC 取消")
	if allow_peek_map:
		parts.append("按住 Space 查看地图")
	hint_label.text = " | ".join(parts)

func _on_confirm_pressed() -> void:
	completed.emit({})

func _on_cancel_pressed() -> void:
	if not allow_cancel:
		return
	cancelled.emit()
	close()
