# 营销规则（M4）
# 目标：集中维护营销板件/产品/占地的核心业务约束，避免营销领域规则散落多处。
class_name MarketingRules
extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

static func get_removed_board_numbers(player_count: int) -> Array[int]:
	# 对齐 docs/rules.md
	if player_count <= 2:
		return [12, 15, 16]
	if player_count == 3:
		return [15, 16]
	if player_count == 4:
		return [16]
	return []

static func require_marketable_product(product: String) -> Result:
	if not ProductRegistryClass.has(product):
		return Result.failure("未知的产品: %s" % product)
	var def_val = ProductRegistryClass.get_def(product)
	if def_val == null or not (def_val is ProductDef):
		return Result.failure("未知的产品: %s" % product)
	var def: ProductDef = def_val
	if def.has_tag("no_marketing"):
		return Result.failure("该产品不能被营销: %s" % product)
	return Result.success(def)

static func require_marketing_employee(employee_type: String, marketing_type: String = "") -> Result:
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)
	if not marketing_type.is_empty():
		var required_usage := "use:marketing:%s" % marketing_type
		if not emp_def.has_usage_tag(required_usage):
			return Result.failure("该员工无法发起 %s 营销" % marketing_type)
	var max_duration := int(emp_def.marketing_max_duration)
	if max_duration <= 0:
		return Result.failure("该员工无法发起营销")
	return Result.success({
		"definition": emp_def,
		"max_duration": max_duration,
	})

static func require_marketing_duration(action: ActionExecutor, command: Command, max_duration: int) -> Result:
	var duration_result := action.optional_int_param(command, "duration", max_duration)
	if not duration_result.ok:
		return duration_result
	var duration: int = int(duration_result.value)
	if duration <= 0:
		return Result.failure("duration 必须 > 0")
	if duration > max_duration:
		return Result.failure("持续时间超出上限: %d > %d" % [duration, max_duration])
	return Result.success(duration)

static func require_airplane_axis(action: ActionExecutor, command: Command, fallback_axis: String = "") -> Result:
	var axis_result := action.optional_string_param(command, "axis", "")
	if not axis_result.ok:
		return axis_result
	var axis := str(axis_result.value).strip_edges()
	if axis.is_empty():
		axis = fallback_axis
	if axis != "row" and axis != "col":
		return Result.failure("飞机缺少 axis（row/col）")
	return Result.success(axis)

static func require_rotation(rotation: int) -> Result:
	if not MapUtilsClass.VALID_ROTATIONS.has(rotation):
		return Result.failure("rotation 非法（期望 0/90/180/270），实际: %d" % rotation)
	return Result.success(rotation)

static func require_board_spec(state: GameState, board_number: int) -> Result:
	if board_number <= 0:
		return Result.failure("board_number 必须 > 0")
	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	if state != null:
		if not def.has_method("is_available_for_player_count") or not def.is_available_for_player_count(state.players.size()):
			return Result.failure("该营销板件在当前玩家数下已移除: #%d" % board_number)
	var marketing_type := str(def.type)
	var footprint_read := extract_footprint_size(def)
	if not footprint_read.ok:
		return footprint_read
	return Result.success({
		"definition": def,
		"marketing_type": marketing_type,
		"footprint_size": footprint_read.value,
	})

static func extract_footprint_size(definition) -> Result:
	var footprint_size := Vector2i.ONE
	if definition is MarketingDef:
		footprint_size = (definition as MarketingDef).footprint_size
	elif definition != null and definition.has_method("get"):
		var fs = definition.get("footprint_size")
		if fs is Vector2i:
			footprint_size = fs
	if footprint_size.x <= 0 or footprint_size.y <= 0:
		return Result.failure("营销板件占地非法: %s" % str(footprint_size))
	return Result.success(footprint_size)

static func get_rotated_footprint_size(footprint_size: Vector2i, rotation: int) -> Result:
	var rotation_read := require_rotation(rotation)
	if not rotation_read.ok:
		return rotation_read
	var size := Vector2i(footprint_size)
	if rotation == 90 or rotation == 270:
		size = Vector2i(footprint_size.y, footprint_size.x)
	return Result.success(size)

static func build_footprint_cells(world_pos: Vector2i, footprint_size: Vector2i) -> Array[Vector2i]:
	var footprint_cells: Array[Vector2i] = []
	for dy in range(footprint_size.y):
		for dx in range(footprint_size.x):
			footprint_cells.append(world_pos + Vector2i(dx, dy))
	return footprint_cells
