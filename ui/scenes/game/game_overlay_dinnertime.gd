# Game scene：晚餐时间 overlay（只读）
extends RefCounted

const DinnerTimeOverlayScene = preload("res://ui/components/dinner_time/dinner_time_overlay.tscn")
const OverlayUtils = preload("res://ui/scenes/game/game_overlay_utils.gd")

var _scene = null
var _bank_break_panel = null

var dinner_time_overlay = null

func _init(scene) -> void:
	_scene = scene

func set_bank_break_panel(panel) -> void:
	_bank_break_panel = panel

func sync_dinnertime_overlay(state: GameState) -> void:
	if state == null:
		_hide_dinnertime_overlay()
		return
	if state.phase != "Dinnertime":
		_hide_dinnertime_overlay()
		return
	if is_instance_valid(_bank_break_panel) and _bank_break_panel.visible:
		return

	_ensure_dinnertime_overlay()
	if not is_instance_valid(dinner_time_overlay):
		return
	if dinner_time_overlay.visible:
		return

	var orders := _build_dinnertime_orders(state)
	if dinner_time_overlay.has_method("set_pending_orders"):
		dinner_time_overlay.set_pending_orders(orders)
	if dinner_time_overlay.has_method("show_overlay"):
		dinner_time_overlay.show_overlay()
	else:
		dinner_time_overlay.visible = true

func hide() -> void:
	_hide_dinnertime_overlay()

func _ensure_dinnertime_overlay() -> void:
	if _scene == null:
		return
	if dinner_time_overlay != null and is_instance_valid(dinner_time_overlay):
		return

	dinner_time_overlay = DinnerTimeOverlayScene.instantiate()
	if is_instance_valid(dinner_time_overlay):
		if dinner_time_overlay.has_signal("phase_completed"):
			dinner_time_overlay.phase_completed.connect(_on_dinnertime_phase_completed)
		_scene.add_child(dinner_time_overlay)

func _hide_dinnertime_overlay() -> void:
	if is_instance_valid(dinner_time_overlay):
		dinner_time_overlay.visible = false

func _on_dinnertime_phase_completed() -> void:
	_hide_dinnertime_overlay()

func _build_dinnertime_orders(state: GameState) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if state == null:
		return orders
	if not (state.round_state is Dictionary):
		return orders

	var dt_val = (state.round_state as Dictionary).get("dinnertime", null)
	if not (dt_val is Dictionary):
		return orders
	var dt: Dictionary = dt_val

	var raw_orders: Array[Dictionary] = []

	var sales_val = dt.get("sales", [])
	if sales_val is Array:
		for sale_val in sales_val:
			if not (sale_val is Dictionary):
				continue
			var sale: Dictionary = sale_val
			var house_id := str(sale.get("house_id", ""))
			if house_id.is_empty():
				continue
			var house_number := OverlayUtils.coerce_int(sale.get("house_number", -1))
			var required := OverlayUtils.normalize_count_dict(sale.get("required", {}))
			var rest_id := str(sale.get("winner_restaurant_id", ""))
			raw_orders.append({
				"house_number": house_number,
				"house_id": house_id,
				"demands": required.duplicate(true),
				"matched_restaurant": rest_id,
				"products": required.duplicate(true),
			})

	var skipped_val = dt.get("skipped", [])
	if skipped_val is Array:
		for sk_val in skipped_val:
			if not (sk_val is Dictionary):
				continue
			var sk: Dictionary = sk_val
			var house_id2 := str(sk.get("house_id", ""))
			if house_id2.is_empty():
				continue
			var house_number2 := OverlayUtils.coerce_int(sk.get("house_number", -1))
			raw_orders.append({
				"house_number": house_number2,
				"house_id": house_id2,
				"demands": OverlayUtils.build_house_demand_counts_from_map(state, house_id2),
				"matched_restaurant": "",
				"products": {},
			})

	raw_orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("house_number", -1)) < int(b.get("house_number", -1))
	)

	for o in raw_orders:
		orders.append(o)
	return orders

