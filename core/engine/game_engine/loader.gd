# GameEngine 存档加载（抽离自 core/engine/game_engine.gd）
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")

static func load_from_archive(engine: GameEngine, archive: Dictionary) -> Result:
	engine._reset_modules_v2()
	# 验证存档格式
	if not archive.has("initial_state") or not archive.has("commands"):
		return Result.failure("无效的存档格式")
	if not archive.has("schema_version"):
		return Result.failure("无效的存档格式: schema_version")
	var schema_read := _parse_int_value(archive["schema_version"], "archive.schema_version")
	if not schema_read.ok:
		return schema_read
	var schema_version: int = int(schema_read.value)
	if schema_version != GameState.SCHEMA_VERSION:
		return Result.failure("不支持的存档 schema_version: %d (期望: %d)" % [schema_version, GameState.SCHEMA_VERSION])

	# 恢复初始状态
	var initial_state_val = archive.get("initial_state", null)
	if initial_state_val == null or not (initial_state_val is Dictionary):
		return Result.failure("无效的存档格式: initial_state")
	var initial_data: Dictionary = initial_state_val
	var state_result := GameState.from_dict(initial_data)
	if not state_result.ok:
		return Result.failure("无效的 initial_state: %s" % state_result.error)
	engine.state = state_result.value

	var rng_val = archive.get("rng", null)
	if not (rng_val is Dictionary):
		return Result.failure("无效的存档格式: rng")
	var rng_data: Dictionary = rng_val
	if rng_data.is_empty():
		return Result.failure("无效的存档格式: rng 不能为空")
	var rng_result := RandomManager.from_dict(rng_data)
	if not rng_result.ok:
		return Result.failure("无效的存档 rng: %s" % rng_result.error)
	engine.random_manager = rng_result.value

	# V2 strict：必须从存档 state.modules 装配当前对局内容（employees/milestones）与 ruleset
	if not (engine.state.modules is Array) or engine.state.modules.is_empty():
		return Result.failure("无效的 initial_state：modules 不能为空（需要模块系统 V2 装配）")

	var base_dir := GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	if archive.has("modules_v2_base_dir"):
		var base_dir_val = archive.get("modules_v2_base_dir", null)
		if not (base_dir_val is String):
			return Result.failure("无效的存档格式: modules_v2_base_dir")
		var base_dir_read: String = str(base_dir_val).strip_edges()
		if base_dir_read.is_empty():
			return Result.failure("无效的存档格式: modules_v2_base_dir 不能为空")
		base_dir = base_dir_read

	var modules_v2_read := engine._apply_modules_v2(Array(engine.state.modules, TYPE_STRING, "", null), base_dir)
	if not modules_v2_read.ok:
		return Result.failure("存档加载失败：模块系统 V2 装配失败: %s" % modules_v2_read.error)
	var expected_plan := Array(engine.state.modules, TYPE_STRING, "", null)
	if engine.module_plan_v2 != expected_plan:
		return Result.failure("存档加载失败：模块计划不一致: archive=%s current=%s" % [str(expected_plan), str(engine.module_plan_v2)])

	var data_result := GameData.from_catalog(engine.content_catalog_v2)
	if not data_result.ok:
		return Result.failure("加载数据失败: %s" % data_result.error)
	engine.game_data = data_result.value
	var setup_actions := engine._setup_action_registry(engine.game_data.pieces)
	if not setup_actions.ok:
		return Result.failure("存档加载失败：ActionRegistry 设置失败: %s" % setup_actions.error)

	var total_cash_read := InvariantsClass.compute_total_cash(engine.state)
	if not total_cash_read.ok:
		return Result.failure("无效的 initial_state：无法计算初始现金总额: %s" % total_cash_read.error)
	if not (engine.state.bank is Dictionary):
		return Result.failure("无效的 initial_state：state.bank 类型错误（期望 Dictionary）")
	if not engine.state.bank.has("reserve_added_total") or not (engine.state.bank["reserve_added_total"] is int):
		return Result.failure("无效的 initial_state：state.bank.reserve_added_total 缺失或类型错误（期望 int）")
	if not engine.state.bank.has("removed_total") or not (engine.state.bank["removed_total"] is int):
		return Result.failure("无效的 initial_state：state.bank.removed_total 缺失或类型错误（期望 int）")
	# _initial_total_cash 语义：不包含“后续注入/移除”的 delta（以便 invariant 使用 base + delta 计算）。
	engine._initial_total_cash = int(total_cash_read.value) - int(engine.state.bank["reserve_added_total"]) + int(engine.state.bank["removed_total"])
	var employee_totals_read := InvariantsClass.compute_employee_totals(engine.state)
	if not employee_totals_read.ok:
		return Result.failure("无效的 initial_state：无法计算初始员工总量: %s" % employee_totals_read.error)
	engine._initial_employee_totals = employee_totals_read.value

	# 重放命令
	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1

	engine._create_checkpoint(0)

	var commands_val = archive.get("commands", null)
	if commands_val == null or not (commands_val is Array):
		return Result.failure("无效的存档格式: commands")

	var commands: Array = commands_val
	for i in range(commands.size()):
		var cmd_data = commands[i]
		if not (cmd_data is Dictionary):
			return Result.failure("回放命令 #%d 格式错误" % i)
		var cmd_read := Command.from_dict(cmd_data)
		if not cmd_read.ok:
			return Result.failure("回放命令 #%d 无效: %s" % [i, cmd_read.error])
		var cmd: Command = cmd_read.value
		if cmd.timestamp < 0:
			return Result.failure("回放命令 #%d 缺少 timestamp" % i)
		var result := engine.execute_command(cmd, true)  # 回放模式
		if not result.ok:
			return Result.failure("回放命令 #%d 失败: %s" % [i, result.error])

	# 若存档记录了当前指针（undo/redo），则回到该位置
	if not archive.has("current_index"):
		return Result.failure("无效的存档格式: current_index")
	var desired_index_read := _parse_int_value(archive["current_index"], "archive.current_index")
	if not desired_index_read.ok:
		return desired_index_read
	var desired_index: int = int(desired_index_read.value)
	if desired_index < -1 or desired_index >= engine.command_history.size():
		return Result.failure("无效的 current_index: %s" % str(archive["current_index"]))
	if desired_index != engine.command_history.size() - 1:
		var rewind_result := engine.rewind_to_command(desired_index)
		if not rewind_result.ok:
			return Result.failure("回退到 current_index 失败: %s" % rewind_result.error)

	GameLog.info("GameEngine", "存档加载完成 - 回放 %d 条命令 (current: %d)" % [
		engine.command_history.size(), engine.current_command_index
	])
	return Result.success(engine.state)

# 解析“应为整数”的值：允许 JSON 数字用 float 表示，但必须是整值；不允许小数与字符串等容错。
static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数），实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数），实际: %s" % [path, typeof(value)])
