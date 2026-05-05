class_name ForwardSimulatorTest
extends RefCounted

const ForwardSimulatorClass = preload("res://core/ai/simulation/forward_simulator.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)

	var source_hash_before := str(engine.get_state().compute_hash())
	var actor := engine.get_state().get_current_player_id()
	var command := Command.create("select_reserve_card", actor, {"selected_index": 0})
	var sim_read := ForwardSimulatorClass.simulate_command(engine, command)
	if not sim_read.ok:
		return sim_read
	if MilestoneEffectRegistryClass.get_current() != engine.ruleset_v2.milestone_effect_registry:
		return Result.failure("source milestone effect registry was not restored after simulation")
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("source hash changed after simulation")
	var sim_data: Dictionary = sim_read.value
	var sim_engine: GameEngine = sim_data.get("engine", null)
	if sim_engine == null:
		return Result.failure("simulation result missing engine")
	if sim_engine.get_state() == null:
		return Result.failure("simulation result missing state")

	var source_exec := engine.execute_command(command.duplicate_command())
	if not source_exec.ok:
		return Result.failure("source execute failed: %s" % source_exec.error)
	if str(engine.get_state().compute_hash()) != str(sim_engine.get_state().compute_hash()):
		return Result.failure("source/simulation hash mismatch after same command")
	return Result.success()
