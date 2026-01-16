# UI：员工职责角色 -> 颜色映射
# 说明：
# - 颜色属于表现层语义，不应放在 core 数据类型里。
# - role 本身仍由 core 提供（EmployeeDef.role），UI 在此做映射。
class_name EmployeeRoleColors
extends RefCounted

const ROLE_COLOR_MANAGER := "#000000"
const ROLE_COLOR_RECRUIT_TRAIN := "#bdb6b5"
const ROLE_COLOR_PRODUCE_FOOD := "#94a869"
const ROLE_COLOR_PROCURE_DRINK := "#adce91"
const ROLE_COLOR_PRICE := "#eba791"
const ROLE_COLOR_MARKETING := "#94c1c7"
const ROLE_COLOR_NEW_SHOP := "#aa3c34"
const ROLE_COLOR_SPECIAL := "#ae94c0"

static func role_to_color_hex(role_in: String) -> String:
	var role: String = str(role_in).strip_edges()
	match role:
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

static func role_to_color(role_in: String) -> Color:
	return Color(role_to_color_hex(role_in))

