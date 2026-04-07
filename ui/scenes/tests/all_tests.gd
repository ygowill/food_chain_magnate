# 全部测试聚合场景（Headless / Autorun）
extends Control

const AllTestsPlanClass = preload("res://ui/scenes/tests/all_tests_plan.gd")
const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")
const CheckCompileScript = preload("res://tools/check_compile.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map/drawer/passes/structures_pass.gd")
const TilePreviewFactoryClass = preload("res://ui/components/reserve_area/tile_preview_factory.gd")

@onready var root_ui: Control = $Root
@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0
var _write_ui_log: bool = true

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless"

func _ready() -> void:
	_write_ui_log = not _is_headless_runtime()
	if not _write_ui_log and is_instance_valid(root_ui):
		root_ui.queue_free()
	_clear_output()
	_append_output("全部测试聚合：按既定顺序依次运行所有 headless 测试。\n")
	_append_output("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")
	if _should_autorun():
		_exit_code = await _run_all()
		if SceneManager != null and SceneManager.has_method("shutdown_current_scene_after_cleanup"):
			SceneManager.shutdown_current_scene_after_cleanup(self, Callable(self, "_prepare_runtime_cleanup_before_quit"), _exit_code)
			return
		await _prepare_runtime_cleanup_before_quit()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = await _run_all()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_all() -> int:
	_append_output("\n--- 开始运行全部测试 ---\n")
	print("[AllTests] START args=%s" % str(OS.get_cmdline_user_args()))

	var tests: Array[Dictionary] = AllTestsPlanClass.build_tests(self)

	var passed := 0
	var failed: Array[String] = []
	var total_start := Time.get_ticks_msec()

	for test_def in tests:
		var name: String = test_def.get("name", "UnknownTest")
		var fn: Callable = test_def.get("fn", Callable())

		_append_output("\n== %s ==\n" % name)
		print("[AllTests] RUN %s" % name)

		var start := Time.get_ticks_msec()
		var call_result = await fn.call()
		var result: Result = call_result if (call_result is Result) else Result.failure("测试返回值类型错误（期望 Result）")
		var duration_ms := Time.get_ticks_msec() - start

		if result.ok:
			passed += 1
			_append_output("PASS (%dms)\n" % duration_ms)
			print("[AllTests] PASS %s (%dms)" % [name, duration_ms])
		else:
			failed.append(name)
			_append_output("FAIL (%dms): %s\n" % [duration_ms, result.error])
			push_error("[AllTests] FAIL %s: %s" % [name, result.error])
			print("[AllTests] FAIL %s (%dms): %s" % [name, duration_ms, result.error])
			if name == "GameSmokeTest":
				var total_ms := Time.get_ticks_msec() - total_start
				var skipped := tests.size() - passed - failed.size()
				_append_output("\n--- 汇总 ---\n")
				_append_output("通过: %d/%d, 总耗时: %dms\n" % [passed, tests.size(), total_ms])
				_append_output("Smoke test 失败：已跳过后续 %d 个测试。\n" % skipped)
				print("[AllTests] FAIL_FAST skipped=%d" % skipped)
				print("[AllTests] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [passed, tests.size(), str(failed), total_ms])
				await _cleanup_runtime_between_tests()
				return 1

		await _cleanup_runtime_between_tests()

	var total_ms := Time.get_ticks_msec() - total_start
	_append_output("\n--- 汇总 ---\n")
	_append_output("通过: %d/%d, 总耗时: %dms\n" % [passed, tests.size(), total_ms])
	print("[AllTests] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [passed, tests.size(), str(failed), total_ms])

	return 0 if failed.is_empty() else 1

func _run_game_smoke_test() -> Result:
	var smoke = get_node_or_null("GameSmokeTest")
	if smoke == null and TestRefs.GameSmokeTestScene != null:
		smoke = TestRefs.GameSmokeTestScene.instantiate()
		add_child(smoke)
		if smoke is CanvasItem:
			(smoke as CanvasItem).visible = false
		await get_tree().process_frame

	if smoke == null or not is_instance_valid(smoke):
		return Result.failure("GameSmokeTest 节点缺失")
	if smoke is CanvasItem:
		(smoke as CanvasItem).visible = false
	if not smoke.has_method("_run_test"):
		return Result.failure("GameSmokeTest 缺少 _run_test()")

	var code = await smoke.call("_run_test")
	await _cleanup_test_node(smoke)
	if code is int and int(code) == 0:
		return Result.success({})
	return Result.failure("GameSmokeTest 失败: exit_code=%s" % str(code))

func _cleanup_test_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.queue_free()
	await _drain_frames(4)

func _prepare_runtime_cleanup_before_quit() -> void:
	_clear_output()
	UiSkinCacheClass.clear_cache()
	EmployeeCardClass.clear_icon_texture_cache()
	StructuresPassClass.clear_drink_source_texture_cache()
	TilePreviewFactoryClass.clear_cached_script()
	if NetClient != null:
		NetClient.shutdown()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	Globals.reset_game_config()
	await _drain_frames(2)

func _cleanup_runtime_between_tests() -> void:
	UiSkinCacheClass.clear_cache()
	EmployeeCardClass.clear_icon_texture_cache()
	StructuresPassClass.clear_drink_source_texture_cache()
	TilePreviewFactoryClass.clear_cached_script()
	if NetClient != null:
		NetClient.shutdown()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	Globals.reset_game_config()
	await _drain_frames(6)

func _run_check_compile_test() -> Result:
	var scan_result: Result = CheckCompileScript.run_scan()
	if scan_result.ok:
		return scan_result

	var details: Dictionary = scan_result.value if (scan_result.value is Dictionary) else {}
	var preview: Array[String] = Array(details.get("preview", []), TYPE_STRING, "", null)
	if preview.is_empty():
		return scan_result
	return Result.failure("%s; first=%s" % [scan_result.error, preview[0]])

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return _is_headless_runtime()

func _drain_frames(count: int) -> void:
	var n := maxi(1, int(count))
	for _i in range(n):
		await get_tree().process_frame

func _append_output(text: String) -> void:
	if not _write_ui_log:
		return
	if is_instance_valid(output):
		output.append_text(text)

func _clear_output() -> void:
	if not _write_ui_log:
		return
	if is_instance_valid(output):
		output.clear()
