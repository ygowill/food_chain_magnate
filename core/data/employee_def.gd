# 员工定义
# 解析模块 content/employees/*.json 中的员工数据
class_name EmployeeDef
extends RefCounted

# === 基础信息 ===
var id: String = ""
var name: String = ""
var description: String = ""

# === 薪资与唯一性 ===
var salary: bool = true  # 是否需要支付薪水
var unique: bool = false  # 是否唯一（如 CEO、CFO）

# === 管理能力 ===
var manager_slots: int = 0  # 可管理的下属槽位数

# === 影响范围 ===
var range_type: String = ""  # "neighborhood", "global", null
var range_value: int = 0     # 范围值（用于 neighborhood 类型）

# === 培训相关 ===
var train_to: Array[String] = []  # 可培训成的职位列表
var train_capacity: int = 0       # 培训容量（培训师专用）

# === 招聘相关 ===
var recruit_capacity: int = 0     # 招聘容量（每回合 Recruit 子阶段可提供的招聘次数）

# === 标签 ===
var tags: Array[String] = []       # 功能标签: recruit, train, cook, etc.
var usage_tags: Array[String] = [] # 使用标签: use:recruit, use:train, etc.

# === 其他 ===
var mandatory: bool = false        # 是否为必须员工
var mandatory_action_id: String = ""  # 可选：mandatory=true 时，对应的强制动作 action_id（为空表示自动应用，无需动作）
var can_be_fired: bool = true  # 是否可被解雇（避免硬编码 employee_id == "ceo"）

# === 营销相关 ===
var marketing_max_duration: int = 0  # 可选：营销活动最大持续回合数（仅营销员使用）

# === UI/规则中的“职责角色” ===
# - 角色是稳定枚举；颜色由角色映射。
var role: String = ""  # manager | recruit_train | produce_food | procure_drink | price | marketing | new_shop | special

# === UI/规则中的“员工颜色” ===
# 说明：
# - 用于 UI 展示与部分规则（例如 New Milestones: FIRST LEMONADE SOLD 的“颜色不变”）。
# - 当前按职责从现有字段推导，不依赖 JSON 显式字段，避免硬编码名单扩散。
const ROLE_COLOR_MANAGER := "#000000"
const ROLE_COLOR_RECRUIT_TRAIN := "#bdb6b5"
const ROLE_COLOR_PRODUCE_FOOD := "#94a869"
const ROLE_COLOR_PROCURE_DRINK := "#adce91"
const ROLE_COLOR_PRICE := "#eba791"
const ROLE_COLOR_MARKETING := "#94c1c7"
const ROLE_COLOR_NEW_SHOP := "#aa3c34"
const ROLE_COLOR_SPECIAL := "#ae94c0"

# === 供应池（路线B）===
# 用于“从内容元数据推导 Pools”，替代 GameConfig.employee_pool.base/one_x_employee_ids 等硬编码列表。
# - fixed: 固定张数（count）
# - one_x: 按玩家人数决定“每种 1x 员工卡”的张数（count 由 rules 提供）
# - none: 不进入供应池（例如 CEO、仅由模块注入等）
var pool_type: String = "none"  # fixed | one_x | none
var pool_count: int = 0  # fixed 专用

# === 可插拔效果（模块系统 V2，M5）===
# effect_id 命名规范：module_id:...
var effect_ids: Array[String] = []

# === 生产能力 ===
var produces_food_type: String = ""  # 生产的食物类型 (burger, pizza, etc.)
var produces_amount: int = 0         # 生产数量

# === 工厂方法 ===

