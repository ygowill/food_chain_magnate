# confirm_dinnertime 状态访问回归测试
class_name ConfirmDinnertimeStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/confirm_dinnertime_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

static func run(player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_confirmed_players_without_partial_mutation(player_count)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_pending_player_id_without_partial_mutation(player_count)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_apply_changes_fails_fast_on_invalid_confirmed_players_without_partial_mutation(player_count: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.phase = DefsClass.PHASE_DINNERTIME
	state.sub_phase = ""

	var pending: Array = []
	for pid in range(player_count):
		pending.append({
			"kind": "confirm_dinnertime",
			"player_id": pid,
		})
	var confirmed: Array = []
	confirmed.append(false)
	confirmed.append({})
	for _i in range(2, player_count):
		confirmed.append(false)

	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_DINNERTIME: pending,
	}
	state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed
	var pending_before := str(state.round_state.get("pending_phase_actions", null))
	var confirmed_before := str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null))

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("confirm_dinnertime", 0, {}))
	if result.ok:
		return Result.failure("online_dinnertime_confirmed_players 非法时应失败")
	var err := str(result.error)
	if err.find(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, err])
	if str(state.round_state.get("pending_phase_actions", null)) != pending_before:
		return Result.failure("失败时不应提前改写 pending_phase_actions")
	if str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)) != confirmed_before:
		return Result.failure("失败时不应提前改写 online_dinnertime_confirmed_players")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_pending_player_id_without_partial_mutation(player_count: int) -> Result:
	if player_count < 2:
		player_count = 2
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	state.phase = DefsClass.PHASE_DINNERTIME
	state.sub_phase = ""

	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_DINNERTIME: [
			{
				"kind": "confirm_dinnertime",
				"player_id": "0",
			},
			{
				"kind": "confirm_dinnertime",
				"player_id": 1,
			},
		],
	}
	var confirmed: Array = []
	for _i in range(player_count):
		confirmed.append(false)
	state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed
	var pending_before := str(state.round_state.get("pending_phase_actions", null))
	var confirmed_before := str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null))

	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("confirm_dinnertime", 0, {}))
	if result.ok:
		return Result.failure("pending_phase_actions[Dinnertime].player_id 非法时应失败")
	var err := str(result.error)
	if err.find("pending_phase_actions[Dinnertime][0].player_id") < 0:
		return Result.failure("错误信息应包含非法 pending player_id 路径，实际: %s" % err)
	if str(state.round_state.get("pending_phase_actions", null)) != pending_before:
		return Result.failure("失败时不应提前改写 pending_phase_actions")
	if str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)) != confirmed_before:
		return Result.failure("失败时不应提前改写 online_dinnertime_confirmed_players")
	return Result.success()
