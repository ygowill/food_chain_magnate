# 游戏状态数据结构
# 存储游戏的完整状态，支持深拷贝、序列化和哈希计算
class_name GameState
extends RefCounted

# 存档/回放用 schema 版本（不兼容旧数据：版本不匹配直接拒绝加载）
const SCHEMA_VERSION := 3

const SerializationClass = preload("res://core/state/game_state_serialization.gd")
const FactoryClass = preload("res://core/state/game_state_factory.gd")

# === 回合与阶段 ===
var round_number: int = 0
var phase: String = "Setup"  # 七阶段之一
var sub_phase: String = ""   # 工作阶段的子阶段

# === 玩家顺序 ===
var turn_order: Array[int] = []
var current_player_index: int = 0
var selection_order: Array[int] = []  # 决定顺序阶段的选择顺序

# === 银行 ===
var bank: Dictionary = {
	"total": 0,
	"broke_count": 0,
	"ceo_slots_after_first_break": -1,  # 首次破产后的 CEO 卡槽数
	"reserve_added_total": 0,  # 通过“银行储备卡”注入的新增现金总额（用于现金守恒不变量）
	"removed_total": 0  # 规则导致的“现金移除”总额（用于现金守恒不变量）
}

# === 规则常量（来自 GameConfig，写入存档以保证复盘一致） ===
var rules: Dictionary = {}

# === 启用的模块（插件化，M5）===
var modules: Array[String] = []

# === 玩家状态 ===
var players: Array[Dictionary] = []
# 每个玩家的结构见 `core/state/game_state_factory.gd`

# === 地图状态 ===
# 说明：具体结构由 `core/map/map_runtime.gd` 写入与维护；GameState 仅持有容器引用。
var map: Dictionary = {}

# === 道路图缓存 (运行时，不序列化) ===
var _road_graph = null  # RoadGraph instance

# === 供应池 ===
var employee_pool: Dictionary = {}  # employee_id -> count
var milestone_pool: Array[String] = []  # 可获取的里程碑

# === 营销实例 ===
var marketing_instances: Array[Dictionary] = []

# === 回合状态 ===
var round_state: Dictionary = {
	"mandatory_actions_completed": {},  # player_id -> [action_ids]
	"actions_this_round": [],  # 本回合已执行的动作
	"action_counts": {},  # player_id -> {action_id -> count}（通常按子阶段重置）
	"sub_phase_passed": {}  # player_id -> true（每次子阶段切换时重置）
}

# === 随机种子 ===
var seed: int = 0

# === 深拷贝 ===
func duplicate_state() -> GameState:
	var copy := GameState.new()
	copy.round_number = round_number
	copy.phase = phase
	copy.sub_phase = sub_phase
	copy.turn_order = Array(turn_order, TYPE_INT, "", null)
	copy.current_player_index = current_player_index
	copy.selection_order = Array(selection_order, TYPE_INT, "", null)
	copy.bank = bank.duplicate(true)
	copy.rules = rules.duplicate(true)
	copy.modules = Array(modules, TYPE_STRING, "", null)
	copy.players = Array(_deep_copy_array(players), TYPE_DICTIONARY, "", null)
	copy.map = map.duplicate(true)
	copy.employee_pool = employee_pool.duplicate()
	copy.milestone_pool = Array(milestone_pool, TYPE_STRING, "", null)
	copy.marketing_instances = Array(_deep_copy_array(marketing_instances), TYPE_DICTIONARY, "", null)
	copy.round_state = round_state.duplicate(true)
	copy.seed = seed
	return copy

func _deep_copy_array(arr: Array) -> Array:
	var result := []
	for item in arr:
		if item is Dictionary:
			result.append(item.duplicate(true))
		elif item is Array:
			result.append(_deep_copy_array(item))
		else:
			result.append(item)
	return result

# === 序列化 ===
func to_dict() -> Dictionary:
	return SerializationClass.to_dict(self, SCHEMA_VERSION)

static func from_dict(data: Dictionary) -> Result:
	var state := GameState.new()
	var apply_result = SerializationClass.apply_from_dict(state, data, SCHEMA_VERSION)
	if not apply_result.ok:
		return apply_result
	return Result.success(state)

# === 状态哈希（用于校验点） ===
func compute_hash() -> String:
	# sort_keys=true 以保证哈希稳定（Dictionary 遍历顺序不应影响结果）
	var json := JSON.stringify(to_dict(), "", true)
	return json.md5_text()

# === 提取关键数值（用于快速验证） ===
func extract_key_values() -> Dictionary:
	var player_cash := []
	var player_employee_count := []
	for p in players:
		player_cash.append(p.get("cash", 0))
		var emp_count: int = p.get("employees", []).size()
		emp_count += p.get("reserve_employees", []).size()
		emp_count += p.get("busy_marketers", []).size()
		player_employee_count.append(emp_count)

	return {
		"round": round_number,
		"phase": phase,
		"bank_total": bank.get("total", 0),
		"player_cash": player_cash,
		"player_employees": player_employee_count,
		"house_count": map.get("houses", {}).size(),
		"marketing_count": marketing_instances.size()
	}

# === 工厂方法 ===

# 仅保留严格入口：必须显式注入 RandomManager + GameConfig（Fail Fast）
static func create_initial_state_with_rng(
	player_count: int,
	rng_seed: int,
	rng_manager,
	config
) -> Result:
	var state := GameState.new()
	return FactoryClass.apply_initial_state(state, player_count, rng_seed, rng_manager, config)

# === 便捷访问方法 ===
func get_player(player_id: int) -> Dictionary:
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	return {}

func get_current_player() -> Dictionary:
	if current_player_index >= 0 and current_player_index < turn_order.size():
		var player_id := turn_order[current_player_index]
		return get_player(player_id)
	return {}

func get_current_player_id() -> int:
	if current_player_index >= 0 and current_player_index < turn_order.size():
		return turn_order[current_player_index]
	return -1

func get_rule_int(rule_key: String) -> int:
	if not (rules is Dictionary):
		assert(false, "GameState.rules 类型错误（期望 Dictionary）")
		return 0
	if not rules.has(rule_key):
		assert(false, "GameState.rules 缺少规则: %s" % rule_key)
		return 0
	var value = rules.get(rule_key, null)
	if not (value is int):
		assert(false, "GameState.rules.%s 类型错误（期望 int），实际: %s" % [rule_key, typeof(value)])
		return 0
	return int(value)

# === 调试 ===
func _to_string() -> String:
	return "[GameState Round%d %s Players:%d Bank:$%d]" % [
		round_number, phase, players.size(), bank.get("total", 0)
	]

func dump() -> String:
	var output := "=== GameState ===\n"
	output += "Round: %d | Phase: %s | SubPhase: %s\n" % [round_number, phase, sub_phase]
	output += "Bank: $%d (Broke: %d)\n" % [bank.get("total", 0), bank.get("broke_count", 0)]
	output += "Turn Order: %s (Current: %d)\n" % [str(turn_order), current_player_index]

	for p in players:
		var emp_count: int = p.get("employees", []).size() + p.get("reserve_employees", []).size()
		output += "Player %d: $%d, Employees: %d, Restaurants: %d\n" % [
			p.get("id", -1),
			p.get("cash", 0),
			emp_count,
			p.get("restaurants", []).size()
		]

	output += "Map: %dx%d cells, %d houses, %d restaurants\n" % [
		map.grid_size.x, map.grid_size.y,
		map.get("houses", {}).size(),
		map.get("restaurants", {}).size()
	]

	return output
