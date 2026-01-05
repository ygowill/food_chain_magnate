# PhaseManager：阶段/子阶段定义 + 查询工具
# 负责：Phase/WorkingSubPhase 的枚举、名称映射、顺序，以及时间戳计算等纯函数。
extends RefCounted

# 七大阶段
enum Phase {
	SETUP,
	RESTRUCTURING,
	ORDER_OF_BUSINESS,
	WORKING,
	DINNERTIME,
	PAYDAY,
	MARKETING,
	CLEANUP,
	GAME_OVER
}

# 阶段名称映射
const PHASE_NAMES := {
	Phase.SETUP: "Setup",
	Phase.RESTRUCTURING: "Restructuring",
	Phase.ORDER_OF_BUSINESS: "OrderOfBusiness",
	Phase.WORKING: "Working",
	Phase.DINNERTIME: "Dinnertime",
	Phase.PAYDAY: "Payday",
	Phase.MARKETING: "Marketing",
	Phase.CLEANUP: "Cleanup",
	Phase.GAME_OVER: "GameOver"
}

# 阶段顺序（不包含 Setup / GameOver）
const PHASE_ORDER := [
	Phase.RESTRUCTURING,
	Phase.ORDER_OF_BUSINESS,
	Phase.WORKING,
	Phase.DINNERTIME,
	Phase.PAYDAY,
	Phase.MARKETING,
	Phase.CLEANUP
]

# 工作阶段子阶段
enum WorkingSubPhase {
	RECRUIT,
	TRAIN,
	MARKETING,
	GET_FOOD,
	GET_DRINKS,
	PLACE_HOUSES,
	PLACE_RESTAURANTS
}

# 子阶段名称映射
const SUB_PHASE_NAMES := {
	WorkingSubPhase.RECRUIT: "Recruit",
	WorkingSubPhase.TRAIN: "Train",
	WorkingSubPhase.MARKETING: "Marketing",
	WorkingSubPhase.GET_FOOD: "GetFood",
	WorkingSubPhase.GET_DRINKS: "GetDrinks",
	WorkingSubPhase.PLACE_HOUSES: "PlaceHouses",
	WorkingSubPhase.PLACE_RESTAURANTS: "PlaceRestaurants"
}

# 子阶段顺序
const SUB_PHASE_ORDER := [
	WorkingSubPhase.RECRUIT,
	WorkingSubPhase.TRAIN,
	WorkingSubPhase.MARKETING,
	WorkingSubPhase.GET_FOOD,
	WorkingSubPhase.GET_DRINKS,
	WorkingSubPhase.PLACE_HOUSES,
	WorkingSubPhase.PLACE_RESTAURANTS
]

# === 查询方法 ===

# 获取阶段序号（用于游戏内时间戳/确定性日志）
# 约定：
# - Setup = 0
# - 其余按 PHASE_ORDER 顺序从 1 开始
static func get_phase_index(phase_name: String) -> int:
	var phase_enum := get_phase_enum(phase_name)
	if phase_enum == -1:
		return -1
	if phase_enum == Phase.SETUP:
		return 0
	if phase_enum == Phase.GAME_OVER:
		return PHASE_ORDER.size() + 1
	var idx := PHASE_ORDER.find(phase_enum)
	if idx == -1:
		return -1
	return idx + 1

# 从字符串获取阶段枚举
static func get_phase_enum(phase_name: String) -> int:
	for phase in PHASE_NAMES:
		if PHASE_NAMES[phase] == phase_name:
			return phase
	return -1

# 从字符串获取子阶段枚举
static func get_sub_phase_enum(sub_phase_name: String) -> int:
	for sub_phase in SUB_PHASE_NAMES:
		if SUB_PHASE_NAMES[sub_phase] == sub_phase_name:
			return sub_phase
	return -1

# 获取阶段名称
static func get_phase_name(phase: int) -> String:
	return PHASE_NAMES.get(phase, "Unknown")

# 获取子阶段名称
static func get_sub_phase_name(sub_phase: int) -> String:
	return SUB_PHASE_NAMES.get(sub_phase, "Unknown")

