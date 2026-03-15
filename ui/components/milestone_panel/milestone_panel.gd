# 里程碑面板组件
# 显示里程碑池与玩家已获得（里程碑为自动授予，不支持手动领取）
class_name MilestonePanel
extends Control

signal cancelled()

@onready var background: ColorRect = $Background
@onready var margin_container: MarginContainer = $MarginContainer
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var milestones_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/MilestonesContainer
@onready var button_row: Control = $MarginContainer/VBoxContainer/ButtonRow
@onready var close_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CloseButton

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EffectUiTextRegistryClass = preload("res://core/rules/effect_ui_text_registry.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@export var show_close_button: bool = true
# LeftPanel 的 “里程碑” Tab 复用同一面板：需要去掉自身背景/边距与最小尺寸，避免与 LeftPanel 风格不一致且产生溢出（issue_tracker #58）。
@export var embedded_in_player_panel: bool = false

var _milestone_pool: Array[String] = []
var _player_milestones: Array[String] = []
var _players: Array = []  # Array[Dictionary]（用于全局视图）
var _global_view: bool = false
var _rules: Dictionary = {}
var _milestone_items: Dictionary = {}  # milestone_id -> MilestoneItem
var _embedded_in_right_panel: bool = false
var _base_custom_minimum_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
		UiStylesClass.apply_button_secondary(close_btn)
	if is_instance_valid(title_label):
		UiStylesClass.apply_label_dark(title_label)
	_apply_embedded_layout()
	_update_close_visibility()
	_rebuild_milestones()

func set_global_view(global_view: bool) -> void:
	_global_view = global_view
	_maybe_rebuild_milestones()

func set_players(players: Array) -> void:
	_players = Array(players, TYPE_DICTIONARY, "", null) if players != null else []
	_maybe_rebuild_milestones()

func set_rules(rules: Dictionary) -> void:
	_rules = rules.duplicate(true) if rules != null else {}
	# 规则可能影响效果文案（例如 CFO 加成百分比），直接重建以刷新文案。
	_rebuild_milestones()

func set_embedded_in_right_panel(embedded: bool) -> void:
	_embedded_in_right_panel = embedded
	_apply_embedded_layout()
	_update_close_visibility()

func set_milestone_pool(pool: Array) -> void:
	_milestone_pool.clear()
	for v in pool:
		_milestone_pool.append(str(v))
	_maybe_rebuild_milestones()

func set_player_milestones(milestones: Array) -> void:
	_player_milestones.clear()
	for v in milestones:
		_player_milestones.append(str(v))
	_maybe_rebuild_milestones()

func refresh() -> void:
	_update_states()

func _update_close_visibility() -> void:
	if not is_instance_valid(button_row):
		return
	# 右侧 Dock 面板中：不允许通过“关闭”退出当前动作流（只允许跳过推进）。
	button_row.visible = show_close_button and (not embedded_in_player_panel) and (not _embedded_in_right_panel)

func _apply_embedded_layout() -> void:
	# 尺寸：嵌入布局时不要用自己的 custom_minimum_size 把父容器撑爆。
	if _base_custom_minimum_size == Vector2.ZERO:
		_base_custom_minimum_size = custom_minimum_size
	if _embedded_in_right_panel or embedded_in_player_panel:
		custom_minimum_size = Vector2.ZERO
	else:
		custom_minimum_size = _base_custom_minimum_size

	# 样式：PlayerPanel(Tab) 里由 LeftPanel 负责背景与外边距。
	if embedded_in_player_panel:
		if is_instance_valid(background):
			background.visible = false
		if is_instance_valid(title_label):
			title_label.visible = false
		if is_instance_valid(margin_container):
			margin_container.add_theme_constant_override("margin_left", 0)
			margin_container.add_theme_constant_override("margin_top", 0)
			margin_container.add_theme_constant_override("margin_right", 0)
			margin_container.add_theme_constant_override("margin_bottom", 0)
	else:
		if is_instance_valid(background):
			background.visible = true
		if is_instance_valid(title_label):
			title_label.visible = true
		if is_instance_valid(margin_container):
			margin_container.add_theme_constant_override("margin_left", 16)
			margin_container.add_theme_constant_override("margin_top", 16)
			margin_container.add_theme_constant_override("margin_right", 16)
			margin_container.add_theme_constant_override("margin_bottom", 16)

func _rebuild_milestones() -> void:
	if milestones_container == null:
		return
	for c in milestones_container.get_children():
		if is_instance_valid(c):
			c.queue_free()
	_milestone_items.clear()

	var ids := _get_desired_milestone_ids()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "暂无里程碑"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 12)
		UiStylesClass.apply_label_hint_dark(empty)
		milestones_container.add_child(empty)
		return

	for ms_id in ids:
		if ms_id.is_empty():
			continue

		var def = MilestoneRegistryClass.get_def(ms_id) if MilestoneRegistryClass.is_loaded() else null
		var item := MilestoneItem.new()
		item.milestone_id = ms_id
		item.milestone_def = def
		item.global_view = _global_view
		item.effect_text = _format_milestone_effect_text(def) if (def != null and def is MilestoneDef) else ms_id
		milestones_container.add_child(item)
		_milestone_items[ms_id] = item

	_update_states()

