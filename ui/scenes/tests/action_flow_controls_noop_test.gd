class_name ActionFlowControlsNoopTest
extends RefCounted

const ActionFlowControlsScene: PackedScene = preload("res://ui/components/action_flow_controls/action_flow_controls.tscn")

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ActionFlowControls）")

	if ActionFlowControlsScene == null:
		return Result.failure("预加载 action_flow_controls.tscn 失败")

	var controls = ActionFlowControlsScene.instantiate()
	if controls == null or not is_instance_valid(controls):
		return Result.failure("实例化 ActionFlowControls 失败")
	host.add_child(controls)
	(controls as Control).visible = true
	await st.process_frame

	if not (controls is ActionFlowControls):
		await _cleanup(controls, st)
		return Result.failure("实例不是 ActionFlowControls")
	var flow_controls: ActionFlowControls = controls

	var cfg := {
		"confirm_end": {
			"visible": true,
			"text": "确认结束",
			"enabled": false,
			"disabled_reason": "等待其他玩家",
		},
		"skip_step": {
			"visible": false,
			"text": "跳过",
			"enabled": true,
			"disabled_reason": "",
		},
		"rollback_last": {
			"visible": true,
			"text": "回退上一步",
			"enabled": false,
			"disabled_reason": "上一条不是你的操作",
			"action_id": "rollback_last_command",
		},
		"rewind": {
			"enabled": false,
		},
	}

	flow_controls.apply_flow_config(cfg)
	var first_apply_count := int(flow_controls.get_flow_config_apply_count())
	if first_apply_count != 1:
		await _cleanup(controls, st)
		return Result.failure("首次 apply_flow_config 应计数 1，实际=%d" % first_apply_count)

	var confirm_button := flow_controls.confirm_end_button
	var skip_button := flow_controls.skip_step_button
	var rollback_button := flow_controls.rollback_last_button
	var rewind_button := flow_controls.rewind_button
	if confirm_button == null or skip_button == null or rollback_button == null or rewind_button == null:
		await _cleanup(controls, st)
		return Result.failure("ActionFlowControls 按钮节点缺失")

	var confirm_state := {
		"visible": bool(confirm_button.visible),
		"text": str(confirm_button.text),
		"disabled": bool(confirm_button.disabled),
		"tooltip": str(confirm_button.tooltip_text),
	}
	var skip_state := {
		"visible": bool(skip_button.visible),
		"text": str(skip_button.text),
		"disabled": bool(skip_button.disabled),
		"tooltip": str(skip_button.tooltip_text),
	}
	var rollback_state := {
		"visible": bool(rollback_button.visible),
		"text": str(rollback_button.text),
		"disabled": bool(rollback_button.disabled),
		"tooltip": str(rollback_button.tooltip_text),
	}
	var rewind_disabled := bool(rewind_button.disabled)

	flow_controls.apply_flow_config(cfg.duplicate(true))
	var second_apply_count := int(flow_controls.get_flow_config_apply_count())
	if second_apply_count != 1:
		await _cleanup(controls, st)
		return Result.failure("相同配置不应重复写 UI，实际 apply_count=%d" % second_apply_count)

	var confirm_state_after := {
		"visible": bool(confirm_button.visible),
		"text": str(confirm_button.text),
		"disabled": bool(confirm_button.disabled),
		"tooltip": str(confirm_button.tooltip_text),
	}
	var skip_state_after := {
		"visible": bool(skip_button.visible),
		"text": str(skip_button.text),
		"disabled": bool(skip_button.disabled),
		"tooltip": str(skip_button.tooltip_text),
	}
	var rollback_state_after := {
		"visible": bool(rollback_button.visible),
		"text": str(rollback_button.text),
		"disabled": bool(rollback_button.disabled),
		"tooltip": str(rollback_button.tooltip_text),
	}
	if confirm_state_after != confirm_state:
		await _cleanup(controls, st)
		return Result.failure("相同配置后 confirm_end 状态不应变化")
	if skip_state_after != skip_state:
		await _cleanup(controls, st)
		return Result.failure("相同配置后 skip_step 状态不应变化")
	if rollback_state_after != rollback_state:
		await _cleanup(controls, st)
		return Result.failure("相同配置后 rollback_last 状态不应变化")
	if bool(rewind_button.disabled) != rewind_disabled:
		await _cleanup(controls, st)
		return Result.failure("相同配置后 rewind disabled 不应变化")

	var changed_cfg := cfg.duplicate(true)
	changed_cfg["skip_step"] = {
		"visible": true,
		"text": "跳过子阶段",
		"enabled": false,
		"disabled_reason": "已有面板承载",
	}
	flow_controls.apply_flow_config(changed_cfg)
	var third_apply_count := int(flow_controls.get_flow_config_apply_count())
	if third_apply_count != 2:
		await _cleanup(controls, st)
		return Result.failure("配置变化后应再写一次 UI，实际 apply_count=%d" % third_apply_count)
	if not bool(skip_button.visible):
		await _cleanup(controls, st)
		return Result.failure("变化后 skip_step 应可见")
	if not bool(skip_button.disabled):
		await _cleanup(controls, st)
		return Result.failure("变化后 skip_step 应 disabled")
	if str(skip_button.text) != "跳过子阶段":
		await _cleanup(controls, st)
		return Result.failure("变化后 skip_step 文案错误: %s" % str(skip_button.text))

	var emitted: Array[String] = []
	flow_controls.action_requested.connect(func(action_id: String, _params: Dictionary):
		emitted.append(action_id)
	)
	var settlement_cfg := {
		"confirm_end": {
			"visible": true,
			"text": "确认营销结算",
			"enabled": true,
			"disabled_reason": "",
			"action_id": "confirm_marketing_settlement",
		},
		"skip_step": {
			"visible": true,
			"text": "跳过营销结算",
			"enabled": true,
			"disabled_reason": "",
			"action_id": "skip_marketing_settlement",
		},
		"rollback_last": {
			"visible": false,
			"enabled": false,
		},
		"rewind": {
			"visible": false,
			"enabled": false,
		},
	}
	flow_controls.apply_flow_config(settlement_cfg)
	confirm_button.emit_signal("pressed")
	skip_button.emit_signal("pressed")
	if emitted != ["confirm_marketing_settlement", "skip_marketing_settlement"]:
		await _cleanup(controls, st)
		return Result.failure("结算控制按钮应发出自定义动作 id，实际=%s" % str(emitted))

	await _cleanup(controls, st)
	return Result.success({})

static func _cleanup(node: Node, st: SceneTree) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await st.process_frame
