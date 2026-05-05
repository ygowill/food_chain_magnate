class_name BotSelfplaySummaryTest
extends RefCounted

const SummaryClass = preload("res://tools/bot_selfplay_summary.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var aggregate := _test_summarize_rows()
	if not aggregate.ok:
		return aggregate
	var formatted := _test_format_summary()
	if not formatted.ok:
		return formatted
	return Result.success({"cases": 2})

static func _test_summarize_rows() -> Result:
	var rows: Array[Dictionary] = [
		{
			"bot": "strategy",
			"ok": true,
			"seed": 1,
			"round": 4,
			"steps": 10,
			"command_count": 10,
			"action_counts": {"recruit": 2, "skip": 1},
			"player_cash": [3, 0],
			"player_employees": [4, 3],
			"player_inventory_units": [1, 0],
			"player_milestones": [2, 1],
			"player_restaurants": [1, 1],
		},
		{
			"bot": "strategy",
			"ok": false,
			"seed": 2,
			"round": 2,
			"steps": 14,
			"command_count": 13,
			"action_counts": {"recruit": 1, "fire": 1},
			"player_cash": [1, 6],
			"player_employees": [3, 4],
			"player_inventory_units": [0, 2],
			"player_milestones": [1, 3],
			"player_restaurants": [1, 2],
		},
		{
			"bot": "osla",
			"ok": true,
			"seed": 3,
			"round": 4,
			"steps": 8,
			"command_count": 8,
			"action_counts": {"recruit": 1, "produce_food": 2},
			"player_cash": [0, 0],
			"player_employees": [4, 4],
			"player_inventory_units": [1, 1],
			"player_milestones": [4, 4],
			"player_restaurants": [1, 1],
		},
	]
	var read := SummaryClass.summarize_rows(rows)
	if not read.ok:
		return read
	var summary: Dictionary = read.value
	if int(summary.get("total_matches", 0)) != 3:
		return Result.failure("summary should count total matches: %s" % str(summary))
	if int(summary.get("total_failures", 0)) != 1:
		return Result.failure("summary should count total failures: %s" % str(summary))
	var bots: Dictionary = summary.get("bots", {})
	var strategy: Dictionary = bots.get("strategy", {})
	if int(strategy.get("matches", 0)) != 2 or int(strategy.get("failures", 0)) != 1:
		return Result.failure("strategy aggregate mismatch: %s" % str(strategy))
	if float(strategy.get("avg_steps", 0.0)) != 12.0:
		return Result.failure("strategy avg_steps mismatch: %s" % str(strategy))
	var actions: Dictionary = strategy.get("action_totals", {})
	if int(actions.get("recruit", 0)) != 3 or int(actions.get("fire", 0)) != 1:
		return Result.failure("strategy action totals mismatch: %s" % str(actions))
	var action_avg: Dictionary = strategy.get("action_avg_per_match", {})
	if float(action_avg.get("recruit", 0.0)) != 1.5:
		return Result.failure("strategy action averages mismatch: %s" % str(action_avg))
	var failed_seeds: Array = strategy.get("failed_seeds", [])
	if failed_seeds.size() != 1 or int(failed_seeds[0]) != 2:
		return Result.failure("strategy failed seeds mismatch: %s" % str(failed_seeds))
	var players: Dictionary = strategy.get("players", {})
	var cash: Dictionary = players.get("cash", {})
	var cash_avg: Array = cash.get("avg", [])
	if cash_avg.size() != 2 or float(cash_avg[0]) != 2.0 or float(cash_avg[1]) != 3.0:
		return Result.failure("strategy cash averages mismatch: %s" % str(cash))
	var restaurants: Dictionary = players.get("restaurants", {})
	var restaurants_max: Array = restaurants.get("max", [])
	if restaurants_max.size() != 2 or float(restaurants_max[1]) != 2.0:
		return Result.failure("strategy restaurant max mismatch: %s" % str(restaurants))
	var osla: Dictionary = bots.get("osla", {})
	if float(osla.get("success_rate", 0.0)) != 1.0:
		return Result.failure("osla success rate mismatch: %s" % str(osla))
	return Result.success()

static func _test_format_summary() -> Result:
	var read := SummaryClass.summarize_rows([
		{
			"bot": "beam",
			"ok": true,
			"seed": 7,
			"round": 4,
			"steps": 9,
			"command_count": 9,
			"action_counts": {"skip": 2},
			"player_cash": [0, 0],
		},
	])
	if not read.ok:
		return read
	var lines := SummaryClass.format_summary(read.value)
	if not _has_line_containing(lines, "SUMMARY matches=1 failures=0 bots=1"):
		return Result.failure("formatted summary should include totals: %s" % str(lines))
	if not _has_line_containing(lines, "BOT beam matches=1 ok=1 failures=0"):
		return Result.failure("formatted summary should include beam aggregate: %s" % str(lines))
	if not _has_line_containing(lines, "ACTIONS beam skip=2"):
		return Result.failure("formatted summary should include action totals: %s" % str(lines))
	return Result.success()

static func _has_line_containing(lines: Array, needle: String) -> bool:
	for line in lines:
		if str(line).contains(needle):
			return true
	return false
