extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const Phase = DefsClass.Phase
const PHASE_NAMES = DefsClass.PHASE_NAMES
const PHASE_ORDER = DefsClass.PHASE_ORDER
const SUB_PHASE_NAMES = DefsClass.SUB_PHASE_NAMES
const SUB_PHASE_ORDER = DefsClass.SUB_PHASE_ORDER

static func build_phase_order_names(order_enums: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for i in range(order_enums.size()):
		var p: int = int(order_enums[i])
		out.append(str(PHASE_NAMES.get(p, "")))
	return out

static func set_phase_order(phase_manager, order_names: Array) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("phase_order 类型错误（期望 Array）")
	if order_names.is_empty():
		return Result.failure("phase_order 不能为空")

	var out_enums: Array[int] = []
	var out_names: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("phase_order[%d] 类型错误（期望 String）" % i)
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("phase_order[%d] 不能为空" % i)
		if seen.has(name):
			return Result.failure("phase_order 重复: %s" % name)
		var p_enum := DefsClass.get_phase_enum(name)
		if p_enum == -1:
			return Result.failure("phase_order[%d] 未知阶段: %s" % [i, name])
		if p_enum == Phase.SETUP or p_enum == Phase.GAME_OVER:
			return Result.failure("phase_order 不允许包含 Setup/GameOver: %s" % name)
		seen[name] = true
		out_enums.append(p_enum)
		out_names.append(name)

	# 约束：仅允许对基础阶段顺序（PHASE_ORDER）做重排，不支持添加/删除阶段（保持 core 默认阶段集合）
	if out_enums.size() != PHASE_ORDER.size():
		return Result.failure("phase_order 长度必须为 %d，实际: %d" % [PHASE_ORDER.size(), out_enums.size()])
	for base_enum in PHASE_ORDER:
		var base_name: String = str(PHASE_NAMES[base_enum])
		if not seen.has(base_name):
			return Result.failure("phase_order 缺少基础阶段: %s" % base_name)

	phase_manager._phase_order_enums = out_enums
	phase_manager._phase_order_names = out_names
	return Result.success()

static func build_default_working_sub_phase_order_names() -> Array[String]:
	var out: Array[String] = []
	for i in range(SUB_PHASE_ORDER.size()):
		var sub_id = SUB_PHASE_ORDER[i]
		out.append(str(SUB_PHASE_NAMES[sub_id]))
	return out

static func set_working_sub_phase_order(phase_manager, order_names: Array) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("working_sub_phase_order 类型错误（期望 Array）")
	if order_names.is_empty():
		return Result.failure("working_sub_phase_order 不能为空")

	var out: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("working_sub_phase_order[%d] 类型错误（期望 String）" % i)
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("working_sub_phase_order[%d] 不能为空" % i)
		if seen.has(name):
			return Result.failure("working_sub_phase_order 重复: %s" % name)
		seen[name] = true
		out.append(name)

	# 必须包含所有基础 Working 子阶段（严格模式：避免核心状态机失配）
	for sub_id in SUB_PHASE_ORDER:
		var base_name: String = str(SUB_PHASE_NAMES[sub_id])
		if not seen.has(base_name):
			return Result.failure("working_sub_phase_order 缺少基础子阶段: %s" % base_name)

	phase_manager._working_sub_phase_order_names = out
	return Result.success()

static func set_cleanup_sub_phase_order(phase_manager, order_names: Array) -> Result:
	if order_names == null or not (order_names is Array):
		return Result.failure("cleanup_sub_phase_order 类型错误（期望 Array）")

	var out: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("cleanup_sub_phase_order[%d] 类型错误（期望 String）" % i)
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("cleanup_sub_phase_order[%d] 不能为空" % i)
		if seen.has(name):
			return Result.failure("cleanup_sub_phase_order 重复: %s" % name)
		seen[name] = true
		out.append(name)

	phase_manager._cleanup_sub_phase_order_names = out
	return Result.success()

static func set_phase_sub_phase_order(phase_manager, phase: int, order_names: Array) -> Result:
	if phase == Phase.WORKING:
		return Result.failure("phase_sub_phase_order: Working 请使用 set_working_sub_phase_order")
	if phase == Phase.CLEANUP:
		return Result.failure("phase_sub_phase_order: Cleanup 请使用 set_cleanup_sub_phase_order")
	if phase == Phase.SETUP or phase == Phase.GAME_OVER:
		return Result.failure("phase_sub_phase_order 不允许包含 Setup/GameOver")
	if order_names == null or not (order_names is Array):
		return Result.failure("phase_sub_phase_order[%s] 类型错误（期望 Array）" % str(PHASE_NAMES.get(phase, phase)))

	if order_names.is_empty():
		phase_manager._phase_sub_phase_orders.erase(phase)
		return Result.success()

	var out: Array[String] = []
	var seen := {}
	for i in range(order_names.size()):
		var v = order_names[i]
		if not (v is String):
			return Result.failure("phase_sub_phase_order[%s][%d] 类型错误（期望 String）" % [str(PHASE_NAMES.get(phase, phase)), i])
		var name: String = str(v)
		if name.is_empty():
			return Result.failure("phase_sub_phase_order[%s][%d] 不能为空" % [str(PHASE_NAMES.get(phase, phase)), i])
		if seen.has(name):
			return Result.failure("phase_sub_phase_order[%s] 重复: %s" % [str(PHASE_NAMES.get(phase, phase)), name])
		seen[name] = true
		out.append(name)

	phase_manager._phase_sub_phase_orders[phase] = out
	return Result.success()

static func get_phase_sub_phase_order_names(phase_manager, phase: int) -> Array[String]:
	if phase_manager._phase_sub_phase_orders.has(phase):
		var v = phase_manager._phase_sub_phase_orders.get(phase, null)
		if v is Array:
			return (v as Array).duplicate()
	return []

