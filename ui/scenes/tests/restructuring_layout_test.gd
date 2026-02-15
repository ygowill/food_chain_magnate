# 重组界面布局回归测试（UI 属性测试）
# 覆盖 issue_tracker #25：
# - RestructuringModal 必须全屏覆盖（忽略 covered_rect）
# - HandArea 在重组模式仅显示 reserve（不显示 active/busy）
# - CompanyStructure 下属卡槽使用 4 列网格（多行）
class_name RestructuringLayoutTest
extends RefCounted

const RestructuringModalScene = preload("res://ui/components/modal_panel/restructuring_modal.tscn")
const HandAreaScene = preload("res://ui/components/hand_area/hand_area.tscn")
const CompanyStructureScene = preload("res://ui/components/company_structure/company_structure.tscn")

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

static func run() -> Result:
	# 确保 EmployeeRegistry 已装配（用于挑选 manager_slots>0 的员工）
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未加载")

	var manager_id := _find_employee_with_manager_slots(5)
	if manager_id.is_empty():
		return Result.failure("找不到 manager_slots>=5 的员工（用于测试下属槽多行布局）")

	var modal = RestructuringModalScene.instantiate()
	var hand = HandAreaScene.instantiate()
	var company = CompanyStructureScene.instantiate()

	# 说明：AllTests autorun 在 _ready() 中同步执行，场景树仍处于 setup 阶段；
	# 这里不把节点加入 tree，仅做“属性/结构”断言，避免 add_child 报错。
	if modal.has_method("_ready"):
		modal.call("_ready")
	if hand.has_method("_ready"):
		hand.call("_ready")
	if company.has_method("_ready"):
		company.call("_ready")

	# open 应忽略 covered_rect 并全屏
	var covered := Rect2(Vector2(10, 10), Vector2(100, 100))
	modal.open(covered)
	if modal.position != Vector2.ZERO:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("RestructuringModal.position=%s (期望 Vector2.ZERO)" % str(modal.position))
	if modal.size.is_equal_approx(covered.size):
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("RestructuringModal.size=%s (不应等于 covered.size=%s)" % [str(modal.size), str(covered.size)])

	# Split children should expand vertically, otherwise CompanyStructure.ManagerScroll may be squeezed to 0 height.
	# (issue_tracker #44)
	var hand_host = modal.get_node_or_null("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split/HandHost")
	var company_host = modal.get_node_or_null("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split/CompanyHost")
	if hand_host == null or not (hand_host is Control):
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("RestructuringModal.HandHost 节点缺失")
	if company_host == null or not (company_host is Control):
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("RestructuringModal.CompanyHost 节点缺失")
	if int((hand_host as Control).size_flags_vertical) != 3:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandHost.size_flags_vertical=%d (期望 3=EXPAND_FILL)" % int((hand_host as Control).size_flags_vertical))
	if int((company_host as Control).size_flags_vertical) != 3:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyHost.size_flags_vertical=%d (期望 3=EXPAND_FILL)" % int((company_host as Control).size_flags_vertical))

	# attach HandArea：应切换到 restructuring 展示模式（仅 reserve）
	if not hand.has_method("get_display_mode") or not hand.has_method("set_display_mode"):
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea 缺少 display_mode 接口（get/set_display_mode）")
	if str(hand.call("get_display_mode")) != "default":
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea 初始 display_mode 非 default")

	modal.attach_hand_area(hand)
	if str(hand.call("get_display_mode")) != "restructuring":
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea attach 后 display_mode=%s (期望 restructuring)" % str(hand.call("get_display_mode")))

	# Restructuring: left panel should fit 3 compact cards per row (issue_tracker #45).
	var hand_min_w := float((hand as Control).custom_minimum_size.x)
	if hand_min_w < 500.0 or hand_min_w > 540.0:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea.custom_minimum_size.x=%s (重组模式期望 3 列≈520)" % str((hand as Control).custom_minimum_size.x))

	var ha: HandArea = hand
	if is_instance_valid(ha.active_section) and ha.active_section.visible:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea.active_section 不应可见（重组模式）")
	if is_instance_valid(ha.busy_section) and ha.busy_section.visible:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea.busy_section 不应可见（重组模式）")
	if is_instance_valid(ha.reserve_section) and not ha.reserve_section.visible:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("HandArea.reserve_section 应可见（重组模式）")

	# CompanyStructure：下属槽应为 GridContainer(4列)
	var cap := 0
	var def_val = EmployeeRegistryClass.get_def(manager_id)
	if def_val is EmployeeDef:
		cap = int((def_val as EmployeeDef).manager_slots)
	if cap <= 4:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("测试所选员工 cap=%d (期望>4)" % cap)

	modal.attach_company_structure(company)
	# CompanyStructure: CEO direct slots area should reserve height (issue_tracker #41).
	var manager_scroll := (company as CompanyStructure).get_node_or_null("MarginContainer/VBoxContainer/ManagerRow/ManagerScroll")
	if manager_scroll == null:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure.ManagerScroll 节点缺失")
	if (manager_scroll as ScrollContainer).custom_minimum_size.y <= 0.0:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure.ManagerScroll.custom_minimum_size.y=%s (期望 > 0)" % str((manager_scroll as ScrollContainer).custom_minimum_size.y))

	var player := {
		"employees": [manager_id],
		"company_structure": {"ceo_slots": 1},
	}
	(company as CompanyStructure).set_player_data(player)

	var manager_container := (company as CompanyStructure).get_node_or_null("MarginContainer/VBoxContainer/ManagerRow/ManagerScroll/ManagerContainer")
	if manager_container == null:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure.ManagerContainer 节点缺失")
	if manager_container.get_child_count() <= 0:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure.ManagerContainer 为空")
	var col0 = manager_container.get_child(0)
	if not (col0 is VBoxContainer) or col0.get_child_count() < 2:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure slot[0] 列结构不符合预期")
	# Direct slot should be centered and not stretched by the reports grid below (issue_tracker #44).
	var direct_host = col0.get_child(0)
	if not (direct_host is CenterContainer) or direct_host.get_child_count() < 1:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure direct slot host 不是 CenterContainer（用于居中直属槽）")
	var reports_box = col0.get_child(1)
	if not (reports_box is VBoxContainer) or reports_box.get_child_count() < 2:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("CompanyStructure reports_box 结构不符合预期")
	var grid = reports_box.get_child(1)
	if not (grid is GridContainer):
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("reports_box[1] 不是 GridContainer")
	if int((grid as GridContainer).columns) != 4:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("reports grid.columns=%d (期望 4)" % int((grid as GridContainer).columns))
	if grid.get_child_count() != cap:
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("reports grid 子节点数量=%d (期望 %d)" % [grid.get_child_count(), cap])

	# close：应恢复 HandArea display_mode
	modal.close()
	if str(hand.call("get_display_mode")) != "default":
		_safe_free(modal)
		_safe_free(hand)
		_safe_free(company)
		return Result.failure("RestructuringModal.close 后 HandArea.display_mode=%s (期望 default)" % str(hand.call("get_display_mode")))

	_safe_free(modal)
	_safe_free(hand)
	_safe_free(company)
	return Result.success()

static func _find_employee_with_manager_slots(min_slots: int) -> String:
	var ids := EmployeeRegistryClass.get_all_ids()
	for eid in ids:
		var def_val = EmployeeRegistryClass.get_def(eid)
		if not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		var cap := int(def.manager_slots)
		if cap >= min_slots:
			return str(def.id)
	return ""

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
