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
		var specific_r := _validate_manual_case_specifics(engine, res_path)
		if not specific_r.ok:
			return _fail(specific_r.error)
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

func _validate_manual_case_specifics(engine: GameEngine, res_path: String) -> Result:
	match res_path:
		"res://testdata/saves/manual_cases/employees/lobbyist.json":
			return _validate_lobbyist_case(engine, res_path)
		"res://testdata/saves/manual_cases/employees/regional_manager.json":
			return _validate_regional_manager_move_case(engine, res_path)
		_:
			return Result.success()

func _validate_lobbyist_case(engine: GameEngine, res_path: String) -> Result:
	if engine == null:
		return Result.failure("lobbyist case engine 为空")
	var state := engine.get_state()
	if state == null:
		return Result.failure("lobbyist case state 为空")
	if str(state.phase) != "Working" or str(state.sub_phase) != "Lobbyists":
		return Result.failure("lobbyist case 应停在 Working/Lobbyists，实际: %s/%s" % [str(state.phase), str(state.sub_phase)])

	var actor := int(state.get_current_player_id())
	if actor != 0:
		return Result.failure("lobbyist case 当前玩家应为 0，实际: %d" % actor)

	var passed_val = state.round_state.get("sub_phase_passed", null)
	if not (passed_val is Dictionary):
		return Result.failure("lobbyist case 缺少 round_state.sub_phase_passed")
	var passed: Dictionary = passed_val
	var actor_passed := false
	if passed.has(actor):
		actor_passed = bool(passed.get(actor))
	elif passed.has(str(actor)):
		actor_passed = bool(passed.get(str(actor)))
	else:
		return Result.failure("lobbyist case sub_phase_passed 缺少玩家 0")
	if actor_passed:
		return Result.failure("lobbyist case 玩家 0 不应已跳过 Lobbyists 子阶段")

	var player := state.get_player(actor)
	if not Array(player.get("employees", [])).has("lobbyist"):
		return Result.failure("lobbyist case 玩家 0 在岗员工缺少 lobbyist")

	var initiatable: Array[String] = engine.action_registry.get_player_initiatable_actions(state, actor)
	if not initiatable.has("place_lobbyists_road"):
		return Result.failure("lobbyist case place_lobbyists_road 应可启动，实际: %s" % str(initiatable))
	return Result.success()

func _validate_regional_manager_move_case(engine: GameEngine, res_path: String) -> Result:
	if engine == null:
		return Result.failure("regional_manager move case engine 为空")
	var state := engine.get_state()
	if state == null:
		return Result.failure("regional_manager move case state 为空")

	var params_read := _read_recommended_move_params_from_md(res_path.trim_suffix(".json") + ".md")
	if not params_read.ok:
		return params_read
	var params: Dictionary = params_read.value
	var rest_id := str(params.get("restaurant_id", "")).strip_edges()
	if rest_id.is_empty():
		return Result.failure("regional_manager 推荐参数缺少 restaurant_id")

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("regional_manager map.restaurants 类型错误")
	var restaurants: Dictionary = restaurants_val
	var rest_val = restaurants.get(rest_id, null)
	if not (rest_val is Dictionary):
		return Result.failure("regional_manager 推荐餐厅不存在: %s" % rest_id)
	var rest: Dictionary = rest_val
	var old_anchor = rest.get("anchor_pos", null)
	var old_cells_read := _read_vector2i_array(rest.get("cells", null), "regional_manager restaurants[%s].cells" % rest_id)
	if not old_cells_read.ok:
		return old_cells_read
	var old_cells: Array = old_cells_read.value

	var actor := state.get_current_player_id()
	var move_result := engine.execute_command(Command.create("move_restaurant", actor, params))
	if not move_result.ok:
		return Result.failure("regional_manager 推荐 move_restaurant 执行失败: %s" % move_result.error)

	var new_state := engine.get_state()
	var new_restaurants_val = new_state.map.get("restaurants", null)
	if not (new_restaurants_val is Dictionary):
		return Result.failure("regional_manager move 后 map.restaurants 类型错误")
	var new_restaurants: Dictionary = new_restaurants_val
	var new_rest_val = new_restaurants.get(rest_id, null)
	if not (new_rest_val is Dictionary):
		return Result.failure("regional_manager move 后餐厅不存在: %s" % rest_id)
	var new_rest: Dictionary = new_rest_val
	var new_anchor = new_rest.get("anchor_pos", null)
	if old_anchor is Vector2i and new_anchor is Vector2i and old_anchor == new_anchor:
		return Result.failure("regional_manager 推荐移动未改变餐厅 anchor_pos: %s" % str(old_anchor))
	var new_cells_read := _read_vector2i_array(new_rest.get("cells", null), "regional_manager moved restaurants[%s].cells" % rest_id)
	if not new_cells_read.ok:
		return new_cells_read
	if _same_vector2i_cell_set(old_cells, new_cells_read.value):
		return Result.failure("regional_manager 推荐移动未改变餐厅占地: %s" % str(old_cells))
	return Result.success()

func _read_recommended_move_params_from_md(res_path: String) -> Result:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取推荐参数文档: %s" % res_path)
	var text := file.get_as_text()
	file.close()

	var params := {}
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.begins_with("- `restaurant_id`:"):
			params["restaurant_id"] = _extract_backtick_value_after_colon(line)
		elif line.begins_with("- `position`:"):
			var pos_value := _extract_backtick_value_after_colon(line)
			var parsed_pos = JSON.parse_string(pos_value)
			if not (parsed_pos is Array) or parsed_pos.size() < 2:
				return Result.failure("推荐 position 解析失败: %s" % pos_value)
			params["position"] = [int(parsed_pos[0]), int(parsed_pos[1])]
		elif line.begins_with("- `rotation`:"):
			params["rotation"] = int(_extract_backtick_value_after_colon(line))

	if not params.has("restaurant_id") or not params.has("position") or not params.has("rotation"):
		return Result.failure("推荐 move_restaurant 参数不完整: %s" % str(params))
	return Result.success(params)

func _extract_backtick_value_after_colon(line: String) -> String:
	var colon_idx := line.find(":")
	if colon_idx < 0:
		return ""
	var start_idx := line.find("`", colon_idx)
	if start_idx < 0:
		return ""
	var end_idx := line.find("`", start_idx + 1)
	if end_idx < 0:
		return ""
	return line.substr(start_idx + 1, end_idx - start_idx - 1)

func _read_vector2i_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	var out: Array = []
	var arr: Array = value
	for i in range(arr.size()):
		if not (arr[i] is Vector2i):
			return Result.failure("%s[%d] 类型错误（期望 Vector2i）" % [path, i])
		out.append(arr[i])
	return Result.success(out)

func _same_vector2i_cell_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var seen := {}
	for av in a:
		if not (av is Vector2i):
			return false
		seen[av] = true
	for bv in b:
		if not (bv is Vector2i):
			return false
		if not seen.has(bv):
			return false
	return true

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
