extends SceneTree

# 批量生成“手工复核用存档”（员工/里程碑）
# 用法：
#   godot --headless --path . --script res://tools/generate_manual_test_saves.gd
# 可选过滤：
#   godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --kind employee
#   godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --id kitchen_trainee

const ManifestClass = preload("res://tools/generate_manual_test_saves_manifest.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")

const OUTPUT_ROOT := "res://testdata/saves/manual_cases"
const UI_LOAD_MODE_PLAYABLE_SNAPSHOT := "playable_snapshot"

const BASELINE_MODULES: Array[String] = [
	"base_rules",
	"base_products",
	"base_pieces",
	"base_employees",
	"base_milestones",
	"base_marketing",
	"base_tiles",
	"base_maps",
]

# 注意：避免在脚本编译期 preload core/tests 或依赖 autoload 的脚本，
# 否则在 `--script` 模式下可能出现“Identifier not found: GameLog/EventBus”的噪音编译报错。
# builder 脚本统一在运行期 load()（registry 构建时）加载。
const BUILDER_SCRIPT_PATHS: Array[String] = [
	"res://tools/manual_test_saves/builders/manual_test_save_employee_builders.gd",
	"res://tools/manual_test_saves/builders/manual_test_save_employee_placement_builders.gd",
	"res://tools/manual_test_saves/builders/manual_test_save_logs_builders.gd",
	"res://tools/manual_test_saves/builders/manual_test_save_milestone_builders.gd",
	"res://tools/manual_test_saves/builders/manual_test_save_marketing_builders.gd",
]

var _builder_registry: Dictionary = {}
var _builder_instances: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var filter_kind := ""
	var filter_id := ""

	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a == "--kind" and i + 1 < args.size():
			filter_kind = str(args[i + 1]).strip_edges()
			i += 2
			continue
		if a == "--id" and i + 1 < args.size():
			filter_id = str(args[i + 1]).strip_edges()
			i += 2
			continue
		i += 1

	print("[ManualTestSaves] START kind=%s id=%s" % [filter_kind, filter_id])

	var cases: Array[Dictionary] = ManifestClass.get_cases()
	if cases.is_empty():
		push_error("[ManualTestSaves] FAIL manifest is empty")
		quit(1)
		return

	var generated := 0
	for case_val in cases:
		if not (case_val is Dictionary):
			push_error("[ManualTestSaves] FAIL case is not a Dictionary: %s" % str(case_val))
			quit(1)
			return
		var c: Dictionary = case_val
		var kind := str(c.get("kind", "")).strip_edges()
		var cid := str(c.get("id", "")).strip_edges()
		if kind.is_empty() or cid.is_empty():
			push_error("[ManualTestSaves] FAIL case missing kind/id: %s" % str(c))
			quit(1)
			return

		if not filter_kind.is_empty() and kind != filter_kind:
			continue
		if not filter_id.is_empty() and cid != filter_id:
			continue

		var r := _generate_case(c)
		if not r.ok:
			push_error("[ManualTestSaves] FAIL %s/%s: %s" % [kind, cid, r.error])
			quit(1)
			return
		generated += 1
		print("[ManualTestSaves] OK   %s/%s -> %s" % [kind, cid, str(r.value)])

	if generated <= 0:
		push_error("[ManualTestSaves] FAIL no cases matched the filter")
		quit(1)
		return

	print("[ManualTestSaves] PASS generated=%d" % generated)
	quit(0)

