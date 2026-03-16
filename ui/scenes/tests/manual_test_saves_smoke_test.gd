# Manual Test Saves Smoke Test（Headless / Autorun）
# 目标：逐个加载 `testdata/saves/manual_cases/**/*.json`，确保存档不损坏、可被 GameEngine.load_from_file 正常读取。
extends Control

const NAME := "ManualTestSavesSmokeTest"
const ROOT_DIR := "res://testdata/saves/manual_cases"

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	if is_instance_valid(output):
		output.clear()
		output.append_text("Manual Test Saves Smoke Test：逐个加载 testdata/saves/manual_cases 下全部 JSON 存档。\n")
		output.append_text("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")

	if _should_autorun():
		_exit_code = _run_test()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = _run_test()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_test() -> int:
	if is_instance_valid(output):
		output.append_text("\n--- 开始测试 ---\n")
	print("[%s] START args=%s" % [NAME, str(OS.get_cmdline_user_args())])

	var files: Array[String] = []
	var scan_err := _collect_json_files(ROOT_DIR, files)
	if not scan_err.is_empty():
		return _fail(scan_err)
	files.sort()
	if files.is_empty():
		return _fail("未找到任何 JSON 存档: %s" % ROOT_DIR)

	var loaded := 0
	for res_path in files:
		var abs_path := ProjectSettings.globalize_path(res_path)
		var engine := GameEngine.new()
		var r: Result = engine.load_from_file(abs_path)
		if not r.ok:
			return _fail("load 失败: %s -> %s" % [res_path, r.error])
		var state := engine.get_state()
		if state == null:
			return _fail("load 成功但 state 为空: %s" % res_path)
		var validate_r := _validate_map_structures(state.map, res_path)
		if not validate_r.ok:
			return _fail(validate_r.error)
		loaded += 1

	if is_instance_valid(output):
		output.append_text("PASS: loaded %d archives\n" % loaded)
	print("[%s] PASS count=%d" % [NAME, loaded])
	return 0

func _fail(msg: String) -> int:
	if is_instance_valid(output):
		output.append_text("FAIL: %s\n" % msg)
	push_error("[%s] FAIL: %s" % [NAME, msg])
	print("[%s] FAIL: %s" % [NAME, msg])
	return 1

func _collect_json_files(dir_path: String, out: Array[String]) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return "无法读取目录: %s" % dir_path

	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			var err := _collect_json_files(path, out)
			if not err.is_empty():
				dir.list_dir_end()
				return err
		else:
			if name.to_lower().ends_with(".json"):
				out.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return ""

func _validate_map_structures(map_data: Dictionary, res_path: String) -> Result:
	if map_data.is_empty():
		return Result.failure("map 为空: %s" % res_path)

	var map_origin: Vector2i = map_data.get("map_origin", Vector2i.ZERO)
	var cells_val = map_data.get("cells", null)
	if not (cells_val is Array):
		return Result.failure("map.cells 类型错误: %s" % res_path)

	var cells: Array = cells_val
	for y in range(cells.size()):
		var row_val = cells[y]
		if not (row_val is Array):
			return Result.failure("map.cells[%d] 类型错误: %s" % [y, res_path])
		var row: Array = row_val
		for x in range(row.size()):
			var cell_val = row[x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var structure_val = cell.get("structure", null)
			if not (structure_val is Dictionary):
				continue
			var structure: Dictionary = structure_val
			if structure.is_empty():
				continue

			var piece_id := str(structure.get("piece_id", "")).strip_edges()
			if piece_id.is_empty():
				return Result.failure("structure.piece_id 为空: %s @ (%d,%d)" % [res_path, x, y])
			if not (structure.get("parent_anchor", null) is Vector2i):
				return Result.failure("structure.parent_anchor 缺失: %s @ (%d,%d) piece=%s" % [res_path, x, y, piece_id])
			if not structure.has("rotation"):
				return Result.failure("structure.rotation 缺失: %s @ (%d,%d) piece=%s" % [res_path, x, y, piece_id])

			var world_pos := Vector2i(x, y) - map_origin
			var anchor: Vector2i = structure.get("parent_anchor", Vector2i.ZERO)
			var expected_anchor_cell := world_pos == anchor
			if structure.has("anchor_cell") and bool(structure.get("anchor_cell", false)) != expected_anchor_cell:
				return Result.failure("structure.anchor_cell 不匹配: %s @ (%d,%d) piece=%s expected=%s" % [res_path, x, y, piece_id, str(expected_anchor_cell)])

	return Result.success()

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
