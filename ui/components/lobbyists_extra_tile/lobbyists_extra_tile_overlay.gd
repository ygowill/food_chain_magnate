class_name LobbyistsExtraTileOverlay
extends Control

signal placement_confirmed(attach_board_pos: Vector2i, side: String, rotation: int, tile_id: String)
signal skip_requested()
signal highlight_requested(tile_id: String, rotation: int)
signal ui_state_changed()

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const TilePickerButtonClass = preload("res://ui/components/lobbyists_extra_tile/tile_picker_button.gd")

@onready var hint_panel: Control = $HintMargin/HintPanel
@onready var hint_label: Label = $HintMargin/HintPanel/VBox/HintLabel
@onready var selected_tile_preview: Control = $HintMargin/HintPanel/VBox/TilesRow/SelectedTilePreview
@onready var tiles_flow: HFlowContainer = $HintMargin/HintPanel/VBox/TilesRow/TilesScroll/TilesFlow
@onready var rotation_option: OptionButton = $HintMargin/HintPanel/VBox/ControlsRow/RotationOption
@onready var confirm_button: Button = $HintMargin/HintPanel/VBox/ControlsRow/ConfirmButton
@onready var skip_button: Button = $HintMargin/HintPanel/VBox/ControlsRow/SkipButton

var _available_tiles: Array[String] = []
var _selected_tile_id: String = ""
var _selected_rotation: int = 0
var _tile_buttons_by_id: Dictionary = {} # tile_id -> Button
var _has_selected_target: bool = false
var _selected_attach_board_pos: Vector2i = Vector2i.ZERO
var _selected_side: String = ""

var _validation_ok: bool = true
var _validation_message: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	if hint_panel != null:
		UiStylesClass.apply_dialog_surface(hint_panel)
	if confirm_button != null:
		UiStylesClass.apply_button_primary(confirm_button)
	if skip_button != null:
		UiStylesClass.apply_button_secondary(skip_button)

	if rotation_option != null and not rotation_option.item_selected.is_connected(_on_rotation_selected):
		rotation_option.item_selected.connect(_on_rotation_selected)
	if confirm_button != null and not confirm_button.pressed.is_connected(request_confirm):
		confirm_button.pressed.connect(request_confirm)
	if skip_button != null and not skip_button.pressed.is_connected(request_skip):
		skip_button.pressed.connect(request_skip)

	_rebuild_rotation_options()
	_rebuild_tile_buttons()
	_update_ui()

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
	_emit_highlight_request()
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

func request_skip() -> void:
	skip_requested.emit()

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
		btn.call("set_tile_rotation", _selected_rotation)
		btn.button_group = group
		btn.button_pressed = (not _selected_tile_id.is_empty()) and tid == _selected_tile_id
		btn.tooltip_text = tid
		btn.pressed.connect(_on_tile_button_pressed.bind(tid))
		tiles_flow.add_child(btn)
		_tile_buttons_by_id[tid] = btn

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
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func _on_rotation_selected(_index: int) -> void:
	if rotation_option == null:
		return
	var id := int(rotation_option.get_selected_id())
	_selected_rotation = _normalize_rotation(id)
	_sync_tile_button_rotations()
	_emit_highlight_request()
	_update_ui()
	ui_state_changed.emit()

func _normalize_rotation(rotation: int) -> int:
	var r := int(rotation) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _emit_highlight_request() -> void:
	highlight_requested.emit(_selected_tile_id, _selected_rotation)

func _update_ui() -> void:
	_update_hint()
	if selected_tile_preview != null and is_instance_valid(selected_tile_preview) and selected_tile_preview.has_method("set_tile"):
		selected_tile_preview.call("set_tile", _selected_tile_id, _selected_rotation)
	if confirm_button != null:
		confirm_button.disabled = not can_confirm()

func _update_hint() -> void:
	if hint_label == null:
		return

	if not _validation_ok and not _validation_message.is_empty():
		hint_label.text = "无法放置：%s" % _validation_message
		return

	if _selected_tile_id.is_empty():
		hint_label.text = "请选择要扩边放置的地图板块"
		return

	if not _has_selected_target:
		hint_label.text = "已选择 tile=%s 旋转:%d°，请点击地图上高亮的边缘格选择扩边位置" % [_selected_tile_id, _selected_rotation]
		return

	hint_label.text = "tile=%s 旋转:%d° | attach=%s side=%s" % [
		_selected_tile_id,
		_selected_rotation,
		str(_selected_attach_board_pos),
		_selected_side,
	]
