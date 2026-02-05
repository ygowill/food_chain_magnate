class_name LobbyistsExtraTileOverlay
extends Control

signal placement_confirmed(attach_board_pos: Vector2i, side: String, rotation: int, tile_id: String)
signal skip_requested()
signal highlight_requested(tile_id: String, rotation: int)
signal ui_state_changed()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const TilePickerButtonClass = preload("res://modules/lobbyists/ui/components/lobbyists_extra_tile/tile_picker_button.gd")
const ActionPanelExtraTileContextScenePath := "res://modules/lobbyists/ui/components/lobbyists_extra_tile/action_panel_extra_tile_context.tscn"

@onready var background: ColorRect = $Background
@onready var picker_toggle_button: Button = $PickerToggleButton
@onready var hint_panel: Control = $Center/HintMargin/HintPanel
@onready var center: Control = $Center
@onready var hint_margin: Control = $Center/HintMargin
@onready var hint_label: Label = $Center/HintMargin/HintPanel/VBox/HeaderRow/HintLabel
@onready var hide_button: Button = $Center/HintMargin/HintPanel/VBox/HeaderRow/HideButton
@onready var tiles_scroll: ScrollContainer = $Center/HintMargin/HintPanel/VBox/TilesRow/TilesScroll
@onready var tiles_stage: VBoxContainer = $Center/HintMargin/HintPanel/VBox/TilesRow/TilesScroll/TilesStage
@onready var tiles_flow: HFlowContainer = $Center/HintMargin/HintPanel/VBox/TilesRow/TilesScroll/TilesStage/TilesFlow
@onready var controls_row: Control = $Center/HintMargin/HintPanel/VBox/ControlsRow
@onready var rotation_option: OptionButton = $Center/HintMargin/HintPanel/VBox/ControlsRow/RotationOption
@onready var confirm_button: Button = $Center/HintMargin/HintPanel/VBox/ControlsRow/ConfirmButton
@onready var skip_button: Button = $Center/HintMargin/HintPanel/VBox/ControlsRow/SkipButton

var _available_tiles: Array[String] = []
var _selected_tile_id: String = ""
var _selected_rotation: int = 0
var _tile_buttons_by_id: Dictionary = {} # tile_id -> Button
var _has_selected_target: bool = false
var _selected_attach_board_pos: Vector2i = Vector2i.ZERO
var _selected_side: String = ""

var _validation_ok: bool = true
var _validation_message: String = ""
var _picker_visible: bool = false
var _matrix_layout_remaining_frames: int = 0
var _matrix_layout_update_scheduled: bool = false

func _ready() -> void:
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	if tiles_scroll != null and is_instance_valid(tiles_scroll) and not tiles_scroll.resized.is_connected(_on_tiles_scroll_resized):
		tiles_scroll.resized.connect(_on_tiles_scroll_resized)

	if background != null and is_instance_valid(background):
		background.visible = false
	if picker_toggle_button != null and is_instance_valid(picker_toggle_button):
		picker_toggle_button.visible = false
		picker_toggle_button.focus_mode = Control.FOCUS_NONE
		UiStylesClass.apply_button_secondary(picker_toggle_button)
		if not picker_toggle_button.pressed.is_connected(show_picker):
			picker_toggle_button.pressed.connect(show_picker)

	if hint_panel != null:
		UiStylesClass.apply_dialog_surface(hint_panel)
	if hide_button != null and is_instance_valid(hide_button):
		hide_button.focus_mode = Control.FOCUS_NONE
		UiStylesClass.apply_button_secondary(hide_button)
		if not hide_button.pressed.is_connected(hide_picker):
			hide_button.pressed.connect(hide_picker)
	if confirm_button != null:
		UiStylesClass.apply_button_primary(confirm_button)
	if skip_button != null:
		UiStylesClass.apply_button_secondary(skip_button)
	if controls_row != null:
		controls_row.visible = false

	if rotation_option != null and not rotation_option.item_selected.is_connected(_on_rotation_selected):
		rotation_option.item_selected.connect(_on_rotation_selected)
	if confirm_button != null and not confirm_button.pressed.is_connected(request_confirm):
		confirm_button.pressed.connect(request_confirm)
	if skip_button != null and not skip_button.pressed.is_connected(request_skip):
		skip_button.pressed.connect(request_skip)

	if tiles_flow != null and is_instance_valid(tiles_flow):
		tiles_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		tiles_flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tiles_flow.size_flags_vertical = 0

	if _picker_visible:
		_update_picker_layout()

	_rebuild_rotation_options()
	_rebuild_tile_buttons()
	_request_tiles_flow_matrix_layout_update(3)
	_apply_picker_visibility()
	_update_ui()

