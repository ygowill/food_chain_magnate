class_name MapBalanceScorer
extends RefCounted

const WEIGHT_DENSITY := 2.0
const WEIGHT_CONCENTRATION := 3.0
const WEIGHT_STRUCTURE := 2.0

static func evaluate(analysis: Dictionary, thresholds: Dictionary) -> Dictionary:
	var checks: Array[Dictionary] = []
	var total_penalty := 0.0

	total_penalty += _append_range_check(
		checks,
		"total_starting_houses",
		"全图初始房屋总数",
		int(analysis.get("total_starting_houses", 0)),
		thresholds.get("total_starting_houses", {}),
		WEIGHT_DENSITY
	)
	total_penalty += _append_max_check(
		checks,
		"max_starting_houses_in_neighborhood",
		"单街区初始房屋数上限",
		int(analysis.get("max_starting_houses_in_neighborhood", 0)),
		thresholds.get("starting_houses_in_neighborhood", {}),
		WEIGHT_CONCENTRATION
	)
	total_penalty += _append_ratio_check(
		checks,
		"max_starting_houses_in_neighborhood_ratio",
		"单街区初始房屋占比上限",
		float(analysis.get("max_starting_houses_in_neighborhood_ratio", 0.0)),
		thresholds.get("starting_houses_in_neighborhood", {}),
		WEIGHT_CONCENTRATION
	)
	total_penalty += _append_max_check(
		checks,
		"max_starting_houses_on_road_system",
		"单道路系统初始房屋数上限",
		int(analysis.get("max_starting_houses_on_road_system", 0)),
		thresholds.get("starting_houses_on_road_system", {}),
		WEIGHT_CONCENTRATION
	)
	total_penalty += _append_ratio_check(
		checks,
		"max_starting_houses_on_road_system_ratio",
		"单道路系统初始房屋占比上限",
		float(analysis.get("max_starting_houses_on_road_system_ratio", 0.0)),
		thresholds.get("starting_houses_on_road_system", {}),
		WEIGHT_CONCENTRATION
	)
	total_penalty += _append_range_check(
		checks,
		"total_drink_locations",
		"全图饮料点总数",
		int(analysis.get("total_drink_locations", 0)),
		thresholds.get("total_drink_locations", {}),
		WEIGHT_DENSITY
	)
	total_penalty += _append_drink_type_checks(checks, analysis, thresholds)
	total_penalty += _append_max_check(
		checks,
		"max_drink_locations_on_road_system",
		"单道路系统饮料点数上限",
		int(analysis.get("max_drink_locations_on_road_system", 0)),
		thresholds.get("drink_locations_on_road_system", {}),
		WEIGHT_CONCENTRATION
	)
	total_penalty += _append_range_check(
		checks,
		"neighborhood_count",
		"独立街区数量",
		int(analysis.get("neighborhood_count", 0)),
		thresholds.get("neighborhood_count", {}),
		WEIGHT_STRUCTURE
	)
	total_penalty += _append_min_check(
		checks,
		"largest_neighborhood_total_spaces",
		"至少一个中型以上街区",
		int(analysis.get("largest_neighborhood_total_spaces", 0)),
		int(thresholds.get("neighborhood_total_space_medium_min", 0)),
		WEIGHT_STRUCTURE
	)
	total_penalty += _append_min_check(
		checks,
		"largest_neighborhood_empty_spaces",
		"至少一个中型以上可建设街区",
		int(analysis.get("largest_neighborhood_empty_spaces", 0)),
		int(thresholds.get("neighborhood_empty_space_medium_min", 0)),
		WEIGHT_STRUCTURE
	)
	total_penalty += _append_range_check(
		checks,
		"road_system_count",
		"独立道路系统数量",
		int(analysis.get("road_system_count", 0)),
		thresholds.get("road_system_count", {}),
		WEIGHT_STRUCTURE
	)
	total_penalty += _append_min_check(
		checks,
		"largest_road_system_route_count",
		"至少一个中型以上道路系统",
		int(analysis.get("largest_road_system_route_count", 0)),
		int(thresholds.get("road_system_route_medium_min", 0)),
		WEIGHT_STRUCTURE
	)

	var failed_checks: Array[String] = []
	for check in checks:
		if not bool(check.get("passed", false)):
			failed_checks.append(str(check.get("id", "")))

	return {
		"passed": failed_checks.is_empty(),
		"score": total_penalty,
		"failed_checks": failed_checks,
		"checks": checks,
	}

