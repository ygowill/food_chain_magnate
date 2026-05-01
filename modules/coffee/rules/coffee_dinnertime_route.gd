extends RefCounted

const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const MODULE_ID := "coffee"
const COFFEE_ID := "coffee"

func register(registrar) -> Result:
	var r = registrar.register_dinnertime_route_purchase_provider("%s:route:coffee" % MODULE_ID, Callable(self, "_dinnertime_route_coffee"), 50)
	if not r.ok:
		return r

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

	var rest := StructuresClass.get_restaurant(state, winner_restaurant_id)
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

	var best_purchase_count := -1
	var best_paths: Array[Dictionary] = []  # [{path, purchases, income_by_player, visited_location_keys, path_key}]

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
			var path_key := _path_key(path)
			var visited_location_keys := _collect_stop_location_keys_for_path(path, stop_index)

			if purchase_count > best_purchase_count:
				best_purchase_count = purchase_count
				best_paths = [{
					"path": path,
					"purchases": purchases,
					"income_by_player": income_by_player,
					"visited_location_keys": visited_location_keys,
					"path_key": path_key,
				}]
			elif purchase_count == best_purchase_count:
				best_paths.append({
					"path": path,
					"purchases": purchases,
					"income_by_player": income_by_player,
					"visited_location_keys": visited_location_keys,
					"path_key": path_key,
				})

	var final_purchases: Array = []
	if best_paths.size() == 1:
		final_purchases = best_paths[0].get("purchases", [])
	elif best_paths.size() > 1:
		# 规则书：同最短且咖啡数量相同，则跳过“无法决定的路段”上的所有餐厅/咖啡店。
		# 这里按“所有同咖啡最优路径的公共停靠点”来确定可决定路段上的停靠点。
		var common := _intersect_location_key_sets(best_paths)
		var canonical: Dictionary = {}
		for entry_val in best_paths:
			var entry: Dictionary = entry_val
			if canonical.is_empty() or str(entry.get("path_key", "")) < str(canonical.get("path_key", "")):
				canonical = entry
		var path: Array[Vector2i] = canonical.get("path", [])
		var filtered := _simulate_coffee_purchases_filtered(state, path, stop_index, cup_breakdowns, common)
		if not filtered.ok:
			return filtered
		var fv: Dictionary = filtered.value
		final_purchases = fv.get("purchases", [])

	# 执行购买：扣库存 + 银行支付
	var warnings: Array[String] = []
	var paid_by_player: Dictionary = {}
	for i in range(final_purchases.size()):
		var purchase_read := _require_purchase(final_purchases[i], "coffee:route:final_purchases[%d]" % i)
		if not purchase_read.ok:
			return purchase_read
		var p: Dictionary = purchase_read.value
		var seller: int = int(p.get("seller", -1))
		var price: int = int(p.get("price", 0))
		if seller < 0 or seller >= state.players.size():
			return Result.failure("coffee: seller 越界: %d" % seller)

		var player_read := PlayerStateAccessClass.require_player(state, seller, "coffee:route:apply")
		if not player_read.ok:
			return player_read
		var player: Dictionary = player_read.value
		var inv_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % seller, "coffee:route:apply")
		if not inv_read.ok:
			return inv_read
		var inv: Dictionary = inv_read.value
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
		"purchases": final_purchases,
		"income_by_player": paid_by_player,
	}).with_warnings(warnings)

static func _simulate_coffee_purchases(state: GameState, path: Array[Vector2i], stop_index: Dictionary, cup_breakdowns: Dictionary) -> Result:
	var inv_left := {}
	for pid in range(state.players.size()):
		var inv_read := PlayerStateAccessClass.require_player_inventory(state, pid, "coffee:route:simulate")
		if not inv_read.ok:
			return inv_read
		var inv: Dictionary = inv_read.value
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
			return Result.failure("coffee: stop_index[%s] 类型错误（期望 Array）" % key)
		var list: Array = list_val
		for item_index in range(list.size()):
			var item_read := _require_stop_item(list[item_index], "coffee: stop_index[%s][%d]" % [key, item_index])
			if not item_read.ok:
				return item_read
			var item: Dictionary = item_read.value
			var kind: String = str(item.get("kind", ""))
			var loc_id: String = str(item.get("id", ""))
			var loc_key := _location_key(kind, loc_id)
			if visited_locations.has(loc_key):
				continue
			var seller: int = int(item.get("owner", -1))
			if seller < 0 or seller >= state.players.size():
				return Result.failure("coffee: stop_index[%s][%d].owner 越界: %d" % [key, item_index, seller])
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
				"source_kind": kind,
				"source_id": loc_id,
				"at": [pos.x, pos.y],
				"price": price,
			})
			inv_left[seller] = int(inv_left.get(seller, 0)) - 1
			visited_locations[loc_key] = true
			income_by_player[seller] = int(income_by_player.get(seller, 0)) + maxi(0, price)

	return Result.success({
		"purchases": purchases,
		"income_by_player": income_by_player,
	})

