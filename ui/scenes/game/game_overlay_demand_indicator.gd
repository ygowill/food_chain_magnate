# Game scene：需求指示器
extends RefCounted

const DemandIndicatorScene = preload("res://ui/components/demand_indicator/demand_indicator.tscn")
const OverlayUtils = preload("res://ui/scenes/game/game_overlay_utils.gd")

var _scene = null
var _map_canvas = null
var _bank_break_panel = null

var demand_indicator = null

func _init(scene, map_canvas) -> void:
	_scene = scene
	_map_canvas = map_canvas

func set_bank_break_panel(panel) -> void:
	_bank_break_panel = panel

func sync_demand_indicator(state: GameState) -> void:
	if state == null:
		_hide_demand_indicator()
		return
	if state.phase != "Dinnertime":
		_hide_demand_indicator()
		return
	if is_instance_valid(_bank_break_panel) and _bank_break_panel.visible:
		_hide_demand_indicator()
		return

	_ensure_demand_indicator()
	if not is_instance_valid(demand_indicator):
		return

	_sync_demand_indicator_transform()

	if demand_indicator.has_method("set_house_demands"):
		demand_indicator.set_house_demands(_build_dinnertime_demand_indicator_data(state))

	demand_indicator.visible = true

func hide() -> void:
	_hide_demand_indicator()

func _ensure_demand_indicator() -> void:
	if _scene == null:
		return

	if demand_indicator == null or not is_instance_valid(demand_indicator):
		demand_indicator = DemandIndicatorScene.instantiate()

	var parent: Node = _map_canvas if is_instance_valid(_map_canvas) else _scene
	if is_instance_valid(demand_indicator) and demand_indicator.get_parent() != parent:
		var old_parent = demand_indicator.get_parent()
		if old_parent != null:
			old_parent.remove_child(demand_indicator)
		parent.add_child(demand_indicator)

func _sync_demand_indicator_transform() -> void:
	if not is_instance_valid(demand_indicator):
		return
	if not is_instance_valid(_map_canvas):
		return

	var cell_size := 40
	if _map_canvas.has_method("get_cell_size"):
		cell_size = int(_map_canvas.call("get_cell_size"))

	var world_origin := Vector2i.ZERO
	if _map_canvas.has_method("get_world_origin"):
		var wo = _map_canvas.call("get_world_origin")
		if wo is Vector2i:
			world_origin = wo

	if demand_indicator.has_method("set_tile_size"):
		demand_indicator.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if demand_indicator.has_method("set_map_offset"):
		demand_indicator.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))

func _hide_demand_indicator() -> void:
	if is_instance_valid(demand_indicator):
		if demand_indicator.has_method("clear_all"):
			demand_indicator.clear_all()
		demand_indicator.visible = false

func _build_dinnertime_demand_indicator_data(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	if not (state.round_state is Dictionary):
		return out
	var dt_val = (state.round_state as Dictionary).get("dinnertime", null)
	if not (dt_val is Dictionary):
		return out
	var dt: Dictionary = dt_val

	var sales_val = dt.get("sales", [])
	if sales_val is Array:
		for sale_val in sales_val:
			if not (sale_val is Dictionary):
				continue
			var sale: Dictionary = sale_val
			var house_id := str(sale.get("house_id", ""))
			if house_id.is_empty():
				continue
			var pos := OverlayUtils.get_house_anchor_world_pos(state, house_id)
			if pos == Vector2i(-1, -1):
				continue
			var required := OverlayUtils.normalize_count_dict(sale.get("required", {}))
			if required.is_empty():
				continue
			out[house_id] = {
				"demands": required,
				"position": pos,
				"satisfied": true,
			}

	return out

