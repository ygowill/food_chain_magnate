class_name SetBrandManagerAirplaneSecondGoodAction
extends ActionExecutor

const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const MILESTONE_ID := "first_brand_manager_used"
const PENDING_KEY := "new_milestones_brand_manager_airplane_pending"

func _init() -> void:
	action_id = "set_brand_manager_airplane_second_good"
	display_name = "飞机追加第二种商品（品牌经理）"
	description = "同回合内可为本次飞机营销追加第二种商品（A→B 顺序结算）；仅在获得里程碑的本回合可用一次"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")

	var player := state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("玩家不存在: %d" % int(command.actor))
	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return Result.failure("player.milestones 类型错误（期望 Array）")
	var milestones: Array = milestones_val
	if not milestones.has(MILESTONE_ID):
		return Result.failure("未获得里程碑：%s" % MILESTONE_ID)

	if not state.round_state.has(PENDING_KEY):
		return Result.failure("当前没有可追加第二种商品的飞机营销")
	var pending_val = state.round_state.get(PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % PENDING_KEY)
	var pending: Dictionary = pending_val
	if not pending.has(command.actor):
		return Result.failure("当前没有可追加第二种商品的飞机营销")
	var info_val = pending.get(command.actor, null)
	if not (info_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [PENDING_KEY, int(command.actor)])
	var info: Dictionary = info_val

	var board_number_val = info.get("board_number", null)
	if not (board_number_val is int):
		return Result.failure("pending.board_number 缺失或类型错误（期望 int）")
	var board_number: int = int(board_number_val)
	if board_number <= 0:
		return Result.failure("pending.board_number 必须 > 0")

	var product_a_val = info.get("product_a", null)
	if not (product_a_val is String):
		return Result.failure("pending.product_a 缺失或类型错误（期望 String）")
	var product_a: String = str(product_a_val)
	if product_a.is_empty():
		return Result.failure("pending.product_a 不能为空")

	var product_b_r := require_string_param(command, "product_b")
	if not product_b_r.ok:
		return product_b_r
	var product_b: String = product_b_r.value
	if product_b.is_empty():
		return Result.failure("product_b 不能为空")
	if product_b == product_a:
		return Result.failure("第二种商品必须不同于第一种商品")
	if not ProductRegistryClass.has(product_b):
		return Result.failure("未知的产品: %s" % product_b)

	var found := false
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", -1)) != board_number:
			continue
		if int(inst.get("owner", -1)) != int(command.actor):
			continue
		if str(inst.get("type", "")) != "airplane":
			return Result.failure("该营销不是 airplane（board #%d）" % board_number)
		if str(inst.get("employee_type", "")) != "brand_manager":
			return Result.failure("该营销不是 brand_manager 发起（board #%d）" % board_number)
		if str(inst.get("product", "")) != product_a:
			return Result.failure("pending.product_a 与实例不一致（board #%d）" % board_number)
		if inst.has("products"):
			var pv = inst.get("products", null)
			if pv is Array and Array(pv).size() > 1:
				return Result.failure("该飞机营销已包含两种商品，无法重复设置")
		found = true
		break
	if not found:
		return Result.failure("未找到对应的飞机营销实例（board #%d）" % board_number)

	var placements: Dictionary = state.map["marketing_placements"]
	var key := str(board_number)
	if not placements.has(key):
		return Result.failure("marketing_placements 缺少 board_number: #%d" % board_number)
	if not (placements[key] is Dictionary):
		return Result.failure("marketing_placements[%s] 类型错误（期望 Dictionary）" % key)

	return Result.success({
		"board_number": board_number,
		"product_a": product_a,
		"product_b": product_b,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value

	var board_number: int = int(info["board_number"])
	var product_a: String = str(info["product_a"])
	var product_b: String = str(info["product_b"])

	for i in range(state.marketing_instances.size()):
		var inst_val = state.marketing_instances[i]
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", -1)) != board_number:
			continue
		if int(inst.get("owner", -1)) != int(command.actor):
			continue
		inst["product"] = product_a
		inst["products"] = [product_a, product_b]
		state.marketing_instances[i] = inst
		break

	var key := str(board_number)
	var placement: Dictionary = state.map["marketing_placements"][key]
	placement["product"] = product_a
	placement["products"] = [product_a, product_b]
	state.map["marketing_placements"][key] = placement

	# 消耗本回合能力
	var pending: Dictionary = state.round_state[PENDING_KEY]
	pending.erase(int(command.actor))
	state.round_state[PENDING_KEY] = pending

	return Result.success({
		"board_number": board_number,
		"products": [product_a, product_b],
	})

