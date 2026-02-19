# 晚餐结算动画：坐标换算与目标位置辅助
class_name DinnertimeAnimationPositionHelpers
extends RefCounted

static func get_world_origin(map_canvas) -> Vector2i:
	if map_canvas != null and is_instance_valid(map_canvas) and map_canvas.has_method("get_world_origin"):
		var ov = map_canvas.get_world_origin()
		if ov is Vector2i:
			return ov
	return Vector2i.ZERO

static func get_cell_size(map_canvas) -> float:
	if map_canvas != null and is_instance_valid(map_canvas):
		return float(map_canvas.get_cell_size())
	return 40.0

static func get_piece_screen_rect(map_canvas, cells: Array[Vector2i], world_origin: Vector2i) -> Rect2:
	if cells.is_empty() or map_canvas == null or not is_instance_valid(map_canvas):
		return Rect2(Vector2(400, 300), Vector2(40, 40))
	var cs := int(map_canvas.get_cell_size())
	var base: Vector2 = (map_canvas as Control).global_position
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c in cells:
		var view := c - world_origin
		var tl := base + Vector2(view) * float(cs)
		var br := tl + Vector2(cs, cs)
		min_v = Vector2(minf(min_v.x, tl.x), minf(min_v.y, tl.y))
		max_v = Vector2(maxf(max_v.x, br.x), maxf(max_v.y, br.y))
	return Rect2(min_v, max_v - min_v)

static func get_piece_canvas_rect(map_canvas, cells: Array[Vector2i], world_origin: Vector2i) -> Rect2:
	if cells.is_empty() or map_canvas == null or not is_instance_valid(map_canvas):
		return Rect2()
	var cs := int(map_canvas.get_cell_size())
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c in cells:
		var view := c - world_origin
		var tl := Vector2(view) * float(cs)
		var br := tl + Vector2(cs, cs)
		min_v = Vector2(minf(min_v.x, tl.x), minf(min_v.y, tl.y))
		max_v = Vector2(maxf(max_v.x, br.x), maxf(max_v.y, br.y))
	return Rect2(min_v, max_v - min_v)

static func global_to_layer(anim_layer: Control, global_pos: Vector2) -> Vector2:
	if is_instance_valid(anim_layer):
		return global_pos - anim_layer.global_position
	return global_pos

static func get_bank_label_global_center(bank_label: Label) -> Vector2:
	if is_instance_valid(bank_label):
		return bank_label.global_position + bank_label.size * 0.5
	return Vector2(400, 30)

static func get_player_tab_global_center(player_panel, player_id: int) -> Vector2:
	if player_panel != null and is_instance_valid(player_panel):
		var grid = player_panel.get("overview_grid")
		if grid is Control and is_instance_valid(grid):
			for node in (grid as Control).get_children():
				if not (node is Control) or not is_instance_valid(node):
					continue
				var card: Control = node
				if card.has_meta("player_id") and int(card.get_meta("player_id")) == player_id:
					var cash: Label = card.find_child("CashLabel", true, false)
					if cash != null and is_instance_valid(cash):
						return cash.global_position + cash.size * 0.5
					return card.global_position + card.size * 0.5
			var cards = (grid as Control).get_children()
			if player_id >= 0 and player_id < cards.size():
				var card2 = cards[player_id]
				if card2 is Control and is_instance_valid(card2):
					var cash2: Label = (card2 as Control).find_child("CashLabel", true, false)
					if cash2 != null and is_instance_valid(cash2):
						return cash2.global_position + cash2.size * 0.5
					return (card2 as Control).global_position + (card2 as Control).size * 0.5
	return Vector2(100, 200)

static func get_revenue_target_global_center(player_panel, sale: Dictionary, owner_id: int) -> Vector2:
	var restaurant_id := str(sale.get("matched_restaurant", sale.get("winner_restaurant_id", ""))).strip_edges()
	if player_panel != null and is_instance_valid(player_panel):
		var grid = player_panel.get("overview_grid")
		if grid is Control and is_instance_valid(grid):
			for node in (grid as Control).get_children():
				if not (node is Control) or not is_instance_valid(node):
					continue
				var card: Control = node
				if not card.has_meta("player_id") or int(card.get_meta("player_id")) != owner_id:
					continue
				if card.has_meta("restaurant_id"):
					var card_restaurant_id := str(card.get_meta("restaurant_id")).strip_edges()
					if not restaurant_id.is_empty() and not card_restaurant_id.is_empty() and card_restaurant_id != restaurant_id:
						continue
				var cash: Label = card.find_child("CashLabel", true, false)
				if cash != null and is_instance_valid(cash):
					return cash.global_position + cash.size * 0.5
				return card.global_position + card.size * 0.5
	return get_player_tab_global_center(player_panel, owner_id)
