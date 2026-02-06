# 6 人局（6 Players 模组）设置对齐测试
# 验证规则书要求：
# - 6 人局使用 4x6 板块网格（需要 New Districts 模块）
# - “1x”员工卡每种使用 3 张
class_name SixPlayersSetupTest
extends RefCounted

static func run(seed_val: int = 12345) -> Result:
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"new_districts",
	]

	var engine := GameEngine.new()
	var init := engine.initialize(6, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("6p+new_districts 初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")
	if not (state.rules is Dictionary):
		return Result.failure("state.rules 类型错误（期望 Dictionary）")

	if int(state.rules.get("one_x_employee_copies", -1)) != 3:
		return Result.failure("6p one_x_employee_copies 应为 3，实际: %s" % str(state.rules.get("one_x_employee_copies", null)))

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	var map: Dictionary = state.map

	var tile_grid_val = map.get("tile_grid_size", null)
	if not (tile_grid_val is Vector2i):
		return Result.failure("state.map.tile_grid_size 类型错误（期望 Vector2i）")
	var tile_grid: Vector2i = tile_grid_val
	if tile_grid != Vector2i(4, 6):
		return Result.failure("6p tile_grid_size 应为 (4,6)，实际: %s" % str(tile_grid))

	var grid_val = map.get("grid_size", null)
	if not (grid_val is Vector2i):
		return Result.failure("state.map.grid_size 类型错误（期望 Vector2i）")
	var grid: Vector2i = grid_val
	var expected_grid := Vector2i(4 * 5, 6 * 5)
	if grid != expected_grid:
		return Result.failure("6p grid_size 应为 %s，实际: %s" % [str(expected_grid), str(grid)])

	# 未启用 new_districts 时应失败，并提示 New Districts（避免仅提示 tile 数量不足）。
	var engine2 := GameEngine.new()
	var init2 := engine2.initialize(6, seed_val)
	if init2.ok:
		return Result.failure("6p 未启用 new_districts 时应初始化失败（实际 ok）")
	var msg := str(init2.error)
	if msg.find("New Districts") == -1 and msg.find("new_districts") == -1:
		return Result.failure("6p 缺少 new_districts 时应提示 New Districts：%s" % msg)

	return Result.success({
		"tile_grid_size": tile_grid,
		"grid_size": grid,
		"one_x_employee_copies": int(state.rules.get("one_x_employee_copies", -1)),
	})

