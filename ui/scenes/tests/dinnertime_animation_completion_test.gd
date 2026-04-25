class_name DinnertimeAnimationCompletionTest
extends RefCounted

const DinnertimeAnimationControllerClass = preload("res://ui/scenes/game/dinnertime/controller.gd")

static func run() -> Result:
	var ctrl = DinnertimeAnimationControllerClass.new()
	var seen := {
		"completed": false,
		"flow_updates": 0,
	}
	ctrl.settlement_completed.connect(func():
		seen["completed"] = true
	)
	ctrl.flow_state_changed.connect(func():
		seen["flow_updates"] = int(seen.get("flow_updates", 0)) + 1
	)

	ctrl.set("_state", 1) # DinnertimeAnimationController.State.PLAYING
	var orders: Array[Dictionary] = [{
		"house_id": "house_test",
		"winner_owner": 0,
		"revenue": 10,
	}]
	ctrl.set("_orders", orders)
	ctrl.set("_current_idx", 0)
	ctrl.set("_previewing", false)
	ctrl.set("_post_income_started", false)
	ctrl.set("_post_income_playing", false)
	ctrl.set("_post_income_done", true)

	ctrl.call("_preview_current")
	if not bool(ctrl.call("can_advance")):
		return Result.failure("晚餐结算预览就绪后应允许从右侧动作面板推进下一笔")
	if int(seen.get("flow_updates", 0)) <= 0:
		return Result.failure("晚餐结算预览状态变化应通知外层刷新动作面板")

	ctrl.call("advance")
	if not bool(seen.get("completed", false)):
		return Result.failure("最后一笔晚餐结算自然播放结束后应触发 settlement_completed")
	if int(ctrl.get("_state")) != 2: # DinnertimeAnimationController.State.DONE
		return Result.failure("晚餐结算完成后状态应为 DONE")
	if bool(ctrl.call("can_advance")):
		return Result.failure("晚餐结算完成后不应继续显示可推进状态")

	return Result.success({})