static func _build_coffee_stop_index(state: GameState, exclude_restaurant_id: String) -> Result:
	var out: Dictionary = {}

	# restaurants
	var restaurants_read := MapStateAccessClass.require_restaurants(state, "coffee:route:build_stop_index")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value
	for rid_val in restaurants.keys():
		if not (rid_val is String):
			return Result.failure("coffee: restaurants key 类型错误（期望 String）: %s" % str(rid_val))
		var rid: String = str(rid_val).strip_edges()
		if rid.is_empty():
			return Result.failure("coffee: restaurants key 不能为空")
		if rid == exclude_restaurant_id:
			continue
		var rest_val = restaurants[rid_val]
		if not (rest_val is Dictionary):
			return Result.failure("coffee: restaurants[%s] 类型错误（期望 Dictionary）" % rid)
		var rest: Dictionary = rest_val
		var owner_read := _parse_int_value(rest.get("owner", null), "coffee: restaurants[%s].owner" % rid)
		if not owner_read.ok:
			return owner_read
		var owner: int = int(owner_read.value)
		if owner < 0 or owner >= state.players.size():
			return Result.failure("coffee: restaurants[%s].owner 越界: %d" % [rid, owner])
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
	var shops_read := MapStateAccessClass.require_dict_field(state, "coffee_shops", "coffee:route:build_stop_index")
	if not shops_read.ok:
		return shops_read
	var shops: Dictionary = shops_read.value
	for sid_val in shops.keys():
		if not (sid_val is String):
			return Result.failure("coffee: coffee_shops key 类型错误（期望 String）: %s" % str(sid_val))
		var sid: String = str(sid_val).strip_edges()
		if sid.is_empty():
			return Result.failure("coffee: coffee_shops key 不能为空")
		var shop_val = shops[sid_val]
		if not (shop_val is Dictionary):
			return Result.failure("coffee: coffee_shops[%s] 类型错误（期望 Dictionary）" % sid)
		var shop: Dictionary = shop_val
		var owner_read := _parse_int_value(shop.get("owner", null), "coffee: coffee_shops[%s].owner" % sid)
		if not owner_read.ok:
			return owner_read
		var owner: int = int(owner_read.value)
		if owner < 0 or owner >= state.players.size():
			return Result.failure("coffee: coffee_shops[%s].owner 越界: %d" % [sid, owner])
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
	var rid := str(rest.get("restaurant_id", "")).strip_edges()
	if rid.is_empty():
		return Result.failure("coffee: restaurant.restaurant_id 为空")
	var read := StructuresClass.get_restaurant_entrance_points(state, rid, rest)
	if not read.ok:
		return Result.failure("coffee: %s" % read.error)
	return read

