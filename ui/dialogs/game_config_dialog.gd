# 高级游戏配置弹窗
# 允许在游戏开始前调整 game_config.json 中的参数
extends ModalDialogBase

signal config_confirmed(overrides: Dictionary)

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const GameConfigClass = preload("res://core/data/game_config.gd")

@onready var background_panel: Panel = $BackgroundPanel
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var page_panel: PanelContainer = $MarginContainer/VBoxContainer/ContentHBox/PagePanel
@onready var confirm_btn: Button = %ConfirmButton
@onready var reset_btn: Button = %ResetButton

@onready var bank_nav_btn: Button = %BankNavBtn
@onready var rules_nav_btn: Button = %RulesNavBtn
@onready var player_nav_btn: Button = %PlayerNavBtn

@onready var bank_page: VBoxContainer = %BankPage
@onready var rules_page: VBoxContainer = %RulesPage
@onready var player_page: VBoxContainer = %PlayerPage

@onready var bank_scroll: ScrollContainer = %BankScroll
@onready var rules_scroll: ScrollContainer = %RulesScroll
@onready var player_scroll: ScrollContainer = %PlayerScroll

var _nav_buttons: Array[Button] = []
var _page_scrolls: Array[Control] = []
var _current_page_index: int = 0

# 默认配置（从 game_config.json 加载）
var _default_cfg: GameConfig = null

# SpinBox 引用
var _spin_bank_per_player: SpinBox = null
var _spin_base_unit_price: SpinBox = null
var _spin_salary_cost: SpinBox = null
var _spin_waitress_tips: SpinBox = null
var _spin_cfo_bonus_percent: SpinBox = null
var _spin_demand_cap_normal: SpinBox = null
var _spin_demand_cap_with_garden: SpinBox = null
var _spin_fridge_capacity: SpinBox = null
var _spin_one_x_copies: Dictionary = {} # "2" -> SpinBox, "3" -> SpinBox, ...
var _spin_starting_cash: SpinBox = null
var _spin_ceo_slots: SpinBox = null
var _spin_reserve_card_selected: SpinBox = null
var _reserve_card_spins: Array[Dictionary] = [] # [{type, cash, ceo_slots}]

# 当前覆盖值
var _overrides: Dictionary = {}

func _ready() -> void:
	super._ready()
	UiStylesClass.apply_dialog_surface(background_panel)
	UiStylesClass.apply_button_primary(confirm_btn)
	UiStylesClass.apply_button_secondary(reset_btn)
	UiStylesClass.apply_panel_poster_alt(page_panel)
	UiStylesClass.apply_label_dark(title_label)

	_nav_buttons = [bank_nav_btn, rules_nav_btn, player_nav_btn]
	_page_scrolls = [bank_scroll, rules_scroll, player_scroll]

	for i in range(_nav_buttons.size()):
		var btn := _nav_buttons[i]
		if btn != null:
			btn.pressed.connect(_on_nav_pressed.bind(i))

	confirm_btn.pressed.connect(_on_confirm_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)

	_load_default_config()
	_build_bank_page()
	_build_rules_page()
	_build_player_page()
	_switch_page(0)

func _load_default_config() -> void:
	var result := GameConfigClass.load_default()
	if result.ok:
		_default_cfg = result.value
	else:
		_default_cfg = GameConfigClass.new()

# ── 导航 ──────────────────────────────────────────────

func _on_nav_pressed(index: int) -> void:
	_switch_page(index)

func _switch_page(index: int) -> void:
	_current_page_index = clampi(index, 0, _page_scrolls.size() - 1)
	for i in range(_page_scrolls.size()):
		if _page_scrolls[i] != null:
			_page_scrolls[i].visible = (i == _current_page_index)
	_update_nav_styles()

func _update_nav_styles() -> void:
	for i in range(_nav_buttons.size()):
		var btn := _nav_buttons[i]
		if btn == null:
			continue
		UiStylesClass.apply_nav_button(btn, i == _current_page_index)

# ── 银行页面 ──────────────────────────────────────────

func _build_bank_page() -> void:
	var section_label := _make_section_label("银行设置")
	bank_page.add_child(section_label)

	_spin_bank_per_player = _add_spin_row(bank_page, "每人银行资金", _default_cfg.bank_default_per_player, 0, 500, 5, "银行总额 = 玩家数 x 此值")

# ── 规则页面 ──────────────────────────────────────────