func _on_resized() -> void:
	if _picker_visible:
		_update_picker_layout()

func _on_tiles_scroll_resized() -> void:
	if _picker_visible:
		_request_tiles_flow_matrix_layout_update(3)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var e: InputEventKey = event
	if not e.pressed or e.echo:
		return

	if e.keycode == KEY_TAB:
		if _picker_visible:
			hide_picker()
		else:
			show_picker()
		get_viewport().set_input_as_handled()
		return

	if e.keycode == KEY_ESCAPE and _picker_visible:
		hide_picker()
		get_viewport().set_input_as_handled()

func is_picker_visible() -> bool:
	return _picker_visible

func show_picker() -> void:
	if _picker_visible:
		return
	_picker_visible = true
	_update_picker_layout()
	_apply_picker_visibility()
	_update_ui()
	_emit_clear_highlight_request()
	ui_state_changed.emit()

func hide_picker() -> void:
	if not _picker_visible:
		return
	_picker_visible = false
	_apply_picker_visibility()
	_update_ui()
	_emit_highlight_request()
	ui_state_changed.emit()

func _apply_picker_visibility() -> void:
	var show := _picker_visible
	if background != null and is_instance_valid(background):
		background.visible = show
	if center != null and is_instance_valid(center):
		center.visible = show
	if hint_margin != null and is_instance_valid(hint_margin):
		hint_margin.visible = show
	if picker_toggle_button != null and is_instance_valid(picker_toggle_button):
		picker_toggle_button.visible = not show
	# While picker is visible, block map interactions (modal full-screen picker).
	mouse_filter = Control.MOUSE_FILTER_STOP if show else Control.MOUSE_FILTER_IGNORE

func set_available_tiles(tile_ids: Array[String]) -> void:
	var ids: Array[String] = []
	var seen := {}
	for v in tile_ids:
		var s := str(v).strip_edges()
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		ids.append(s)
	ids.sort()
	_available_tiles = ids

	if _available_tiles.is_empty():
		_selected_tile_id = ""
	elif _selected_tile_id.is_empty() or not _available_tiles.has(_selected_tile_id):
		_selected_tile_id = _available_tiles[0]

	_rebuild_tile_buttons()
	_update_ui()
	ui_state_changed.emit()

func get_selected_tile_id() -> String:
	return _selected_tile_id

func get_selected_rotation() -> int:
	return _selected_rotation

func get_selected_attach_board_pos() -> Vector2i:
	return _selected_attach_board_pos

func get_selected_side() -> String:
	return _selected_side

func set_selected_target(attach_board_pos: Vector2i, side: String) -> void:
	_has_selected_target = true
	_selected_attach_board_pos = attach_board_pos
	_selected_side = str(side).strip_edges()
	_update_ui()
	ui_state_changed.emit()

func clear_target() -> void:
	_has_selected_target = false
	_selected_attach_board_pos = Vector2i.ZERO
	_selected_side = ""
	_validation_ok = true
	_validation_message = ""
	_update_ui()
	ui_state_changed.emit()

func set_validation(valid: bool, message: String = "") -> void:
	_validation_ok = bool(valid)
	_validation_message = str(message).strip_edges()
	_update_ui()
	ui_state_changed.emit()

func can_confirm() -> bool:
	return (not _selected_tile_id.is_empty()) and _has_selected_target and _validation_ok

func request_confirm() -> void:
	if not can_confirm():
		return
	placement_confirmed.emit(_selected_attach_board_pos, _selected_side, _selected_rotation, _selected_tile_id)

func request_cancel() -> void:
	# ActionPanel ContextPanel 取消按钮：用于“放弃扩边”避免软锁。
	request_skip()

func request_skip() -> void:
	skip_requested.emit()

func set_selected_rotation(rotation: int) -> void:
	_selected_rotation = _normalize_rotation(rotation)
	_sync_tile_button_rotations()
	if rotation_option != null:
		for i in range(rotation_option.get_item_count()):
			if int(rotation_option.get_item_id(i)) == _selected_rotation:
				rotation_option.select(i)
				break
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func rotate_clockwise() -> void:
	var next := _selected_rotation + 90
	if next >= 360:
		next = 0
	set_selected_rotation(next)

