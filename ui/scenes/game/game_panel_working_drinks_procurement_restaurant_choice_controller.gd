# Game scene：Working/Drinks Procurement 起点餐厅选择 UI/overlay 同步
# 拆分自：`game_panel_working_drinks_procurement_controller.gd`
extends RefCounted

const StructuresClass = preload("res://core/map/map_runtime/structures.gd")

var _controller_ref: WeakRef = null

func setup(controller) -> void:
	_controller_ref = weakref(controller)

func _get_controller():
	if _controller_ref == null:
		return null
	return _controller_ref.get_ref()

func clear_ui_and_overlays() -> void:
	var c = _get_controller()
	if c == null:
		return
	var canvas = c._get_map_canvas()
	if canvas != null and canvas.has_method("clear_procure_drinks_restaurant_indices"):
		canvas.call("clear_procure_drinks_restaurant_indices")
	elif canvas != null and canvas.has_method("clear_procure_drinks_selected_restaurant_anchor"):
		canvas.call("clear_procure_drinks_selected_restaurant_anchor")
	if canvas != null and canvas.has_method("clear_procure_drinks_hovered_restaurant_anchor"):
		canvas.call("clear_procure_drinks_hovered_restaurant_anchor")

	if is_instance_valid(c.production_panel) and c.production_panel.has_method("set_drinks_procure_restaurants"):
		var empty: Array[Dictionary] = []
		c.production_panel.set_drinks_procure_restaurants(empty, "", false)
	if is_instance_valid(c.production_panel) and c.production_panel.has_method("set_drinks_hover_preview_text"):
		c.production_panel.call("set_drinks_hover_preview_text", "")

	c._procure_hover_start_restaurant_id = ""
	c._procure_hover_preview_active = false

func sync_ui_and_overlays(state: GameState) -> void:
	var c = _get_controller()
	if c == null:
		return
	if state == null:
		return
	if str(c._procure_selected_employee_type).is_empty() or str(c._procure_selected_employee_type) == "errand_boy":
		return

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty():
		return
	restaurant_ids.sort()

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return
	var restaurants: Dictionary = restaurants_val

	var index_by_id: Dictionary = {}
	for i in range(restaurant_ids.size()):
		index_by_id[str(restaurant_ids[i])] = i + 1

	var options: Array[Dictionary] = []
	var index_by_anchor: Dictionary = {}
	for rid in restaurant_ids:
		if not restaurants.has(rid):
			continue
		var rest_val = restaurants[rid]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var idx := int(index_by_id.get(rid, options.size() + 1))
		var ep = rest.get("entrance_pos", null)
		var entrance_pos: Vector2i = Vector2i(-1, -1)
		if ep is Vector2i:
			entrance_pos = Vector2i(ep)

		var label := "餐厅 %d" % idx
		if entrance_pos != Vector2i(-1, -1):
			label = "餐厅 %d @ (%d,%d)" % [idx, entrance_pos.x, entrance_pos.y]
		options.append({"id": rid, "label": label})

		if restaurant_ids.size() > 1 and entrance_pos != Vector2i(-1, -1):
			index_by_anchor[entrance_pos] = idx

	var is_air = bool(c._is_air_procure_employee_type(str(c._procure_selected_employee_type)))
	var require_selection := is_air and restaurant_ids.size() > 1

	var selected_id := str(c._procure_selected_start_restaurant_id).strip_edges()
	if selected_id.is_empty() and is_air:
		selected_id = str(c._procure_air_start_restaurant_id).strip_edges()
	if selected_id.is_empty() and (not is_air):
		selected_id = str(restaurant_ids[0]).strip_edges()
		c._procure_selected_start_restaurant_id = selected_id

	if is_instance_valid(c.production_panel) and c.production_panel.has_method("set_drinks_procure_restaurants"):
		c.production_panel.set_drinks_procure_restaurants(options, selected_id, require_selection)

	var canvas = c._get_map_canvas()
	if canvas != null:
		if canvas.has_method("set_procure_drinks_restaurant_indices"):
			if restaurant_ids.size() > 1:
				canvas.call("set_procure_drinks_restaurant_indices", index_by_anchor)
			elif canvas.has_method("clear_procure_drinks_restaurant_indices"):
				canvas.call("clear_procure_drinks_restaurant_indices")

		var selected_anchor := Vector2i(-1, -1)
		if not selected_id.is_empty() and restaurants.has(selected_id) and (restaurants[selected_id] is Dictionary):
			var rest2: Dictionary = restaurants[selected_id]
			var ep2 = rest2.get("entrance_pos", null)
			if ep2 is Vector2i:
				selected_anchor = Vector2i(ep2)

		if canvas.has_method("set_procure_drinks_selected_restaurant_anchor"):
			if selected_anchor != Vector2i(-1, -1):
				canvas.call("set_procure_drinks_selected_restaurant_anchor", selected_anchor)
			elif canvas.has_method("clear_procure_drinks_selected_restaurant_anchor"):
				canvas.call("clear_procure_drinks_selected_restaurant_anchor")

