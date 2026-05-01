# rural_marketeers 状态访问回归测试
class_name RuralMarketeersStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/rural_marketeers/rules/entry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_init_state_initializes_rural_area_supply_and_offramps()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_missing_rural_area()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_invalid_rural_area_type()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_invalid_offramp_supply_type()
	if not r.ok:
		return r
	r = _test_restructuring_fails_fast_on_negative_offramp_supply()
	if not r.ok:
		return r
	r = _test_placement_conflicts_detects_offramp_connection()
	if not r.ok:
		return r
	r = _test_placement_conflicts_fails_fast_on_missing_offramps()
	if not r.ok:
		return r
	r = _test_placement_conflicts_fail_fast_on_invalid_offramps_type()
	if not r.ok:
		return r
	r = _test_airplane_conflict_validation_detects_existing_offramp_overlap(seed_val)
	if not r.ok:
		return r
	r = _test_airplane_conflict_validation_fails_fast_on_missing_grid_size(seed_val)
	if not r.ok:
		return r
	r = _test_airplane_conflict_validation_fails_fast_on_missing_tile_grid_size(seed_val)
	if not r.ok:
		return r
	r = _test_airplane_conflict_validation_fails_fast_on_invalid_offramps_type(seed_val)
	if not r.ok:
		return r
	r = _test_airplane_conflict_validation_ignores_removed_board_before_grid_checks(seed_val)
	if not r.ok:
		return r
	r = _test_marketing_before_exit_blocks_when_pending_player_exists()
	if not r.ok:
		return r
	r = _test_marketing_before_exit_fails_fast_on_invalid_pending_flag_type()
	if not r.ok:
		return r
	r = _test_milestone_effect_marks_pending_flag_and_consumes_supply()
	if not r.ok:
		return r
	r = _test_milestone_effect_fails_fast_on_invalid_supply_type()
	if not r.ok:
		return r
	r = _test_milestone_effect_fails_fast_on_invalid_pending_flag_type()
	if not r.ok:
		return r
	return Result.success({"cases": 19})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"houses": {
			"house_1": {"house_id": "house_1", "has_garden": false},
		}
	}
	return state

static func _make_airplane_validation_state(seed_val: int) -> Result:
	MarketingRegistryClass.reset()
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化 engine 失败: %s" % init.error)
	var state := engine.get_state()
	state.map["rural_marketeers_offramps"] = []
	return Result.success(state)

static func _make_airplane_command() -> Command:
	return Command.create("initiate_marketing", 0, {
		"board_number": 6,
		"position": [0, 0],
		"axis": "col",
	})

static func _test_init_state_initializes_rural_area_supply_and_offramps() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var result := entry._init_state(state, null)
	if not result.ok:
		return Result.failure("_init_state 失败: %s" % result.error)
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("执行后 state.map.houses 应存在")
	var houses: Dictionary = state.map["houses"]
	if not houses.has("rural_area") or not (houses["rural_area"] is Dictionary):
		return Result.failure("应初始化 houses[rural_area]")
	var rural: Dictionary = houses["rural_area"]
	if str(rural.get("house_number", "")) != "zzzz_rural_area":
		return Result.failure("rural_area.house_number 应为 zzzz_rural_area，实际: %s" % str(rural))
	if int(state.map.get("rural_marketeers_offramp_supply_remaining", -1)) != 3:
		return Result.failure("offramp supply 应初始化为 3，实际: %s" % str(state.map.get("rural_marketeers_offramp_supply_remaining", null)))
	if not (state.map.get("rural_marketeers_offramps", null) is Array):
		return Result.failure("rural_marketeers_offramps 应初始化为 Array")
	return Result.success()