func _build_rules_page() -> void:
	var section_label := _make_section_label("规则参数")
	rules_page.add_child(section_label)

	_spin_base_unit_price = _add_spin_row(rules_page, "基础单价", _default_cfg.rule_base_unit_price, 1, 100, 1, "食物/饮料基础售价")
	_spin_salary_cost = _add_spin_row(rules_page, "员工薪资", _default_cfg.rule_salary_cost, 0, 50, 1, "每位员工每轮薪资")
	_spin_waitress_tips = _add_spin_row(rules_page, "服务员小费", _default_cfg.rule_waitress_tips, 0, 50, 1, "服务员额外收入")
	_spin_cfo_bonus_percent = _add_spin_row(rules_page, "CFO 奖金比例", _default_cfg.rule_cfo_bonus_percent, 0, 200, 5, "CFO 收入加成百分比")
	_spin_demand_cap_normal = _add_spin_row(rules_page, "普通需求上限", _default_cfg.rule_demand_cap_normal, 1, 20, 1, "每栋房屋最大需求量")
	_spin_demand_cap_with_garden = _add_spin_row(rules_page, "花园需求上限", _default_cfg.rule_demand_cap_with_garden, 1, 30, 1, "有花园时的需求上限")
	_spin_fridge_capacity = _add_spin_row(rules_page, "冰箱容量/产品", _default_cfg.rule_fridge_capacity_per_product, 1, 50, 1, "每种产品冰箱存储上限")

	# 1x 员工副本数
	var copies_sep := HSeparator.new()
	rules_page.add_child(copies_sep)
	var copies_label := _make_section_label("1x 员工副本数（按玩家人数）")
	rules_page.add_child(copies_label)

	for pc in ["2", "3", "4", "5", "6"]:
		var default_val: int = int(_default_cfg.rule_one_x_employee_copies_by_player_count.get(pc, 1))
		var spin := _add_spin_row(rules_page, "%s 人" % pc, default_val, 0, 10, 1)
		_spin_one_x_copies[pc] = spin

# ── 玩家页面 ──────────────────────────────────────────

func _build_player_page() -> void:
	var section_label := _make_section_label("玩家初始状态")
	player_page.add_child(section_label)

	_spin_starting_cash = _add_spin_row(player_page, "初始现金", _default_cfg.player_starting_cash, 0, 500, 5, "每位玩家起始资金")
	_spin_ceo_slots = _add_spin_row(player_page, "CEO 初始槽位", int(_default_cfg.player_starting_company_structure.get("ceo_slots", 3)), 1, 10, 1, "CEO 可管理的初始下属数")
	_spin_reserve_card_selected = _add_spin_row(player_page, "默认储备卡索引", _default_cfg.player_reserve_card_selected, 0, 2, 1, "默认选中的储备卡（0/1/2）")

	# 储备卡配置
	var cards_sep := HSeparator.new()
	player_page.add_child(cards_sep)
	var cards_label := _make_section_label("储备卡配置")
	player_page.add_child(cards_label)

	_reserve_card_spins.clear()
	for i in range(_default_cfg.player_reserve_cards.size()):
		var card: Dictionary = _default_cfg.player_reserve_cards[i]
		var card_label := Label.new()
		card_label.text = "储备卡 %d" % (i + 1)
		UiStylesClass.apply_label_dark(card_label)
		player_page.add_child(card_label)

		var type_spin := _add_spin_row(player_page, "  类型", int(card.get("type", 0)), 1, 100, 1)
		var cash_spin := _add_spin_row(player_page, "  现金", int(card.get("cash", 0)), 0, 500, 5)
		var slots_spin := _add_spin_row(player_page, "  CEO 槽位", int(card.get("ceo_slots", 0)), 1, 10, 1)
		_reserve_card_spins.append({"type": type_spin, "cash": cash_spin, "ceo_slots": slots_spin})

# ── UI 构建工具 ───────────────────────────────────────

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	UiStylesClass.apply_label_hint_dark(label)
	return label

func _add_spin_row(parent: VBoxContainer, label_text: String, default_value: int, min_val: int, max_val: int, step: int, hint: String = "") -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	UiStylesClass.apply_label_dark(label)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = default_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size = Vector2(100, 0)
	UiStylesClass.apply_spin_box_field(spin)
	row.add_child(spin)

	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.custom_minimum_size = Vector2(0, 0)
		hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStylesClass.apply_label_hint_dark(hint_label)
		row.add_child(hint_label)

	return spin

# ── 数据读写 ──────────────────────────────────────────

func load_overrides(overrides: Dictionary) -> void:
	_overrides = overrides.duplicate()
	_apply_overrides_to_ui()

