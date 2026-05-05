extends SceneTree

const SummaryClass = preload("res://tools/bot_selfplay_summary.gd")

const NAME := "BotSelfplaySummary"

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

	var options: Dictionary = parse_result.value
	var paths: Array[String] = options["inputs"]
	var summary_read := SummaryClass.summarize_files(paths)
	if not summary_read.ok:
		push_error("[%s] FAIL %s" % [NAME, summary_read.error])
		quit(1)
		return
	var summary: Dictionary = summary_read.value
	var json := JSON.stringify(summary, "", true)
	if bool(options.get("json_only", false)):
		print(json)
	else:
		for line in SummaryClass.format_summary(summary):
			print(line)
		print("[%s] JSON %s" % [NAME, json])

	var output_json := str(options.get("output_json", "")).strip_edges()
	if not output_json.is_empty():
		var write_read := _write_json(output_json, json)
		if not write_read.ok:
			push_error("[%s] FAIL %s" % [NAME, write_read.error])
			quit(1)
			return
		print("[%s] WROTE_JSON %s" % [NAME, output_json])
	quit(0)

static func _parse_args(args: Array[String]) -> Result:
	var options := {
		"inputs": [] as Array[String],
		"output_json": "",
		"json_only": false,
	}
	for raw_arg in args:
		var arg := str(raw_arg).strip_edges()
		if arg.is_empty():
			continue
		if arg.begins_with("--input="):
			var path := arg.trim_prefix("--input=").strip_edges()
			if path.is_empty():
				return Result.failure("--input cannot be empty")
			options["inputs"].append(path)
		elif arg.begins_with("--output-json="):
			options["output_json"] = arg.trim_prefix("--output-json=").strip_edges()
		elif arg == "--json-only":
			options["json_only"] = true
		else:
			return Result.failure("unknown argument: %s" % arg)
	if Array(options["inputs"]).is_empty():
		return Result.failure("at least one --input path is required")
	return Result.success(options)

static func _write_json(path: String, json: String) -> Result:
	var prepare_read := _prepare_output_file(path)
	if not prepare_read.ok:
		return prepare_read
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot open --output-json: %s" % path)
	file.store_string(json)
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

static func _print_usage() -> void:
	print("Usage: tools/summarize_bot_selfplay.sh --input=res://.godot/selfplay_strategy.jsonl [--input=res://.godot/selfplay_osla.jsonl] [--output-json=res://.godot/bot_selfplay_summary.json] [--json-only]")
