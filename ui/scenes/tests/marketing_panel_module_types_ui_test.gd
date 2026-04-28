# MarketingPanel module marketing type regression test
# Ensures module-defined marketing types (e.g., gourmet_guide) appear in the MarketingPanel selector.
class_name MarketingPanelModuleTypesUiTest
extends RefCounted

const MarketingPanelClass = preload("res://ui/components/marketing_panel/marketing_panel.gd")
const MarketingPanelScene = preload("res://ui/components/marketing_panel/marketing_panel.tscn")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")
const MarketingPanelIconCacheClass = preload("res://ui/components/marketing_panel/marketing_panel_icon_cache.gd")
const MarketingTypeButtonClass = preload("res://ui/components/marketing_panel/marketing_type_button.gd")

class FakeMarketingSkin:
	extends RefCounted

	var texture: Texture2D

	func _init(p_texture: Texture2D) -> void:
		texture = p_texture

	func get_marketing_texture(_type_id: String) -> Texture2D:
		return texture

static func run() -> Result:
	var r1 := _case_module_type_visible()
	if not r1.ok:
		return r1
	var r2 := _case_duplicate_marketers_render_multiple_items()
	if not r2.ok:
		return r2
	var r3 := _case_marketer_badge_rules_hide_single_use_and_tags()
	if not r3.ok:
		return r3
	var r4 := _case_single_multitype_marketer_renders_once_and_filters_types()
	if not r4.ok:
		return r4
	var r5 := _case_scene_flow_containers_expand_horizontally()
	if not r5.ok:
		return r5
	var r6 := _case_type_button_hides_availability_counts()
	if not r6.ok:
		return r6
	var r7 := _case_marketing_icon_cache_contains_full_texture()
	if not r7.ok:
		return r7
	return Result.success({})

static func _case_module_type_visible() -> Result:
	var panel := MarketingPanelClass.new()
	var container := HFlowContainer.new()
	panel.add_child(container)
	panel.type_container = container

	panel.set_available_marketers([
		{"staff_id": 1, "employee_type": "gourmet_food_critic", "type": "gourmet_guide", "marketing_types": ["gourmet_guide"], "max_duration": 3, "capacity": 1, "used": 0, "remaining": 1},
	])
	panel.set_available_boards({"gourmet_guide": [17, 18]})

	if str(panel._selected_type) != "gourmet_guide":
		_safe_free(panel)
		return Result.failure("MarketingPanel should auto-select the only available type gourmet_guide (selected=%s)" % str(panel._selected_type))

	if not panel._type_buttons.has("gourmet_guide"):
		_safe_free(panel)
		return Result.failure("MarketingPanel should include module marketing type gourmet_guide")

	var btn = panel._type_buttons.get("gourmet_guide", null)
	if btn == null or not is_instance_valid(btn):
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide button invalid: %s" % str(btn))

	if str(btn.type_id) != "gourmet_guide":
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide type_id mismatch: %s" % str(btn.type_id))

	if not bool(btn.is_available):
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide should be available when marketer+boards exist")

	_safe_free(panel)
	return Result.success({})