func _maybe_rebuild_milestones() -> void:
	if milestones_container == null:
		return

	var desired_ids := _get_desired_milestone_ids()
	var current_ids: Array[String] = []
	for k in _milestone_items.keys():
		current_ids.append(str(k))
	current_ids.sort()

	if desired_ids != current_ids:
		_rebuild_milestones()
	else:
		_update_states()

func _get_desired_milestone_ids() -> Array[String]:
	var set := {}
	if _global_view:
		for v in _milestone_pool:
			var mid := str(v)
			if mid.is_empty():
				continue
			set[mid] = true
		for pid in range(_players.size()):
			var p_val = _players[pid]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			for m in Array(p.get("milestones", [])):
				var mid2 := str(m)
				if mid2.is_empty():
					continue
				set[mid2] = true
	else:
		for v in _player_milestones:
			var mid := str(v)
			if mid.is_empty():
				continue
			set[mid] = true

	var ids: Array[String] = []
	for k in set.keys():
		ids.append(str(k))

	ids.sort()
	return ids

func _update_states() -> void:
	var pool_counts := {}
	for v in _milestone_pool:
		var mid := str(v)
		if mid.is_empty():
			continue
		pool_counts[mid] = int(pool_counts.get(mid, 0)) + 1

	var claimed_by: Dictionary = {}  # milestone_id -> Array[int]
	if _global_view:
		for pid in range(_players.size()):
			var p_val = _players[pid]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			for m in Array(p.get("milestones", [])):
				var mid2 := str(m)
				if mid2.is_empty():
					continue
				if not claimed_by.has(mid2):
					claimed_by[mid2] = []
				var arr: Array = claimed_by[mid2]
				if not arr.has(pid):
					arr.append(pid)
				claimed_by[mid2] = arr

	for ms_id in _milestone_items.keys():
		var item: MilestoneItem = _milestone_items[ms_id]
		if is_instance_valid(item):
			var is_claimed := false
			var owners: Array = []
			if _global_view:
				owners = Array(claimed_by.get(ms_id, []))
				is_claimed = not owners.is_empty()
			else:
				is_claimed = _player_milestones.has(ms_id)
			var pool_count := int(pool_counts.get(ms_id, 0))
			item.set_state(is_claimed, pool_count, owners)

func _on_close_pressed() -> void:
	cancelled.emit()

func _format_milestone_effect_text(def: MilestoneDef) -> String:
	if def == null:
		return ""

	var lines: Array[String] = []

	# effects.type（MilestoneEffectRegistry）
	for e_val in def.effects:
		if not (e_val is Dictionary):
			continue
		var eff: Dictionary = e_val
		var t := str(eff.get("type", "")).strip_edges()
		if t.is_empty():
			continue
		var line := _describe_effect_dict(t, eff)
		if not line.is_empty():
			lines.append(line)

	# effect_ids（EffectRegistry，通过结算阶段分段调用）
	for eid_val in def.effect_ids:
		var eid := str(eid_val).strip_edges()
		if eid.is_empty():
			continue
		var line2 := _describe_effect_id(eid)
		if not line2.is_empty():
			lines.append(line2)

	# 某些里程碑的行为由模块规则通过“是否拥有该里程碑”判断实现（effects 可能为 noop）
	lines.append_array(_describe_milestone_id(def.id))

	# 去重（保序）
	var seen := {}
	var out: Array[String] = []
	for s0 in lines:
		var s := str(s0).strip_edges()
		if s.is_empty():
			continue
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)

	return "\n".join(out)