static func from_dict(data: Dictionary) -> Result:
	var emp := EmployeeDef.new()

	var id_read := _parse_string(data.get("id", null), "EmployeeDef.id", false)
	if not id_read.ok:
		return id_read
	emp.id = id_read.value

	var name_read := _parse_string(data.get("name", null), "EmployeeDef.name", false)
	if not name_read.ok:
		return name_read
	emp.name = name_read.value

	var desc_read := _parse_string(data.get("description", null), "EmployeeDef.description", true)
	if not desc_read.ok:
		return desc_read
	emp.description = desc_read.value

	if not data.has("role"):
		return Result.failure("EmployeeDef.role 缺失（必须提供）")
	var role_read := _parse_string(data.get("role", null), "EmployeeDef.role", false)
	if not role_read.ok:
		return role_read
	emp.role = role_read.value
	if emp.role != "manager" \
			and emp.role != "recruit_train" \
			and emp.role != "produce_food" \
			and emp.role != "procure_drink" \
			and emp.role != "price" \
			and emp.role != "marketing" \
			and emp.role != "new_shop" \
			and emp.role != "special":
		return Result.failure("EmployeeDef.role 不支持: %s" % emp.role)

	var salary_read := _parse_bool(data.get("salary", null), "EmployeeDef.salary")
	if not salary_read.ok:
		return salary_read
	emp.salary = bool(salary_read.value)

	var unique_read := _parse_bool(data.get("unique", null), "EmployeeDef.unique")
	if not unique_read.ok:
		return unique_read
	emp.unique = bool(unique_read.value)

	var manager_slots_read := _parse_non_negative_int(data.get("manager_slots", null), "EmployeeDef.manager_slots")
	if not manager_slots_read.ok:
		return manager_slots_read
	emp.manager_slots = int(manager_slots_read.value)

	var range_val = data.get("range", null)
	if not (range_val is Dictionary):
		return Result.failure("EmployeeDef.range 缺失或类型错误（期望 Dictionary）")
	var range: Dictionary = range_val

	var range_type_val = range.get("type", null)
	if range_type_val == null:
		emp.range_type = ""
	else:
		var range_type_read := _parse_string(range_type_val, "EmployeeDef.range.type", false)
		if not range_type_read.ok:
			return range_type_read
		var rt: String = range_type_read.value
		if rt != "road" and rt != "air":
			return Result.failure("EmployeeDef.range.type 不支持: %s" % rt)
		emp.range_type = rt

	var range_value_read := _parse_int(range.get("value", null), "EmployeeDef.range.value")
	if not range_value_read.ok:
		return range_value_read
	emp.range_value = int(range_value_read.value)
	if emp.range_value < -1:
		return Result.failure("EmployeeDef.range.value 必须 >= -1，实际: %d" % emp.range_value)
	if emp.range_type.is_empty() and emp.range_value != 0:
		return Result.failure("EmployeeDef.range.type 为空时 range.value 必须为 0，实际: %d" % emp.range_value)

	var train_to_read := _parse_string_array(data.get("train_to", null), "EmployeeDef.train_to", true)
	if not train_to_read.ok:
		return train_to_read
	emp.train_to = train_to_read.value

	var train_capacity_read := _parse_non_negative_int(data.get("train_capacity", null), "EmployeeDef.train_capacity")
	if not train_capacity_read.ok:
		return train_capacity_read
	emp.train_capacity = int(train_capacity_read.value)

	var tags_read := _parse_string_array(data.get("tags", null), "EmployeeDef.tags", true)
	if not tags_read.ok:
		return tags_read
	emp.tags = tags_read.value

	var usage_tags_read := _parse_string_array(data.get("usage_tags", null), "EmployeeDef.usage_tags", true)
	if not usage_tags_read.ok:
		return usage_tags_read
	emp.usage_tags = usage_tags_read.value

	# recruit_capacity（严格）：use:recruit 时必须提供且 > 0；未声明 use:recruit 时不允许提供
	var has_recruit_usage := emp.has_usage_tag("use:recruit")
	if data.has("recruit_capacity"):
		if not has_recruit_usage:
			return Result.failure("EmployeeDef.recruit_capacity 仅允许在 usage_tags 包含 use:recruit 时提供")
		var rc_read := _parse_non_negative_int(data.get("recruit_capacity", null), "EmployeeDef.recruit_capacity")
		if not rc_read.ok:
			return rc_read
		emp.recruit_capacity = int(rc_read.value)
		if emp.recruit_capacity <= 0:
			return Result.failure("EmployeeDef.recruit_capacity 必须 > 0")
	else:
		if has_recruit_usage:
			return Result.failure("EmployeeDef.recruit_capacity 缺失（usage_tags 包含 use:recruit 时必须提供）")
		emp.recruit_capacity = 0

	var mandatory_read := _parse_bool(data.get("mandatory", null), "EmployeeDef.mandatory")
	if not mandatory_read.ok:
		return mandatory_read
	emp.mandatory = bool(mandatory_read.value)

	# mandatory_action_id（可选，但 mandatory=true 时必须提供以避免硬编码映射）
	if data.has("mandatory_action_id"):
		var mai_read := _parse_string(data.get("mandatory_action_id", null), "EmployeeDef.mandatory_action_id", true)
		if not mai_read.ok:
			return mai_read
		emp.mandatory_action_id = mai_read.value
	else:
		if emp.mandatory:
			return Result.failure("EmployeeDef.mandatory_action_id 缺失（mandatory=true 时必须提供；为空字符串表示自动应用）")
		emp.mandatory_action_id = ""

	# can_be_fired（可选）：默认 true
	if data.has("can_be_fired"):
		var cbf_read := _parse_bool(data.get("can_be_fired", null), "EmployeeDef.can_be_fired")
		if not cbf_read.ok:
			return cbf_read
		emp.can_be_fired = bool(cbf_read.value)
	else:
		emp.can_be_fired = true

	if data.has("marketing_max_duration"):
		var mmd_read := _parse_non_negative_int(data.get("marketing_max_duration", null), "EmployeeDef.marketing_max_duration")
		if not mmd_read.ok:
			return mmd_read
		emp.marketing_max_duration = int(mmd_read.value)
		if emp.marketing_max_duration <= 0:
			return Result.failure("EmployeeDef.marketing_max_duration 必须 > 0")

	if data.has("produces"):
		var produces_val = data.get("produces", null)
		if not (produces_val is Dictionary):
			return Result.failure("EmployeeDef.produces 类型错误（期望 Dictionary）")
		var produces: Dictionary = produces_val
		var food_type_read := _parse_string(produces.get("food_type", null), "EmployeeDef.produces.food_type", false)
		if not food_type_read.ok:
			return food_type_read
		emp.produces_food_type = food_type_read.value

		var amount_read := _parse_int(produces.get("amount", null), "EmployeeDef.produces.amount")
		if not amount_read.ok:
			return amount_read
		emp.produces_amount = int(amount_read.value)
		if emp.produces_amount <= 0:
			return Result.failure("EmployeeDef.produces.amount 必须 > 0")

	# pool（可选）：用于 Pools 推导（路线B）
	if data.has("pool"):
		var pool_val = data.get("pool", null)
		if not (pool_val is Dictionary):
			return Result.failure("EmployeeDef.pool 类型错误（期望 Dictionary）")
		var pool: Dictionary = pool_val

		var type_read := _parse_string(pool.get("type", null), "EmployeeDef.pool.type", false)
		if not type_read.ok:
			return type_read
		var ptype: String = type_read.value
		if ptype != "fixed" and ptype != "one_x" and ptype != "none":
			return Result.failure("EmployeeDef.pool.type 不支持: %s" % ptype)
		emp.pool_type = ptype

		match ptype:
			"fixed":
				var count_read := _parse_non_negative_int(pool.get("count", null), "EmployeeDef.pool.count")
				if not count_read.ok:
					return count_read
				emp.pool_count = int(count_read.value)
				if emp.pool_count <= 0:
					return Result.failure("EmployeeDef.pool.count 必须 > 0")
			"one_x":
				if pool.has("count"):
					return Result.failure("EmployeeDef.pool.type=one_x 不应包含 count")
				emp.pool_count = 0
			"none":
				if pool.has("count"):
					return Result.failure("EmployeeDef.pool.type=none 不应包含 count")
				emp.pool_count = 0
	else:
		emp.pool_type = "none"
		emp.pool_count = 0

	# effect_ids（可选）：用于 EffectRegistry（M5）
	if data.has("effect_ids"):
		var effect_ids_read := _parse_string_array(data.get("effect_ids", null), "EmployeeDef.effect_ids", true)
		if not effect_ids_read.ok:
			return effect_ids_read
		emp.effect_ids = effect_ids_read.value
		for i in range(emp.effect_ids.size()):
			var eid: String = emp.effect_ids[i]
			var colon_idx := eid.find(":")
			if colon_idx <= 0 or colon_idx >= eid.length() - 1:
				return Result.failure("EmployeeDef.effect_ids[%d] 必须为 module_id:...，实际: %s" % [i, eid])
	else:
		emp.effect_ids = []

	return Result.success(emp)

