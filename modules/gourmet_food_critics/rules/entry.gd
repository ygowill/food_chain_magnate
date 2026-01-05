extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

const MODULE_ID := "gourmet_food_critics"
const MARKETING_TYPE := "gourmet_guide"
const GLOBAL_MAX_ACTIVE := 3

func register(registrar) -> Result:
	var r = registrar.register_employee_patch("marketer", {"add_train_to": ["gourmet_food_critic"]})
	if not r.ok:
		return r

	r = registrar.register_marketing_type(
		MARKETING_TYPE,
		{"requires_edge": true},
		Callable(self, "_get_gourmet_guide_house_ids")
	)
	if not r.ok:
		return r

	r = registrar.register_action_validator(
		"initiate_marketing",
		"%s:gourmet_guide_limit_and_conflicts" % MODULE_ID,
		Callable(self, "_validate_initiate_marketing"),
		10
	)
	if not r.ok:
		return r

	return Result.success()

func _get_gourmet_guide_house_ids(state: GameState, _marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("%s: state.map.houses 缺失或类型错误（期望 Dictionary）" % MODULE_ID)

	var houses: Dictionary = state.map["houses"]
	var out: Array[String] = []

	for house_id_val in houses.keys():
		if not (house_id_val is String):
			return Result.failure("%s: houses key 类型错误（期望 String）" % MODULE_ID)
		var house_id: String = str(house_id_val)
		var house_val = houses.get(house_id, null)
		if house_val == null or not (house_val is Dictionary):
			return Result.failure("%s: houses[%s] 类型错误（期望 Dictionary）" % [MODULE_ID, house_id])
		var house: Dictionary = house_val

		if not house.has("has_garden") or not (house["has_garden"] is bool):
			return Result.failure("%s: houses[%s].has_garden 缺失或类型错误（期望 bool）" % [MODULE_ID, house_id])
		if bool(house["has_garden"]):
			out.append(house_id)

	out.sort()
	return Result.success(out)

func _validate_initiate_marketing(state: GameState, command: Command) -> Result:
	if state == null or command == null:
		return Result.success()
	if not (command.params is Dictionary):
		return Result.success()

	if not command.params.has("board_number"):
		return Result.success()
	var bn_read := _parse_int_value(command.params.get("board_number", null), "board_number")
	if not bn_read.ok:
		return bn_read
	var board_number: int = int(bn_read.value)
	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.success()
	if str(def.type) != MARKETING_TYPE:
		return Result.success()

	# 1) 全局最多 3 个同类 token
	var active := 0
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if str(inst.get("type", "")) == MARKETING_TYPE:
			active += 1
	if active >= GLOBAL_MAX_ACTIVE:
		return Result.failure("美食指南全局最多同时存在 %d 个（当前: %d）" % [GLOBAL_MAX_ACTIVE, active])

	# 2) 与 offramp 同格互斥（offramp 来自模块12，但此处不依赖其脚本；按状态字段检测）
	if not command.params.has("position"):
		return Result.success()
	var pos_val = command.params.get("position", null)
	if not (pos_val is Array) or (pos_val as Array).size() != 2:
		return Result.failure("%s: position 格式错误（期望 [x,y]）" % MODULE_ID)
	var arr: Array = pos_val
	var x_read := _parse_int_value(arr[0], "position[0]")
	if not x_read.ok:
		return x_read
	var y_read := _parse_int_value(arr[1], "position[1]")
	if not y_read.ok:
		return y_read
	var world_pos := Vector2i(int(x_read.value), int(y_read.value))

	if state.map is Dictionary and state.map.has("rural_marketeers_offramps") and (state.map["rural_marketeers_offramps"] is Array):
		var offramps: Array = state.map["rural_marketeers_offramps"]
		for i in range(offramps.size()):
			var o_val = offramps[i]
			if not (o_val is Dictionary):
				continue
			var o: Dictionary = o_val
			var p = o.get("pos", null)
			if p is Vector2i and p == world_pos:
				return Result.failure("美食指南不能放置在已有高速公路出口的格子: %s" % str(world_pos))

	return Result.success()

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

