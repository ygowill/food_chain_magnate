# Replay runner (development tool)
# Usage (Godot 4):
#   godot --headless --script res://tools/replay_runner.gd -- res://tools/replays/m1_phase_cycle_22.json
extends Node

func _ready() -> void:
	var args := OS.get_cmdline_args()
	var scenario_path := "res://tools/replays/m1_phase_cycle_22.json"
	if args.size() >= 2 and args[0] == "--":
		scenario_path = args[1]
	elif args.size() >= 1:
		scenario_path = args[0]

	var scenario_result := _load_json(scenario_path)
	if not scenario_result.ok:
		push_error("Failed to load scenario: %s" % scenario_result.error)
		get_tree().quit()
		return

	var scenario: Dictionary = scenario_result.value
	var player_count: int = int(scenario.get("player_count", 2))
	var seed: int = int(scenario.get("seed", 0))
	var checkpoint_interval: int = int(scenario.get("checkpoint_interval", 50))
	var commands_data: Array = scenario.get("commands", [])
	var expect: Dictionary = scenario.get("expect", {})

	var engine := GameEngine.new()
	var init_result := engine.initialize(player_count, seed)
	if not init_result.ok:
		push_error("GameEngine.initialize failed: %s" % init_result.error)
		get_tree().quit()
		return

	engine.checkpoint_interval = checkpoint_interval

	var exec_result := _execute_commands(engine, commands_data)
	if not exec_result.ok:
		push_error("Command execution failed: %s" % exec_result.error)
		get_tree().quit()
		return

	var state := engine.get_state()
	var final_hash := state.compute_hash()
	var final_kv := state.extract_key_values()

	var expect_result := _check_expectations(state, final_kv, expect)
	if not expect_result.ok:
		push_error("Expectations failed: %s" % expect_result.error)
		get_tree().quit()
		return

	var replay_hash_before := final_hash
	var replay_result := engine.full_replay()
	if not replay_result.ok:
		push_error("Full replay failed: %s" % replay_result.error)
		get_tree().quit()
		return

	var replay_hash_after := engine.get_state().compute_hash()
	if replay_hash_after != replay_hash_before:
		push_error("Determinism check failed: hash mismatch (%s vs %s)" % [
			replay_hash_before.substr(0, 8),
			replay_hash_after.substr(0, 8)
		])
		get_tree().quit()
		return

	var checkpoint_verify := engine.verify_checkpoints()
	if not checkpoint_verify.ok:
		push_error("Checkpoint verify failed: %s" % checkpoint_verify.error)
		get_tree().quit()
		return

	print("OK  scenario=%s" % scenario.get("name", scenario_path))
	print("OK  commands=%d checkpoints=%d" % [engine.get_command_history().size(), engine.checkpoints.size()])
	print("OK  final_hash=%s..." % final_hash.substr(0, 8))
	print("OK  final_kv=%s" % str(final_kv))
	get_tree().quit()

func _load_json(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("Cannot open file: %s" % path)
	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("Invalid JSON: %s" % path)
	return Result.success(parsed)

func _execute_commands(engine: GameEngine, commands_data: Array) -> Result:
	for i in range(commands_data.size()):
		var cmd_data = commands_data[i]
		if not (cmd_data is Dictionary):
			return Result.failure("Command #%d is not an object" % i)

		var action_id: String = str(cmd_data.get("action_id", ""))
		if action_id.is_empty():
			return Result.failure("Command #%d missing action_id" % i)

		var params: Dictionary = cmd_data.get("params", {})
		var actor_val = cmd_data.get("actor", -1)

		var cmd: Command
		if actor_val is String:
			var actor_str = actor_val
			if actor_str == "system":
				cmd = Command.create_system(action_id, params)
			elif actor_str == "current":
				cmd = Command.create(action_id, engine.get_state().get_current_player_id(), params)
			else:
				return Result.failure("Command #%d has invalid actor string: %s" % [i, actor_str])
		else:
			var actor: int = int(actor_val)
			if actor < 0:
				cmd = Command.create_system(action_id, params)
			else:
				cmd = Command.create(action_id, actor, params)

		var result := engine.execute_command(cmd)
		if not result.ok:
			return Result.failure("Command #%d (%s) failed: %s" % [i, action_id, result.error])

	return Result.success()

func _check_expectations(state: GameState, key_values: Dictionary, expect: Dictionary) -> Result:
	if expect.is_empty():
		return Result.success()

	if expect.has("round") and int(expect.round) != int(state.round_number):
		return Result.failure("round mismatch: expected %d, got %d" % [int(expect.round), state.round_number])

	if expect.has("phase") and str(expect.phase) != str(state.phase):
		return Result.failure("phase mismatch: expected %s, got %s" % [str(expect.phase), state.phase])

	if expect.has("sub_phase") and str(expect.sub_phase) != str(state.sub_phase):
		return Result.failure("sub_phase mismatch: expected %s, got %s" % [str(expect.sub_phase), state.sub_phase])

	# Optional key values assertions (subset match)
	var expect_kv: Dictionary = expect.get("key_values", {})
	for k in expect_kv.keys():
		if not key_values.has(k) or str(key_values[k]) != str(expect_kv[k]):
			return Result.failure("key_values[%s] mismatch: expected %s, got %s" % [
				str(k), str(expect_kv[k]), str(key_values.get(k, null))
			])

	return Result.success()