func _apply_overrides_to_ui() -> void:
	# 先恢复默认值
	_reset_ui_to_defaults()
	# 再应用覆盖
	for key in _overrides:
		var val = _overrides[key]
		match key:
			"bank.default_per_player":
				if _spin_bank_per_player != null: _spin_bank_per_player.value = int(val)
			"rules.base_unit_price":
				if _spin_base_unit_price != null: _spin_base_unit_price.value = int(val)
			"rules.salary_cost":
				if _spin_salary_cost != null: _spin_salary_cost.value = int(val)
			"rules.waitress_tips":
				if _spin_waitress_tips != null: _spin_waitress_tips.value = int(val)
			"rules.cfo_bonus_percent":
				if _spin_cfo_bonus_percent != null: _spin_cfo_bonus_percent.value = int(val)
			"rules.demand_cap_normal":
				if _spin_demand_cap_normal != null: _spin_demand_cap_normal.value = int(val)
			"rules.demand_cap_with_garden":
				if _spin_demand_cap_with_garden != null: _spin_demand_cap_with_garden.value = int(val)
			"rules.fridge_capacity_per_product":
				if _spin_fridge_capacity != null: _spin_fridge_capacity.value = int(val)
			"rules.one_x_employee_copies_by_player_count":
				if val is Dictionary:
					for pc in val:
						if _spin_one_x_copies.has(str(pc)):
							_spin_one_x_copies[str(pc)].value = int(val[pc])
			"player.starting_cash":
				if _spin_starting_cash != null: _spin_starting_cash.value = int(val)
			"player.starting_company_structure.ceo_slots":
				if _spin_ceo_slots != null: _spin_ceo_slots.value = int(val)
			"player.reserve_card_selected":
				if _spin_reserve_card_selected != null: _spin_reserve_card_selected.value = int(val)
			"player.reserve_cards":
				if val is Array:
					for i in range(mini(val.size(), _reserve_card_spins.size())):
						var card: Dictionary = val[i] if val[i] is Dictionary else {}
						var spins: Dictionary = _reserve_card_spins[i]
						if spins.has("type"): spins["type"].value = int(card.get("type", 0))
						if spins.has("cash"): spins["cash"].value = int(card.get("cash", 0))
						if spins.has("ceo_slots"): spins["ceo_slots"].value = int(card.get("ceo_slots", 0))

func _reset_ui_to_defaults() -> void:
	if _default_cfg == null:
		return
	if _spin_bank_per_player != null: _spin_bank_per_player.value = _default_cfg.bank_default_per_player
	if _spin_base_unit_price != null: _spin_base_unit_price.value = _default_cfg.rule_base_unit_price
	if _spin_salary_cost != null: _spin_salary_cost.value = _default_cfg.rule_salary_cost
	if _spin_waitress_tips != null: _spin_waitress_tips.value = _default_cfg.rule_waitress_tips
	if _spin_cfo_bonus_percent != null: _spin_cfo_bonus_percent.value = _default_cfg.rule_cfo_bonus_percent
	if _spin_demand_cap_normal != null: _spin_demand_cap_normal.value = _default_cfg.rule_demand_cap_normal
	if _spin_demand_cap_with_garden != null: _spin_demand_cap_with_garden.value = _default_cfg.rule_demand_cap_with_garden
	if _spin_fridge_capacity != null: _spin_fridge_capacity.value = _default_cfg.rule_fridge_capacity_per_product
	for pc in _spin_one_x_copies:
		_spin_one_x_copies[pc].value = int(_default_cfg.rule_one_x_employee_copies_by_player_count.get(pc, 1))
	if _spin_starting_cash != null: _spin_starting_cash.value = _default_cfg.player_starting_cash
	if _spin_ceo_slots != null: _spin_ceo_slots.value = int(_default_cfg.player_starting_company_structure.get("ceo_slots", 3))
	if _spin_reserve_card_selected != null: _spin_reserve_card_selected.value = _default_cfg.player_reserve_card_selected
	for i in range(mini(_default_cfg.player_reserve_cards.size(), _reserve_card_spins.size())):
		var card: Dictionary = _default_cfg.player_reserve_cards[i]
		var spins: Dictionary = _reserve_card_spins[i]
		if spins.has("type"): spins["type"].value = int(card.get("type", 0))
		if spins.has("cash"): spins["cash"].value = int(card.get("cash", 0))
		if spins.has("ceo_slots"): spins["ceo_slots"].value = int(card.get("ceo_slots", 0))

