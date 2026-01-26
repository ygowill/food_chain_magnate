# Marketing demand_generated event payload test
# Covers issue_tracker #48: leaving Marketing should emit per-board DEMAND_GENERATED events with house numbers.
class_name MarketingDemandGeneratedEventTest
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")

static func run() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var old_state: GameState = engine.get_state().duplicate_state()
	old_state.phase = "Marketing"
	old_state.sub_phase = ""
	old_state.round_number = 3

	# Minimal house table for id->number mapping in the event payload.
	old_state.map = {
		"houses": {
			"h1": {"house_number": 2},
			"h2": {"house_number": 5},
		}
	}
	old_state.round_state = {} if not (old_state.round_state is Dictionary) else old_state.round_state
	old_state.round_state["marketing"] = {
		"processed": [
			{
				"board_number": 14,
				"type": "billboard",
				"owner": 0,
				"employee_type": "marketing_trainee",
				"product": "burger",
				"world_pos": Vector2i(1, 2),
				"affected_houses": ["h1", "h2"],
				"demands_added": 6,
			}
		]
	}

	var new_state: GameState = old_state.duplicate_state()
	new_state.phase = "Cleanup"

	var events := CommandRunnerClass.build_phase_change_events(old_state, new_state)
	var found := false
	for e_val in events:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if str(e.get("type", "")) != EventBus.EventType.DEMAND_GENERATED:
			continue
		var data_val = e.get("data", null)
		if not (data_val is Dictionary):
			return Result.failure("demand_generated.data must be Dictionary")
		var data: Dictionary = data_val
		if int(data.get("player_id", -1)) != 0:
			return Result.failure("player_id mismatch: %s" % str(data))
		if int(data.get("board_number", 0)) != 14:
			return Result.failure("board_number mismatch: %s" % str(data))
		if int(data.get("demands_added", 0)) != 6:
			return Result.failure("demands_added mismatch: %s" % str(data))
		var nums_val = data.get("affected_house_numbers", null)
		if not (nums_val is Array):
			return Result.failure("affected_house_numbers missing: %s" % str(data))
		var nums: Array = nums_val
		if nums.size() != 2 or int(nums[0]) != 2 or int(nums[1]) != 5:
			return Result.failure("affected_house_numbers mismatch: %s" % str(nums))
		found = true
		break

	if not found:
		return Result.failure("expected DEMAND_GENERATED event when leaving Marketing")

	return Result.success({})
