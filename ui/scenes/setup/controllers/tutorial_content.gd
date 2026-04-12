# GameSetup scene：教学文案与步骤定义
# 负责：
# - 开局页导览步骤文案
class_name GameSetupTutorialContent
extends RefCounted

static func build_setup_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"player_count_section",
		"先决定本局规模",
		"这里选择玩家人数。第一局推荐从 2 人或 3 人开始，信息量更可控。"
	)
	if _is_target_available(targets.get("first_time_option", null)):
		steps.append({
			"target_key": "first_time_option",
			"title": "建议勾选初次体验",
			"body": "它会启用短游戏并关闭里程碑。如果你从欢迎弹窗进入教学局，这里也会自动替你设置好。",
		})
	elif _is_target_available(targets.get("game_options_section", null)):
		steps.append({
			"target_key": "game_options_section",
			"title": "先看游戏选项",
			"body": "这里可以切换短游戏、里程碑等关键规则预设，首局建议保持简单。",
		})
	_append_step_if_target_available(
		steps,
		targets,
		"modules_section",
		"扩展模块先少碰",
		"模块会增加新规则和新内容。第一局建议先理解基础流程，再回头尝试扩展。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"start_button",
		"准备好后开始游戏",
		"进入地图后，我会继续带你认识主要界面区域。"
	)
	return steps

static func _append_step_if_target_available(
	steps: Array,
	targets: Dictionary,
	target_key: String,
	title: String,
	body: String
) -> void:
	if not _is_target_available(targets.get(target_key, null)):
		return
	steps.append({
		"target_key": target_key,
		"title": title,
		"body": body,
	})

static func _is_target_available(target) -> bool:
	if not (target is Control):
		return false
	var control: Control = target
	return is_instance_valid(control) and control.is_visible_in_tree()
