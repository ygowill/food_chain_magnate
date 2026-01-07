# 餐厅放置覆盖层组件
# - 只负责收集输入：restaurant_id（可选）、rotation、position
# - 地图选点由 game.gd 通过 MapCanvas 信号回填
class_name RestaurantPlacementOverlay
extends Control

signal placement_confirmed(position: Vector2i, rotation: int, restaurant_id: String)
signal cancelled()
signal preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String)
signal preview_cleared()
signal highlight_requested(mode: String, rotation: int, restaurant_id: String)

@onready var hint_label: Label = $HintPanel/HintLabel
@onready var bottom_bar: HBoxContainer = $BottomBar
@onready var confirm_btn: Button = $BottomBar/ConfirmButton
@onready var cancel_btn: Button = $BottomBar/CancelButton

var _mode: String = "place_restaurant"  # place_restaurant | move_restaurant
var _selected_position: Vector2i = Vector2i(-1, -1)
var _selected_rotation: int = 0
var _available_restaurants: Array[String] = []
var _selected_restaurant_id: String = ""

var _restaurant_option: OptionButton = null
var _rotation_option: OptionButton = null

var _validation_ok: bool = true
var _validation_message: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	_ensure_controls()
	_update_ui()
	visible = false

func set_mode(action_id: String) -> void:
	_mode = action_id
	clear_selection()
	_update_ui()
	_emit_highlight_request()

func set_map_data(_map_data: Dictionary) -> void:
	# 预留：后续可根据 PlacementValidator 扫描可放置位置并高亮
	pass

func set_available_restaurants(restaurant_ids: Array[String]) -> void:
	_available_restaurants = restaurant_ids.duplicate()
	_rebuild_restaurant_options()
	_update_confirm_state()
	_emit_highlight_request()

func set_selected_restaurant(restaurant_id: String) -> void:
	_selected_restaurant_id = restaurant_id
	_sync_restaurant_selection()
	_update_confirm_state()
	_emit_highlight_request()

func set_selected_position(position: Vector2i) -> void:
	_selected_position = position
	_emit_preview()
	_update_ui()

func set_validation(valid: bool, message: String = "") -> void:
	_validation_ok = valid
	_validation_message = message
	_update_ui()

func clear_selection() -> void:
	_selected_position = Vector2i(-1, -1)
	_selected_rotation = 0
	_selected_restaurant_id = ""
	_validation_ok = true
	_validation_message = ""
	_sync_rotation_selection()
	_sync_restaurant_selection()
	_emit_preview()
	_update_ui()
	_emit_highlight_request()

func _ensure_controls() -> void:
	if bottom_bar == null:
		return

	if _restaurant_option == null:
		_restaurant_option = OptionButton.new()
		_restaurant_option.custom_minimum_size = Vector2(140, 0)
		_restaurant_option.item_selected.connect(_on_restaurant_selected)
		bottom_bar.add_child(_restaurant_option)
		bottom_bar.move_child(_restaurant_option, 0)

	if _rotation_option == null:
		_rotation_option = OptionButton.new()
		_rotation_option.custom_minimum_size = Vector2(110, 0)
		_rotation_option.item_selected.connect(_on_rotation_selected)
		bottom_bar.add_child(_rotation_option)
		bottom_bar.move_child(_rotation_option, 1)

	_rebuild_rotation_options()
	_rebuild_restaurant_options()

func _rebuild_rotation_options() -> void:
	if _rotation_option == null:
		return
	_rotation_option.clear()

	for rot in [0, 90, 180, 270]:
		_rotation_option.add_item("%d°" % rot)
		var idx := _rotation_option.get_item_count() - 1
		_rotation_option.set_item_metadata(idx, rot)

	_sync_rotation_selection()

func _rebuild_restaurant_options() -> void:
	if _restaurant_option == null:
		return
	_restaurant_option.clear()

	var ids: Array[String] = []
	for rid in _available_restaurants:
		var s := str(rid)
		if not s.is_empty():
			ids.append(s)
	ids.sort()

	for rid2 in ids:
		_restaurant_option.add_item(rid2)
		var idx := _restaurant_option.get_item_count() - 1
		_restaurant_option.set_item_metadata(idx, rid2)

	_sync_restaurant_selection()
	_update_ui()