func _collect_overrides_from_ui() -> Dictionary:
	var result: Dictionary = {}
	if _default_cfg == null:
		return result

	# 只收集与默认值不同的字段
	if _spin_bank_per_player != null and int(_spin_bank_per_player.value) != _default_cfg.bank_default_per_player:
		result["bank.default_per_player"] = int(_spin_bank_per_player.value)
	if _spin_base_unit_price != null and int(_spin_base_unit_price.value) != _default_cfg.rule_base_unit_price:
		result["rules.base_unit_price"] = int(_spin_base_unit_price.value)
	if _spin_salary_cost != null and int(_spin_salary_cost.value) != _default_cfg.rule_salary_cost:
		result["rules.salary_cost"] = int(_spin_salary_cost.value)
	if _spin_waitress_tips != null and int(_spin_waitress_tips.value) != _default_cfg.rule_waitress_tips:
		result["rules.waitress_tips"] = int(_spin_waitress_tips.value)
	if _spin_cfo_bonus_percent != null and int(_spin_cfo_bonus_percent.value) != _default_cfg.rule_cfo_bonus_percent:
		result["rules.cfo_bonus_percent"] = int(_spin_cfo_bonus_percent.value)
	if _spin_demand_cap_normal != null and int(_spin_demand_cap_normal.value) != _default_cfg.rule_demand_cap_normal:
		result["rules.demand_cap_normal"] = int(_spin_demand_cap_normal.value)
	if _spin_demand_cap_with_garden != null and int(_spin_demand_cap_with_garden.value) != _default_cfg.rule_demand_cap_with_garden:
		result["rules.demand_cap_with_garden"] = int(_spin_demand_cap_with_garden.value)
	if _spin_fridge_capacity != null and int(_spin_fridge_capacity.value) != _default_cfg.rule_fridge_capacity_per_product:
		result["rules.fridge_capacity_per_product"] = int(_spin_fridge_capacity.value)

	# 1x 员工副本数
	var copies_changed := false
	var copies_dict: Dictionary = {}
	for pc in ["2", "3", "4", "5", "6"]:
		var ui_val := int(_spin_one_x_copies[pc].value) if _spin_one_x_copies.has(pc) else 0
		var default_val := int(_default_cfg.rule_one_x_employee_copies_by_player_count.get(pc, 1))
		copies_dict[pc] = ui_val
		if ui_val != default_val:
			copies_changed = true
	if copies_changed:
		result["rules.one_x_employee_copies_by_player_count"] = copies_dict

	if _spin_starting_cash != null and int(_spin_starting_cash.value) != _default_cfg.player_starting_cash:
		result["player.starting_cash"] = int(_spin_starting_cash.value)
	if _spin_ceo_slots != null and int(_spin_ceo_slots.value) != int(_default_cfg.player_starting_company_structure.get("ceo_slots", 3)):
		result["player.starting_company_structure.ceo_slots"] = int(_spin_ceo_slots.value)
	if _spin_reserve_card_selected != null and int(_spin_reserve_card_selected.value) != _default_cfg.player_reserve_card_selected:
		result["player.reserve_card_selected"] = int(_spin_reserve_card_selected.value)

	# 储备卡
	var cards_changed := false
	var cards_arr: Array[Dictionary] = []
	for i in range(_reserve_card_spins.size()):
		var spins: Dictionary = _reserve_card_spins[i]
		var ui_card: Dictionary = {
			"type": int(spins["type"].value),
			"cash": int(spins["cash"].value),
			"ceo_slots": int(spins["ceo_slots"].value),
		}
		cards_arr.append(ui_card)
		if i < _default_cfg.player_reserve_cards.size():
			var def_card: Dictionary = _default_cfg.player_reserve_cards[i]
			if ui_card["type"] != int(def_card.get("type", 0)) or ui_card["cash"] != int(def_card.get("cash", 0)) or ui_card["ceo_slots"] != int(def_card.get("ceo_slots", 0)):
				cards_changed = true
	if cards_changed:
		result["player.reserve_cards"] = cards_arr

	return result

# ── 按钮事件 ──────────────────────────────────────────

func _on_confirm_pressed() -> void:
	_overrides = _collect_overrides_from_ui()
	config_confirmed.emit(_overrides)
	close()

func _on_reset_pressed() -> void:
	_overrides = {}
	_reset_ui_to_defaults()
	config_confirmed.emit(_overrides)
	close()

func _grab_default_focus() -> void:
	if confirm_btn != null:
		confirm_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

func get_override_count() -> int:
	return _overrides.size()