static func _get_structure_adjacent_roads(state: GameState, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		if CellsClass.has_cell_any(state, cell) and CellsClass.has_road_at_any(state, cell):
			set[_pos_key(cell)] = cell
		for dir in MapUtilsClass.DIRECTIONS:
			var n := MapUtilsClass.get_neighbor_pos(cell, dir)
			if not CellsClass.has_cell_any(state, n):
				continue
			if CellsClass.has_road_at_any(state, n):
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

static func _location_key(kind: String, id: String) -> String:
	if kind.is_empty() or id.is_empty():
		return ""
	return "%s:%s" % [kind, id]

static func _collect_stop_location_keys_for_path(path: Array[Vector2i], stop_index: Dictionary) -> Dictionary:
	var out := {}
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
			var kind: String = str(item.get("kind", ""))
			var id: String = str(item.get("id", ""))
			var lk := _location_key(kind, id)
			if lk.is_empty():
				continue
			out[lk] = true
	return out

static func _intersect_location_key_sets(best_paths: Array[Dictionary]) -> Dictionary:
	if best_paths.is_empty():
		return {}
	var first_val = best_paths[0].get("visited_location_keys", {})
	if not (first_val is Dictionary):
		return {}
	var common: Dictionary = first_val.duplicate(true)
	for i in range(1, best_paths.size()):
		var v = best_paths[i].get("visited_location_keys", {})
		if not (v is Dictionary):
			common.clear()
			return common
		var set_i: Dictionary = v
		var keys := common.keys()
		for k in keys:
			if not set_i.has(k):
				common.erase(k)
	return common

static func _simulate_coffee_purchases_filtered(
	state: GameState,
	path: Array[Vector2i],
	stop_index: Dictionary,
	cup_breakdowns: Dictionary,
	allowed_location_keys: Dictionary
) -> Result:
	var inv_left := {}
	for pid in range(state.players.size()):
		var inv_read := PlayerStateAccessClass.require_player_inventory(state, pid, "coffee:route:simulate_filtered")
		if not inv_read.ok:
			return inv_read
		var inv: Dictionary = inv_read.value
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
			return Result.failure("coffee: stop_index[%s] 类型错误（期望 Array）" % key)
		var list: Array = list_val
		for item_index in range(list.size()):
			var item_read := _require_stop_item(list[item_index], "coffee: stop_index[%s][%d]" % [key, item_index])
			if not item_read.ok:
				return item_read
			var item: Dictionary = item_read.value
			var kind: String = str(item.get("kind", ""))
			var loc_id: String = str(item.get("id", ""))
			var loc_key := _location_key(kind, loc_id)
			if loc_key.is_empty():
				return Result.failure("coffee: stop_index[%s][%d] location key 为空" % [key, item_index])
			if not allowed_location_keys.has(loc_key):
				continue
			if visited_locations.has(loc_key):
				continue
			var seller: int = int(item.get("owner", -1))
			if seller < 0 or seller >= state.players.size():
				return Result.failure("coffee: stop_index[%s][%d].owner 越界: %d" % [key, item_index, seller])
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
				"source_kind": kind,
				"source_id": loc_id,
				"at": [pos.x, pos.y],
				"price": price,
			})
			inv_left[seller] = int(inv_left.get(seller, 0)) - 1
			visited_locations[loc_key] = true
			income_by_player[seller] = int(income_by_player.get(seller, 0)) + maxi(0, price)

	return Result.success({
		"purchases": purchases,
		"income_by_player": income_by_player,
	})

static func _require_stop_item(item_val, path: String) -> Result:
	if not (item_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var item: Dictionary = item_val
	var kind_val = item.get("kind", null)
	if not (kind_val is String):
		return Result.failure("%s.kind 缺失或类型错误（期望 String）" % path)
	var kind := str(kind_val).strip_edges()
	if kind.is_empty():
		return Result.failure("%s.kind 不能为空" % path)
	var id_val = item.get("id", null)
	if not (id_val is String):
		return Result.failure("%s.id 缺失或类型错误（期望 String）" % path)
	var loc_id := str(id_val).strip_edges()
	if loc_id.is_empty():
		return Result.failure("%s.id 不能为空" % path)
	var owner_read := _parse_int_value(item.get("owner", null), "%s.owner" % path)
	if not owner_read.ok:
		return owner_read
	item["kind"] = kind
	item["id"] = loc_id
	item["owner"] = int(owner_read.value)
	return Result.success(item)

static func _require_purchase(purchase_val, path: String) -> Result:
	if not (purchase_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var purchase: Dictionary = purchase_val
	var seller_read := _parse_int_value(purchase.get("seller", null), "%s.seller" % path)
	if not seller_read.ok:
		return seller_read
	var price_read := _parse_int_value(purchase.get("price", null), "%s.price" % path)
	if not price_read.ok:
		return price_read
	purchase["seller"] = int(seller_read.value)
	purchase["price"] = int(price_read.value)
	return Result.success(purchase)

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 缺失或类型错误（期望 int）" % path)
