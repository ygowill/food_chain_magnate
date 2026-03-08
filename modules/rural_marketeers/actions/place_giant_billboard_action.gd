class_name PlaceGiantBillboardAction
extends ActionExecutor

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const MODULE_ID := "rural_marketeers"
const RURAL_HOUSE_ID := "rural_area"
const EMPLOYEE_ID := "rural_marketeer"

const BILLBOARD_SIDES: Array[String] = ["N", "E", "S", "W"]
const BILLBOARD_BOARD_NUMBER_BY_SIDE := {
	"N": 5000,
	"E": 5001,
	"S": 5002,
	"W": 5003,
}

func _init() -> void:
	action_id = "place_giant_billboard"
	display_name = "放置巨型广告牌"
	description = "使用乡村营销员在乡村地区放置一个永久的巨型广告牌"
	requires_actor = true
	is_mandatory = false
	ui_hide_if_not_initiatable = true
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	if player.is_empty():
		return false

	var employees_val = player.get("employees", null)
	if not (employees_val is Array):
		return false
	var employees: Array = employees_val

	var has_emp := false
	for v in employees:
		if v is String and str(v) == EMPLOYEE_ID:
			has_emp = true
			break
	if not has_emp:
		return false

	var houses_read := MapStateAccessClass.require_houses(state, action_id)
	if not houses_read.ok:
		return false
	var houses: Dictionary = houses_read.value
	var rural_val = houses.get(RURAL_HOUSE_ID, null)
	if not (rural_val is Dictionary):
		return false
	var boards_val = rural_val.get("giant_billboards", null)
	if not (boards_val is Dictionary):
		return false
	var boards: Dictionary = boards_val

	# 至少存在一个未占用的边，才允许“启动”该动作（缺参状态也算可启动）。
	for side in BILLBOARD_SIDES:
		if not boards.has(side):
			return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var side_read := require_string_param(command, "side")
	if not side_read.ok:
		return side_read
	var side: String = side_read.value
	if not BILLBOARD_SIDES.has(side):
		return Result.failure("side 非法（期望 N/E/S/W）: %s" % side)

	var product_read := require_string_param(command, "product")
	if not product_read.ok:
		return product_read
	var product: String = product_read.value
	var product_rule_read := MarketingRulesClass.require_marketable_product(product)
	if not product_rule_read.ok:
		return product_rule_read
	var def: ProductDef = product_rule_read.value
	if not (def.has_tag("food") or def.has_tag("drink")):
		return Result.failure("巨型广告牌只能营销食物或饮料: %s" % product)

	var player := state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("玩家不存在: %d" % command.actor)
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("player.employees 缺失或类型错误（期望 Array）")
	var employees: Array = player["employees"]
	var has_emp := false
	for i in range(employees.size()):
		var v = employees[i]
		if not (v is String):
			return Result.failure("player.employees[%d] 类型错误（期望 String）" % i)
		if str(v) == EMPLOYEE_ID:
			has_emp = true
			break
	if not has_emp:
		return Result.failure("你没有激活的 %s" % EMPLOYEE_ID)

	var houses_read := MapStateAccessClass.require_houses(state, action_id)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	if not houses.has(RURAL_HOUSE_ID) or not (houses[RURAL_HOUSE_ID] is Dictionary):
		return Result.failure("缺少 rural_area（模块未正确初始化）")
	var rural: Dictionary = houses[RURAL_HOUSE_ID]
	if not rural.has("giant_billboards") or not (rural["giant_billboards"] is Dictionary):
		return Result.failure("rural_area.giant_billboards 缺失或类型错误（期望 Dictionary）")
	var boards: Dictionary = rural["giant_billboards"]
	if boards.has(side):
		return Result.failure("该侧已放置巨型广告牌: %s" % side)

	return Result.success({
		"side": side,
		"product": product,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value
	var side: String = str(info.get("side", ""))
	var product: String = str(info.get("product", ""))

	var houses_read := MapStateAccessClass.require_houses(state, action_id)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	if not houses.has(RURAL_HOUSE_ID) or not (houses[RURAL_HOUSE_ID] is Dictionary):
		return Result.failure("缺少 rural_area（模块未正确初始化）")
	var rural: Dictionary = houses[RURAL_HOUSE_ID]
	if not rural.has("giant_billboards") or not (rural["giant_billboards"] is Dictionary):
		return Result.failure("rural_area.giant_billboards 缺失或类型错误（期望 Dictionary）")
	var boards: Dictionary = rural["giant_billboards"]

	# 将 rural_marketeer 从在岗移到忙碌（永久）
	var removed := StateUpdaterClass.remove_from_array(state.players[command.actor], "employees", EMPLOYEE_ID)
	if not removed:
		return Result.failure("你没有激活的 %s" % EMPLOYEE_ID)
	StateUpdaterClass.append_to_array(state.players[command.actor], "busy_marketers", EMPLOYEE_ID)

	boards[side] = {
		"board_number": int(BILLBOARD_BOARD_NUMBER_BY_SIDE.get(side, 0)),
		"owner": int(command.actor),
		"product": product,
	}
	rural["giant_billboards"] = boards
	houses[RURAL_HOUSE_ID] = rural
	state.map["houses"] = houses

	var ms := MilestoneSystemClass.process_event(state, "UseEmployee", {
		"player_id": int(command.actor),
		"id": EMPLOYEE_ID
	})
	var result := Result.success({
		"player_id": int(command.actor),
		"side": side,
		"product": product,
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(UseEmployee/%s): %s" % [EMPLOYEE_ID, ms.error])
	return result