# 检查是否在工作阶段
static func is_working_phase(state: GameState) -> bool:
	return state.phase == "Working"

# 获取当前子阶段索引
static func get_sub_phase_index(state: GameState) -> int:
	# 允许模块通过 round_state.working_sub_phase_order 注入自定义子阶段顺序（字符串数组）。
	# 约定：state.sub_phase 存储子阶段名称（如 "Recruit" / "Lobbyists"）。
	if state != null and (state.round_state is Dictionary):
		var rs: Dictionary = state.round_state
		if rs.has("working_sub_phase_order"):
			var order_val = rs.get("working_sub_phase_order", null)
			if order_val is Array:
				var order: Array = order_val
				return order.find(state.sub_phase)

	var sub_phase := get_sub_phase_enum(state.sub_phase)
	return SUB_PHASE_ORDER.find(sub_phase)

# 计算确定性的“游戏内时间戳”
# 对齐 docs/design.md（round * 1000 + phase_index * 100 + sub_phase_index）
static func compute_timestamp(state: GameState) -> int:
	var phase_index := get_phase_index(state.phase)
	if state != null and (state.round_state is Dictionary):
		var rs: Dictionary = state.round_state
		if rs.has("phase_order"):
			var order_val = rs.get("phase_order", null)
			if order_val is Array:
				var order: Array = order_val
				if state.phase == "Setup":
					phase_index = 0
				elif state.phase == "GameOver":
					phase_index = order.size() + 1
				else:
					var idx := order.find(state.phase)
					if idx != -1:
						phase_index = idx + 1
	var sub_phase_index := 0
	if not state.sub_phase.is_empty():
		sub_phase_index = max(0, get_any_sub_phase_index(state))
	return state.round_number * 1000 + phase_index * 100 + sub_phase_index

static func get_any_sub_phase_index(state: GameState) -> int:
	if state.phase == "Working":
		return get_sub_phase_index(state)
	if state != null and (state.round_state is Dictionary):
		var rs: Dictionary = state.round_state
		if rs.has("phase_sub_phase_orders"):
			var v = rs.get("phase_sub_phase_orders", null)
			if v is Dictionary:
				var all: Dictionary = v
				if all.has(state.phase):
					var order_val = all.get(state.phase, null)
					if order_val is Array:
						return (order_val as Array).find(state.sub_phase)
	return 0

# 获取阶段进度（用于显示）
static func get_phase_progress(state: GameState) -> Dictionary:
	var phase := get_phase_enum(state.phase)
	var phase_index := PHASE_ORDER.find(phase)
	var total_phases := PHASE_ORDER.size()
	if state != null and (state.round_state is Dictionary):
		var rs: Dictionary = state.round_state
		if rs.has("phase_order"):
			var order_val = rs.get("phase_order", null)
			if order_val is Array:
				var order: Array = order_val
				total_phases = order.size()
				phase_index = order.find(state.phase)

	var result := {
		"phase": state.phase,
		"phase_index": phase_index,
		"total_phases": total_phases,
		"sub_phase": state.sub_phase,
		"sub_phase_index": -1,
		"total_sub_phases": SUB_PHASE_ORDER.size()
	}

	if is_working_phase(state):
		result.sub_phase_index = get_sub_phase_index(state)
		if state != null and (state.round_state is Dictionary):
			var rs: Dictionary = state.round_state
			if rs.has("working_sub_phase_order"):
				var order_val = rs.get("working_sub_phase_order", null)
				if order_val is Array:
					result.total_sub_phases = (order_val as Array).size()
	elif not state.sub_phase.is_empty():
		result.sub_phase_index = get_any_sub_phase_index(state)
		if state != null and (state.round_state is Dictionary):
			var rs: Dictionary = state.round_state
			if rs.has("phase_sub_phase_orders"):
				var v = rs.get("phase_sub_phase_orders", null)
				if v is Dictionary:
					var all: Dictionary = v
					if all.has(state.phase):
						var order_val2 = all.get(state.phase, null)
						if order_val2 is Array:
							result.total_sub_phases = (order_val2 as Array).size()

	return result