func _generate_case(c: Dictionary) -> Result:
	var kind := str(c.get("kind", "")).strip_edges()
	var cid := str(c.get("id", "")).strip_edges()
	var title := str(c.get("title", "")).strip_edges()
	var player_count := int(c.get("player_count", 2))
	var seed := int(c.get("seed", 0))
	var enabled_modules: Array[String] = []
	var enabled_val = c.get("enabled_modules", [])
	if enabled_val is Array:
		for v in Array(enabled_val):
			if v is String and not str(v).strip_edges().is_empty():
				enabled_modules.append(str(v).strip_edges())
	enabled_modules = _merge_enabled_modules(enabled_modules)
	var exclude_modules: Array[String] = []
	var exclude_val = c.get("exclude_modules", [])
	if exclude_val is Array:
		for v in Array(exclude_val):
			if v is String and not str(v).strip_edges().is_empty():
				exclude_modules.append(str(v).strip_edges())
	if not exclude_modules.is_empty():
		enabled_modules = _exclude_modules(enabled_modules, exclude_modules)

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed, enabled_modules)
	if not init.ok:
		return Result.failure("GameEngine.initialize failed: %s" % init.error)

	var build := _run_builder(engine, c)
	if not build.ok:
		return build
	var build_ctx: Dictionary = build.value if (build.value is Dictionary) else {}

	# 把当前状态“冻结”为 archive.initial_state（减少命令历史噪音，便于手工复核）。
	# 部分用例（如日志回放）需要保留命令历史；可通过 case.freeze_as_initial=false 禁用（由 builder 自行控制冻结点）。
	var freeze_as_initial := true
	var freeze_val = c.get("freeze_as_initial", true)
	if freeze_val is bool:
		freeze_as_initial = bool(freeze_val)
	if freeze_as_initial:
		_freeze_engine_as_initial(engine)

	var dir_name := _kind_to_dir(kind)
	if dir_name.is_empty():
		return Result.failure("unknown kind: %s" % kind)

	var rel_json_res_path := "%s/%s/%s.json" % [OUTPUT_ROOT, dir_name, cid]
	var abs_json_path := ProjectSettings.globalize_path(rel_json_res_path)
	var abs_dir := abs_json_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)

	var archive_r := engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive failed: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var ui_load_mode := str(c.get("ui_load_mode", "")).strip_edges()
	if ui_load_mode.is_empty() and freeze_as_initial:
		ui_load_mode = UI_LOAD_MODE_PLAYABLE_SNAPSHOT
	if not ui_load_mode.is_empty():
		archive["ui_load_mode"] = ui_load_mode
	var save := ArchiveClass.save_archive_to_file(archive, abs_json_path)
	if not save.ok:
		return Result.failure("save archive failed: %s" % save.error)

	var md_text := _build_markdown(c, build_ctx, rel_json_res_path, engine.get_state())
	var abs_md_path := abs_json_path.trim_suffix(".json") + ".md"
	var md_write := _write_text(abs_md_path, md_text)
	if not md_write.ok:
		return Result.failure("write md failed: %s" % md_write.error)

	# 生成后做一次 load 校验，避免写出坏档。
	var verify_engine := GameEngine.new()
	var load_r := verify_engine.load_from_file(abs_json_path)
	if not load_r.ok:
		return Result.failure("load verification failed: %s" % load_r.error)

	return Result.success({
		"json": rel_json_res_path,
		"md": abs_md_path,
		"title": title,
	})

