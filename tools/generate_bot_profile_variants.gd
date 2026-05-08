extends SceneTree

const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")

const NAME := "BotProfileVariantGenerator"
const DEFAULT_BASE_PROFILE := "base_revenue_growth_v1"
const DEFAULT_OUTPUT_DIR := "res://.godot/bot_profile_variants"
const DEFAULT_MAX_VARIANTS := 64
const DEFAULT_RANDOM_SAMPLES := 0
const DEFAULT_RANDOM_SEED := 12345
const SAMPLE_MODE_CONTINUOUS := "continuous"
const SAMPLE_MODE_DISCRETE := "discrete"
const MAX_VARIANT_ID_LENGTH := 140

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		_print_usage()
		quit(0)
		return
	var parse_result := _parse_args(args)
	if not parse_result.ok:
		push_error("[%s] FAIL %s" % [NAME, parse_result.error])
		_print_usage()
		quit(2)
		return
	var run_result := run(parse_result.value)
	if not run_result.ok:
		push_error("[%s] FAIL %s" % [NAME, run_result.error])
		quit(1)
		return
	print("[%s] PASS variants=%d output_dir=%s" % [
		NAME,
		int(run_result.value.get("count", 0)),
		str(run_result.value.get("output_dir", "")),
	])
	quit(0)

static func run(options: Dictionary) -> Result:
	var base_profile := str(options.get("base_profile", DEFAULT_BASE_PROFILE)).strip_edges()
	if base_profile.is_empty():
		return Result.failure("--base-profile cannot be empty")
	var output_dir := str(options.get("output_dir", DEFAULT_OUTPUT_DIR)).strip_edges()
	if output_dir.is_empty():
		return Result.failure("--output-dir cannot be empty")
	var manifest_path := str(options.get("manifest", "")).strip_edges()
	var max_variants := int(options.get("max_variants", DEFAULT_MAX_VARIANTS))
	if max_variants <= 0:
		return Result.failure("--max-variants must be > 0")
	var random_samples := int(options.get("random_samples", DEFAULT_RANDOM_SAMPLES))
	if random_samples < 0:
		return Result.failure("--random-samples must be >= 0")
	var random_seed := int(options.get("random_seed", DEFAULT_RANDOM_SEED))
	var sample_mode := str(options.get("sample_mode", SAMPLE_MODE_CONTINUOUS)).strip_edges()
	if sample_mode.is_empty():
		sample_mode = SAMPLE_MODE_CONTINUOUS
	if not _is_supported_sample_mode(sample_mode):
		return Result.failure("--sample-mode must be continuous or discrete")
	var scales := _scale_array(options.get("scales", []))
	if scales.is_empty():
		return Result.failure("at least one --scale is required")

	var base_path := StrategyProfileClass.resolve_profile_path(base_profile)
	var base_read := _read_json(base_path)
	if not base_read.ok:
		return base_read
	var base_data: Dictionary = base_read.value
	var sampling := {
		"mode": "cartesian",
	}
	var combinations := []
	if random_samples > 0:
		combinations = _build_random_combinations(scales, random_samples, random_seed, sample_mode)
		sampling = {
			"mode": sample_mode,
			"random_seed": random_seed,
			"random_samples": random_samples,
		}
	else:
		combinations = _build_combinations(scales)
	if combinations.size() > max_variants:
		return Result.failure("variant count %d exceeds --max-variants=%d" % [combinations.size(), max_variants])

	var prepare := _prepare_output_dir(output_dir)
	if not prepare.ok:
		return prepare

	var variants: Array[Dictionary] = []
	for combination in combinations:
		var variant := base_data.duplicate(true)
		var apply_read := _apply_combination(variant, Array(combination))
		if not apply_read.ok:
			return apply_read
		var changes: Array = apply_read.value
		var variant_id := _variant_id(str(base_data.get("id", base_profile)), changes, variants.size())
		variant["id"] = variant_id
		var path := "%s/%s.json" % [output_dir.trim_suffix("/"), variant_id]
		var write_read := _write_json(path, JSON.stringify(variant, "  ", false))
		if not write_read.ok:
			return write_read
		var row := {
			"id": variant_id,
			"path": path,
			"changes": changes,
		}
		variants.append(row)
		print("[%s] VARIANT id=%s path=%s changes=%s" % [NAME, variant_id, path, str(changes)])

	var result := {
		"base_profile": base_profile,
		"base_path": base_path,
		"output_dir": output_dir,
		"count": variants.size(),
		"sampling": sampling,
		"variants": variants,
	}
	if not manifest_path.is_empty():
		result["manifest"] = manifest_path
		var manifest_write := _write_json(manifest_path, JSON.stringify(result, "  ", false))
		if not manifest_write.ok:
			return manifest_write
		print("[%s] WROTE_MANIFEST %s" % [NAME, manifest_path])
	return Result.success(result)