func _describe_milestone_id(milestone_id: String) -> Array[String]:
	match milestone_id:
		"first_campaign_manager_used":
			return ["本回合获得后：活动经理（campaign_manager）营销可额外放置第二张同类型板件（一次）"]
		"first_brand_manager_used":
			return ["本回合获得后：品牌经理（brand_manager）飞机营销可追加第二种商品（一次）"]
		"first_brand_director_used":
			return [
				"你的电波营销永久生效",
				"品牌总监（brand_director）忙碌到游戏结束",
			]
		"first_new_restaurant":
			return ["解锁动作：放置餐厅阶段可免费放置1个永久邮箱（mailbox#7-#10，不绑定营销员，需与自家餐厅同街区）"]
		"first_burger_sold":
			return ["CEO 卡槽至少为 4（永久）"]
		"first_pizza_sold":
			return ["首次卖出披萨后：前3个买披萨的房屋，对应卖家需放置1张持续2回合的披萨电波营销（未处理完会阻止阶段推进）"]
		_:
			return []

func _describe_effect_dict(effect_type: String, effect: Dictionary) -> String:
	var from_reg := EffectUiTextRegistryClass.get_milestone_effect_type_text(effect_type)
	if not from_reg.is_empty():
		return from_reg

	match effect_type:
		"noop":
			return ""
		"gain_card":
			var v := str(effect.get("value", "")).strip_edges()
			if v.is_empty():
				return "获得员工卡"
			return "获得员工卡：%s（手牌）" % _get_employee_name(v)
		"gain_cards":
			var list_val = effect.get("value", null)
			if not (list_val is Array):
				return "获得员工卡（多张）"
			var names: Array[String] = []
			for item in list_val:
				var id := str(item).strip_edges()
				if id.is_empty():
					continue
				names.append(_get_employee_name(id))
			return "获得员工卡：%s（手牌）" % "、".join(names) if not names.is_empty() else "获得员工卡（手牌）"
		"peek_reserve_cards":
			return "可以查看全部储备卡"
		"ban_card":
			var target := str(effect.get("target", "")).strip_edges()
			if target.is_empty():
				return "禁用员工卡"
			return "禁用员工卡：%s（你不能再获得它）" % _get_employee_name(target)
		"multi_trainer_on_one":
			return "培训：允许链式培训/连续培训同一员工"
		"base_price_delta":
			var v := _format_signed_int(effect.get("value", null))
			return "基础单价%s" % v if not v.is_empty() else "基础单价调整"
		"sell_bonus":
			var product := str(effect.get("product", "")).strip_edges()
			var value := _format_signed_int(effect.get("value", null), true)
			var name := _get_product_category_name(product)
			if value.is_empty():
				return "营销售卖奖励：%s" % name
			return "营销售卖奖励：每卖出1个%s%s" % [name, value]
		"salary_total_delta":
			var v := _format_signed_int(effect.get("value", null))
			return "发薪总额%s" % v if not v.is_empty() else "发薪总额调整"
		"gain_fridge":
			var cap := _format_positive_int(effect.get("value", null))
			return "获得冰箱：清理阶段食物+饮料总量最多保留%s" % cap if not cap.is_empty() else "获得冰箱"
		"waitress_tips":
			var v := _format_positive_int(effect.get("value", null))
			return "晚餐：每位女服务员小费%s" % v if not v.is_empty() else "晚餐：女服务员小费提升"
		"procure_plus_one":
			var v := _format_positive_int(effect.get("value", null))
			return "采购饮品：每个来源额外+%s" % v if not v.is_empty() else "采购饮品：每个来源额外+1"
		"drinks_per_source_delta":
			var targets := _get_effect_targets(effect)
			var v := _format_positive_int(effect.get("value", null))
			var who := _format_employee_list(targets)
			if who.is_empty():
				who = "指定员工"
			return "%s采购：每个来源额外+%s" % [who, v] if not v.is_empty() else "%s采购：每个来源额外加成" % who
		"distance_plus_one":
			var targets := _get_effect_targets(effect)
			var who := _format_employee_list(targets)
			if who.is_empty():
				who = "指定员工"
			return "%s采购距离+1" % who
		"marketing_no_salary":
			return "营销员工免薪"
		"marketing_permanent":
			return "之后放置的营销活动永久生效"
		"turnorder_empty_slots":
			var v := _format_positive_int(effect.get("value", null))
			return "决定顺序：空卡槽加成+%s" % v if not v.is_empty() else "决定顺序：空卡槽加成"
		"ceo_get_cfo":
			return "从下一回合起：晚餐收入获得 CFO 加成"
		"extra_marketing":
			var t := str(effect.get("value", "")).strip_edges()
			if t == "radio":
				return "电波营销：每房屋放置2个需求（而非1个）"
			return "营销强化"
		"train_from_active_same_color":
			return "培训：允许从在职员工培训（同色限制）"
		"salary_pay_with_tokens":
			return "发薪：可用食物/饮品库存抵扣"
		"salary_allow_unpaid":
			return "发薪：允许欠薪"
		"salary_cost_override":
			var v := _format_positive_int(effect.get("value", null))
			return "工资单价改为%s" % v if not v.is_empty() else "工资单价调整"
		"employee_no_salary":
			var target := str(effect.get("target", "")).strip_edges()
			return "%s免薪" % _get_employee_name(target) if not target.is_empty() else "指定员工免薪"
		"bank_burn_on_discount_ge_3":
			return "使用折扣（-$3）后：下回合重组结束时银行移除最多$100"
		_:
			return "效果：%s" % effect_type

