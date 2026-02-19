# GameTimelineController：step_timeline seek 辅助
# 用途：抽取回放/复盘 step seek 的 state 恢复逻辑，减少重复实现。
class_name GameTimelineStepSeekHelpers
extends RefCounted

static func restore_state_from_step_timeline(timeline: Dictionary, steps: Array, cursor_step_index: int) -> Result:
	if timeline == null or timeline.is_empty():
		return Result.failure("timeline 为空")
	if steps == null:
		return Result.failure("steps 为空")

	var target := int(cursor_step_index)
	var state_dict: Dictionary = {}
	var anchor_cmd := -1

	if target < 0:
		var init_val = timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			state_dict = Dictionary(init_val)
	else:
		if target >= steps.size():
			return Result.failure("step 越界: step=%d" % target)
		var step_val = steps[target]
		if step_val is Dictionary:
			var step: Dictionary = step_val
			anchor_cmd = int(step.get("anchor_command_index", -1))
			var sd_val = step.get("state_dict", null)
			if sd_val is Dictionary:
				state_dict = Dictionary(sd_val)

	if state_dict.is_empty():
		return Result.failure("缺少 state 快照: step=%d" % target)

	var restore_r := GameState.from_dict(state_dict)
	if not restore_r.ok:
		return Result.failure("恢复 state 失败: %s" % restore_r.error)

	var restored: GameState = restore_r.value
	if restored == null:
		return Result.failure("恢复 state 为空")

	return Result.success({
		"state": restored,
		"anchor_command_index": anchor_cmd,
	})
