# HandArea UI 回归测试
# 目标：确保 set_employees 重建时不会因重复 employee_id 泄漏旧卡牌（导致“混合两名玩家员工”）
class_name HandAreaViewSwitchTest
extends RefCounted

const HandAreaClass = preload("res://ui/components/hand_area/hand_area.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")

static func run() -> Result:
	var hand_area = HandAreaClass.new()

	# 使用最小控件树即可；无需加入 SceneTree（本测试只验证容器子节点是否被正确清空/重建）。
	hand_area.active_container = HFlowContainer.new()
	hand_area.reserve_container = HFlowContainer.new()
	hand_area.busy_container = HFlowContainer.new()
	hand_area.active_section = VBoxContainer.new()
	hand_area.reserve_section = VBoxContainer.new()
	hand_area.busy_section = VBoxContainer.new()

	# 挂到父节点便于统一释放，避免 headless 测试退出时资源泄漏告警。
	hand_area.add_child(hand_area.active_container)
	hand_area.add_child(hand_area.reserve_container)
	hand_area.add_child(hand_area.busy_container)
	hand_area.add_child(hand_area.active_section)
	hand_area.add_child(hand_area.reserve_section)
	hand_area.add_child(hand_area.busy_section)

	# 玩家 A：含重复员工类型
	hand_area.set_employees(["ceo", "recruiter", "recruiter"], [], [])
	var a_ids := _collect_child_employee_ids(hand_area.active_container)
	if a_ids != ["ceo", "recruiter", "recruiter"]:
		var fail := Result.failure("HandArea active_container 首次构建不符合预期: %s" % str(a_ids))
		_safe_free(hand_area)
		return fail

	# 切换到玩家 B：若清理不彻底，会残留上一位玩家的重复卡牌
	hand_area.set_employees(["ceo", "cfo"], [], [])
	var b_ids := _collect_child_employee_ids(hand_area.active_container)
	if b_ids != ["ceo", "cfo"]:
		var fail2 := Result.failure("HandArea active_container 切换玩家后仍残留旧卡牌: %s" % str(b_ids))
		_safe_free(hand_area)
		return fail2

	var ok := Result.success({
		"player_a": ["ceo", "recruiter", "recruiter"],
		"player_b": ["ceo", "cfo"],
	})
	_safe_free(hand_area)
	return ok

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()

static func _collect_child_employee_ids(container: Node) -> Array[String]:
	var out: Array[String] = []
	if container == null:
		return out
	for child in container.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if child.get_script() != EmployeeCardClass:
			continue
		out.append(str(child.employee_id))
	out.sort()
	return out