static func _parse_args(args: Array[String]) -> Result:
	var options := {
		"base_profile": DEFAULT_BASE_PROFILE,
		"output_dir": DEFAULT_OUTPUT_DIR,
		"manifest": "",
		"max_variants": DEFAULT_MAX_VARIANTS,
		"random_samples": DEFAULT_RANDOM_SAMPLES,
		"random_seed": DEFAULT_RANDOM_SEED,
		"sample_mode": SAMPLE_MODE_CONTINUOUS,
		"scales": [],
	}
	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg.begins_with("--base-profile="):
			var value := arg.trim_prefix("--base-profile=").strip_edges()
			if value.is_empty():
				return Result.failure("--base-profile cannot be empty")
			options["base_profile"] = value
		elif arg.begins_with("--output-dir="):
			var value := arg.trim_prefix("--output-dir=").strip_edges()
			if value.is_empty():
				return Result.failure("--output-dir cannot be empty")
			options["output_dir"] = value
		elif arg.begins_with("--manifest="):
			var value := arg.trim_prefix("--manifest=").strip_edges()
			if value.is_empty():
				return Result.failure("--manifest cannot be empty")
			options["manifest"] = value
		elif arg.begins_with("--max-variants="):
			var value := arg.trim_prefix("--max-variants=").strip_edges()
			if not value.is_valid_int():
				return Result.failure("--max-variants must be an integer")
			options["max_variants"] = int(value)
		elif arg.begins_with("--random-samples="):
			var value := arg.trim_prefix("--random-samples=").strip_edges()
			if not value.is_valid_int():
				return Result.failure("--random-samples must be an integer")
			options["random_samples"] = int(value)
		elif arg.begins_with("--samples="):
			var value := arg.trim_prefix("--samples=").strip_edges()
			if not value.is_valid_int():
				return Result.failure("--samples must be an integer")
			options["random_samples"] = int(value)
		elif arg.begins_with("--random-seed="):
			var value := arg.trim_prefix("--random-seed=").strip_edges()
			if not value.is_valid_int():
				return Result.failure("--random-seed must be an integer")
			options["random_seed"] = int(value)
		elif arg.begins_with("--sample-mode="):
			var value := arg.trim_prefix("--sample-mode=").strip_edges()
			if not _is_supported_sample_mode(value):
				return Result.failure("--sample-mode must be continuous or discrete")
			options["sample_mode"] = value
		elif arg.begins_with("--scale="):
			var scale_read := _parse_scale_arg(arg.trim_prefix("--scale="))
			if not scale_read.ok:
				return scale_read
			options["scales"].append(scale_read.value)
		else:
			return Result.failure("unknown argument: %s" % arg)
	return Result.success(options)

static func _parse_scale_arg(raw_value: String) -> Result:
	var value := raw_value.strip_edges()
	var equals_index := value.find("=")
	if equals_index <= 0 or equals_index >= value.length() - 1:
		return Result.failure("--scale must use path=factor[,factor] syntax")
	var path_text := value.substr(0, equals_index).strip_edges()
	var factors_text := value.substr(equals_index + 1).strip_edges()
	var path: Array[String] = []
	for part in path_text.split(".", false):
		var key := str(part).strip_edges()
		if key.is_empty():
			return Result.failure("--scale path cannot contain empty segments")
		path.append(key)
	if path.is_empty():
		return Result.failure("--scale path cannot be empty")
	var factors: Array[float] = []
	for part in factors_text.split(",", false):
		var factor_text := str(part).strip_edges()
		if factor_text.is_empty() or not factor_text.is_valid_float():
			return Result.failure("--scale factor must be numeric: %s" % raw_value)
		var factor := float(factor_text)
		if factor <= 0.0:
			return Result.failure("--scale factor must be > 0: %s" % raw_value)
		factors.append(factor)
	if factors.is_empty():
		return Result.failure("--scale requires at least one factor")
	return Result.success({
		"path": path,
		"factors": factors,
	})

static func _scale_array(value) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for item in Array(value):
			if item is Dictionary:
				out.append(Dictionary(item))
	return out

static func _build_combinations(scales: Array[Dictionary]) -> Array:
	var combinations := [[]]
	for scale in scales:
		var next := []
		var path: Array = Array(scale.get("path", []))
		var factors: Array = Array(scale.get("factors", []))
		for combination in combinations:
			for factor in factors:
				var row: Array = Array(combination).duplicate(true)
				row.append({
					"path": path.duplicate(),
					"factor": float(factor),
				})
				next.append(row)
		combinations = next
	return combinations