func _merge_enabled_modules(extra: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for m in BASELINE_MODULES:
		if m.is_empty():
			continue
		if seen.has(m):
			continue
		seen[m] = true
		out.append(m)
	for m2 in extra:
		var s := str(m2).strip_edges()
		if s.is_empty():
			continue
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out

func _exclude_modules(enabled: Array[String], exclude: Array[String]) -> Array[String]:
	var blocked := {}
	for m in exclude:
		var s := str(m).strip_edges()
		if s.is_empty():
			continue
		blocked[s] = true

	var out: Array[String] = []
	for m2 in enabled:
		var s2 := str(m2).strip_edges()
		if s2.is_empty():
			continue
		if blocked.has(s2):
			continue
		out.append(s2)
	return out

func _kind_to_dir(kind: String) -> String:
	match kind:
		"employee":
			return "employees"
		"milestone":
			return "milestones"
		"logs":
			return "logs"
		"marketing":
			return "marketing"
		_:
			return ""

func _freeze_engine_as_initial(engine: GameEngine) -> void:
	if engine == null:
		return
	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1
	engine.create_checkpoint(0)

func _write_text(abs_path: String, text: String) -> Result:
	if abs_path.is_empty():
		return Result.failure("path is empty")
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot open file: %s" % abs_path)
	file.store_string(text)
	file.close()
	return Result.success(abs_path)

func _build_markdown(c: Dictionary, build_ctx: Dictionary, rel_json_res_path: String, state: GameState) -> String:
	var kind := str(c.get("kind", "")).strip_edges()
	var cid := str(c.get("id", "")).strip_edges()
	var title := str(c.get("title", "")).strip_edges()
	var purpose := str(c.get("purpose", "")).strip_edges()
	var steps: Array = c.get("steps", [])
	var expected: Array = c.get("expected", [])
	var related: Array = c.get("related_tests", [])

	var player_count := int(c.get("player_count", 2))
	var seed := int(c.get("seed", 0))

	var header := "# %s/%s" % [kind, cid]
	if not title.is_empty():
		header += " - %s" % title
	var out := header + "\n\n"

	out += "## 存档\n\n"
	out += "- JSON: `%s`\n" % rel_json_res_path
	out += "- 玩家数: %d\n" % player_count
	out += "- Seed: %d\n" % seed
	if state != null:
		out += "- 当前位置: %s/%s (round=%d current_player=%d)\n" % [
			str(state.phase),
			str(state.sub_phase),
			int(state.round_number),
			int(state.get_current_player_id()),
		]

	if not purpose.is_empty():
		out += "\n## 目的\n\n"
		out += "- %s\n" % purpose

	var scenario_val = build_ctx.get("scenario", null)
	if scenario_val is Array and not (scenario_val as Array).is_empty():
		out += "\n## 情景设计\n\n"
		for s in (scenario_val as Array):
			var line := str(s).strip_edges()
			if line.is_empty():
				continue
			out += "- %s\n" % line
	elif scenario_val is String:
		var line := str(scenario_val).strip_edges()
		if not line.is_empty():
			out += "\n## 情景设计\n\n"
			out += "- %s\n" % line

	out += "\n## 复核步骤\n\n"
	if steps is Array and not steps.is_empty():
		for idx in range(steps.size()):
			out += "%d. %s\n" % [idx + 1, str(steps[idx])]
	else:
		out += "1. （待补充）\n"

	out += "\n## 预期结果\n\n"
	if expected is Array and not expected.is_empty():
		for e in expected:
			out += "- %s\n" % str(e)
	else:
		out += "- （待补充）\n"

	var suggested_val = build_ctx.get("suggested_command", null)
	if suggested_val is Dictionary:
		var sc: Dictionary = suggested_val
		var action_id := str(sc.get("action_id", "")).strip_edges()
		if not action_id.is_empty():
			out += "\n## 推荐参数（可选）\n\n"
			out += "- action_id: `%s`\n" % action_id
			if sc.has("actor"):
				out += "- actor: `%s`\n" % str(sc.get("actor"))
			if sc.has("params") and (sc["params"] is Dictionary):
				out += "- params:\n"
				for k in (sc["params"] as Dictionary).keys():
					out += "	- `%s`: `%s`\n" % [str(k), str((sc["params"] as Dictionary)[k])]

	out += "\n## 关联单元测试\n\n"
	if related is Array and not related.is_empty():
		for t in related:
			out += "- `%s`\n" % str(t)
	else:
		out += "- （暂无）\n"

	return out

func _ensure_builder_registry() -> Result:
	if not _builder_registry.is_empty():
		return Result.success()

	var registry := {}
	var instances: Array = []
	for path in BUILDER_SCRIPT_PATHS:
		if path.is_empty():
			continue
		var s = load(path)
		if s == null:
			return Result.failure("cannot load builder script: %s" % path)
		var inst = s.new()
		instances.append(inst)
		if not inst.has_method("get_registry"):
			return Result.failure("builder script missing get_registry(): %s" % path)
		var local = inst.call("get_registry")
		if not (local is Dictionary):
			return Result.failure("get_registry() must return Dictionary: %s" % path)
		for k in (local as Dictionary).keys():
			var name := str(k).strip_edges()
			if name.is_empty():
				return Result.failure("builder name is empty (script=%s)" % path)
			if registry.has(name):
				return Result.failure("duplicate builder registered: %s" % name)
			var cb = (local as Dictionary)[k]
			if not (cb is Callable):
				return Result.failure("builder entry is not Callable: %s" % name)
			registry[name] = cb

	_builder_registry = registry
	_builder_instances = instances
	return Result.success()

func _run_builder(engine: GameEngine, c: Dictionary) -> Result:
	var name := str(c.get("builder", "")).strip_edges()
	if name.is_empty():
		return Result.failure("builder is empty")

	var reg_init := _ensure_builder_registry()
	if not reg_init.ok:
		return reg_init

	if not _builder_registry.has(name):
		return Result.failure("unknown builder: %s" % name)
	var cb = _builder_registry.get(name, null)
	if not (cb is Callable):
		return Result.failure("builder registry entry is not Callable: %s" % name)
	var out = (cb as Callable).call(engine, c)
	if out is Result:
		return out
	return Result.failure("builder did not return Result: %s" % name)
