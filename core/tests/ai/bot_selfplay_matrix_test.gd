class_name BotSelfplayMatrixTest
extends RefCounted

const MatrixToolClass = preload("res://tools/run_bot_selfplay_matrix.gd")
const TuningToolClass = preload("res://tools/run_bot_tuning_matrix.gd")
const ProfileVariantToolClass = preload("res://tools/generate_bot_profile_variants.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var parse := _test_parse_configs()
	if not parse.ok:
		return parse
	var smoke := _test_run_matrix()
	if not smoke.ok:
		return smoke
	var tuning := _test_run_tuning_matrix()
	if not tuning.ok:
		return tuning
	var variants := _test_generate_profile_variants()
	if not variants.ok:
		return variants
	var rankings := _test_rank_opening_metrics_from_synthetic_summary()
	if not rankings.ok:
		return rankings
	return Result.success({"cases": 5})

static func _test_parse_configs() -> Result:
	var parsed := MatrixToolClass._parse_args([
		"--config=random",
		"--config=random,strategy",
		"--players=2",
		"--profile=base_revenue_growth_v1",
	])
	if not parsed.ok:
		return parsed
	var configs: Array = Dictionary(parsed.value).get("configs", [])
	if configs.size() != 2:
		return Result.failure("matrix should parse repeated configs: %s" % str(parsed.value))
	if str(configs[0]) != str(["random"]) or str(configs[1]) != str(["random", "strategy"]):
		return Result.failure("matrix config parse mismatch: %s" % str(configs))
	if str(Dictionary(parsed.value).get("profile", "")) != "base_revenue_growth_v1":
		return Result.failure("matrix profile parse mismatch: %s" % str(parsed.value))
	var bad := MatrixToolClass._parse_args(["--config=random,"])
	if bad.ok:
		return Result.failure("matrix should reject empty bot id in config")
	var tuning_parsed := TuningToolClass._parse_args([
		"--profile=base_revenue_v1",
		"--profile=base_revenue_growth_v1",
		"--config=strategy",
		"--players=2",
		"--jobs=2",
	])
	if not tuning_parsed.ok:
		return tuning_parsed
	var profiles: Array = Dictionary(tuning_parsed.value).get("profiles", [])
	if profiles.size() != 2 or str(profiles[0]) != "base_revenue_v1" or str(profiles[1]) != "base_revenue_growth_v1":
		return Result.failure("tuning matrix should parse repeated profiles: %s" % str(tuning_parsed.value))
	if int(Dictionary(tuning_parsed.value).get("parallel_jobs", 0)) != 2:
		return Result.failure("tuning matrix should parse --jobs: %s" % str(tuning_parsed.value))
	if int(Dictionary(tuning_parsed.value).get("matches", 0)) != TuningToolClass.MIN_TUNING_MATCHES:
		return Result.failure("tuning matrix should default to minimum tuning seeds: %s" % str(tuning_parsed.value))
	var bad_jobs := TuningToolClass._parse_args(["--jobs=0"])
	if bad_jobs.ok:
		return Result.failure("tuning matrix should reject non-positive --jobs")
	var bad_matches := TuningToolClass._parse_args(["--matches=2"])
	if bad_matches.ok:
		return Result.failure("tuning matrix should reject fewer than three matches")
	var tuning_dir_parsed := TuningToolClass._parse_args([
		"--profile-dir=res://data/bots",
		"--config=random",
	])
	if not tuning_dir_parsed.ok:
		return tuning_dir_parsed
	var dir_profiles: Array = Dictionary(tuning_dir_parsed.value).get("profiles", [])
	if not dir_profiles.has("res://data/bots/base_revenue_v1.json") or not dir_profiles.has("res://data/bots/base_revenue_growth_v1.json"):
		return Result.failure("tuning matrix should parse profile directories: %s" % str(tuning_dir_parsed.value))
	var variant_parsed := ProfileVariantToolClass._parse_args([
		"--base-profile=base_revenue_growth_v1",
		"--random-samples=5",
		"--random-seed=67890",
		"--sample-mode=continuous",
		"--scale=action_weights.recruit=0.9,1.1",
	])
	if not variant_parsed.ok:
		return variant_parsed
	var scales: Array = Dictionary(variant_parsed.value).get("scales", [])
	if scales.size() != 1 or Array(Dictionary(scales[0]).get("factors", [])).size() != 2:
		return Result.failure("profile variant generator should parse scale factors: %s" % str(variant_parsed.value))
	if int(Dictionary(variant_parsed.value).get("random_samples", 0)) != 5 or int(Dictionary(variant_parsed.value).get("random_seed", 0)) != 67890:
		return Result.failure("profile variant generator should parse random sampling args: %s" % str(variant_parsed.value))
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
		"profile": "base_revenue_growth_v1",
	})
	if not run_read.ok:
		return run_read
	if int(run_read.value.get("configs", 0)) != 2 or int(run_read.value.get("matches", 0)) != 2:
		return Result.failure("matrix run counts mismatch: %s" % str(run_read.value))
	var summary: Dictionary = Dictionary(run_read.value.get("summary", {}))
	var bots: Dictionary = Dictionary(summary.get("bots", {}))
	if not bots.has("random@base_revenue_growth_v1") or not bots.has("random_vs_strategy@base_revenue_growth_v1"):
		return Result.failure("matrix summary should group single and mixed configs: %s" % str(summary))
	if int(summary.get("total_failures", 0)) != 0:
		return Result.failure("matrix smoke should not fail: %s" % str(summary))
	return Result.success()

