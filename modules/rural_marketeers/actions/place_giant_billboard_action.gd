class_name PlaceGiantBillboardAction
extends ActionExecutor

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

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
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

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
	if not ProductRegistryClass.has(product):
		return Result.failure("未知的产品: %s" % product)

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

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	if not houses.has(RURAL_HOUSE_ID) or not (houses[RURAL_HOUSE_ID] is Dictionary):
		return Result.failure("缺少 rural_area（模块未正确初始化）")
	var rural: Dictionary = houses[RURAL_HOUSE_ID]
	if not rural.has("giant_billboards") or not (rural["giant_billboards"] is Dictionary):
		return Result.failure("rural_area.giant_billboards 缺失或类型错误（期望 Dictionary）")
	var boards: Dictionary = rural["giant_billboards"]
	if boards.has(side):
		return Result.failure("该侧已放置巨型广告牌: %s" % side)

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var side_read := require_string_param(command, "side")
	if not side_read.ok:
		return side_read
	var side: String = side_read.value

	var product_read := require_string_param(command, "product")
	if not product_read.ok:
		return product_read
	var product: String = product_read.value

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	var rural: Dictionary = houses[RURAL_HOUSE_ID]
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