static func _case_duplicate_marketers_render_multiple_items() -> Result:
	var panel := MarketingPanelClass.new()
	var type_container := HFlowContainer.new()
	var picker := EmployeePickerClass.new()
	panel.add_child(type_container)
	panel.add_child(picker)
	panel.type_container = type_container
	panel.marketer_option = picker

	panel.set_available_marketers([
		{"staff_id": 11, "employee_type": "marketing_trainee", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 1, "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 12, "employee_type": "marketing_trainee", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 1, "capacity": 1, "used": 0, "remaining": 1},
	])
	panel.set_available_boards({"billboard": [11, 13]})

	if str(panel._selected_type) != "billboard":
		_safe_free(panel)
		return Result.failure("MarketingPanel should auto-select billboard in duplicate marketer case (selected=%s)" % str(panel._selected_type))

	var item_count := picker.get_child_count()
	if item_count != 2:
		_safe_free(panel)
		return Result.failure("MarketingPanel should render 2 marketer items for duplicate marketers, got: %d" % item_count)
	if int(panel._selected_staff_id) != 11:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应默认选中最小可用 staff_id=11，实际: %s" % str(panel._selected_staff_id))
	if not picker.has_method("set_selected"):
		_safe_free(panel)
		return Result.failure("EmployeePicker 缺少 set_selected")
	picker.set_selected("staff:12")
	panel._on_marketer_selected("marketing_trainee")
	if int(panel._selected_staff_id) != 12:
		_safe_free(panel)
		return Result.failure("MarketingPanel 切换实例后应保留 staff_id=12，实际: %s" % str(panel._selected_staff_id))

	_safe_free(panel)
	return Result.success({})

static func _case_marketer_badge_rules_hide_single_use_and_tags() -> Result:
	var panel := MarketingPanelClass.new()
	var type_container := HFlowContainer.new()
	var picker := EmployeePickerClass.new()
	panel.add_child(type_container)
	panel.add_child(picker)
	panel.type_container = type_container
	panel.marketer_option = picker

	panel.set_available_marketers([
		{"staff_id": 21, "employee_type": "marketing_trainee", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 1, "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 22, "employee_type": "campaign_manager", "type": "billboard", "marketing_types": ["billboard"], "max_duration": 3, "capacity": 3, "used": 1, "remaining": 2},
	])
	panel.set_available_boards({"billboard": [11, 13]})

	if picker.get_child_count() != 2:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应渲染 2 个 marketer item，实际: %d" % picker.get_child_count())

	var single_item = picker.get_child(0)
	var multi_item = picker.get_child(1)
	if str(single_item.get("badge_text")) != "":
		_safe_free(panel)
		return Result.failure("单次 marketer 不应显示 1/1 badge，实际: %s" % str(single_item.get("badge_text")))
	if str(single_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("MarketingPanel 单次 marketer 不应显示 可用/已用 tag，实际: %s" % str(single_item.get("tag_text")))
	if str(multi_item.get("badge_text")) != "2/3":
		_safe_free(panel)
		return Result.failure("多次 marketer 应显示 2/3 badge，实际: %s" % str(multi_item.get("badge_text")))
	if str(multi_item.get("tag_text")) != "":
		_safe_free(panel)
		return Result.failure("MarketingPanel 多次 marketer 不应显示 可用/已用 tag，实际: %s" % str(multi_item.get("tag_text")))

	_safe_free(panel)
	return Result.success({})

static func _case_single_multitype_marketer_renders_once_and_filters_types() -> Result:
	var panel := MarketingPanelClass.new()
	var type_container := HFlowContainer.new()
	var picker := EmployeePickerClass.new()
	panel.add_child(type_container)
	panel.add_child(picker)
	panel.type_container = type_container
	panel.marketer_option = picker

	panel.set_available_boards({"billboard": [11], "mailbox": [21]})
	panel.set_available_marketers([
		{"staff_id": 31, "employee_type": "campaign_manager", "type": "billboard", "marketing_types": ["billboard", "mailbox"], "max_duration": 3, "capacity": 1, "used": 0, "remaining": 1},
		{"staff_id": 31, "employee_type": "campaign_manager", "type": "mailbox", "marketing_types": ["billboard", "mailbox"], "max_duration": 3, "capacity": 1, "used": 0, "remaining": 1},
	])

	if picker.get_child_count() != 1:
		_safe_free(panel)
		return Result.failure("同一 staff 支持多个营销类型时，MarketingPanel 应只渲染 1 个 marketer item，实际: %d" % picker.get_child_count())
	if int(panel._selected_staff_id) != 31:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应先默认选中唯一营销员 staff_id=31，实际: %s" % str(panel._selected_staff_id))
	if str(panel._selected_type) != "":
		_safe_free(panel)
		return Result.failure("唯一营销员有多个可用营销类型时，不应自动选择类型，实际: %s" % str(panel._selected_type))
	if not panel._type_buttons.has("billboard") or not panel._type_buttons.has("mailbox"):
		_safe_free(panel)
		return Result.failure("选中 campaign_manager 后应显示 billboard/mailbox 类型按钮，实际: %s" % str(panel._type_buttons.keys()))

	panel._on_type_selected("billboard")
	if picker.get_child_count() != 1:
		_safe_free(panel)
		return Result.failure("选择营销类型后不应重复渲染同一营销员，实际: %d" % picker.get_child_count())
	if int(panel._selected_staff_id) != 31:
		_safe_free(panel)
		return Result.failure("选择营销类型后应保留先选的营销员 staff_id=31，实际: %s" % str(panel._selected_staff_id))

	_safe_free(panel)
	return Result.success({})

static func _case_scene_flow_containers_expand_horizontally() -> Result:
	var panel: Node = MarketingPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("MarketingPanel scene instantiate failed")
	if not (panel is Control):
		_safe_free(panel)
		return Result.failure("MarketingPanel scene root should be Control")
	var root: Control = panel
	if root.custom_minimum_size.x < 450.0:
		_safe_free(panel)
		return Result.failure("MarketingPanel 应提供稳定横向宽度，实际 custom_minimum_size=%s" % str(root.custom_minimum_size))

	var paths: Array[String] = [
		"MarginContainer/VBoxContainer",
		"MarginContainer/VBoxContainer/ScrollContainer",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/MarketerSection",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/MarketerSection/MarketerOption",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TypeSection",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TypeSection/TypeContainer",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/BoardSection",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/BoardSection/BoardFlow",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ProductSection",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ProductSection/ProductFlow",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/DurationSection",
		"MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/DurationSection/DurationFlow",
	]
	for path in paths:
		var node: Node = panel.get_node_or_null(path)
		if node == null or not (node is Control):
			_safe_free(panel)
			return Result.failure("MarketingPanel 横向布局节点缺失: %s" % path)
		var control: Control = node
		if int(control.size_flags_horizontal) != int(Control.SIZE_EXPAND_FILL):
			_safe_free(panel)
			return Result.failure("MarketingPanel %s 应横向填充以支持 HFlow 横排换行，实际: %s" % [path, str(control.size_flags_horizontal)])

	_safe_free(panel)
	return Result.success({})

static func _case_type_button_hides_availability_counts() -> Result:
	var btn = MarketingTypeButtonClass.new()
	btn.type_id = "billboard"
	btn.type_def = {"id": "billboard", "name": "广告牌", "icon": "B", "color": Color.WHITE}
	btn.is_available = true
	btn.marketer_count = 3
	btn.board_count = 4
	btn._build_ui()

	var label_texts := _collect_label_texts(btn)
	for text in label_texts:
		if text.contains("员工") or text.contains("板件") or text.contains("不可用"):
			_safe_free(btn)
			return Result.failure("营销类型按钮不应显示员工/板件/可用性统计文本，实际标签: %s" % str(label_texts))

	if btn._icon_rect == null:
		_safe_free(btn)
		return Result.failure("营销类型按钮应创建 TextureRect 图标节点")
	if int(btn._icon_rect.expand_mode) != int(TextureRect.EXPAND_IGNORE_SIZE):
		_safe_free(btn)
		return Result.failure("营销类型按钮图标应忽略贴图原始尺寸以填入图标槽，实际 expand_mode=%s" % str(btn._icon_rect.expand_mode))
	if int(btn._icon_rect.stretch_mode) != int(TextureRect.STRETCH_KEEP_ASPECT_CENTERED):
		_safe_free(btn)
		return Result.failure("营销类型按钮图标应完整等比居中显示，实际 stretch_mode=%s" % str(btn._icon_rect.stretch_mode))

	var blocking_child := _find_mouse_blocking_descendant(btn)
	if blocking_child != "":
		_safe_free(btn)
		return Result.failure("营销类型按钮子控件不应截获点击事件，阻塞节点: %s" % blocking_child)

	_safe_free(btn)
	return Result.success({})

static func _case_marketing_icon_cache_contains_full_texture() -> Result:
	var img := Image.create(80, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(20):
		for x in range(8):
			img.set_pixel(x, y, Color(1, 0, 0, 1))
			img.set_pixel(79 - x, y, Color(0, 1, 0, 1))

	var source_tex := ImageTexture.create_from_image(img)
	var cache = MarketingPanelIconCacheClass.new()
	cache._skin = FakeMarketingSkin.new(source_tex)
	var scaled: Texture2D = cache.get_marketing_icon_texture("wide_test", Vector2i(40, 40))
	if scaled == null:
		return Result.failure("营销类型图标缓存应返回缩放后的贴图")

	var out := scaled.get_image()
	if out == null or out.is_empty():
		return Result.failure("营销类型图标缩放结果应可读取像素")
	if out.get_size() != Vector2i(40, 40):
		return Result.failure("营销类型图标缩放结果尺寸应为 40x40，实际: %s" % str(out.get_size()))

	var left_edge_alpha := out.get_pixel(0, 20).a
	var right_edge_alpha := out.get_pixel(39, 20).a
	if left_edge_alpha <= 0.1 or right_edge_alpha <= 0.1:
		return Result.failure("营销类型图标应完整保留宽图左右边缘，实际 alpha=(%s, %s)" % [str(left_edge_alpha), str(right_edge_alpha)])

	return Result.success({})

static func _collect_label_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node is Label:
		out.append(str((node as Label).text))
	for child in node.get_children():
		if child is Node:
			out.append_array(_collect_label_texts(child))
	return out

static func _find_mouse_blocking_descendant(node: Node) -> String:
	for child in node.get_children():
		if child is Control:
			var control: Control = child
			if int(control.mouse_filter) != int(Control.MOUSE_FILTER_IGNORE):
				return str(child.name)
		var nested := _find_mouse_blocking_descendant(child)
		if not nested.is_empty():
			return "%s/%s" % [str(child.name), nested]
	return ""

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
