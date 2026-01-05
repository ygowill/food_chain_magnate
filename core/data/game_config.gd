# 游戏配置（P3）
# 从 data/config/game_config.json 读取“初始状态与规则常量”的可配置数据。
class_name GameConfig
extends RefCounted

const DEFAULT_PATH := "res://data/config/game_config.json"
const SUPPORTED_SCHEMA_VERSION := 2

var schema_version: int = 1

# === bank / rules ===
var bank_default_per_player: int = 50

var rule_base_unit_price: int = 10
var rule_salary_cost: int = 5
var rule_waitress_tips: int = 3
var rule_cfo_bonus_percent: int = 50
var rule_demand_cap_normal: int = 3
var rule_demand_cap_with_garden: int = 5
var rule_fridge_capacity_per_product: int = 10
var rule_one_x_employee_copies_by_player_count: Dictionary = {}

# === player starting state ===
var player_starting_cash: int = 0
var player_starting_employees: Array[String] = ["ceo"]
var player_starting_inventory: Dictionary = {
	"burger": 0,
	"pizza": 0,
	"soda": 0,
	"lemonade": 0,
	"beer": 0,
}
var player_starting_company_structure: Dictionary = {
	"ceo_slots": 3,
	"structure": []
}
var player_reserve_cards: Array[Dictionary] = [
	{"type": 5, "cash": 50, "ceo_slots": 2},
	{"type": 10, "cash": 100, "ceo_slots": 3},
	{"type": 20, "cash": 150, "ceo_slots": 4},
]
var player_reserve_card_selected: int = 1

static func load_default() -> Result:
	return load_from_file(DEFAULT_PATH)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开 GameConfig: %s" % path)

	var json := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("无法解析 GameConfig: %s" % path)

	return from_dict(parsed)

static func from_dict(data: Dictionary) -> Result:
	var cfg := GameConfig.new()

	var schema_val = data.get("schema_version", null)
	var schema_read := _parse_int(schema_val, "schema_version")
	if not schema_read.ok:
		return schema_read
	cfg.schema_version = int(schema_read.value)
	if cfg.schema_version != SUPPORTED_SCHEMA_VERSION:
		return Result.failure("不支持的 GameConfig.schema_version: %d (期望: %d)" % [cfg.schema_version, SUPPORTED_SCHEMA_VERSION])

	var bank_val = data.get("bank", null)
	if not (bank_val is Dictionary):
		return Result.failure("GameConfig.bank 缺失或类型错误（期望 Dictionary）")
	var bank: Dictionary = bank_val
	if not bank.has("default_per_player"):
		return Result.failure("GameConfig.bank 缺少 default_per_player")
	var bank_default_read := _parse_non_negative_int(bank.get("default_per_player", null), "bank.default_per_player")
	if not bank_default_read.ok:
		return bank_default_read
	cfg.bank_default_per_player = int(bank_default_read.value)

	var rules_val = data.get("rules", null)
	if not (rules_val is Dictionary):
		return Result.failure("GameConfig.rules 缺失或类型错误（期望 Dictionary）")
	var rules: Dictionary = rules_val

	var base_unit_price_read := _parse_non_negative_int(rules.get("base_unit_price", null), "rules.base_unit_price")
	if not base_unit_price_read.ok:
		return base_unit_price_read
	cfg.rule_base_unit_price = int(base_unit_price_read.value)

	var salary_cost_read := _parse_non_negative_int(rules.get("salary_cost", null), "rules.salary_cost")
	if not salary_cost_read.ok:
		return salary_cost_read
	cfg.rule_salary_cost = int(salary_cost_read.value)

	var waitress_tips_read := _parse_non_negative_int(rules.get("waitress_tips", null), "rules.waitress_tips")
	if not waitress_tips_read.ok:
		return waitress_tips_read
	cfg.rule_waitress_tips = int(waitress_tips_read.value)

	var cfo_bonus_percent_read := _parse_non_negative_int(rules.get("cfo_bonus_percent", null), "rules.cfo_bonus_percent")
	if not cfo_bonus_percent_read.ok:
		return cfo_bonus_percent_read
	cfg.rule_cfo_bonus_percent = int(cfo_bonus_percent_read.value)

	var demand_cap_normal_read := _parse_non_negative_int(rules.get("demand_cap_normal", null), "rules.demand_cap_normal")
	if not demand_cap_normal_read.ok:
		return demand_cap_normal_read
	cfg.rule_demand_cap_normal = int(demand_cap_normal_read.value)

	var demand_cap_with_garden_read := _parse_non_negative_int(rules.get("demand_cap_with_garden", null), "rules.demand_cap_with_garden")
	if not demand_cap_with_garden_read.ok:
		return demand_cap_with_garden_read
	cfg.rule_demand_cap_with_garden = int(demand_cap_with_garden_read.value)

	var fridge_capacity_read := _parse_non_negative_int(rules.get("fridge_capacity_per_product", null), "rules.fridge_capacity_per_product")
	if not fridge_capacity_read.ok:
		return fridge_capacity_read
	cfg.rule_fridge_capacity_per_product = int(fridge_capacity_read.value)

	var one_x_copies_val = rules.get("one_x_employee_copies_by_player_count", null)
	if not (one_x_copies_val is Dictionary):
		return Result.failure("GameConfig.rules.one_x_employee_copies_by_player_count 缺失或类型错误（期望 Dictionary）")
	var one_x_copies: Dictionary = one_x_copies_val
	cfg.rule_one_x_employee_copies_by_player_count = {}
	for player_count_key in ["2", "3", "4", "5"]:
		if not one_x_copies.has(player_count_key):
			return Result.failure("GameConfig.rules.one_x_employee_copies_by_player_count 缺少 key: %s" % player_count_key)
		var c_read := _parse_non_negative_int(one_x_copies.get(player_count_key, null), "rules.one_x_employee_copies_by_player_count.%s" % player_count_key)
		if not c_read.ok:
			return c_read
		cfg.rule_one_x_employee_copies_by_player_count[player_count_key] = int(c_read.value)

	var player_val = data.get("player", null)
	if not (player_val is Dictionary):
		return Result.failure("GameConfig.player 缺失或类型错误（期望 Dictionary）")
	var player: Dictionary = player_val

	var starting_cash_read := _parse_non_negative_int(player.get("starting_cash", null), "player.starting_cash")
	if not starting_cash_read.ok:
		return starting_cash_read
	cfg.player_starting_cash = int(starting_cash_read.value)

	var starting_employees_read := _parse_string_array(player.get("starting_employees", null), "player.starting_employees")
	if not starting_employees_read.ok:
		return starting_employees_read
	cfg.player_starting_employees = starting_employees_read.value

	var starting_inventory_read := _parse_int_dict(player.get("starting_inventory", null), "player.starting_inventory")
	if not starting_inventory_read.ok:
		return starting_inventory_read
	cfg.player_starting_inventory = starting_inventory_read.value

	var cs_val = player.get("starting_company_structure", null)
	if not (cs_val is Dictionary):
		return Result.failure("GameConfig.player.starting_company_structure 缺失或类型错误（期望 Dictionary）")
	cfg.player_starting_company_structure = cs_val.duplicate(true)

	var reserve_cards_read := _parse_reserve_cards(player.get("reserve_cards", null), "player.reserve_cards")
	if not reserve_cards_read.ok:
		return reserve_cards_read
	cfg.player_reserve_cards = reserve_cards_read.value

	var reserve_card_selected_read := _parse_non_negative_int(player.get("reserve_card_selected", null), "player.reserve_card_selected")
	if not reserve_card_selected_read.ok:
		return reserve_card_selected_read
	cfg.player_reserve_card_selected = int(reserve_card_selected_read.value)
	if cfg.player_reserve_card_selected < 0 or cfg.player_reserve_card_selected >= cfg.player_reserve_cards.size():
		return Result.failure("GameConfig.player.reserve_card_selected 越界: %d (cards=%d)" % [cfg.player_reserve_card_selected, cfg.player_reserve_cards.size()])

	if cfg.player_starting_employees.is_empty():
		return Result.failure("GameConfig.player.starting_employees 不能为空")

	return Result.success(cfg)