func _describe_effect_id(effect_id: String) -> String:
	var from_reg := EffectUiTextRegistryClass.get_effect_id_text(effect_id)
	if not from_reg.is_empty():
		return from_reg

	match effect_id:
		"base_rules:marketing:demand_amount:first_radio":
			return "电波营销：每房屋放置2个需求（而非1个）"
		"base_rules:dinnertime:income_bonus:ceo_get_cfo":
			var percent := int(_rules.get("cfo_bonus_percent", 0))
			if percent > 0:
				return "晚餐收入：CFO 加成 +%d%%（向上取整）" % percent
			return "晚餐收入：CFO 加成（向上取整）"
		_:
			return ""

func _get_effect_targets(effect: Dictionary) -> Array[String]:
	var targets_val = effect.get("targets", null)
	if not (targets_val is Array):
		return []
	var out: Array[String] = []
	for v in targets_val:
		var s := str(v).strip_edges()
		if s.is_empty():
			continue
		out.append(s)
	return out

func _format_employee_list(employee_ids: Array[String]) -> String:
	if employee_ids.is_empty():
		return ""
	var names: Array[String] = []
	for eid in employee_ids:
		var id := str(eid).strip_edges()
		if id.is_empty():
			continue
		names.append(_get_employee_name(id))
	return "、".join(names)

func _get_employee_name(employee_id: String) -> String:
	if employee_id.is_empty():
		return ""
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val != null and def_val is EmployeeDef:
			return str((def_val as EmployeeDef).name)
	return employee_id

func _get_product_category_name(product: String) -> String:
	match product:
		"burger":
			return "汉堡"
		"pizza":
			return "披萨"
		"drink":
			return "饮品"
		_:
			# 容错：回退到 ProductRegistry 名称或原 id
			if not product.is_empty() and ProductRegistryClass.is_loaded():
				var def_val = ProductRegistryClass.get_def(product)
				if def_val != null and def_val is ProductDef:
					return str((def_val as ProductDef).name)
			return product if not product.is_empty() else "商品"

func _format_positive_int(value) -> String:
	if value is int:
		var i := int(value)
		return str(i) if i >= 0 else ""
	if value is float:
		var f := float(value)
		if f == floor(f) and int(f) >= 0:
			return str(int(f))
	return ""

func _format_signed_int(value, force_plus: bool = false) -> String:
	if value is int:
		var i := int(value)
		if i == 0:
			return "+0" if force_plus else "0"
		if i > 0:
			return "+%d" % i
		return str(i)
	if value is float:
		var f := float(value)
		if f == floor(f):
			return _format_signed_int(int(f), force_plus)
	return ""


