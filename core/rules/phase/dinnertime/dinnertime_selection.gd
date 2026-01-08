# DinnertimeSettlement：候选餐厅选择/平局规则
class_name DinnertimeSelection
extends RefCounted

const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const DinnertimeInventoryClass = preload("res://core/rules/phase/dinnertime/dinnertime_inventory.gd")
const DinnertimeDistanceClass = preload("res://core/rules/phase/dinnertime/dinnertime_distance.gd")
const DinnertimeEffectsClass = preload("res://core/rules/phase/dinnertime/dinnertime_effects.gd")

static func pick_winner_for_required(
	state: GameState,
	effect_registry,
	road_graph,
	grid_size: Vector2i,
	restaurants: Dictionary,
	house_id: String,
	house: Dictionary,
	required: Dictionary,
	warnings: Array[String],
	distance_delta_segment: String,
	tiebreak_segment: String
) -> Result:
	var winner: Dictionary = {}
	var tiebreak_cache: Dictionary = {}

	for rest_key in restaurants.keys():
		if not (rest_key is String):
			return Result.failure("晚餐结算失败：restaurants key 类型错误（期望 String）")
		var rest_id: String = str(rest_key)
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			return Result.failure("晚餐结算失败：restaurant 类型错误: restaurants[%s]（期望 Dictionary）" % rest_id)
		var rest: Dictionary = rest_val
		if rest.is_empty():
			continue

		if not rest.has("owner") or not (rest["owner"] is int):
			return Result.failure("晚餐结算失败：restaurants[%s].owner 缺失或类型错误（期望 int）" % rest_id)
		var owner: int = rest["owner"]
		if owner < 0 or owner >= state.players.size():
			return Result.failure("晚餐结算失败：restaurants[%s].owner 越界: %d" % [rest_id, owner])

		var player_val = state.players[owner]
		if not (player_val is Dictionary):
			return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % owner)
		var player: Dictionary = player_val

		var has_inv := DinnertimeInventoryClass.player_has_inventory(player, required)
		if not has_inv.ok:
			return has_inv
		if not bool(has_inv.value):
			continue

		var distance_read := DinnertimeDistanceClass.get_restaurant_to_house_distance(road_graph, state, grid_size, rest_id, rest, house_id, house)
		if not distance_read.ok:
			return distance_read
		var distance_info: Dictionary = distance_read.value
		if distance_info.is_empty():
			continue

		var breakdown_read := PricingPipelineClass.calculate_sale_breakdown(state, owner, house, required)
		if not breakdown_read.ok:
			return Result.failure("晚餐结算失败：PricingPipeline 失败: %s" % breakdown_read.error)
		var breakdown: Dictionary = breakdown_read.value

		assert(breakdown.has("decision_unit_price") and breakdown["decision_unit_price"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 decision_unit_price（期望 int）")
		assert(breakdown.has("unit_price") and breakdown["unit_price"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 unit_price（期望 int）")
		assert(breakdown.has("revenue") and breakdown["revenue"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 revenue（期望 int）")
		assert(breakdown.has("quantity") and breakdown["quantity"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 quantity（期望 int）")
		assert(breakdown.has("has_garden") and breakdown["has_garden"] is bool, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 has_garden（期望 bool）")
		assert(breakdown.has("price_part") and breakdown["price_part"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 price_part（期望 int）")
		assert(breakdown.has("bonus") and breakdown["bonus"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 bonus（期望 int）")

		assert(distance_info.has("distance") and distance_info["distance"] is int, "内部错误: distance_info.distance 缺失或类型错误（期望 int）")
		assert(distance_info.has("steps") and distance_info["steps"] is int, "内部错误: distance_info.steps 缺失或类型错误（期望 int）")
		assert(distance_info.has("path") and distance_info["path"] is Array, "内部错误: distance_info.path 缺失或类型错误（期望 Array[Vector2i]）")

		var decision_unit_price: int = breakdown["decision_unit_price"]
		var dist: int = distance_info["distance"]

		var dist_ctx := {
			"distance": dist,
			"steps": int(distance_info["steps"]),
			"path": distance_info["path"],
			"house_id": house_id,
			"restaurant_id": rest_id,
			"allow_negative": false,
		}
		var dist_eff := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, owner, effect_registry, distance_delta_segment, dist_ctx)
		if not dist_eff.ok:
			return dist_eff
		warnings.append_array(dist_eff.warnings)
		dist_eff = DinnertimeEffectsClass.apply_milestone_effects_by_segment(state, owner, effect_registry, distance_delta_segment, dist_ctx)
		if not dist_eff.ok:
			return dist_eff
		warnings.append_array(dist_eff.warnings)
		dist_eff = DinnertimeEffectsClass.apply_global_effects_by_segment(state, owner, effect_registry, distance_delta_segment, dist_ctx)
		if not dist_eff.ok:
			return dist_eff
		warnings.append_array(dist_eff.warnings)
		var dist_val = dist_ctx.get("distance", null)
		if not (dist_val is int):
			return Result.failure("晚餐结算失败：distance ctx.distance 类型错误（期望 int）")
		var allow_neg_val = dist_ctx.get("allow_negative", false)
		if not (allow_neg_val is bool):
			return Result.failure("晚餐结算失败：distance ctx.allow_negative 类型错误（期望 bool）")
		var allow_negative: bool = bool(allow_neg_val)
		dist = int(dist_val)
		if dist < 0 and not allow_negative:
			return Result.failure("晚餐结算失败：distance ctx.distance 不能为负数: %d" % dist)

		var score: int = decision_unit_price + dist
		var tiebreak_score := 0
		if tiebreak_cache.has(owner):
			var cached = tiebreak_cache.get(owner, 0)
			if not (cached is int):
				return Result.failure("晚餐结算失败：tiebreak_cache[%d] 类型错误（期望 int）" % owner)
			tiebreak_score = int(cached)
		else:
			var ctx := {
				"score": 0,
				"house_id": house_id,
				"restaurant_id": rest_id,
			}
			var eff := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, owner, effect_registry, tiebreak_segment, ctx)
			if not eff.ok:
				return eff
			warnings.append_array(eff.warnings)
			var sc_val = ctx.get("score", 0)
			if not (sc_val is int):
				return Result.failure("晚餐结算失败：tiebreak ctx.score 类型错误（期望 int）")
			tiebreak_score = int(sc_val)
			tiebreak_cache[owner] = tiebreak_score

		var candidate := {
			"restaurant_id": rest_id,
			"owner": owner,
			"score": score,
			"distance": dist,
			"steps": int(distance_info["steps"]),
			"tiebreak_score": int(tiebreak_score),
			"unit_price": int(breakdown["unit_price"]),
			"decision_unit_price": decision_unit_price,
			"breakdown": breakdown,
		}

		if winner.is_empty() or _is_candidate_better(state, candidate, winner):
			winner = candidate

	return Result.success(winner)

static func _is_candidate_better(state: GameState, a: Dictionary, b: Dictionary) -> bool:
	assert(a.has("score") and a["score"] is int, "内部错误: candidate.score 缺失或类型错误（期望 int）")
	assert(b.has("score") and b["score"] is int, "内部错误: candidate.score 缺失或类型错误（期望 int）")
	assert(a.has("tiebreak_score") and a["tiebreak_score"] is int, "内部错误: candidate.tiebreak_score 缺失或类型错误（期望 int）")
	assert(b.has("tiebreak_score") and b["tiebreak_score"] is int, "内部错误: candidate.tiebreak_score 缺失或类型错误（期望 int）")
	assert(a.has("owner") and a["owner"] is int, "内部错误: candidate.owner 缺失或类型错误（期望 int）")
	assert(b.has("owner") and b["owner"] is int, "内部错误: candidate.owner 缺失或类型错误（期望 int）")
	assert(a.has("distance") and a["distance"] is int, "内部错误: candidate.distance 缺失或类型错误（期望 int）")
	assert(b.has("distance") and b["distance"] is int, "内部错误: candidate.distance 缺失或类型错误（期望 int）")
	assert(a.has("steps") and a["steps"] is int, "内部错误: candidate.steps 缺失或类型错误（期望 int）")
	assert(b.has("steps") and b["steps"] is int, "内部错误: candidate.steps 缺失或类型错误（期望 int）")
	assert(a.has("restaurant_id") and a["restaurant_id"] is String, "内部错误: candidate.restaurant_id 缺失或类型错误（期望 String）")
	assert(b.has("restaurant_id") and b["restaurant_id"] is String, "内部错误: candidate.restaurant_id 缺失或类型错误（期望 String）")

	# 1) score 更小者优先（单价 + 距离）
	var a_score: int = int(a["score"])
	var b_score: int = int(b["score"])
	if a_score != b_score:
		return a_score < b_score

	# 2) tiebreak_score 更大者优先（默认=女服务员数量）
	var a_tb: int = int(a["tiebreak_score"])
	var b_tb: int = int(b["tiebreak_score"])
	if a_tb != b_tb:
		return a_tb > b_tb

	# 3) 回合顺序靠前者优先
	var a_owner: int = int(a["owner"])
	var b_owner: int = int(b["owner"])
	var a_rank := _turn_order_rank(state, a_owner)
	var b_rank := _turn_order_rank(state, b_owner)
	if a_rank != b_rank:
		return a_rank < b_rank

	# 4) 同一玩家多个餐厅：选距离更短（更稳定）
	var a_dist: int = int(a["distance"])
	var b_dist: int = int(b["distance"])
	if a_dist != b_dist:
		return a_dist < b_dist

	var a_steps: int = int(a["steps"])
	var b_steps: int = int(b["steps"])
	if a_steps != b_steps:
		return a_steps < b_steps

	return str(a["restaurant_id"]) < str(b["restaurant_id"])

static func _turn_order_rank(state: GameState, player_id: int) -> int:
	var idx := state.turn_order.find(player_id)
	return idx if idx >= 0 else 999999