func _rebuild_rotation_options() -> void:
	if rotation_option == null:
		return
	rotation_option.clear()
	for r in [0, 90, 180, 270]:
		rotation_option.add_item("%d°" % int(r), int(r))
	rotation_option.select(0)

func _rebuild_tile_buttons() -> void:
	_tile_buttons_by_id.clear()
	if tiles_flow == null or not is_instance_valid(tiles_flow):
		return

	for child in tiles_flow.get_children():
		child.queue_free()

	var group := ButtonGroup.new()
	group.allow_unpress = false

	for id in _available_tiles:
		var tid := str(id).strip_edges()
		if tid.is_empty():
			continue

		var btn = TilePickerButtonClass.new()
		btn.tile_id = tid
		if btn.has_method("set_tile_rotation"):
			btn.call("set_tile_rotation", _selected_rotation)
		btn.button_group = group
		btn.button_pressed = (not _selected_tile_id.is_empty()) and tid == _selected_tile_id
		btn.tooltip_text = tid
		btn.pressed.connect(_on_tile_button_pressed.bind(tid))
		tiles_flow.add_child(btn)
		_tile_buttons_by_id[tid] = btn
	tiles_flow.queue_sort()
	_request_tiles_flow_matrix_layout_update(3)

func _sync_tile_button_rotations() -> void:
	for tid in _tile_buttons_by_id.keys():
		var btn_val = _tile_buttons_by_id.get(tid, null)
		if btn_val is Node and is_instance_valid(btn_val) and btn_val.has_method("set_tile_rotation"):
			btn_val.call("set_tile_rotation", _selected_rotation)

func _on_tile_button_pressed(tile_id_in: String) -> void:
	var tid := str(tile_id_in).strip_edges()
	if tid.is_empty():
		return
	_selected_tile_id = tid
	hide_picker()

func _update_picker_layout() -> void:
	if hint_panel == null or not is_instance_valid(hint_panel):
		return
	var vp := get_viewport_rect().size
	# Full-screen panel (keep a minimal outer margin via HintMargin).
	var w := maxf(320.0, vp.x - 24.0)
	var h := maxf(260.0, vp.y - 24.0)
	hint_panel.custom_minimum_size = Vector2(w, h)
	hint_panel.minimum_size_changed.emit()
	if hint_panel.has_method("queue_sort"):
		hint_panel.queue_sort()
	_request_tiles_flow_matrix_layout_update(3)

func _request_tiles_flow_matrix_layout_update(frames: int = 2) -> void:
	if not _picker_visible:
		return
	_matrix_layout_remaining_frames = maxi(_matrix_layout_remaining_frames, maxi(1, int(frames)))
	if _matrix_layout_update_scheduled:
		return
	_matrix_layout_update_scheduled = true
	call_deferred("_run_tiles_flow_matrix_layout_update")

func _run_tiles_flow_matrix_layout_update() -> void:
	_matrix_layout_update_scheduled = false
	if not _picker_visible:
		_matrix_layout_remaining_frames = 0
		return
	_update_tiles_flow_matrix_layout()

	_matrix_layout_remaining_frames -= 1
	if _matrix_layout_remaining_frames > 0 and not _matrix_layout_update_scheduled:
		_matrix_layout_update_scheduled = true
		call_deferred("_run_tiles_flow_matrix_layout_update")