static func from_json(json_string: String) -> Result:
	var parsed = JSON.parse_string(json_string)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("EmployeeDef JSON 解析失败（期望 Dictionary）")
	return from_dict(parsed)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开员工定义文件: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

# === 严格解析辅助 ===

static func _parse_string(value, path: String, allow_empty: bool) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = value
	if not allow_empty and s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_bool(value, path: String) -> Result:
	if not (value is bool):
		return Result.failure("%s 类型错误（期望 bool）" % path)
	return Result.success(bool(value))

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r

static func _parse_string_array(value, path: String, allow_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		var s_read := _parse_string(item, "%s[%d]" % [path, i], false)
		if not s_read.ok:
			return s_read
		out.append(s_read.value)
	if not allow_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

# === 序列化 ===

func to_dict() -> Dictionary:
	var result := {
		"id": id,
		"name": name,
		"description": description,
		"salary": salary,
		"unique": unique,
		"role": role,
		"manager_slots": manager_slots,
		"range": {
			"type": range_type if not range_type.is_empty() else null,
			"value": range_value,
		},
		"train_to": train_to,
		"train_capacity": train_capacity,
		"tags": tags,
		"usage_tags": usage_tags,
		"mandatory": mandatory,
		"can_be_fired": can_be_fired,
		"effect_ids": effect_ids,
	}
	if recruit_capacity > 0:
		result["recruit_capacity"] = recruit_capacity
	if mandatory:
		result["mandatory_action_id"] = mandatory_action_id

	if pool_type != "none":
		var pool: Dictionary = {"type": pool_type}
		if pool_type == "fixed":
			pool["count"] = pool_count
		result["pool"] = pool

	if marketing_max_duration > 0:
		result["marketing_max_duration"] = marketing_max_duration

	# 仅在有生产能力时添加 produces 字段
	if not produces_food_type.is_empty() and produces_amount > 0:
		result["produces"] = {
			"food_type": produces_food_type,
			"amount": produces_amount
		}

	return result

# === 查询方法 ===

# 是否有指定标签
func has_tag(tag: String) -> bool:
	return tags.has(tag)

# 是否有指定使用标签
func has_usage_tag(usage_tag: String) -> bool:
	return usage_tags.has(usage_tag)

# 是否为入门级员工（可直接招聘）
func is_entry_level() -> bool:
	# 入门级员工应由数据显式标记（避免硬编码列表/推断逻辑）
	return has_tag("entry_level")

# 是否可管理其他员工
func is_manager() -> bool:
	return manager_slots > 0

# 是否为培训师
func is_trainer() -> bool:
	return train_capacity > 0 or has_tag("train")

# 是否可生产食物
func can_produce() -> bool:
	return not produces_food_type.is_empty() and produces_amount > 0

# 是否可采购饮料
func can_procure() -> bool:
	return has_tag("procure")

# 获取“职责角色”（用于 UI 与“同色培训”规则）
func get_role() -> String:
	return role

# 获取“职责颜色”（用于 UI 与“同色培训”规则）
func get_role_color() -> String:
	var r := get_role()
	match r:
		"manager":
			return ROLE_COLOR_MANAGER
		"recruit_train":
			return ROLE_COLOR_RECRUIT_TRAIN
		"produce_food":
			return ROLE_COLOR_PRODUCE_FOOD
		"procure_drink":
			return ROLE_COLOR_PROCURE_DRINK
		"price":
			return ROLE_COLOR_PRICE
		"marketing":
			return ROLE_COLOR_MARKETING
		"new_shop":
			return ROLE_COLOR_NEW_SHOP
		"special":
			return ROLE_COLOR_SPECIAL
		_:
			return ROLE_COLOR_SPECIAL

# 获取生产信息（返回 null 如果不能生产）
func get_production_info() -> Dictionary:
	if not can_produce():
		return {}
	return {
		"food_type": produces_food_type,
		"amount": produces_amount
	}

# === 调试 ===

func _to_string() -> String:
	return "[EmployeeDef %s: %s]" % [id, name]

func dump() -> String:
	var output := "=== EmployeeDef: %s ===\n" % id
	output += "Name: %s\n" % name
	output += "Description: %s\n" % description
	output += "Salary: %s | Unique: %s\n" % [salary, unique]
	if mandatory:
		output += "Mandatory Action: %s\n" % mandatory_action_id
	output += "Manager Slots: %d\n" % manager_slots
	output += "Range: %s (%d)\n" % [range_type, range_value]
	output += "Train To: %s\n" % str(train_to)
	output += "Train Capacity: %d\n" % train_capacity
	output += "Tags: %s\n" % str(tags)
	output += "Usage Tags: %s\n" % str(usage_tags)
	if marketing_max_duration > 0:
		output += "Marketing Max Duration: %d\n" % marketing_max_duration
	if can_produce():
		output += "Produces: %d x %s\n" % [produces_amount, produces_food_type]
	return output
