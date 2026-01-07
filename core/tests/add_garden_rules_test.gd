# 添加花园规则测试（P2）
# 验证：
# - 添加花园需要在岗的“可添加花园员工”（数据驱动：usage_tags）
# - PlaceHouses 子阶段内“放置房屋/添加花园”共享次数上限（每名可放置房屋/花园员工 1 次）
class_name AddGardenRulesTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	state.sub_phase = "PlaceHouses"
	if state.phase != "Working" or state.sub_phase != "PlaceHouses":
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
	var take := StateUpdaterClass.take_from_pool(state, "new_business_dev", 2)
	if not take.ok:
		return Result.failure("从员工池取出 new_business_dev 失败: %s" % take.error)
	for _i in range(2):
		var add := StateUpdaterClass.add_employee(state, actor, "new_business_dev", false)
		if not add.ok:
			return Result.failure("添加 new_business_dev 失败: %s" % add.error)

	# 3) 寻找一个可行的“放置房屋 -> 添加花园”组合并执行
	var plan := _find_place_house_then_garden_plan(engine, actor)
	if plan.is_empty():
		return Result.failure("找不到可行的“放置房屋 -> 添加花园”组合（可能是地图数据异常）")

	var old_house_ids := {}
	for hid in engine.get_state().map.get("houses", {}).keys():
		old_house_ids[str(hid)] = true

	var place_cmd: Command = plan.get("place_cmd", null)
	var direction := str(plan.get("direction", ""))
	if place_cmd == null or direction.is_empty():
		return Result.failure("测试计划结构无效")

	var exec_place := engine.execute_command(place_cmd)
	if not exec_place.ok:
		return Result.failure("放置房屋失败: %s (%s)" % [exec_place.error, str(place_cmd)])

	# 找到新创建的 house_id（与 PlaceHouseAction 的事件逻辑一致）
	var target_house_id := ""
	for hid in engine.get_state().map.get("houses", {}).keys():
		var id := str(hid)
		if not old_house_ids.has(id):
			target_house_id = id
			break
	if target_house_id.is_empty():
		return Result.failure("未能找到新创建的 house_id")

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
	var cell := MapRuntimeClass.get_cell(state, anchor_pos)
	var structure: Dictionary = cell.get("structure", {})
	if str(structure.get("piece_id", "")) != "house_with_garden":
		return Result.failure("房屋锚点格应为 house_with_garden，实际: %s" % str(structure.get("piece_id", "")))

	# 4) 与 place_house 共享次数：只有 2 名员工时，执行 2 次后不应再允许放置房屋
	state.sub_phase = "PlaceHouses"
	var cmd_house := Command.create("place_house", actor, {"position": [0, 0], "rotation": 0})
	var exec_house := engine.execute_command(cmd_house)
	if exec_house.ok:
		return Result.failure("同一子阶段不应允许在添加花园后继续放置房屋（次数应耗尽）")
	if str(exec_house.error).find("已用完") < 0:
		return Result.failure("放置房屋被拒绝应提示次数已用完，实际: %s" % exec_house.error)

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"actor": actor,
		"house_id": target_house_id,
	})

static func _find_place_house_then_garden_plan(engine: GameEngine, actor: int) -> Dictionary:
	var state := engine.get_state()
	var place_exec := engine.action_registry.get_executor("place_house")
	var garden_exec := engine.action_registry.get_executor("add_garden")
	if place_exec == null or garden_exec == null:
		return {}

	var old_house_ids := {}
	for hid in state.map.get("houses", {}).keys():
		old_house_ids[str(hid)] = true

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]
	var directions := ["N", "E", "S", "W"]

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				var place_cmd := Command.create("place_house", actor, {"position": [x, y], "rotation": rot})
				var vr := place_exec.validate(state, place_cmd)
				if not vr.ok:
					continue

				# 预演放置，找出新 house_id
				var preview := place_exec.compute_new_state(state, place_cmd)
				if not preview.ok:
					continue
				var preview_state: GameState = preview.value

				var new_house_id := ""
				for hid in preview_state.map.get("houses", {}).keys():
					var id := str(hid)
					if not old_house_ids.has(id):
						new_house_id = id
						break
				if new_house_id.is_empty():
					continue

				# 在预演状态下尝试添加花园
				for d in directions:
					var garden_cmd := Command.create("add_garden", actor, {"house_id": new_house_id, "direction": d})
					var vr2 := garden_exec.validate(preview_state, garden_cmd)
					if vr2.ok:
						return {
							"place_cmd": place_cmd,
							"house_id": new_house_id,
							"direction": d,
						}

	return {}