static func _append_range_check(
	checks: Array[Dictionary],
	id: String,
	label: String,
	value: int,
	range_def,
	weight: float
) -> float:
	if not (range_def is Dictionary):
		checks.append(_make_failed_check(id, label, value, "range 缺失", weight, weight))
		return weight
	var min_v := int(range_def.get("min", 0))
	var max_v := int(range_def.get("max", 0))
	var penalty := 0.0
	if value < min_v:
		penalty = (float(min_v - value) / float(maxi(1, min_v))) * weight
	elif value > max_v:
		penalty = (float(value - max_v) / float(maxi(1, max_v))) * weight
	checks.append({
		"id": id,
		"label": label,
		"value": value,
		"expected": "%d-%d" % [min_v, max_v],
		"passed": penalty == 0.0,
		"penalty": penalty,
		"weight": weight,
	})
	return penalty

static func _append_max_check(
	checks: Array[Dictionary],
	id: String,
	label: String,
	value: int,
	max_def,
	weight: float
) -> float:
	if not (max_def is Dictionary):
		checks.append(_make_failed_check(id, label, value, "max 缺失", weight, weight))
		return weight
	var max_v := int(max_def.get("max", 0))
	var penalty := 0.0
	if value > max_v:
		penalty = (float(value - max_v) / float(maxi(1, max_v))) * weight
	checks.append({
		"id": id,
		"label": label,
		"value": value,
		"expected": "<= %d" % max_v,
		"passed": penalty == 0.0,
		"penalty": penalty,
		"weight": weight,
	})
	return penalty

static func _append_ratio_check(
	checks: Array[Dictionary],
	id: String,
	label: String,
	value: float,
	max_def,
	weight: float
) -> float:
	if not (max_def is Dictionary):
		checks.append(_make_failed_check(id, label, value, "max_ratio 缺失", weight, weight))
		return weight
	var max_ratio := float(max_def.get("max_ratio", 0.0))
	var penalty := 0.0
	if value > max_ratio:
		penalty = ((value - max_ratio) / maxf(0.01, max_ratio)) * weight
	checks.append({
		"id": id,
		"label": label,
		"value": value,
		"expected": "<= %.2f" % max_ratio,
		"passed": penalty == 0.0,
		"penalty": penalty,
		"weight": weight,
	})
	return penalty

static func _append_min_check(
	checks: Array[Dictionary],
	id: String,
	label: String,
	value: int,
	min_v: int,
	weight: float
) -> float:
	var penalty := 0.0
	if value < min_v:
		penalty = (float(min_v - value) / float(maxi(1, min_v))) * weight
	checks.append({
		"id": id,
		"label": label,
		"value": value,
		"expected": ">= %d" % min_v,
		"passed": penalty == 0.0,
		"penalty": penalty,
		"weight": weight,
	})
	return penalty

static func _append_drink_type_checks(checks: Array[Dictionary], analysis: Dictionary, thresholds: Dictionary) -> float:
	var total_penalty := 0.0
	var min_count := int(thresholds.get("drink_type_min", 0))
	var required_val = thresholds.get("required_drink_types", [])
	var required: Array = required_val if required_val is Array else []
	var counts_val = analysis.get("drink_counts_by_type", {})
	var counts: Dictionary = counts_val if counts_val is Dictionary else {}
	for drink_type_val in required:
		var drink_type := str(drink_type_val)
		var value := int(counts.get(drink_type, 0))
		var penalty := 0.0
		if value < min_count:
			penalty = (float(min_count - value) / float(maxi(1, min_count))) * WEIGHT_CONCENTRATION
		checks.append({
			"id": "drink_type_min_%s" % drink_type,
			"label": "饮料类型最低数量：%s" % drink_type,
			"value": value,
			"expected": ">= %d" % min_count,
			"passed": penalty == 0.0,
			"penalty": penalty,
			"weight": WEIGHT_CONCENTRATION,
		})
		total_penalty += penalty
	return total_penalty

static func _make_failed_check(id: String, label: String, value, expected: String, penalty: float, weight: float) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"value": value,
		"expected": expected,
		"passed": false,
		"penalty": penalty,
		"weight": weight,
	}
