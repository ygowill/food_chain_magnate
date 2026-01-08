# 员工定义
# 解析模块 content/employees/*.json 中的员工数据
class_name EmployeeDef
extends RefCounted

const Parser = preload("res://core/data/employee_def/parser.gd")
const Serialization = preload("res://core/data/employee_def/serialization.gd")
const Debug = preload("res://core/data/employee_def/debug.gd")

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
	return Parser.apply_from_dict(emp, data)

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

# === 序列化 ===

func to_dict() -> Dictionary:
	return Serialization.to_dict(self)

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
	return Debug.dump(self)