static func _test_run_tuning_matrix() -> Result:
	var run_read := TuningToolClass.run({
		"profiles": ["base_revenue_v1"],
		"configs": [["random"]],
		"player_count": 2,
		"start_seed": 12345,
		"matches": 3,
		"target_round": 2,
		"max_steps": 180,
		"budget_ms": 80,
		"trace_tail": 1,
	})
	if not run_read.ok:
		return run_read
	if int(run_read.value.get("profiles", 0)) != 1 or int(run_read.value.get("configs", 0)) != 1 or int(run_read.value.get("matches", 0)) != 3:
		return Result.failure("tuning matrix run counts mismatch: %s" % str(run_read.value))
	var profile_sources: Array = Dictionary(run_read.value).get("profile_sources", [])
	if str(profile_sources) != str(["base_revenue_v1"]):
		return Result.failure("tuning matrix should retain profile sources: %s" % str(run_read.value))
	var rankings: Array = Dictionary(run_read.value).get("rankings", [])
	if rankings.size() != 1:
		return Result.failure("tuning matrix should emit one ranking row: %s" % str(run_read.value))
	var rank: Dictionary = Dictionary(rankings[0])
	if int(rank.get("rank", 0)) != 1 or str(rank.get("profile", "")) != "base_revenue_v1" or str(rank.get("bot", "")) != "random@base_revenue_v1":
		return Result.failure("tuning matrix ranking row mismatch: %s" % str(rank))
	if float(rank.get("score", 0.0)) <= 0.0 or float(rank.get("success_rate", 0.0)) != 1.0:
		return Result.failure("tuning matrix ranking should expose objective and success: %s" % str(rank))
	var profile_summaries: Dictionary = Dictionary(run_read.value.get("profile_summaries", {}))
	if not profile_summaries.has("base_revenue_v1"):
		return Result.failure("tuning matrix should retain per-profile summary: %s" % str(run_read.value))
	var profile_rankings: Array = Dictionary(run_read.value).get("profile_rankings", [])
	if profile_rankings.size() != 1:
		return Result.failure("tuning matrix should emit one profile ranking row: %s" % str(run_read.value))
	var profile_rank: Dictionary = Dictionary(profile_rankings[0])
	if int(profile_rank.get("rank", 0)) != 1 or str(profile_rank.get("profile", "")) != "base_revenue_v1" or str(profile_rank.get("best_bot", "")) != "random@base_revenue_v1":
		return Result.failure("tuning matrix profile ranking mismatch: %s" % str(profile_rank))
	return Result.success()

