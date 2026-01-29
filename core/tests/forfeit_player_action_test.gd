# 弃权动作：移除玩家资产（M4）
# - 移除：餐厅、营销板件（marketing_instances/marketing_placements）、员工/库存/里程碑/现金等
# - 不移除：房屋/花园
class_name ForfeitPlayerActionTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init_r := engine.initialize(player_count, seed)
	if not init_r.ok:
		return Result.failure("initialize 失败: %s" % init_r.error)

	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		return Result.failure("complete_setup 失败: %s" % setup_r.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")
	if not (state.players is Array) or state.players.size() < 2:
		return Result.failure("players 数量错误")

	var target_id := 0

	# 预置：现金（通过 debug_give_money 注入，保持现金守恒）
	var give_r: Result = engine.execute_command(Command.create("debug_give_money", -1, {"player_id": target_id, "amount": 123}))
	if not give_r.ok:
		return Result.failure("debug_give_money 失败: %s" % give_r.error)

	state = engine.get_state()
	var player0: Dictionary = state.get_player(target_id)
	var cash_before := int(player0.get("cash", 0))
	if cash_before < 123:
		return Result.failure("debug_give_money 未生效: cash=%d" % cash_before)

	var bank_before := int(Dictionary(state.bank).get("removed_total", 0))

	# 预置：员工（应移除除 CEO 外的所有员工，并归还到 employee_pool）
	var pool_before: Dictionary = Dictionary(state.employee_pool).duplicate(true)
	var available: Array[String] = []
	for k in state.employee_pool.keys():
		var emp_id := str(k).strip_edges()
		if emp_id.is_empty() or emp_id == "ceo":
			continue
		var n := int(state.employee_pool.get(k, 0))
		if n > 0:
			available.append(emp_id)
	available.sort()
	if available.size() < 4:
		return Result.failure("employee_pool 可用员工不足，无法构造测试用例")

	var emp_active_1 := available[0]
	var emp_active_2 := available[1]
	var emp_reserve := available[2]
	var emp_busy := available[3]

	# 从池中“取走”员工（保持员工守恒不变量），再放到玩家的各区域
	state.employee_pool[emp_active_1] = int(state.employee_pool.get(emp_active_1, 0)) - 1
	state.employee_pool[emp_active_2] = int(state.employee_pool.get(emp_active_2, 0)) - 1
	state.employee_pool[emp_reserve] = int(state.employee_pool.get(emp_reserve, 0)) - 1
	state.employee_pool[emp_busy] = int(state.employee_pool.get(emp_busy, 0)) - 1

	player0 = state.get_player(target_id)
	player0["employees"] = ["ceo", emp_active_1, emp_active_2]
	player0["reserve_employees"] = [emp_reserve]
	player0["busy_marketers"] = [emp_busy]
	state.players[target_id] = player0

	# 预置：库存/里程碑（应清空）
	player0 = state.get_player(target_id)
	var inv: Dictionary = Dictionary(player0.get("inventory", {})).duplicate(true)
	if inv.is_empty():
		inv["burger"] = 3
	for k in inv.keys():
		inv[k] = 2
	player0["inventory"] = inv
	player0["milestones"] = ["dummy_milestone"]
	state.players[target_id] = player0

	# 预置：营销板件（应移除 owner=target_id）
	state.marketing_instances = [
		{"owner": 0, "type": "test", "board_number": 1},
		{"owner": 1, "type": "test", "board_number": 2},
	]
	if state.map is Dictionary:
		var map0: Dictionary = Dictionary(state.map)
		map0["marketing_placements"] = {
			"a": {"owner": 0},
			"b": {"owner": 1},
		}
		state.map = map0

	# 预置：房屋（不应被移除，即便 owner=target_id）
	var house_cell_x := -1
	var house_cell_y := -1
	if state.map is Dictionary and state.map.has("cells") and (state.map["cells"] is Array):
		var map1: Dictionary = Dictionary(state.map)
		var cells: Array = Array(map1.get("cells", []))
		for y in range(cells.size()):
			var row_val = cells[y]
			if not (row_val is Array):
				continue
			var row: Array = Array(row_val)
			for x in range(row.size()):
				var cell_val = row[x]
				if not (cell_val is Dictionary):
					continue
				var cell: Dictionary = Dictionary(cell_val)
				var structure_val = cell.get("structure", null)
				if structure_val is Dictionary and Dictionary(structure_val).is_empty():
					house_cell_x = x
					house_cell_y = y
					cell["structure"] = {
						"piece_id": "house_with_garden",
						"owner": target_id,
						"dynamic": true,
					}
					row[x] = cell
					cells[y] = row
					break
			if house_cell_x >= 0:
				break
		map1["cells"] = cells
		if not map1.has("houses") or not (map1["houses"] is Dictionary):
			map1["houses"] = {}
		map1["houses"]["test_house"] = {"owner": target_id}
		state.map = map1

	# 执行弃权
	var cmd := Command.create("forfeit_player", target_id, {})
	var fr: Result = engine.execute_command(cmd)
	if not fr.ok:
		return Result.failure("forfeit_player 失败: %s" % fr.error)

	state = engine.get_state()
	var player_after: Dictionary = state.get_player(target_id)
	if not bool(player_after.get("forfeited", false)):
		return Result.failure("forfeited 未标记")

	if int(player_after.get("cash", -1)) != 0:
		return Result.failure("cash 未清零: %d" % int(player_after.get("cash", -1)))
	var bank_after := int(Dictionary(state.bank).get("removed_total", 0))
	if bank_after != bank_before + cash_before:
		return Result.failure("bank.removed_total 未增加: before=%d after=%d" % [bank_before, bank_after])

	# 员工归还到池：应回到初始 pool 值（本测试先从 pool 取走，再弃权归还）
	var expected_emps: Array[String] = [emp_active_1, emp_active_2, emp_reserve, emp_busy]
	for emp_id in expected_emps:
		var before := int(pool_before.get(emp_id, 0))
		var after := int(Dictionary(state.employee_pool).get(emp_id, 0))
		if after != before:
			return Result.failure("employee_pool[%s] 未恢复: before=%d after=%d" % [str(emp_id), before, after])

	var emps: Array = Array(player_after.get("employees", []))
	if emps.size() != 1 or str(emps[0]) != "ceo":
		return Result.failure("employees 未仅保留 CEO: %s" % str(emps))
	if not Array(player_after.get("reserve_employees", [])).is_empty():
		return Result.failure("reserve_employees 未清空")
	if not Array(player_after.get("busy_marketers", [])).is_empty():
		return Result.failure("busy_marketers 未清空")

	# 库存清零
	var inv_after_val = player_after.get("inventory", null)
	if not (inv_after_val is Dictionary):
		return Result.failure("inventory 类型错误（期望 Dictionary）")
	var inv_after: Dictionary = Dictionary(inv_after_val)
	for k2 in inv_after.keys():
		if int(inv_after.get(k2, 0)) != 0:
			return Result.failure("inventory[%s] 未清零: %s" % [str(k2), str(inv_after.get(k2, null))])

	# 里程碑清空
	if not Array(player_after.get("milestones", [])).is_empty():
		return Result.failure("milestones 未清空")

	# 餐厅移除：玩家列表清空；地图 restaurants 中不应存在 owner=target_id
	if not Array(player_after.get("restaurants", [])).is_empty():
		return Result.failure("restaurants 未清空")
	if state.map is Dictionary and state.map.has("restaurants") and (state.map["restaurants"] is Dictionary):
		var rests: Dictionary = Dictionary(state.map["restaurants"])
		var has_other := false
		for rid_val in rests.keys():
			var rest_val = rests.get(rid_val, null)
			if rest_val is Dictionary and int(Dictionary(rest_val).get("owner", -1)) == target_id:
				return Result.failure("map.restaurants 未移除 owner=%d 的餐厅: %s" % [target_id, str(rid_val)])
			if rest_val is Dictionary and int(Dictionary(rest_val).get("owner", -1)) != -1:
				has_other = true
		if not has_other:
			return Result.failure("其它玩家餐厅不应被全部移除")

	# 营销移除
	for inst_val in Array(state.marketing_instances):
		if inst_val is Dictionary and int(Dictionary(inst_val).get("owner", -1)) == target_id:
			return Result.failure("marketing_instances 未移除 owner=%d" % target_id)
	if state.map is Dictionary and state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var places: Dictionary = Dictionary(state.map["marketing_placements"])
		for k3 in places.keys():
			var p_val = places.get(k3, null)
			if p_val is Dictionary and int(Dictionary(p_val).get("owner", -1)) == target_id:
				return Result.failure("marketing_placements 未移除 owner=%d key=%s" % [target_id, str(k3)])

	# 房屋不移除
	if state.map is Dictionary and state.map.has("houses") and (state.map["houses"] is Dictionary):
		var houses: Dictionary = Dictionary(state.map["houses"])
		if not houses.has("test_house"):
			return Result.failure("houses 被错误移除")
	if house_cell_x >= 0 and house_cell_y >= 0 and state.map is Dictionary and state.map.has("cells") and (state.map["cells"] is Array):
		var cells2: Array = Array(state.map["cells"])
		var row2: Array = Array(cells2[house_cell_y])
		var cell2: Dictionary = Dictionary(row2[house_cell_x])
		var s2 = cell2.get("structure", null)
		if not (s2 is Dictionary):
			return Result.failure("house cell structure 类型错误")
		var sd: Dictionary = Dictionary(s2)
		if str(sd.get("piece_id", "")) != "house_with_garden" or int(sd.get("owner", -1)) != target_id:
			return Result.failure("house cell 被错误移除/修改: %s" % str(sd))

	return Result.success()