func _sync_rotation_selection() -> void:
	if _rotation_option == null:
		return
	for i in range(_rotation_option.get_item_count()):
		if int(_rotation_option.get_item_metadata(i)) == _selected_rotation:
			_rotation_option.select(i)
			return
	if _rotation_option.get_item_count() > 0:
		_rotation_option.select(0)
		_selected_rotation = int(_rotation_option.get_item_metadata(0))

func _sync_restaurant_selection() -> void:
	if _restaurant_option == null:
		return
	if _restaurant_option.get_item_count() <= 0:
		return

	if not _selected_restaurant_id.is_empty():
		for i in range(_restaurant_option.get_item_count()):
			if str(_restaurant_option.get_item_metadata(i)) == _selected_restaurant_id:
				_restaurant_option.select(i)
				return

	_restaurant_option.select(0)
	_selected_restaurant_id = str(_restaurant_option.get_item_metadata(0))

func _on_rotation_selected(index: int) -> void:
	if _rotation_option == null:
		return
	var meta = _rotation_option.get_item_metadata(index)
	_selected_rotation = int(meta)
	_emit_preview()
	_emit_highlight_request()
	_update_confirm_state()
	_update_ui()

func _on_restaurant_selected(index: int) -> void:
	if _restaurant_option == null:
		return
	var meta = _restaurant_option.get_item_metadata(index)
	_selected_restaurant_id = str(meta)
	_emit_preview()
	_emit_highlight_request()
	_update_confirm_state()
	_update_ui()

func _update_ui() -> void:
	if _restaurant_option != null:
		_restaurant_option.visible = (_mode == "move_restaurant")
		_restaurant_option.disabled = (_mode != "move_restaurant")

	if confirm_btn != null:
		confirm_btn.text = "确认移动" if _mode == "move_restaurant" else "确认放置"

	_update_hint()
	_update_confirm_state()

func _update_hint() -> void:
	if hint_label == null:
		return

	if not _validation_ok and not _validation_message.is_empty():
		hint_label.text = "无法放置：%s" % _validation_message
		return

	if _mode == "move_restaurant":
		if _selected_restaurant_id.is_empty():
			hint_label.text = "请选择要移动的餐厅，并在地图上点击目标位置"
			return
		if _selected_position == Vector2i(-1, -1):
			hint_label.text = "已选择餐厅: %s，请在地图上点击目标位置" % _selected_restaurant_id
			return
		hint_label.text = "餐厅 %s → (%d,%d) 旋转:%d°" % [
			_selected_restaurant_id,
			_selected_position.x,
			_selected_position.y,
			_selected_rotation
		]
		return

	# place_restaurant
	if _selected_position == Vector2i(-1, -1):
		hint_label.text = "请在地图上点击放置位置"
	else:
		hint_label.text = "放置位置: (%d,%d) 旋转:%d°" % [_selected_position.x, _selected_position.y, _selected_rotation]

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return

	var ok := true
	ok = ok and (_selected_position != Vector2i(-1, -1))
	if _mode == "move_restaurant":
		ok = ok and not _selected_restaurant_id.is_empty()
	ok = ok and _validation_ok
	confirm_btn.disabled = not ok

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_position == Vector2i(-1, -1):
		return

	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	placement_confirmed.emit(_selected_position, _selected_rotation, rid)

func _on_cancel_pressed() -> void:
	cancelled.emit()
	visible = false
	preview_cleared.emit()
	_emit_highlight_request()

func _emit_preview() -> void:
	if _selected_position == Vector2i(-1, -1):
		preview_cleared.emit()
		return
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	preview_requested.emit(_mode, _selected_position, _selected_rotation, rid)

func _emit_highlight_request() -> void:
	var rid := _selected_restaurant_id if _mode == "move_restaurant" else ""
	highlight_requested.emit(_mode, _selected_rotation, rid)
