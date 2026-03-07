# 价格强制动作状态访问回归测试
class_name PriceModifierStateAccessTest
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SetPriceActionClass = preload("res://gameplay/actions/set_price_action.gd")
const SetDiscountActionClass = preload("res://gameplay/actions/set_discount_action.gd")
const SetLuxuryPriceActionClass = preload("res://gameplay/actions/set_luxury_price_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_set_price_rejects_string_player_key_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_set_discount_rejects_string_player_key_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_set_luxury_price_rejects_string_player_key_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _test_set_price_rejects_string_player_key_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var setup_read := _build_working_state_with_provider(player_count, seed_val, "pricing_manager")
	if not setup_read.ok:
		return setup_read
	var payload: Dictionary = setup_read.value
	var state: GameState = payload["state"]
	var player_id := int(payload["player_id"])
	var provider_id := str(payload["provider_id"])
	var action = SetPriceActionClass.new()
	var result := action._apply_changes(state, Command.create(ActionIdsClass.SET_PRICE, player_id, {}))
	return _assert_failed_price_modifier_write(state, player_id, provider_id, ActionIdsClass.SET_PRICE, result)

static func _test_set_discount_rejects_string_player_key_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var setup_read := _build_working_state_with_provider(player_count, seed_val, "discount_manager")
	if not setup_read.ok:
		return setup_read
	var payload: Dictionary = setup_read.value
	var state: GameState = payload["state"]
	var player_id := int(payload["player_id"])
	var provider_id := str(payload["provider_id"])
	var action = SetDiscountActionClass.new()
	var result := action._apply_changes(state, Command.create(ActionIdsClass.SET_DISCOUNT, player_id, {}))
	return _assert_failed_price_modifier_write(state, player_id, provider_id, ActionIdsClass.SET_DISCOUNT, result)

static func _test_set_luxury_price_rejects_string_player_key_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var setup_read := _build_working_state_with_provider(player_count, seed_val, "luxury_manager")
	if not setup_read.ok:
		return setup_read
	var payload: Dictionary = setup_read.value
	var state: GameState = payload["state"]
	var player_id := int(payload["player_id"])
	var provider_id := str(payload["provider_id"])
	var action = SetLuxuryPriceActionClass.new()
	var result := action._apply_changes(state, Command.create(ActionIdsClass.SET_LUXURY_PRICE, player_id, {}))
	return _assert_failed_price_modifier_write(state, player_id, provider_id, ActionIdsClass.SET_LUXURY_PRICE, result)

static func _assert_failed_price_modifier_write(state: GameState, player_id: int, provider_id: String, action_id: String, result: Result) -> Result:
	if result.ok:
		return Result.failure("%s 在 price_modifiers 使用字符串玩家 key 时应失败" % action_id)
	var err := str(result.error)
	if err.find("price_modifiers") < 0 or err.find("字符串玩家 key") < 0:
		return Result.failure("%s 错误信息应包含 price_modifiers 与 字符串玩家 key，实际: %s" % [action_id, err])
	var mac_val = state.round_state.get("mandatory_actions_completed", null)
	if not (mac_val is Dictionary):
		return Result.failure("%s: mandatory_actions_completed 应保持为 Dictionary" % action_id)
	var mac: Dictionary = mac_val
	var completed_val = mac.get(player_id, null)
	if not (completed_val is Array):
		return Result.failure("%s: mandatory_actions_completed[%d] 应保持为 Array" % [action_id, player_id])
	if Array(completed_val).has(action_id):
		return Result.failure("%s: 失败时不应提前标记 mandatory_actions_completed" % action_id)
	var pm_val = state.round_state.get("price_modifiers", null)
	if not (pm_val is Dictionary):
		return Result.failure("%s: price_modifiers 应保持为 Dictionary" % action_id)
	var price_modifiers: Dictionary = pm_val
	if price_modifiers.has(player_id):
		return Result.failure("%s: 失败时不应补写 int 玩家 key 的 price_modifiers" % action_id)
	if not price_modifiers.has(str(player_id)):
		return Result.failure("%s: 失败时应保留原始字符串玩家 key 供排错" % action_id)
	var legacy_val = price_modifiers.get(str(player_id), null)
	if not (legacy_val is Dictionary):
		return Result.failure("%s: 原始字符串玩家 key 值应保持为 Dictionary" % action_id)
	if Dictionary(legacy_val).has(provider_id):
		return Result.failure("%s: 失败时不应提前写入 provider modifier" % action_id)
	return Result.success()

static func _build_working_state_with_provider(player_count: int, seed_val: int, provider_id: String) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	var player_id := state.get_current_player_id()
	if player_id < 0:
		return Result.failure("无法获取当前玩家")
	var pool_before := int(state.employee_pool.get(provider_id, 0))
	if pool_before <= 0:
		return Result.failure("员工池中 %s 数量不足" % provider_id)

	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT
	state.employee_pool[provider_id] = pool_before - 1
	state.players[player_id]["employees"].append(provider_id)
	state.round_state["mandatory_actions_completed"] = {
		player_id: [],
	}
	state.round_state["price_modifiers"] = {
		str(player_id): {"legacy": 0},
	}
	return Result.success({
		"state": state,
		"player_id": player_id,
		"provider_id": provider_id,
	})