static func _test_generate_profile_variants() -> Result:
	var output_dir := "res://.godot/bot_profile_variant_sample_suffix_test"
	var manifest_path := "%s/manifest.json" % output_dir
	var run_read := ProfileVariantToolClass.run({
		"base_profile": "base_revenue_growth_v1",
		"output_dir": output_dir,
		"manifest": manifest_path,
		"max_variants": 4,
		"scales": [
			{
				"path": ["action_weights", "recruit"],
				"factors": [0.9, 1.1],
			},
		],
	})
	if not run_read.ok:
		return run_read
	if int(run_read.value.get("count", 0)) != 2:
		return Result.failure("profile variant generator should emit two variants: %s" % str(run_read.value))
	if str(run_read.value.get("manifest", "")) != manifest_path or not FileAccess.file_exists(manifest_path):
		return Result.failure("profile variant generator should write manifest: %s" % str(run_read.value))
	var variants: Array = Dictionary(run_read.value).get("variants", [])
	if variants.size() != 2:
		return Result.failure("profile variant rows mismatch: %s" % str(run_read.value))
	var first: Dictionary = Dictionary(variants[0])
	var first_path := str(first.get("path", ""))
	if first_path.is_empty() or not FileAccess.file_exists(first_path):
		return Result.failure("profile variant file should exist: %s" % str(first))
	var file := FileAccess.open(first_path, FileAccess.READ)
	if file == null:
		return Result.failure("profile variant file should be readable: %s" % first_path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return Result.failure("profile variant JSON should parse: %s" % first_path)
	var profile: Dictionary = Dictionary(parsed)
	var weights: Dictionary = Dictionary(profile.get("action_weights", {}))
	var first_changes: Array = Array(first.get("changes", []))
	if first_changes.size() != 1:
		return Result.failure("profile variant should expose one scale change: %s" % str(first))
	var first_change: Dictionary = Dictionary(first_changes[0])
	if str(first_change.get("path", "")) != "action_weights.recruit":
		return Result.failure("profile variant should scale recruit path: %s" % str(first_change))
	if not is_equal_approx(float(weights.get("recruit", 0.0)), float(first_change.get("value", -1.0))):
		return Result.failure("profile variant should scale recruit weight: %s" % str(profile))
	var random_output_dir := "res://.godot/bot_profile_random_variant_test"
	var random_run := ProfileVariantToolClass.run({
		"base_profile": "base_revenue_growth_v1",
		"output_dir": random_output_dir,
		"max_variants": 3,
		"random_samples": 3,
		"random_seed": 24680,
		"sample_mode": ProfileVariantToolClass.SAMPLE_MODE_CONTINUOUS,
		"scales": [
			{
				"path": ["action_weights", "recruit"],
				"factors": [0.8, 1.2],
			},
			{
				"path": ["action_weights", "train"],
				"factors": [0.7, 1.3],
			},
		],
	})
	if not random_run.ok:
		return random_run
	if int(random_run.value.get("count", 0)) != 3:
		return Result.failure("profile variant random generator should emit requested samples: %s" % str(random_run.value))
	var sampling: Dictionary = Dictionary(random_run.value.get("sampling", {}))
	if str(sampling.get("mode", "")) != ProfileVariantToolClass.SAMPLE_MODE_CONTINUOUS or int(sampling.get("random_samples", 0)) != 3:
		return Result.failure("profile variant random generator should expose sampling metadata: %s" % str(random_run.value))
	var random_variants: Array = Dictionary(random_run.value).get("variants", [])
	if random_variants.size() != 3:
		return Result.failure("profile variant random rows mismatch: %s" % str(random_run.value))
	for random_variant_val in random_variants:
		var random_variant: Dictionary = Dictionary(random_variant_val)
		var changes: Array = Array(random_variant.get("changes", []))
		if changes.size() != 2:
			return Result.failure("profile variant random sample should change each sampled path: %s" % str(random_variant))
		for change_val in changes:
			var change: Dictionary = Dictionary(change_val)
			var path := str(change.get("path", ""))
			var factor := float(change.get("factor", 0.0))
			if path == "action_weights.recruit" and (factor < 0.8 or factor > 1.2):
				return Result.failure("profile variant random recruit factor out of range: %s" % str(change))
			if path == "action_weights.train" and (factor < 0.7 or factor > 1.3):
				return Result.failure("profile variant random train factor out of range: %s" % str(change))
	var many_scale_random := ProfileVariantToolClass.run({
		"base_profile": "base_revenue_growth_v1",
		"output_dir": "res://.godot/bot_profile_random_many_scale_test",
		"max_variants": 2,
		"random_samples": 2,
		"random_seed": 86420,
		"sample_mode": ProfileVariantToolClass.SAMPLE_MODE_CONTINUOUS,
		"scales": [
			{"path": ["action_weights", "recruit"], "factors": [0.8, 1.2]},
			{"path": ["action_weights", "train"], "factors": [0.8, 1.2]},
			{"path": ["action_weights", "initiate_marketing"], "factors": [0.8, 1.2]},
			{"path": ["action_weights", "produce_food"], "factors": [0.8, 1.2]},
			{"path": ["action_weights", "procure_drinks"], "factors": [0.8, 1.2]},
			{"path": ["employee_priorities", "kitchen_trainee"], "factors": [0.8, 1.2]},
			{"path": ["employee_priorities", "marketing_trainee"], "factors": [0.8, 1.2]},
			{"path": ["employee_priorities", "trainer"], "factors": [0.8, 1.2]},
			{"path": ["employee_priorities", "errand_boy"], "factors": [0.8, 1.2]},
		],
	})
	if not many_scale_random.ok:
		return many_scale_random
	if int(many_scale_random.value.get("count", 0)) != 2:
		return Result.failure("profile variant random generator should not expand cartesian scale count: %s" % str(many_scale_random.value))
	var derived_id := ProfileVariantToolClass._variant_id(
		"base_revenue_growth_v1__action_weights_recruit_x0_823__action_weights_train_x1_18__action_weights_initiate_marketing_x1_171__action_we__v001",
		[
			{
				"path": "action_weights.recruit",
				"factor": 1.1,
			},
		],
		1
	)
	if derived_id.ends_with("__v001") or not derived_id.ends_with("__sample_001"):
		return Result.failure("profile variant derived ids should keep a unique sample suffix: %s" % derived_id)
	var tuning_parsed := TuningToolClass._parse_args([
		"--profile-list=%s" % manifest_path,
		"--config=random",
	])
	if not tuning_parsed.ok:
		return tuning_parsed
	var manifest_profiles: Array = Dictionary(tuning_parsed.value).get("profiles", [])
	if manifest_profiles.size() != 2 or not manifest_profiles.has(first_path):
		return Result.failure("tuning matrix should parse generated manifest profiles: %s" % str(tuning_parsed.value))
	var tuning_dir_parsed := TuningToolClass._parse_args([
		"--profile-dir=%s" % output_dir,
		"--config=random",
	])
	if not tuning_dir_parsed.ok:
		return tuning_dir_parsed
	var dir_profiles: Array = Dictionary(tuning_dir_parsed.value).get("profiles", [])
	if dir_profiles.size() != 2 or dir_profiles.has(manifest_path) or not dir_profiles.has(first_path):
		return Result.failure("tuning matrix should scan generated profile dirs without manifest: %s" % str(tuning_dir_parsed.value))
	return Result.success()

static func _test_rank_opening_metrics_from_synthetic_summary() -> Result:
	var run_read := TuningToolClass._finish_run(
		["base_revenue_growth_v1", "candidate_opening_v1"],
		[["strategy"]],
		[
			{
				"profile_config": "base_revenue_growth_v1",
				"summary": _synthetic_profile_summary("strategy@base_revenue_growth_v1", 709.0, 2.0),
				"rows": [],
				"failures": 0,
			},
			{
				"profile_config": "candidate_opening_v1",
				"summary": _synthetic_profile_summary("strategy@candidate_opening_v1", 869.0, 0.0),
				"rows": [],
				"failures": 0,
			},
		],
		"",
		""
	)
	if not run_read.ok:
		return run_read
	var rankings: Array = Dictionary(run_read.value).get("rankings", [])
	if rankings.size() != 2:
		return Result.failure("synthetic tuning matrix should emit two rankings: %s" % str(run_read.value))
	var first_rank: Dictionary = Dictionary(rankings[0])
	var second_rank: Dictionary = Dictionary(rankings[1])
	if str(first_rank.get("profile", "")) != "candidate_opening_v1" or int(first_rank.get("rank", 0)) != 1:
		return Result.failure("candidate profile should rank first: %s" % str(rankings))
	if str(second_rank.get("profile", "")) != "base_revenue_growth_v1" or int(second_rank.get("rank", 0)) != 2:
		return Result.failure("baseline profile should rank second: %s" % str(rankings))
	if not is_equal_approx(float(first_rank.get("pre_revenue_errand_boy_recruit_avg", -1.0)), 0.0):
		return Result.failure("rank row should expose candidate opening errand count: %s" % str(first_rank))
	if not is_equal_approx(float(second_rank.get("pre_revenue_errand_boy_recruit_avg", -1.0)), 2.0):
		return Result.failure("rank row should expose baseline opening errand count: %s" % str(second_rank))

	var profile_rankings: Array = Dictionary(run_read.value).get("profile_rankings", [])
	if profile_rankings.size() != 2 or str(Dictionary(profile_rankings[0]).get("profile", "")) != "candidate_opening_v1":
		return Result.failure("profile rankings should follow best objective score: %s" % str(profile_rankings))
	return Result.success()

static func _synthetic_profile_summary(bot_name: String, score: float, pre_revenue_errand_count: float) -> Dictionary:
	return {
		"bots": {
			bot_name: {
				"matches": 1,
				"failures": 0,
				"success_rate": 1.0,
				"avg_round": 4.0,
				"avg_steps": 44.0,
				"avg_command_count": 44.0,
				"opening": {
					"players_without_positive_cash_avg_per_match": 2.0,
					"first_positive_cash_round_avg": 0.0,
					"scalar_avg_per_match": {
						"pre_revenue_errand_boy_recruit_count": pre_revenue_errand_count,
						"pre_revenue_pricing_manager_recruit_count": 0.0,
						"pre_revenue_procure_drinks_count": 0.0,
					},
				},
				"search": {
					"time_ms_avg_per_match": 0.0,
					"budget_expired_avg_per_match": 0.0,
				},
				"tuning_objective": {
					"score": score,
				},
			},
		},
		"total_failures": 0,
	}