func build_reserve_cards() -> Array[Dictionary]:
	return player_reserve_cards.duplicate(true)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 缺失或类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	var n: int = int(r.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return Result.success(n)

static func _parse_string_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 缺失或类型错误（期望 Array）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is String):
			return Result.failure("%s[%d] 类型错误（期望 String），实际: %s" % [path, i, str(typeof(item))])
		var s := str(item)
		if s.is_empty():
			return Result.failure("%s[%d] 不能为空字符串" % [path, i])
		out.append(s)
	return Result.success(out)

static func _parse_int_dict(value, path: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s 缺失或类型错误（期望 Dictionary）" % path)
	var out := {}
	for k in value.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String），实际: %s" % [path, str(typeof(k))])
		var key := str(k)
		var v_read := _parse_non_negative_int(value.get(k, null), "%s.%s" % [path, key])
		if not v_read.ok:
			return v_read
		out[key] = int(v_read.value)
	return Result.success(out)

static func _parse_non_negative_int_dict(value: Dictionary, path: String) -> Result:
	var out := {}
	for k in value.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String），实际: %s" % [path, str(typeof(k))])
		var key := str(k)
		var v_read := _parse_non_negative_int(value.get(k, null), "%s.%s" % [path, key])
		if not v_read.ok:
			return v_read
		out[key] = int(v_read.value)
	return Result.success(out)

static func _parse_reserve_cards(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 缺失或类型错误（期望 Array）" % path)
	var out: Array[Dictionary] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		var card: Dictionary = item
		for required_key in ["type", "cash", "ceo_slots"]:
			if not card.has(required_key):
				return Result.failure("%s[%d] 缺少字段: %s" % [path, i, required_key])
		var t_read := _parse_non_negative_int(card.get("type", null), "%s[%d].type" % [path, i])
		if not t_read.ok:
			return t_read
		var cash_read := _parse_non_negative_int(card.get("cash", null), "%s[%d].cash" % [path, i])
		if not cash_read.ok:
			return cash_read
		var slots_read := _parse_non_negative_int(card.get("ceo_slots", null), "%s[%d].ceo_slots" % [path, i])
		if not slots_read.ok:
			return slots_read
		out.append({
			"type": int(t_read.value),
			"cash": int(cash_read.value),
			"ceo_slots": int(slots_read.value),
		})
	return Result.success(out)
