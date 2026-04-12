class_name TutorialSpotlightOverlay
extends ModalDialogBase

signal tour_finished(completed: bool)

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var highlight_frame: PanelContainer = $HighlightFrame
@onready var card_panel: PanelContainer = $CardPanel
@onready var title_label: Label = $CardPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var body_label: RichTextLabel = $CardPanel/MarginContainer/VBoxContainer/BodyLabel
@onready var progress_label: Label = $CardPanel/MarginContainer/VBoxContainer/ProgressLabel
@onready var prev_button: Button = $CardPanel/MarginContainer/VBoxContainer/ButtonRow/PrevButton
@onready var skip_button: Button = $CardPanel/MarginContainer/VBoxContainer/ButtonRow/SkipButton
@onready var next_button: Button = $CardPanel/MarginContainer/VBoxContainer/ButtonRow/NextButton

var _steps: Array[Dictionary] = []
var _targets_provider: Callable = Callable()
var _on_completed: Callable = Callable()
var _on_skipped: Callable = Callable()
var _step_index: int = 0
var _target_rect: Rect2 = Rect2()
var _dim_color: Color = Color(0.05, 0.04, 0.03, 0.75)
var _pending_start_requested: bool = false

const _HIGHLIGHT_MARGIN := 10.0
const _CARD_GAP := 18.0
const _SCREEN_MARGIN := 18.0
const _DIM_HOLE_EXTRA_MARGIN := 4.0

func _ready() -> void:
	super._ready()
	_apply_visual_styles()
	_connect_signals()
	highlight_frame.visible = false
	card_panel.visible = false
	if is_instance_valid(overlay):
		overlay.visible = false
	if _pending_start_requested and not _steps.is_empty():
		call_deferred("_start_current_tour")

func start_tour(
	steps: Array,
	targets_provider: Callable,
	on_completed: Callable = Callable(),
	on_skipped: Callable = Callable()
) -> void:
	_steps.clear()
	for step_val in steps:
		if step_val is Dictionary:
			_steps.append((step_val as Dictionary).duplicate(true))
	if _steps.is_empty():
		return

	_targets_provider = targets_provider
	_on_completed = on_completed
	_on_skipped = on_skipped
	_step_index = 0
	_pending_start_requested = true
	if not _is_ui_ready():
		if is_instance_valid(overlay):
			overlay.visible = false
		return
	_start_current_tour()

func _is_ui_ready() -> bool:
	return (
		is_node_ready()
		and highlight_frame != null
		and card_panel != null
		and title_label != null
		and body_label != null
		and progress_label != null
		and prev_button != null
		and skip_button != null
		and next_button != null
	)

func _start_current_tour() -> void:
	if not _is_ui_ready():
		return
	if _steps.is_empty():
		_pending_start_requested = false
		return
	_pending_start_requested = false
	if is_instance_valid(overlay):
		overlay.visible = false
	open()
	card_panel.visible = true
	_apply_step()

func is_tour_running() -> bool:
	return visible and not _steps.is_empty()

func cancel_tour(mark_completed: bool = false) -> void:
	if _steps.is_empty() and not visible:
		return
	_pending_start_requested = false
	_finish_tour(mark_completed)

func _apply_visual_styles() -> void:
	UiStylesClass.apply_panel_poster_alt(card_panel)
	UiStylesClass.apply_label_dark(title_label)
	UiStylesClass.apply_rich_text_dark(body_label)
	UiStylesClass.apply_label_hint_dark(progress_label)
	UiStylesClass.apply_button_secondary(prev_button)
	UiStylesClass.apply_button_secondary(skip_button)
	UiStylesClass.apply_button_primary(next_button)

	var highlight_style := StyleBoxFlat.new()
	highlight_style.bg_color = Color(1, 1, 1, 0.02)
	highlight_style.border_color = Color(0.93, 0.73, 0.24, 0.95)
	highlight_style.set_border_width_all(3)
	highlight_style.corner_radius_top_left = 10
	highlight_style.corner_radius_top_right = 10
	highlight_style.corner_radius_bottom_left = 10
	highlight_style.corner_radius_bottom_right = 10
	highlight_frame.add_theme_stylebox_override("panel", highlight_style)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_color = UiStylesClass.get_overlay_dim_color()

