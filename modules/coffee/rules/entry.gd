extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

const PlaceOrMoveCoffeeShopActionClass = preload("res://modules/coffee/actions/place_or_move_coffee_shop_action.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

const MODULE_ID := "coffee"
const COFFEE_ID := "coffee"

func register(registrar) -> Result:
	var r = registrar.register_action_executor(PlaceOrMoveCoffeeShopActionClass.new())
	if not r.ok:
		return r

	r = registrar.register_state_initializer("%s:init_state" % MODULE_ID, Callable(self, "_init_state"), 50)
	if not r.ok:
		return r

	r = registrar.register_extension_settlement(Phase.CLEANUP, Point.ENTER, Callable(self, "_cleanup_discard_coffee"), 150)
	if not r.ok:
		return r

	r = registrar.register_dinnertime_route_purchase_provider("%s:route:coffee" % MODULE_ID, Callable(self, "_dinnertime_route_coffee"), 50)
	if not r.ok:
		return r

	return Result.success()

func _init_state(state: GameState, _rng_manager) -> Result:
	if state == null:
		return Result.failure("coffee:init_state: state 为空")
	if not (state.players is Array):
		return Result.failure("coffee:init_state: state.players 类型错误（期望 Array）")
	if not (state.map is Dictionary):
		return Result.failure("coffee:init_state: state.map 类型错误（期望 Dictionary）")

	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("coffee:init_state: player[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		player["coffee_shop_tokens_remaining"] = 3
		state.players[pid] = player

	if not state.map.has("coffee_shops"):
		state.map["coffee_shops"] = {}
	if not (state.map["coffee_shops"] is Dictionary):
		return Result.failure("coffee:init_state: state.map.coffee_shops 类型错误（期望 Dictionary）")
	if not state.map.has("next_coffee_shop_id"):
		state.map["next_coffee_shop_id"] = 1
	if not (state.map["next_coffee_shop_id"] is int):
		return Result.failure("coffee:init_state: state.map.next_coffee_shop_id 类型错误（期望 int）")

	return Result.success()

func _cleanup_discard_coffee(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("coffee:cleanup: state 为空")
	if not (state.players is Array):
		return Result.failure("coffee:cleanup: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("coffee:cleanup: state.round_state 类型错误（期望 Dictionary）")

	var discarded: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("coffee:cleanup: player[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		var inv_val = player.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("coffee:cleanup: player[%d].inventory 类型错误（期望 Dictionary）" % pid)
		var inv: Dictionary = inv_val
		var before: int = int(inv.get(COFFEE_ID, 0))
		if before > 0:
			inv[COFFEE_ID] = 0
			player["inventory"] = inv
			state.players[pid] = player
			discarded.append({
				"player_id": pid,
				"amount": before,
			})

	state.round_state["coffee"] = {
		"discarded": discarded
	}
	return Result.success()

func _dinnertime_route_coffee(state: GameState, ctx: Dictionary) -> Result:
	if state == null:
		return Result.failure("coffee:route: state 为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("coffee:route: ctx 类型错误（期望 Dictionary）")
	var house_id: String = str(ctx.get("house_id", ""))
	if house_id.is_empty():
		return Result.failure("coffee:route: house_id 为空")
	var house_val = ctx.get("house", null)
	if not (house_val is Dictionary):
		return Result.failure("coffee:route: house 类型错误（期望 Dictionary）")
	var house: Dictionary = house_val
	var winner_restaurant_id: String = str(ctx.get("winner_restaurant_id", ""))
	if winner_restaurant_id.is_empty():
		return Result.failure("coffee:route: winner_restaurant_id 为空")
	var road_graph = ctx.get("road_graph", null)
	if road_graph == null or not road_graph.has_method("get_reachable_neighbors"):
		return Result.failure("coffee:route: road_graph 无效")

	# 计算 house / winner restaurant 对应的“可上路点”
	var house_cells_any: Array = house.get("cells", [])
	var house_cells: Array[Vector2i] = []
	for i in range(house_cells_any.size()):
		var p = house_cells_any[i]
		if not (p is Vector2i):
			return Result.failure("coffee:route: house.cells[%d] 类型错误（期望 Vector2i）" % i)
		house_cells.append(p)
	var house_roads := _get_structure_adjacent_roads(state, house_cells)
	if house_roads.is_empty():
		return Result.success({"purchases": [], "income_by_player": {}})

	var rest := MapRuntimeClass.get_restaurant(state, winner_restaurant_id)
	var entrance_points_read := _get_restaurant_entrance_points(state, rest)
	if not entrance_points_read.ok:
		return entrance_points_read
	var entrance_points_any = entrance_points_read.value
	if not (entrance_points_any is Array):
		return Result.failure("coffee:route: entrance_points 类型错误（期望 Array[Vector2i]）")
	var entrance_points: Array[Vector2i] = []
	var entrance_any: Array = entrance_points_any
	for i in range(entrance_any.size()):
		var p = entrance_any[i]
		if not (p is Vector2i):
			return Result.failure("coffee:route: entrance_points[%d] 类型错误（期望 Vector2i）" % i)
		entrance_points.append(p)
	var rest_roads := _get_structure_adjacent_roads(state, entrance_points)
	if rest_roads.is_empty():
		return Result.success({"purchases": [], "income_by_player": {}})

	# 找到最小 boundary_crossings（跨板块次数）- primary
	var min_crossings := INF
	var candidate_pairs: Array[Dictionary] = []
	for s in house_roads:
		for t in rest_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok:
				continue
			var spv: Dictionary = sp.value
			var c: int = int(spv.get("boundary_crossings", spv.get("distance", INF)))
			if c < min_crossings:
				min_crossings = c
				candidate_pairs = [{"start": s, "end": t}]
			elif c == min_crossings:
				candidate_pairs.append({"start": s, "end": t})
	if min_crossings == INF:
		return Result.success({"purchases": [], "income_by_player": {}})

	# 构建“路过可买咖啡”的索引：road_pos -> [{kind, id, owner}]
	var stop_index_read := _build_coffee_stop_index(state, winner_restaurant_id)
	if not stop_index_read.ok:
		return stop_index_read
	var stop_index: Dictionary = stop_index_read.value

	# 预计算每个 owner 的单杯咖啡收入（复用 PricingPipeline）
	var cup_breakdowns := {}
	for pid in range(state.players.size()):
		var b_read := PricingPipelineClass.calculate_sale_breakdown(state, pid, house, {COFFEE_ID: 1})
		if not b_read.ok:
			return Result.failure("coffee: PricingPipeline 失败: %s" % b_read.error)
		cup_breakdowns[pid] = b_read.value

	var best := {
		"purchases": [],
		"income_by_player": {},
		"steps": INF,
		"path_key": "",
	}

	for pair_val in candidate_pairs:
		var pair: Dictionary = pair_val
		var start: Vector2i = pair["start"]
		var end: Vector2i = pair["end"]

		var dist_to_end := _compute_min_crossings_to_target(road_graph, end)
		if not dist_to_end.has(_pos_key(start)):
			continue

		var paths: Array = []
		var visited := {}
		visited[_pos_key(start)] = true
		var build_ok := _enumerate_paths_min_crossings(road_graph, start, end, min_crossings, 0, dist_to_end, visited, [start], paths, 2000)
		if not build_ok.ok:
			return build_ok

		for path_any in paths:
			var path: Array[Vector2i] = path_any
			var sim := _simulate_coffee_purchases(state, path, stop_index, cup_breakdowns)
			if not sim.ok:
				return sim
			var simv: Dictionary = sim.value
			var purchases: Array = simv.get("purchases", [])
			var income_by_player: Dictionary = simv.get("income_by_player", {})

			var purchase_count := purchases.size()
			var best_count := int(best["purchases"].size())
			var steps: int = path.size() - 1
			var key := _path_key(path)

			var better := false
			if purchase_count > best_count:
				better = true
			elif purchase_count == best_count:
				if steps < int(best["steps"]):
					better = true
				elif steps == int(best["steps"]):
					better = key < str(best["path_key"])

			if better:
				best["purchases"] = purchases
				best["income_by_player"] = income_by_player
				best["steps"] = steps
				best["path_key"] = key

	# 执行购买：扣库存 + 银行支付
	var warnings: Array[String] = []
	var paid_by_player: Dictionary = {}
	for p_val in best["purchases"]:
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var seller: int = int(p.get("seller", -1))
		var price: int = int(p.get("price", 0))
		if seller < 0 or seller >= state.players.size():
			return Result.failure("coffee: seller 越界: %d" % seller)

		var player: Dictionary = state.players[seller]
		var inv: Dictionary = player.get("inventory", {})
		var before: int = int(inv.get(COFFEE_ID, 0))
		if before <= 0:
			return Result.failure("coffee: 库存不足（应在模拟阶段避免）: player=%d" % seller)
		inv[COFFEE_ID] = before - 1
		player["inventory"] = inv
		state.players[seller] = player

		if price > 0:
			var pay := BankruptcyRulesClass.pay_bank_to_player(state, seller, price, "咖啡收入")
			if not pay.ok:
				return Result.failure("coffee: 银行支付失败: %s" % pay.error)
			warnings.append_array(pay.warnings)
			paid_by_player[seller] = int(paid_by_player.get(seller, 0)) + price

	return Result.success({
		"purchases": best["purchases"],
		"income_by_player": paid_by_player,
	}).with_warnings(warnings)

static func _simulate_coffee_purchases(state: GameState, path: Array[Vector2i], stop_index: Dictionary, cup_breakdowns: Dictionary) -> Result:
	var inv_left := {}
	for pid in range(state.players.size()):
		var player: Dictionary = state.players[pid]
		var inv: Dictionary = player.get("inventory", {})
		inv_left[pid] = int(inv.get(COFFEE_ID, 0))

	var purchases: Array[Dictionary] = []
	var income_by_player: Dictionary = {}
	var visited_locations := {}

	for pos in path:
		var key := _pos_key(pos)
		if not stop_index.has(key):
			continue
		var list_val = stop_index[key]
		if not (list_val is Array):
			continue
		var list: Array = list_val
		for item_val in list:
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			var loc_id: String = str(item.get("id", ""))
			if loc_id.is_empty() or visited_locations.has(loc_id):
				continue
			var seller: int = int(item.get("owner", -1))
			if seller < 0:
				continue
			if int(inv_left.get(seller, 0)) <= 0:
				continue

			var bd_val = cup_breakdowns.get(seller, null)
			if not (bd_val is Dictionary):
				return Result.failure("coffee: cup_breakdowns[%d] 缺失" % seller)
			var bd: Dictionary = bd_val
			var price: int = int(bd.get("revenue", 0))

			purchases.append({
				"kind": "coffee",
				"seller": seller,
				"source_kind": str(item.get("kind", "")),
				"source_id": loc_id,
				"at": [pos.x, pos.y],
				"price": price,
			})
			inv_left[seller] = int(inv_left.get(seller, 0)) - 1
			visited_locations[loc_id] = true
			income_by_player[seller] = int(income_by_player.get(seller, 0)) + maxi(0, price)

	return Result.success({
		"purchases": purchases,
		"income_by_player": income_by_player,
	})

static func _build_coffee_stop_index(state: GameState, exclude_restaurant_id: String) -> Result:
	var out: Dictionary = {}

	# restaurants
	if not (state.map is Dictionary) or not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("coffee: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]
	for rid_val in restaurants.keys():
		var rid: String = str(rid_val)
		if rid.is_empty() or rid == exclude_restaurant_id:
			continue
		var rest_val = restaurants[rid_val]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var owner: int = int(rest.get("owner", -1))
		if owner < 0:
			continue
		var entrance_points_read := _get_restaurant_entrance_points(state, rest)
		if not entrance_points_read.ok:
			return entrance_points_read
		var entrance_points_any = entrance_points_read.value
		if not (entrance_points_any is Array):
			return Result.failure("coffee: entrance_points 类型错误（期望 Array[Vector2i]）: %s" % rid)
		var entrance_points: Array[Vector2i] = []
		var entrance_any: Array = entrance_points_any
		for i in range(entrance_any.size()):
			var p = entrance_any[i]
			if not (p is Vector2i):
				return Result.failure("coffee: entrance_points[%d] 类型错误（期望 Vector2i）: %s" % [i, rid])
			entrance_points.append(p)
		var roads := _get_structure_adjacent_roads(state, entrance_points)
		for rp in roads:
			var k := _pos_key(rp)
			if not out.has(k):
				out[k] = []
			var list: Array = out[k]
			list.append({"kind": "restaurant", "id": rid, "owner": owner})
			out[k] = list

	# coffee shops
	if not state.map.has("coffee_shops") or not (state.map["coffee_shops"] is Dictionary):
		return Result.failure("coffee: state.map.coffee_shops 缺失或类型错误（期望 Dictionary）")
	var shops: Dictionary = state.map["coffee_shops"]
	for sid_val in shops.keys():
		var sid: String = str(sid_val)
		if sid.is_empty():
			continue
		var shop_val = shops[sid_val]
		if not (shop_val is Dictionary):
			continue
		var shop: Dictionary = shop_val
		var owner: int = int(shop.get("owner", -1))
		if owner < 0:
			continue
		var anchor_val = shop.get("anchor_pos", null)
		if not (anchor_val is Vector2i):
			return Result.failure("coffee: coffee_shop[%s].anchor_pos 类型错误（期望 Vector2i）" % sid)
		var roads := _get_structure_adjacent_roads(state, [anchor_val])
		for rp in roads:
			var k := _pos_key(rp)
			if not out.has(k):
				out[k] = []
			var list: Array = out[k]
			list.append({"kind": "coffee_shop", "id": sid, "owner": owner})
			out[k] = list

	# 稳定排序（同一 road_pos 上多个停靠点）
	for k in out.keys():
		var list_val = out[k]
		if list_val is Array:
			var list: Array = list_val
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if str(a.kind) != str(b.kind):
					return str(a.kind) < str(b.kind)
				return str(a.id) < str(b.id)
			)
			out[k] = list

	return Result.success(out)

static func _get_restaurant_entrance_points(state: GameState, rest: Dictionary) -> Result:
	if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
		return Result.failure("coffee: restaurant.entrance_pos 缺失或类型错误（期望 Vector2i）")
	var entrance: Vector2i = rest["entrance_pos"]
	var owner: int = int(rest.get("owner", -1))
	if owner < 0 or owner >= state.players.size():
		return Result.success([entrance])

	var player: Dictionary = state.players[owner]
	var drive_thru_active := false
	if player.has("drive_thru_active"):
		var v = player["drive_thru_active"]
		if not (v is bool):
			return Result.failure("coffee: drive_thru_active 类型错误（期望 bool）")
		drive_thru_active = bool(v)
	if not drive_thru_active:
		return Result.success([entrance])

	if not rest.has("cells") or not (rest["cells"] is Array):
		return Result.failure("coffee: restaurant.cells 缺失或类型错误（期望 Array[Vector2i]）")
	var cells_any: Array = rest["cells"]
	if cells_any.is_empty():
		return Result.success([entrance])
	var cells: Array[Vector2i] = []
	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("coffee: restaurant.cells[%d] 类型错误（期望 Vector2i）" % i)
		cells.append(c)

	var bounds := MapUtilsClass.get_footprint_bounds(cells)
	var min_pos: Vector2i = bounds["min"]
	var max_pos: Vector2i = bounds["max"]
	return Result.success([
		Vector2i(min_pos.x, min_pos.y),
		Vector2i(max_pos.x, min_pos.y),
		Vector2i(min_pos.x, max_pos.y),
		Vector2i(max_pos.x, max_pos.y),
	])

static func _get_structure_adjacent_roads(state: GameState, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		if MapRuntimeClass.has_cell_any(state, cell) and MapRuntimeClass.has_road_at_any(state, cell):
			set[_pos_key(cell)] = cell
		for dir in MapUtilsClass.DIRECTIONS:
			var n := MapUtilsClass.get_neighbor_pos(cell, dir)
			if not MapRuntimeClass.has_cell_any(state, n):
				continue
			if MapRuntimeClass.has_road_at_any(state, n):
				set[_pos_key(n)] = n
	var result: Array[Vector2i] = []
	for k in set.keys():
		result.append(set[k])
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return result

static func _compute_min_crossings_to_target(road_graph, target: Vector2i) -> Dictionary:
	# 0-1 BFS on road positions
	var dist: Dictionary = {}
	var dq: Array[Vector2i] = []
	dist[_pos_key(target)] = 0
	dq.append(target)

	while not dq.is_empty():
		var cur: Vector2i = dq.pop_front()
		var cur_key := _pos_key(cur)
		var cur_d: int = int(dist[cur_key])
		var neighbors: Array[Vector2i] = road_graph.get_reachable_neighbors(cur)
		for nb in neighbors:
			var w: int = 1 if MapUtilsClass.crosses_tile_boundary(cur, nb) else 0
			var nk := _pos_key(nb)
			var nd := cur_d + w
			if not dist.has(nk) or nd < int(dist[nk]):
				dist[nk] = nd
				if w == 0:
					dq.push_front(nb)
				else:
					dq.append(nb)

	return dist

static func _enumerate_paths_min_crossings(
	road_graph,
	current: Vector2i,
	target: Vector2i,
	min_crossings: int,
	current_crossings: int,
	dist_to_target: Dictionary,
	visited: Dictionary,
	path: Array[Vector2i],
	out_paths: Array,
	max_paths: int
) -> Result:
	if out_paths.size() > max_paths:
		return Result.failure("coffee: 路径数量过多（>%d），无法确定性比较" % max_paths)
	if current == target:
		out_paths.append(path.duplicate())
		return Result.success()

	var cur_key := _pos_key(current)
	if not dist_to_target.has(cur_key):
		return Result.success()

	var neighbors: Array[Vector2i] = road_graph.get_reachable_neighbors(current)
	neighbors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	for nb in neighbors:
		var nk := _pos_key(nb)
		if visited.has(nk):
			continue
		if not dist_to_target.has(nk):
			continue
		var w: int = 1 if MapUtilsClass.crosses_tile_boundary(current, nb) else 0
		var next_crossings := current_crossings + w
		if next_crossings > min_crossings:
			continue
		var rem := int(dist_to_target[nk])
		if next_crossings + rem != min_crossings:
			continue
		visited[nk] = true
		path.append(nb)
		var r := _enumerate_paths_min_crossings(road_graph, nb, target, min_crossings, next_crossings, dist_to_target, visited, path, out_paths, max_paths)
		if not r.ok:
			return r
		path.pop_back()
		visited.erase(nk)

	return Result.success()

static func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

static func _path_key(path: Array[Vector2i]) -> String:
	var parts: Array[String] = []
	for p in path:
		parts.append(_pos_key(p))
	return "|".join(parts)