static func _test_restructuring_fails_fast_on_missing_rural_area() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map["rural_marketeers_offramp_supply_remaining"] = 3
	state.map["rural_marketeers_offramps"] = []
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("缺失 rural_area 时 restructuring hook 应失败")
	var err := str(result.error)
	if err.find("rural_area") < 0:
		return Result.failure("错误信息应包含 rural_area，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_missing_houses() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_invalid_rural_area_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var init_result := entry._init_state(state, null)
	if not init_result.ok:
		return init_result
	state.map["houses"]["rural_area"] = []
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("rural_area 类型错误时应失败")
	var err := str(result.error)
	if err.find("rural_area") < 0:
		return Result.failure("错误信息应包含 rural_area，实际: %s" % err)
	return Result.success()


static func _test_restructuring_fails_fast_on_invalid_offramp_supply_type() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var init_result := entry._init_state(state, null)
	if not init_result.ok:
		return init_result
	state.map["rural_marketeers_offramp_supply_remaining"] = "bad"
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("offramp supply 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramp_supply_remaining") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramp_supply_remaining，实际: %s" % err)
	return Result.success()

static func _test_restructuring_fails_fast_on_negative_offramp_supply() -> Result:
	var entry = EntryClass.new()
	var state := _make_state()
	var init_result := entry._init_state(state, null)
	if not init_result.ok:
		return init_result
	state.map["rural_marketeers_offramp_supply_remaining"] = -1
	var result := entry._on_restructuring_before_enter(state)
	if result.ok:
		return Result.failure("负数 offramp supply 时应失败")
	var err := str(result.error)
	if err.find("不能为负数") < 0:
		return Result.failure("错误信息应提示不能为负数，实际: %s" % err)
	return Result.success()

static func _test_placement_conflicts_detects_offramp_connection() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.map = {
		"rural_marketeers_offramps": [
			{"pos": Vector2i(1, 0), "side": "N"},
		]
	}
	var result := entry._get_placement_conflicts_at_world_pos(state, Vector2i(1, 0), {})
	if not result.ok:
		return Result.failure("合法 offramps 时不应失败: %s" % result.error)
	var conflicts: Array = result.value
	if conflicts.size() != 1 or str(conflicts[0]).find("offramp_connection") < 0:
		return Result.failure("应返回 offramp connection conflict，实际: %s" % str(conflicts))
	return Result.success()

static func _test_placement_conflicts_fails_fast_on_missing_offramps() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.map = {}
	var result := entry._get_placement_conflicts_at_world_pos(state, Vector2i(1, 0), {})
	if result.ok:
		return Result.failure("缺失 offramps 时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramps，实际: %s" % err)
	return Result.success()

static func _test_placement_conflicts_fail_fast_on_invalid_offramps_type() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.map = {
		"rural_marketeers_offramps": {},
	}
	var result := entry._get_placement_conflicts_at_world_pos(state, Vector2i(1, 0), {})
	if result.ok:
		return Result.failure("offramps 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramps，实际: %s" % err)
	return Result.success()

static func _test_airplane_conflict_validation_detects_existing_offramp_overlap(seed_val: int) -> Result:
	var state_read := _make_airplane_validation_state(seed_val)
	if not state_read.ok:
		return state_read
	var entry = EntryClass.new()
	var state: GameState = state_read.value
	state.map["rural_marketeers_offramps"] = [
		{"pos": Vector2i(2, 0), "side": "N"},
	]
	var result := entry._validate_airplane_offramp_conflict(state, _make_airplane_command())
	if result.ok:
		return Result.failure("飞机与 offramp 重叠时应失败")
	var err := str(result.error)
	if err.find("飞机不能与已有高速公路出口重叠") < 0:
		return Result.failure("错误信息应提示 overlap，实际: %s" % err)
	return Result.success()

static func _test_airplane_conflict_validation_fails_fast_on_missing_grid_size(seed_val: int) -> Result:
	var state_read := _make_airplane_validation_state(seed_val)
	if not state_read.ok:
		return state_read
	var entry = EntryClass.new()
	var state: GameState = state_read.value
	state.map.erase("grid_size")
	var result := entry._validate_airplane_offramp_conflict(state, _make_airplane_command())
	if result.ok:
		return Result.failure("缺失 grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.grid_size，实际: %s" % err)
	return Result.success()

static func _test_airplane_conflict_validation_fails_fast_on_missing_tile_grid_size(seed_val: int) -> Result:
	var state_read := _make_airplane_validation_state(seed_val)
	if not state_read.ok:
		return state_read
	var entry = EntryClass.new()
	var state: GameState = state_read.value
	state.map.erase("tile_grid_size")
	var result := entry._validate_airplane_offramp_conflict(state, _make_airplane_command())
	if result.ok:
		return Result.failure("缺失 tile_grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.tile_grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.tile_grid_size，实际: %s" % err)
	return Result.success()

static func _test_airplane_conflict_validation_fails_fast_on_invalid_offramps_type(seed_val: int) -> Result:
	var state_read := _make_airplane_validation_state(seed_val)
	if not state_read.ok:
		return state_read
	var entry = EntryClass.new()
	var state: GameState = state_read.value
	state.map["rural_marketeers_offramps"] = {}
	var result := entry._validate_airplane_offramp_conflict(state, _make_airplane_command())
	if result.ok:
		return Result.failure("offramps 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramps") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramps，实际: %s" % err)
	return Result.success()

static func _test_airplane_conflict_validation_ignores_removed_board_before_grid_checks(seed_val: int) -> Result:
	var state_read := _make_airplane_validation_state(seed_val)
	if not state_read.ok:
		return state_read
	var entry = EntryClass.new()
	var state: GameState = state_read.value
	state.map.erase("grid_size")
	var command := Command.create("initiate_marketing", 0, {
		"board_number": 12,
		"position": [0, 0],
	})
	var result := entry._validate_airplane_offramp_conflict(state, command)
	if not result.ok:
		return Result.failure("已移除的非 airplane board 应被忽略，实际: %s" % result.error)
	return Result.success()

static func _test_marketing_before_exit_blocks_when_pending_player_exists() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [{}, {}]
	state.round_state = {
		"rural_marketeers_offramp_pending": {
			0: true,
			1: false,
		}
	}
	var result := entry._on_working_marketing_before_exit(state)
	if result.ok:
		return Result.failure("存在 pending player 时应阻止离开 Marketing")
	var err := str(result.error)
	if err.find("[0]") < 0:
		return Result.failure("错误信息应包含阻塞玩家列表，实际: %s" % err)
	return Result.success()

static func _test_marketing_before_exit_fails_fast_on_invalid_pending_flag_type() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [{}, {}]
	state.round_state = {
		"rural_marketeers_offramp_pending": {
			0: "bad",
		}
	}
	var result := entry._on_working_marketing_before_exit(state)
	if result.ok:
		return Result.failure("pending flag 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.rural_marketeers_offramp_pending[0]") < 0:
		return Result.failure("错误信息应包含 round_state.rural_marketeers_offramp_pending[0]，实际: %s" % err)
	return Result.success()

static func _test_milestone_effect_marks_pending_flag_and_consumes_supply() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [{}, {}]
	state.map = {
		"rural_marketeers_offramp_supply_remaining": 2,
	}
	state.round_state = {}
	var result := entry._milestone_effect_grant_offramp_placement(state, 1, "", {})
	if not result.ok:
		return Result.failure("里程碑发放 offramp 失败: %s" % result.error)
	if int(state.map.get("rural_marketeers_offramp_supply_remaining", -1)) != 1:
		return Result.failure("offramp supply 应减为 1，实际: %s" % str(state.map.get("rural_marketeers_offramp_supply_remaining", null)))
	var pending_val = state.round_state.get("rural_marketeers_offramp_pending", null)
	if not (pending_val is Dictionary):
		return Result.failure("应写入 round_state.rural_marketeers_offramp_pending")
	var pending: Dictionary = pending_val
	if not bool(pending.get(1, false)):
		return Result.failure("玩家 1 应被标记为 pending")
	return Result.success()


static func _test_milestone_effect_fails_fast_on_invalid_supply_type() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [{}, {}]
	state.map = {
		"rural_marketeers_offramp_supply_remaining": "bad",
	}
	state.round_state = {}
	var result := entry._milestone_effect_grant_offramp_placement(state, 1, "", {})
	if result.ok:
		return Result.failure("supply 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.rural_marketeers_offramp_supply_remaining") < 0:
		return Result.failure("错误信息应包含 state.map.rural_marketeers_offramp_supply_remaining，实际: %s" % err)
	return Result.success()

static func _test_milestone_effect_fails_fast_on_invalid_pending_flag_type() -> Result:
	var entry = EntryClass.new()
	var state := GameState.new()
	state.players = [{}, {}]
	state.map = {
		"rural_marketeers_offramp_supply_remaining": 2,
	}
	state.round_state = {
		"rural_marketeers_offramp_pending": {
			1: "bad",
		}
	}
	var result := entry._milestone_effect_grant_offramp_placement(state, 1, "", {})
	if result.ok:
		return Result.failure("pending flag 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.rural_marketeers_offramp_pending[1]") < 0:
		return Result.failure("错误信息应包含 round_state.rural_marketeers_offramp_pending[1]，实际: %s" % err)
	return Result.success()