func _update_tiles_flow_matrix_layout() -> void:
	if tiles_flow == null or not is_instance_valid(tiles_flow):
		return

	var count := _available_tiles.size()
	if count <= 0:
		tiles_flow.custom_minimum_size = Vector2.ZERO
		return

	var tile_w := 160.0
	var tile_h := 190.0
	if tiles_flow.get_child_count() > 0:
		var c0 = tiles_flow.get_child(0)
		if c0 is Control and is_instance_valid(c0):
			var ms := (c0 as Control).get_combined_minimum_size()
			if ms.x > 4.0 and ms.y > 4.0:
				tile_w = float(ms.x)
				tile_h = float(ms.y)

	var h_sep := float(tiles_flow.get_theme_constant("h_separation"))
	if h_sep <= 0.0:
		h_sep = 12.0
	var v_sep := float(tiles_flow.get_theme_constant("v_separation"))
	if v_sep <= 0.0:
		v_sep = 12.0

	var avail_w := 0.0
	if tiles_scroll != null and is_instance_valid(tiles_scroll):
		avail_w = float(tiles_scroll.size.x)
	if avail_w <= 64.0:
		avail_w = float(get_viewport_rect().size.x - 72.0)
	avail_w = maxf(avail_w, tile_w)

	var avail_h := 0.0
	if tiles_scroll != null and is_instance_valid(tiles_scroll):
		avail_h = float(tiles_scroll.size.y)
	if avail_h <= 64.0:
		avail_h = float(get_viewport_rect().size.y - 200.0)

	var max_cols_fit := maxi(1, int(floor((avail_w + h_sep) / (tile_w + h_sep))))

	var best_cols := 1
	var best_square_score := 2147483647.0
	var best_waste := 2147483647
	var best_fits_height := false
	for cols in range(1, max_cols_fit + 1):
		var rows := int(ceil(float(count) / float(cols)))
		var w := float(cols) * tile_w + float(maxi(0, cols - 1)) * h_sep
		var h := float(rows) * tile_h + float(maxi(0, rows - 1)) * v_sep
		var square_score := absf(w - h)
		var waste := rows * cols - count
		var fits_h := avail_h <= 64.0 or h <= avail_h + 0.5

		if best_fits_height and not fits_h:
			continue
		if (not best_fits_height) and fits_h:
			best_cols = cols
			best_square_score = square_score
			best_waste = waste
			best_fits_height = true
			continue
		if square_score < best_square_score:
			best_cols = cols
			best_square_score = square_score
			best_waste = waste
		elif is_equal_approx(square_score, best_square_score):
			if waste < best_waste:
				best_cols = cols
				best_waste = waste
			elif waste == best_waste and cols < best_cols:
				best_cols = cols

	var best_rows := int(ceil(float(count) / float(best_cols)))
	var desired_w := float(best_cols) * tile_w + float(maxi(0, best_cols - 1)) * h_sep
	var desired_h := float(best_rows) * tile_h + float(maxi(0, best_rows - 1)) * v_sep

	tiles_flow.custom_minimum_size = Vector2(desired_w, desired_h)
	tiles_flow.minimum_size_changed.emit()
	tiles_flow.queue_sort()

	# ScrollContainer doesn't automatically expand its child to viewport size; ensure TilesStage is at
	# least as large as the visible area so Top/Bottom spacers can center the matrix.
	if tiles_stage != null and is_instance_valid(tiles_stage):
		var stage_w := avail_w
		var stage_h := maxf(avail_h, desired_h)
		if stage_w <= 4.0:
			stage_w = desired_w
		if stage_h <= 4.0:
			stage_h = desired_h
		tiles_stage.custom_minimum_size = Vector2(stage_w, stage_h)
		tiles_stage.minimum_size_changed.emit()
		tiles_stage.queue_sort()

func _on_rotation_selected(_index: int) -> void:
	if rotation_option == null:
		return
	var id := int(rotation_option.get_selected_id())
	set_selected_rotation(id)

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _emit_highlight_request() -> void:
	highlight_requested.emit(_selected_tile_id, _selected_rotation)

func _emit_clear_highlight_request() -> void:
	highlight_requested.emit("", 0)

func _update_ui() -> void:
	_update_hint()
	if confirm_button != null:
		confirm_button.disabled = not can_confirm()

func get_hint_text() -> String:
	if not _validation_ok and not _validation_message.is_empty():
		return "无法放置：%s" % _validation_message

	if _picker_visible:
		return "请选择要扩边放置的地图板块（Tab 隐藏/显示）"

	if _selected_tile_id.is_empty():
		return "请选择要扩边放置的地图板块"

	if not _has_selected_target:
		return "已选择 tile=%s 旋转:%d°，请点击地图上高亮的边缘格选择扩边位置" % [_selected_tile_id, _selected_rotation]

	return "tile=%s 旋转:%d° | attach=%s side=%s" % [
		_selected_tile_id,
		_selected_rotation,
		str(_selected_attach_board_pos),
		_selected_side,
	]

func get_action_panel_context_spec() -> Dictionary:
	return {
		"title": "🗺️ 扩边放置板块",
		"hint": get_hint_text(),
		"confirm_text": "确认放置",
		"cancel_text": "放弃扩边",
		"custom_scene": ActionPanelExtraTileContextScenePath,
	}

func _update_hint() -> void:
	if hint_label == null:
		return
	hint_label.text = get_hint_text()
