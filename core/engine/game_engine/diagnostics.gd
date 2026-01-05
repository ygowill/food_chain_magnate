# GameEngine：调试/状态快照
# 负责：生成 dump 文本与简要状态信息（用于 UI/日志）。
extends RefCounted

static func dump(
	state: GameState,
	command_history: Array[Command],
	current_command_index: int,
	checkpoints: Array[Dictionary]
) -> String:
	if state == null:
		return "=== GameEngine ===\n[uninitialized]\n"

	var output := "=== GameEngine ===\n"
	output += "Commands: %d (current: %d)\n" % [command_history.size(), current_command_index]
	output += "Checkpoints: %d\n" % checkpoints.size()
	output += "State Hash: %s\n" % state.compute_hash().substr(0, 16)
	output += "\n"
	output += state.dump()
	return output

static func get_status(
	state: GameState,
	command_history: Array[Command],
	current_command_index: int,
	checkpoints: Array[Dictionary]
) -> Dictionary:
	if state == null:
		return {
			"command_count": command_history.size(),
			"current_index": current_command_index,
			"checkpoint_count": checkpoints.size(),
			"state_hash": "",
			"round": -1,
			"phase": "",
			"sub_phase": ""
		}
	return {
		"command_count": command_history.size(),
		"current_index": current_command_index,
		"checkpoint_count": checkpoints.size(),
		"state_hash": state.compute_hash(),
		"round": state.round_number,
		"phase": state.phase,
		"sub_phase": state.sub_phase
	}