func _connect_signals() -> void:
	prev_button.pressed.connect(_on_prev_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	next_button.pressed.connect(_on_next_pressed)

func _apply_step() -> void:
	if _steps.is_empty():
		_finish_tour(true)
		return
	_step_index = clampi(_step_index, 0, _steps.size() - 1)

	var step: Dictionary = _steps[_step_index]
	title_label.text = str(step.get("title", "教学"))
	body_label.text = str(step.get("body", "")).strip_edges()
	progress_label.text = "步骤 %d / %d" % [_step_index + 1, _steps.size()]
	prev_button.visible = _step_index > 0
	next_button.text = "完成" if _step_index >= _steps.size() - 1 else "下一步"

	_refresh_target_rect()
	call_deferred("_refresh_layout")

func _refresh_target_rect() -> void:
	_target_rect = Rect2()
	highlight_frame.visible = false

	var step: Dictionary = _steps[_step_index]
	var target_key := str(step.get("target_key", "")).strip_edges()
	if target_key.is_empty():
		queue_redraw()
		return

	var target := _resolve_target(target_key)
	if target == null:
		queue_redraw()
		return

	var target_control := target as Control
	if not is_instance_valid(target_control) or not target_control.visible:
		queue_redraw()
		return

	var global_rect := _get_target_visible_global_rect(target_control)
	if global_rect.size.x <= 0.0 or global_rect.size.y <= 0.0:
		queue_redraw()
		return

	var self_rect := get_global_rect()
	_target_rect = Rect2(global_rect.position - self_rect.position, global_rect.size)
	highlight_frame.position = _target_rect.position - Vector2(_HIGHLIGHT_MARGIN, _HIGHLIGHT_MARGIN)
	highlight_frame.size = _target_rect.size + Vector2(_HIGHLIGHT_MARGIN * 2.0, _HIGHLIGHT_MARGIN * 2.0)
	highlight_frame.visible = true
	queue_redraw()

func _get_target_visible_global_rect(target_control: Control) -> Rect2:
	if not is_instance_valid(target_control):
		return Rect2()

	var rect := target_control.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()

	var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	rect = rect.intersection(viewport_rect)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()

	var parent_node: Node = target_control.get_parent()
	while parent_node != null:
		if parent_node is Control:
			var parent_control := parent_node as Control
			if parent_control.clip_contents:
				rect = rect.intersection(parent_control.get_global_rect())
				if rect.size.x <= 0.0 or rect.size.y <= 0.0:
					return Rect2()
		parent_node = parent_node.get_parent()

	return rect

func _resolve_target(target_key: String) -> Control:
	if not _targets_provider.is_valid():
		return null
	var raw_targets = _targets_provider.call()
	if not (raw_targets is Dictionary):
		return null
	var targets: Dictionary = raw_targets
	var node = targets.get(target_key, null)
	if node is Control:
		return node as Control
	return null

func _refresh_layout() -> void:
	if not visible:
		return
	_refresh_target_rect()

	var viewport_size := get_viewport_rect().size
	var card_size := card_panel.get_combined_minimum_size()
	card_panel.size = card_size

	if _target_rect.size == Vector2.ZERO:
		card_panel.position = (viewport_size - card_size) * 0.5
		return

	var right_pos := Vector2(_target_rect.end.x + _CARD_GAP, _target_rect.position.y)
	if _fits_card(right_pos, card_size, viewport_size):
		card_panel.position = _clamp_card_position(right_pos, card_size, viewport_size)
		return

	var left_pos := Vector2(_target_rect.position.x - card_size.x - _CARD_GAP, _target_rect.position.y)
	if _fits_card(left_pos, card_size, viewport_size):
		card_panel.position = _clamp_card_position(left_pos, card_size, viewport_size)
		return

	var below_pos := Vector2(_target_rect.position.x, _target_rect.end.y + _CARD_GAP)
	if _fits_card(below_pos, card_size, viewport_size):
		card_panel.position = _clamp_card_position(below_pos, card_size, viewport_size)
		return

	var above_pos := Vector2(_target_rect.position.x, _target_rect.position.y - card_size.y - _CARD_GAP)
	if _fits_card(above_pos, card_size, viewport_size):
		card_panel.position = _clamp_card_position(above_pos, card_size, viewport_size)
		return

	card_panel.position = _clamp_card_position((viewport_size - card_size) * 0.5, card_size, viewport_size)

func _draw() -> void:
	if not visible:
		return

	var full_rect := Rect2(Vector2.ZERO, size)
	if full_rect.size.x <= 0.0 or full_rect.size.y <= 0.0:
		return

	if _target_rect.size == Vector2.ZERO:
		draw_rect(full_rect, _dim_color, true)
		return

	var hole_rect := _target_rect.grow(_HIGHLIGHT_MARGIN + _DIM_HOLE_EXTRA_MARGIN)
	hole_rect.position.x = clampf(hole_rect.position.x, 0.0, full_rect.size.x)
	hole_rect.position.y = clampf(hole_rect.position.y, 0.0, full_rect.size.y)
	hole_rect.size.x = clampf(hole_rect.size.x, 0.0, maxf(0.0, full_rect.size.x - hole_rect.position.x))
	hole_rect.size.y = clampf(hole_rect.size.y, 0.0, maxf(0.0, full_rect.size.y - hole_rect.position.y))

	_draw_dim_rect(Rect2(0.0, 0.0, full_rect.size.x, hole_rect.position.y))
	_draw_dim_rect(Rect2(0.0, hole_rect.position.y, hole_rect.position.x, hole_rect.size.y))
	_draw_dim_rect(Rect2(hole_rect.end.x, hole_rect.position.y, full_rect.size.x - hole_rect.end.x, hole_rect.size.y))
	_draw_dim_rect(Rect2(0.0, hole_rect.end.y, full_rect.size.x, full_rect.size.y - hole_rect.end.y))

func _draw_dim_rect(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_rect(rect, _dim_color, true)

func _fits_card(pos: Vector2, card_size: Vector2, viewport_size: Vector2) -> bool:
	return (
		pos.x >= _SCREEN_MARGIN
		and pos.y >= _SCREEN_MARGIN
		and pos.x + card_size.x <= viewport_size.x - _SCREEN_MARGIN
		and pos.y + card_size.y <= viewport_size.y - _SCREEN_MARGIN
	)

func _clamp_card_position(pos: Vector2, card_size: Vector2, viewport_size: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, _SCREEN_MARGIN, viewport_size.x - card_size.x - _SCREEN_MARGIN),
		clampf(pos.y, _SCREEN_MARGIN, viewport_size.y - card_size.y - _SCREEN_MARGIN)
	)

func _on_prev_pressed() -> void:
	if _step_index <= 0:
		return
	_step_index -= 1
	_apply_step()

func _on_skip_pressed() -> void:
	_finish_tour(false)

func _on_next_pressed() -> void:
	if _step_index >= _steps.size() - 1:
		_finish_tour(true)
		return
	_step_index += 1
	_apply_step()

func _finish_tour(completed: bool) -> void:
	var callback := _on_completed if completed else _on_skipped
	_pending_start_requested = false
	_steps.clear()
	_targets_provider = Callable()
	_on_completed = Callable()
	_on_skipped = Callable()
	close()
	highlight_frame.visible = false
	card_panel.visible = false
	if is_instance_valid(overlay):
		overlay.visible = false
	_target_rect = Rect2()
	queue_redraw()
	tour_finished.emit(completed)
	if callback.is_valid():
		callback.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible and not _steps.is_empty():
		call_deferred("_refresh_layout")

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_finish_tour(false)
			get_viewport().set_input_as_handled()