static func _build_random_combinations(scales: Array[Dictionary], sample_count: int, random_seed: int, sample_mode: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var combinations := []
	for _i in range(sample_count):
		var row := []
		for scale in scales:
			var path: Array = Array(scale.get("path", []))
			var factors: Array = Array(scale.get("factors", []))
			row.append({
				"path": path.duplicate(),
				"factor": _sample_factor(factors, rng, sample_mode),
			})
		combinations.append(row)
	return combinations

static func _sample_factor(factors: Array, rng: RandomNumberGenerator, sample_mode: String) -> float:
	if factors.is_empty():
		return 1.0
	if sample_mode == SAMPLE_MODE_DISCRETE or factors.size() == 1:
		var index := rng.randi_range(0, factors.size() - 1)
		return _round3(float(factors[index]))
	var min_factor := float(factors[0])
	var max_factor := min_factor
	for factor_val in factors:
		var factor := float(factor_val)
		if factor < min_factor:
			min_factor = factor
		if factor > max_factor:
			max_factor = factor
	return _round3(rng.randf_range(min_factor, max_factor))

static func _is_supported_sample_mode(value: String) -> bool:
	return value == SAMPLE_MODE_CONTINUOUS or value == SAMPLE_MODE_DISCRETE

static func _apply_combination(profile: Dictionary, combination: Array) -> Result:
	var changes: Array[Dictionary] = []
	for change_val in combination:
		var change: Dictionary = Dictionary(change_val)
		var path: Array = Array(change.get("path", []))
		var factor := float(change.get("factor", 1.0))
		var original_read := _get_nested_number(profile, path)
		if not original_read.ok:
			return original_read
		var original := float(original_read.value)
		var new_value := _round3(original * factor)
		var set_read := _set_nested_number(profile, path, new_value)
		if not set_read.ok:
			return set_read
		changes.append({
			"path": _path_text(path),
			"factor": factor,
			"original": original,
			"value": new_value,
		})
	return Result.success(changes)

static func _get_nested_number(root: Dictionary, path: Array) -> Result:
	var current = root
	for i in range(path.size()):
		var key := str(path[i])
		if not (current is Dictionary) or not Dictionary(current).has(key):
			return Result.failure("profile path not found: %s" % _path_text(path))
		current = Dictionary(current).get(key)
	if current is int or current is float:
		return Result.success(float(current))
	return Result.failure("profile path is not numeric: %s" % _path_text(path))

static func _set_nested_number(root: Dictionary, path: Array, value: float) -> Result:
	if path.is_empty():
		return Result.failure("profile path cannot be empty")
	var current := root
	for i in range(path.size() - 1):
		var key := str(path[i])
		if not current.has(key) or not (current.get(key) is Dictionary):
			return Result.failure("profile path parent not found: %s" % _path_text(path))
		current = Dictionary(current.get(key))
	current[str(path.back())] = value
	return Result.success()

static func _variant_id(base_id: String, changes: Array, index: int = -1) -> String:
	var parts: Array[String] = [_sanitize_id(base_id)]
	for change_val in changes:
		var change: Dictionary = Dictionary(change_val)
		parts.append("%s_x%s" % [
			_sanitize_id(str(change.get("path", ""))),
			_factor_id(float(change.get("factor", 1.0))),
		])
	var suffix := "__sample_%03d" % maxi(0, index)
	var full_id := "__".join(parts) + suffix
	if full_id.length() <= MAX_VARIANT_ID_LENGTH:
		return full_id
	var keep_length := maxi(1, MAX_VARIANT_ID_LENGTH - suffix.length())
	return full_id.substr(0, keep_length).trim_suffix("_") + suffix

static func _sanitize_id(value: String) -> String:
	var out := value.strip_edges()
	for token in [".", "/", "\\", ":", "=", ",", " "]:
		out = out.replace(token, "_")
	return out

static func _factor_id(factor: float) -> String:
	var text := "%.3f" % factor
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	text = text.trim_suffix(".")
	return text.replace("-", "m").replace(".", "_")

static func _path_text(path: Array) -> String:
	var parts: Array[String] = []
	for item in path:
		parts.append(str(item))
	return ".".join(parts)

static func _read_json(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("cannot open base profile: %s" % path)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return Result.failure("base profile JSON must be a Dictionary: %s" % path)
	return Result.success(Dictionary(parsed))

static func _write_json(path: String, text: String) -> Result:
	var prepare := _prepare_output_file(path)
	if not prepare.ok:
		return prepare
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot write JSON: %s" % path)
	file.store_string(text)
	file.store_string("\n")
	file.close()
	return Result.success()

static func _prepare_output_file(path: String) -> Result:
	var global_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		global_path = ProjectSettings.globalize_path(path)
	var parent := global_path.get_base_dir()
	if parent.is_empty():
		return Result.success()
	var err := DirAccess.make_dir_recursive_absolute(parent)
	if err != OK:
		return Result.failure("cannot create output directory %s: %s" % [parent, error_string(err)])
	return Result.success()

static func _prepare_output_dir(path: String) -> Result:
	var global_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		global_path = ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(global_path)
	if err != OK:
		return Result.failure("cannot create output directory %s: %s" % [path, error_string(err)])
	return Result.success()

static func _round3(value: float) -> float:
	return round(value * 1000.0) / 1000.0

static func _print_usage() -> void:
	print("Usage: tools/generate_bot_profile_variants.sh --base-profile=base_revenue_growth_v1 --scale=action_weights.recruit=0.9,1.1 [--scale=employee_priorities.burger_cook=0.95,1.05] [--random-samples=32] [--random-seed=12345] [--sample-mode=continuous|discrete] [--output-dir=res://.godot/bot_profile_variants] [--manifest=res://.godot/bot_profile_variants/manifest.json] [--max-variants=64]")
