class_name CoffeeShopPlacementOverlay
extends Control

signal placement_confirmed(action_id: String, mode: String, position: Vector2i, from_shop_id: String)
signal highlight_refresh_requested()
signal ui_state_changed()

const ActionPanelContextScenePath := "res://modules/coffee/ui/components/coffee_shop/action_panel_coffee_shop_context.gd"

var _action_id: String = ""
var _mode: String = "place" # place | move

var _tokens_remaining: int = 0
var _triggers_remaining: int = 0

var _available_shops: Array[Dictionary] = [] # [{shop_id:String, anchor_pos:Vector2i}]
var _selected_from_shop_id: String = ""

var _selected_position: Vector2i = Vector2i(-1, -1)

var _validation_ok: bool = true
var _validation_message: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func setup_for_action(action_id: String, mode: String, tokens_remaining: int, triggers_remaining: int, available_shops: Array[Dictionary]) -> void:
	var aid := str(action_id).strip_edges()
	var m := str(mode).strip_edges()
	if m != "place" and m != "move":
		m = "place"

	var action_changed := (aid != _action_id)
	var mode_changed := (m != _mode)

	_action_id = aid
	_mode = m
	_tokens_remaining = int(tokens_remaining)
	_triggers_remaining = int(triggers_remaining)
	_set_available_shops_internal(available_shops)

	if action_changed or mode_changed:
		clear_target()

	if _mode == "place":
		if not _selected_from_shop_id.is_empty():
			_selected_from_shop_id = ""
			highlight_refresh_requested.emit()

	if _mode == "move":
		if _selected_from_shop_id.is_empty() or not _has_shop_id(_selected_from_shop_id):
			_selected_from_shop_id = _available_shops[0].get("shop_id", "") if not _available_shops.is_empty() else ""
			clear_target()
			highlight_refresh_requested.emit()

	ui_state_changed.emit()

func get_action_id() -> String:
	return _action_id

func get_mode() -> String:
	return _mode

func get_tokens_remaining() -> int:
	return _tokens_remaining

func get_triggers_remaining() -> int:
	return _triggers_remaining

func get_available_shops() -> Array[Dictionary]:
	return _available_shops.duplicate(true)

func get_selected_from_shop_id() -> String:
	return _selected_from_shop_id

func set_selected_from_shop_id(shop_id: String) -> void:
	var sid := str(shop_id).strip_edges()
	if sid.is_empty():
		return
	if not _has_shop_id(sid):
		return
	if sid == _selected_from_shop_id:
		return
	_selected_from_shop_id = sid
	clear_target()
	highlight_refresh_requested.emit()
	ui_state_changed.emit()

func get_selected_position() -> Vector2i:
	return _selected_position

func set_selected_position(position: Vector2i) -> void:
	_selected_position = Vector2i(position)
	_validation_ok = true
	_validation_message = ""
	ui_state_changed.emit()

func clear_target() -> void:
	_selected_position = Vector2i(-1, -1)
	_validation_ok = true
	_validation_message = ""
	ui_state_changed.emit()

func set_validation(valid: bool, message: String = "") -> void:
	_validation_ok = bool(valid)
	_validation_message = str(message).strip_edges()
	ui_state_changed.emit()

func can_confirm() -> bool:
	if not _validation_ok:
		return false
	if _selected_position == Vector2i(-1, -1):
		return false
	if _mode == "move" and _selected_from_shop_id.is_empty():
		return false
	return true

func request_confirm() -> void:
	if not can_confirm():
		return
	placement_confirmed.emit(_action_id, _mode, _selected_position, _selected_from_shop_id)

func request_cancel() -> void:
	visible = false
	ui_state_changed.emit()

func get_hint_text() -> String:
	if not _validation_ok and not _validation_message.is_empty():
		return "无法放置：%s" % _validation_message

	var mode_label := "放置" if _mode == "place" else "移动"
	var target_label := ""
	if _selected_position != Vector2i(-1, -1):
		target_label = " @ (%d,%d)" % [_selected_position.x, _selected_position.y]

	if _action_id == "place_or_move_coffee_shop":
		if _triggers_remaining > 0:
			if _mode == "move" and _selected_from_shop_id.is_empty():
				return "培训触发：你可以立即移动 1 个咖啡店（剩余 %d 次）。请先选择要移动的咖啡店。" % _triggers_remaining
			if _selected_position == Vector2i(-1, -1):
				return "培训触发：你可以立即%s 1 个咖啡店（剩余 %d 次）。请点击地图上高亮格选择位置（需在距离 2 内且邻接道路）。" % [mode_label, _triggers_remaining]
			return "培训触发：%s咖啡店%s（剩余 %d 次）" % [mode_label, target_label, _triggers_remaining]
		return "培训触发：你可以立即%s 1 个咖啡店。请点击地图上高亮格选择位置。" % mode_label

	if _action_id == "resolve_first_coffee_sold_bonus_coffee_shop":
		if _mode == "move" and _selected_from_shop_id.is_empty():
			return "里程碑奖励：请移动 1 个咖啡店。请先选择要移动的咖啡店。"
		if _selected_position == Vector2i(-1, -1):
			return "里程碑奖励：请%s 1 个咖啡店。请点击地图上高亮格选择位置（无距离限制，仍需邻接道路）。" % mode_label
		return "里程碑奖励：%s咖啡店%s" % [mode_label, target_label]

	if _selected_position == Vector2i(-1, -1):
		return "请点击地图上高亮格选择咖啡店位置"
	return "咖啡店%s" % target_label

func get_action_panel_context_spec() -> Dictionary:
	var title := "☕ 放置/移动咖啡店"
	if _action_id == "place_or_move_coffee_shop":
		title = "☕ 培训：放置/移动咖啡店"
	elif _action_id == "resolve_first_coffee_sold_bonus_coffee_shop":
		title = "☕ 首杯咖啡：额外咖啡店"

	var confirm_text := "确认放置" if _mode == "place" else "确认移动"
	return {
		"title": title,
		"hint": get_hint_text(),
		"confirm_text": confirm_text,
		"cancel_text": "关闭",
		"custom_scene": ActionPanelContextScenePath,
	}

func _set_available_shops_internal(shops_in: Array[Dictionary]) -> void:
	var out: Array[Dictionary] = []
	var seen := {}
	for v in shops_in:
		if not (v is Dictionary):
			continue
		var d: Dictionary = v
		var sid := str(d.get("shop_id", "")).strip_edges()
		if sid.is_empty() or seen.has(sid):
			continue
		var pos_val = d.get("anchor_pos", null)
		var pos: Vector2i = pos_val if pos_val is Vector2i else Vector2i(-1, -1)
		out.append({"shop_id": sid, "anchor_pos": pos})
		seen[sid] = true
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("shop_id", "")) < str(b.get("shop_id", ""))
	)
	_available_shops = out

func _has_shop_id(shop_id: String) -> bool:
	var sid := str(shop_id).strip_edges()
	if sid.is_empty():
		return false
	for d in _available_shops:
		if str(d.get("shop_id", "")) == sid:
			return true
	return false

