class_name BotSelfplayMatrixTest
extends RefCounted

const MatrixToolClass = preload("res://tools/run_bot_selfplay_matrix.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var parse := _test_parse_configs()
	if not parse.ok:
		return parse
	var smoke := _test_run_matrix()
	if not smoke.ok:
		return smoke
	return Result.success({"cases": 2})

static func _test_parse_configs() -> Result:
	var parsed := MatrixToolClass._parse_args([
		"--config=random",
		"--config=random,strategy",
		"--players=2",
	])
	if not parsed.ok:
		return parsed
	var configs: Array = Dictionary(parsed.value).get("configs", [])
	if configs.size() != 2:
		return Result.failure("matrix should parse repeated configs: %s" % str(parsed.value))
	if str(configs[0]) != str(["random"]) or str(configs[1]) != str(["random", "strategy"]):
		return Result.failure("matrix config parse mismatch: %s" % str(configs))
	var bad := MatrixToolClass._parse_args(["--config=random,"])
	if bad.ok:
		return Result.failure("matrix should reject empty bot id in config")
	return Result.success()

static func _test_run_matrix() -> Result:
	var run_read := MatrixToolClass.run({
		"configs": [["random"], ["random", "strategy"]],
		"player_count": 2,
		"start_seed": 12345,
		"matches": 1,
		"target_round": 2,
		"max_steps": 180,
		"budget_ms": 80,
		"trace_tail": 2,
	})
	if not run_read.ok:
		return run_read
	if int(run_read.value.get("configs", 0)) != 2 or int(run_read.value.get("matches", 0)) != 2:
		return Result.failure("matrix run counts mismatch: %s" % str(run_read.value))
	var summary: Dictionary = Dictionary(run_read.value.get("summary", {}))
	var bots: Dictionary = Dictionary(summary.get("bots", {}))
	if not bots.has("random") or not bots.has("random_vs_strategy"):
		return Result.failure("matrix summary should group single and mixed configs: %s" % str(summary))
	if int(summary.get("total_failures", 0)) != 0:
		return Result.failure("matrix smoke should not fail: %s" % str(summary))
	return Result.success()
