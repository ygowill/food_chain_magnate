# 添加花园规则测试（P2）
# 验证：
# - 添加花园需要在岗的“可添加花园员工”（数据驱动：usage_tags）
# - PlaceHouses 子阶段内“放置房屋/添加花园”共享次数上限（每名可放置房屋/花园员工 1 次）
class_name AddGardenRulesTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("应处于 Working/PlaceHouses，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	# 1) 没有可添加花园员工：应拒绝添加花园（即使 house_id 不存在也应先报“需要可添加花园员工”）
	var cmd_fail := Command.create("add_garden", actor, {"house_id": "nonexistent_house", "direction": "N"})
	var exec_fail := engine.execute_command(cmd_fail)
	if exec_fail.ok:
		return Result.failure("没有可添加花园员工时不应允许添加花园")
	if str(exec_fail.error).find("可添加花园") < 0:
		return Result.failure("拒绝原因应包含'可添加花园'，实际: %s" % exec_fail.error)

	# 2) 给玩家添加 2 名在岗员工（便于在同一子阶段内完成“放置房屋 + 添加花园”）
	state = engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "new_business_developer", 2)
	if not take.ok:
		return Result.failure("从员工池取出 new_business_developer 失败: %s" % take.error)
	for _i in range(2):
		var add := StateUpdaterClass.add_employee(state, actor, "new_business_developer", false)
		if not add.ok:
			return Result.failure("添加 new_business_developer 失败: %s" % add.error)

	# 3) 寻找一个可行的“对印刷房屋添加花园”的组合并执行
	var plan := _find_add_garden_plan(engine, actor)
	if plan.is_empty():
		return Result.failure("找不到可行的“添加花园”目标（可能是地图数据异常）")

	var target_house_id := str(plan.get("house_id", ""))
	var direction := str(plan.get("direction", ""))
	if target_house_id.is_empty() or direction.is_empty():
		return Result.failure("测试计划结构无效")

	var garden_cmd := Command.create("add_garden", actor, {"house_id": target_house_id, "direction": direction})
	var exec_ok := engine.execute_command(garden_cmd)
	if not exec_ok.ok:
		return Result.failure("添加花园应成功，但失败: %s (%s)" % [exec_ok.error, str(garden_cmd)])

	state = engine.get_state()
	var house: Dictionary = state.map.get("houses", {}).get(target_house_id, {})
	if house.is_empty():
		return Result.failure("添加花园后房屋应存在: %s" % target_house_id)
	if not bool(house.get("has_garden", false)):
		return Result.failure("添加花园后 house.has_garden 应为 true")

	var anchor_pos: Vector2i = house.get("anchor_pos", Vector2i.ZERO)
	var cell := CellsClass.get_cell(state, anchor_pos)
	var structure: Dictionary = cell.get("structure", {})
	if str(structure.get("piece_id", "")) != "house_with_garden":
		return Result.failure("房屋锚点格应为 house_with_garden，实际: %s" % str(structure.get("piece_id", "")))

	# 4) 与 place_house 共享次数：只有 2 名员工时，执行 2 次后不应再允许放置房屋
	state = engine.get_state()
	var hn1 := _pick_house_number(state)
	if hn1 <= 0:
		return Result.failure("无法获取可用房屋编号（用于 place_house）")
	var place_cmd_ok := _find_first_valid_house_placement(engine, actor, hn1)
	if place_cmd_ok == null:
		return Result.failure("找不到合法的房屋放置点（可能是地图数据异常）")
	var exec_place := engine.execute_command(place_cmd_ok)
	if not exec_place.ok:
		return Result.failure("放置房屋应成功，但失败: %s (%s)" % [exec_place.error, str(place_cmd_ok)])

	state = engine.get_state()
	var hn2 := _pick_house_number(state)
	if hn2 <= 0:
		return Result.failure("无法获取剩余房屋编号（用于验证次数耗尽）")
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	var cmd_house := Command.create("place_house", actor, {"position": [0, 0], "rotation": 0, "house_number": hn2})
	var exec_house := engine.execute_command(cmd_house)
	if exec_house.ok:
		return Result.failure("同一子阶段不应允许在执行 2 次后继续放置房屋（次数应耗尽）")
	if str(exec_house.error).find("已用完") < 0:
		return Result.failure("放置房屋被拒绝应提示次数已用完，实际: %s" % exec_house.error)

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"actor": actor,
		"house_id": target_house_id,
	})

static func _find_add_garden_plan(engine: GameEngine, actor: int) -> Dictionary:
	var state := engine.get_state()
	var garden_exec := engine.action_registry.get_executor("add_garden")
	if garden_exec == null:
		return {}

	var directions := ["N", "E", "S", "W"]

	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return {}
	var houses: Dictionary = houses_val
	for hid_val in houses.keys():
		var hid := str(hid_val).strip_edges()
		if hid.is_empty():
			continue
		var house_val = houses.get(hid_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		if bool(house.get("has_garden", false)):
			continue

		for d in directions:
			var garden_cmd := Command.create("add_garden", actor, {"house_id": hid, "direction": d})
			var vr2 := garden_exec.validate(state, garden_cmd)
			if vr2.ok:
				return {"house_id": hid, "direction": d}

	return {}

static func _find_first_valid_house_placement(engine: GameEngine, actor: int, house_number: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_house")
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var cmd := Command.create("place_house", actor, {"position": [x, y], "rotation": r, "house_number": int(house_number)})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd

	return null

static func _pick_house_number(state: GameState) -> int:
	if state == null or not (state.map is Dictionary):
		return -1
	var supply_val = state.map.get("house_number_supply_remaining", null)
	if supply_val is Array:
		var nums: Array[int] = []
		for v in Array(supply_val):
			if v is int:
				nums.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					nums.append(int(f))
		nums.sort()
		return int(nums[0]) if not nums.is_empty() else -1
	# Fallback
	return 1
