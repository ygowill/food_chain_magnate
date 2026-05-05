class_name BotSelfplayToolTest
extends RefCounted

const SelfplayToolClass = preload("res://tools/run_bot_selfplay.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var parse := _test_parse_mixed_bot_args()
	if not parse.ok:
		return parse
	var smoke := _test_run_mixed_bot_config()
	if not smoke.ok:
		return smoke
	return Result.success({"cases": 2})

static func _test_parse_mixed_bot_args() -> Result:
	var parsed := SelfplayToolClass._parse_args([
		"--players=2",
		"--bots=random,strategy",
		"--matches=1",
	])
	if not parsed.ok:
		return parsed
	var options: Dictionary = parsed.value
	var bot_ids: Array = options.get("bot_ids", [])
	if bot_ids.size() != 2 or str(bot_ids[0]) != "random" or str(bot_ids[1]) != "strategy":
		return Result.failure("--bots parse mismatch: %s" % str(options))
	var resolved := SelfplayToolClass._resolve_bot_ids(options, 2)
	if not resolved.ok:
		return resolved
	if str(resolved.value) != str(["random", "strategy"]):
		return Result.failure("resolved bot ids mismatch: %s" % str(resolved.value))
	var config_id := SelfplayToolClass._bot_config_id(resolved.value)
	if config_id != "random_vs_strategy":
		return Result.failure("bot config id mismatch: %s" % config_id)
	var conflict := SelfplayToolClass._parse_args(["--bot=strategy", "--bots=random,strategy"])
	if conflict.ok:
		return Result.failure("--bot and --bots conflict should fail")
	var empty_bot := SelfplayToolClass._parse_args(["--bots=random,"])
	if empty_bot.ok:
		return Result.failure("--bots should reject empty bot ids")
	return Result.success()

static func _test_run_mixed_bot_config() -> Result:
	var run_read := SelfplayToolClass.run({
		"player_count": 2,
		"start_seed": 12345,
		"matches": 1,
		"target_round": 2,
		"max_steps": 180,
		"budget_ms": 80,
		"trace_tail": 4,
		"bot_ids": ["random", "strategy"],
	})
	if not run_read.ok:
		return run_read
	var rows: Array = Dictionary(run_read.value).get("rows", [])
	if rows.size() != 1:
		return Result.failure("mixed selfplay should emit one row: %s" % str(run_read.value))
	var row: Dictionary = rows[0]
	if str(row.get("bot_config", "")) != "random_vs_strategy":
		return Result.failure("mixed selfplay row missing bot_config: %s" % str(row))
	if str(row.get("bot_ids", [])) != str(["random", "strategy"]):
		return Result.failure("mixed selfplay row missing bot_ids: %s" % str(row))
	if not bool(row.get("ok", false)):
		return Result.failure("mixed selfplay should reach target round: %s" % str(row))
	if int(row.get("round", 0)) < 2:
		return Result.failure("mixed selfplay should reach round 2: %s" % str(row))
	return Result.success()