# === 内部类：里程碑项 ===
class MilestoneItem extends PanelContainer:
	var milestone_id: String = ""

	var milestone_def = null  # MilestoneDef | null
	var effect_text: String = ""
	var global_view: bool = false

	var _is_claimed: bool = false
	var _pool_count: int = 0
	var _claimed_by_players: Array[int] = []

	var _name_label: Label
	var _desc_label: Label
	var _status_label: Label

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(0, 70)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		add_child(hbox)

		# 左侧：信息
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.add_theme_constant_override("separation", 4)
		hbox.add_child(info_box)

		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 15)
		UiStylesClass.apply_label_dark(_name_label)
		_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(_name_label)

		_desc_label = Label.new()
		_desc_label.add_theme_font_size_override("font_size", 12)
		UiStylesClass.apply_label_hint_dark(_desc_label)
		_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(_desc_label)

		# 右侧：状态/按钮
		var right_box := VBoxContainer.new()
		right_box.custom_minimum_size = Vector2(80, 0)
		right_box.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(right_box)

		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 12)
		UiStylesClass.apply_label_hint_dark(_status_label)
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_box.add_child(_status_label)

		update_display()
		_update_style()

	func update_display() -> void:
		if _name_label != null:
			var name := milestone_id
			if milestone_def != null and milestone_def is MilestoneDef:
				name = str((milestone_def as MilestoneDef).name)
			name = _strip_id_suffix(name)
			_name_label.text = name
			_name_label.tooltip_text = name

		if _desc_label != null:
			var text := effect_text
			if text.is_empty():
				text = milestone_id
			_desc_label.text = text

	func _strip_id_suffix(raw_name: String) -> String:
		var s := str(raw_name).strip_edges()
		var mid := str(milestone_id).strip_edges()
		if mid.is_empty():
			return s

		var suffixes: Array[String] = [
			" (" + mid + ")",
			"(" + mid + ")",
			" （" + mid + "）",
			"（" + mid + "）",
		]
		for suffix in suffixes:
			if s.ends_with(suffix):
				s = s.substr(0, s.length() - suffix.length()).strip_edges()
				break
		return s

	func set_state(claimed: bool, pool_count: int, claimed_by_players: Array = []) -> void:
		_is_claimed = claimed
		_pool_count = pool_count
		_claimed_by_players = []
		for v in Array(claimed_by_players):
			if v is int:
				_claimed_by_players.append(int(v))

		if _status_label != null:
			if global_view:
				var parts: Array[String] = []
				if not _claimed_by_players.is_empty():
					_claimed_by_players.sort()
					var names: Array[String] = []
					for pid in _claimed_by_players:
						var n := ""
						if Globals != null and Globals.has_method("get_player_name"):
							n = str(Globals.get_player_name(pid))
						if n.is_empty():
							n = "玩家%d" % (pid + 1)
						names.append(n)
					parts.append("已获得：%s" % "、".join(names))
				if pool_count > 0:
					parts.append("供应x%d" % pool_count)
				_status_label.text = "\n".join(parts)
				UiStylesClass.apply_label_hint_dark(_status_label)
				_status_label.visible = not parts.is_empty()
			else:
				if claimed:
					_status_label.text = "已获得"
					UiStylesClass.apply_label_success(_status_label)
					_status_label.visible = true
				elif pool_count > 0:
					_status_label.text = "供应x%d" % pool_count
					UiStylesClass.apply_label_hint_dark(_status_label)
					_status_label.visible = true
				else:
					_status_label.text = ""
					_status_label.visible = false

		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if _is_claimed and not global_view:
			style.bg_color = Color(UiStylesClass.COLOR_FIELD_BG.r, UiStylesClass.COLOR_FIELD_BG.g, UiStylesClass.COLOR_FIELD_BG.b, 0.86)
			style.border_color = Color(UiStylesClass.COLOR_TEXT_SUCCESS.r, UiStylesClass.COLOR_TEXT_SUCCESS.g, UiStylesClass.COLOR_TEXT_SUCCESS.b, 0.45)
			style.set_border_width_all(1)
		elif _pool_count > 0:
			style.bg_color = Color(UiStylesClass.COLOR_FIELD_BG.r, UiStylesClass.COLOR_FIELD_BG.g, UiStylesClass.COLOR_FIELD_BG.b, 0.92)
			style.border_color = Color(UiStylesClass.COLOR_TEXT_HINT.r, UiStylesClass.COLOR_TEXT_HINT.g, UiStylesClass.COLOR_TEXT_HINT.b, 0.36)
			style.set_border_width_all(1)
		elif _is_claimed and global_view:
			style.bg_color = Color(UiStylesClass.COLOR_FIELD_BG.r, UiStylesClass.COLOR_FIELD_BG.g, UiStylesClass.COLOR_FIELD_BG.b, 0.86)
			style.border_color = Color(UiStylesClass.COLOR_TEXT_SUCCESS.r, UiStylesClass.COLOR_TEXT_SUCCESS.g, UiStylesClass.COLOR_TEXT_SUCCESS.b, 0.45)
			style.set_border_width_all(1)
		else:
			style.bg_color = Color(UiStylesClass.COLOR_FIELD_BG_DISABLED.r, UiStylesClass.COLOR_FIELD_BG_DISABLED.g, UiStylesClass.COLOR_FIELD_BG_DISABLED.b, 0.82)
			style.border_color = Color(UiStylesClass.COLOR_FIELD_BORDER.r, UiStylesClass.COLOR_FIELD_BORDER.g, UiStylesClass.COLOR_FIELD_BORDER.b, 0.2)
			style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)

		# 供应池以外变暗
		if not _is_claimed and _pool_count <= 0:
			modulate = Color(0.82, 0.82, 0.82, 0.92)
		else:
			modulate = Color(1, 1, 1, 1)
