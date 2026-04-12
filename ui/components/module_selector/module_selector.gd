# 模块选择面板（复用 Hotseat 的分组/依赖/冲突处理逻辑）
extends VBoxContainer

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")
const ModulePlanBuilderClass = preload("res://core/modules/v2/module_plan_builder.gd")
const ModuleSelectorLogicClass = preload("res://ui/components/module_selector/module_selector_logic.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

signal selection_changed(enabled_modules_v2: Array)
signal notes_changed(text: String)
signal load_failed(message: String)
signal game_options_changed(options: Dictionary)

const _GROUP_BG_COLORS: Array[Color] = [
	Color(0.95, 0.90, 0.80, 0.62),
	Color(0.94, 0.87, 0.74, 0.62),
	Color(0.92, 0.84, 0.70, 0.62),
	Color(0.96, 0.89, 0.77, 0.62),
	Color(0.91, 0.83, 0.67, 0.62),
	Color(0.93, 0.86, 0.72, 0.62),
]

var _modules_base_dir_spec: String = ""
var _setup_player_count: int = 0

var _available_modules: Dictionary = {} # module_id -> ModuleManifest
var _optional_module_ids: Array[String] = []
var _logic = ModuleSelectorLogicClass.new()
var _module_checkboxes: Dictionary = {} # module_id -> CheckBox
var _requested_optional_modules: Dictionary = {} # module_id -> true（用户显式选择）
var _locked_optional_modules: Dictionary = {} # module_id -> true（被依赖，禁止取消）
var _forced_optional_modules: Dictionary = {} # module_id -> reason（外部约束强制启用/锁定）

var _suppress_signals: bool = false
var _editable: bool = true

var _show_tooltips: bool = true
var _show_notes: bool = true
var _show_game_options: bool = false
var _options_editable: bool = true

# 游戏选项（非模块）：用于在 Setup 前调整少量核心规则预设
const _OPT_ID_SHORT_GAME := "short_game"
const _OPT_ID_NO_MILESTONES := "no_milestones"
const _OPT_ID_FIRST_TIME := "first_time_experience"
const _OPT_ID_NO_CFO_MILESTONE := "no_cfo_milestone"
const _OPT_ID_NO_BROADCAST_MILESTONE := "no_broadcast_milestone"

var _opt_short_game: bool = false
var _opt_no_milestones: bool = false
var _opt_no_cfo_milestone: bool = false
var _opt_no_broadcast_milestone: bool = false
var _suppress_game_option_signals: bool = false

var _opt_count_label: Label = null
var _opt_short_game_cb: CheckBox = null
var _opt_no_milestones_cb: CheckBox = null
var _opt_first_time_cb: CheckBox = null
var _opt_no_cfo_cb: CheckBox = null
var _opt_no_broadcast_cb: CheckBox = null

var _header_row: HBoxContainer = null
var _groups_container: GridContainer = null
var _notes_label: Label = null
var _action_buttons: Array = [] # BaseButton
var _group_select_checkboxes: Dictionary = {} # group_id -> CheckBox
var _group_module_ids: Dictionary = {} # group_id -> Array[String]
var _group_count_labels: Dictionary = {} # group_id -> Label

func _ready() -> void:
	_ensure_base_ui()

func set_show_tooltips(show: bool) -> void:
	_ensure_base_ui()
	_show_tooltips = bool(show)
	_recompute_modules_and_apply_to_ui()
	_refresh_game_options_ui()

func set_show_notes(show: bool) -> void:
	_ensure_base_ui()
	_show_notes = bool(show)
	_recompute_modules_and_apply_to_ui()

func set_show_game_options(show: bool) -> void:
	_ensure_base_ui()
	_show_game_options = bool(show)
	# 仅影响 UI 布局，不应影响模块选择
	_build_modules_ui()
	_recompute_modules_and_apply_to_ui()

func set_editable(editable: bool) -> void:
	_ensure_base_ui()
	_editable = bool(editable)
	_options_editable = bool(editable)
	for btn in _action_buttons:
		if btn != null and is_instance_valid(btn):
			btn.disabled = not editable
	_recompute_modules_and_apply_to_ui()
	_refresh_game_options_ui()

func set_modules_editable(editable: bool) -> void:
	_ensure_base_ui()
	_editable = bool(editable)
	for btn in _action_buttons:
		if btn != null and is_instance_valid(btn):
			btn.disabled = not _editable
	_recompute_modules_and_apply_to_ui()

func set_game_options_editable(editable: bool) -> void:
	_ensure_base_ui()
	_options_editable = bool(editable)
	_refresh_game_options_ui()

func get_game_options() -> Dictionary:
	return {
		_OPT_ID_SHORT_GAME: _opt_short_game,
		_OPT_ID_NO_MILESTONES: _opt_no_milestones,
		_OPT_ID_FIRST_TIME: _opt_short_game and _opt_no_milestones,
		_OPT_ID_NO_CFO_MILESTONE: _opt_no_cfo_milestone,
		_OPT_ID_NO_BROADCAST_MILESTONE: _opt_no_broadcast_milestone,
	}

func get_game_config_overrides_patch() -> Dictionary:
	var out: Dictionary = {}

	if _opt_short_game:
		out["bank.default_per_player"] = 75
		out["rules.salary_cost"] = 0
		out["rules.bankruptcy_max_breaks"] = 1
		out["rules.bankruptcy_extra_reserve_per_player"] = 0
		out["setup.auto_select_reserve_cards"] = true

	if _opt_no_milestones:
		out["milestones.enabled"] = false
	else:
		var disabled: Array[String] = []
		if _opt_no_cfo_milestone:
			disabled.append("first_have_100")
		if _opt_no_broadcast_milestone:
			disabled.append("first_radio")
		if not disabled.is_empty():
			out["milestones.disabled_ids"] = disabled

	return out

func get_tutorial_targets() -> Dictionary:
	return {
		"module_selector_root": self,
		"game_options_root": _groups_container,
		"first_time_option": _opt_first_time_cb,
	}

func set_game_options_from_overrides_patch(overrides_patch: Dictionary) -> void:
	_ensure_base_ui()
	var patch: Dictionary = Dictionary(overrides_patch) if overrides_patch is Dictionary else {}
	var salary_cost := int(patch.get("rules.salary_cost", -1))
	var bankruptcy_breaks := int(patch.get("rules.bankruptcy_max_breaks", -1))
	var bank_default_per_player := int(patch.get("bank.default_per_player", -1))
	var bankruptcy_reserve := int(patch.get("rules.bankruptcy_extra_reserve_per_player", -1))
	var auto_select_reserve_cards := bool(patch.get("setup.auto_select_reserve_cards", false))
	var is_legacy_short_game := salary_cost == 0 and bankruptcy_breaks == 1 and bankruptcy_reserve == 75
	var is_current_short_game := salary_cost == 0 and bankruptcy_breaks == 1 and bank_default_per_player == 75 and auto_select_reserve_cards
	_opt_short_game = is_current_short_game or is_legacy_short_game

	var milestones_enabled := true
	if patch.has("milestones.enabled"):
		milestones_enabled = bool(patch.get("milestones.enabled", true))
	_opt_no_milestones = not milestones_enabled

	var disabled_ids: Array = []
	var disabled_val = patch.get("milestones.disabled_ids", null)
	if disabled_val is Array:
		disabled_ids = Array(disabled_val)
	_opt_no_cfo_milestone = disabled_ids.has("first_have_100")
	_opt_no_broadcast_milestone = disabled_ids.has("first_radio")
	_refresh_game_options_ui()

func set_modules_base_dir(base_dir_spec: String) -> Result:
	_ensure_base_ui()
	_modules_base_dir_spec = str(base_dir_spec)
	return _load_modules_and_build_ui()

func set_setup_player_count(player_count: int) -> void:
	# 用于 Setup/RoomConfig：根据 module.json 的 setup_constraints 自动强制启用模块。
	_setup_player_count = int(player_count)
	if _available_modules.is_empty():
		return
	_refresh_forced_optional_modules_for_setup_context()
	_recompute_modules_and_apply_to_ui()

func set_initial_enabled_modules_v2(enabled_modules_v2: Array) -> void:
	_requested_optional_modules.clear()
	for mid_val in enabled_modules_v2:
		var id := str(mid_val).strip_edges()
		if id.is_empty():
			continue
		if id.begins_with("base_"):
			continue
		_requested_optional_modules[id] = true
	_recompute_modules_and_apply_to_ui()

func set_forced_optional_modules(module_ids: Array, reason: String = "") -> void:
	# 仅影响“可选模块”（非 base_*）。用于 UI 层对规则书约束做强制启用/锁定。
	_forced_optional_modules.clear()
	var r := str(reason).strip_edges()
	for mid_val in module_ids:
		var id := str(mid_val).strip_edges()
		if id.is_empty():
			continue
		if id.begins_with("base_"):
			continue
		_forced_optional_modules[id] = r
	_recompute_modules_and_apply_to_ui()

func get_enabled_modules_v2() -> Array[String]:
	var base: Array[String] = GameDefaultsClass.build_default_enabled_modules_v2()

	var effective_optional := _logic.compute_effective_optional_modules(_requested_optional_modules, _forced_optional_modules)
	var removed_base := _logic.compute_removed_base_modules_from_conflicts(effective_optional)
	for base_id in removed_base.keys():
		base.erase(str(base_id))

	var requested: Array[String] = []
	var seen := {}
	for mid_val in _requested_optional_modules.keys():
		var id := str(mid_val)
		if id.is_empty() or id.begins_with("base_"):
			continue
		seen[id] = true
		requested.append(id)
	for mid_val2 in _forced_optional_modules.keys():
		var id2 := str(mid_val2)
		if id2.is_empty() or id2.begins_with("base_"):
			continue
		if seen.has(id2):
			continue
		requested.append(id2)
	requested.sort()

	var out: Array[String] = []
	out.append_array(base)
	out.append_array(requested)
	return Array(out, TYPE_STRING, "", null)

func validate_selection() -> Result:
	if _available_modules.is_empty():
		return Result.failure("模块列表为空")
	var enabled := get_enabled_modules_v2()
	return ModulePlanBuilderClass.build_plan(_available_modules, enabled)

func _ensure_base_ui() -> void:
	if _header_row != null and is_instance_valid(_header_row):
		return

	# 组件自身的布局
	add_theme_constant_override("separation", 8)

	_header_row = HBoxContainer.new()
	_header_row.name = "HeaderRow"
	_header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_header_row.add_theme_constant_override("separation", 10)
	add_child(_header_row)

	var modules_label := Label.new()
	modules_label.text = "模块与选项"
	modules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_label_dark(modules_label)
	_header_row.add_child(modules_label)

	var select_all_btn := Button.new()
	select_all_btn.text = "全选"
	select_all_btn.custom_minimum_size = Vector2(72, 30)
	UiStylesClass.apply_button_secondary(select_all_btn)
	select_all_btn.pressed.connect(_on_select_all_modules_pressed)
	_header_row.add_child(select_all_btn)
	_action_buttons.append(select_all_btn)

	var clear_all_btn := Button.new()
	clear_all_btn.text = "全不选"
	clear_all_btn.custom_minimum_size = Vector2(72, 30)
	UiStylesClass.apply_button_secondary(clear_all_btn)
	clear_all_btn.pressed.connect(_on_clear_all_modules_pressed)
	_header_row.add_child(clear_all_btn)
	_action_buttons.append(clear_all_btn)

	_groups_container = GridContainer.new()
	_groups_container.name = "Groups"
	_groups_container.columns = 2
	_groups_container.add_theme_constant_override("h_separation", 16)
	_groups_container.add_theme_constant_override("v_separation", 14)
	add_child(_groups_container)

	_notes_label = Label.new()
	_notes_label.name = "NotesLabel"
	_notes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_notes_label.visible = false
	UiStylesClass.apply_label_hint_dark(_notes_label)
	add_child(_notes_label)

func _set_notes(text: String) -> void:
	var s := str(text).strip_edges()
	if _notes_label == null or not is_instance_valid(_notes_label):
		return
	if not _show_notes:
		_notes_label.text = ""
		_notes_label.visible = false
		notes_changed.emit("")
		return
	_notes_label.text = s
	_notes_label.visible = not s.is_empty()
	notes_changed.emit(s)

func _load_modules_and_build_ui() -> Result:
	_available_modules.clear()
	_optional_module_ids.clear()

	var base_dirs_read = ModuleDirSpecClass.parse_base_dirs(_modules_base_dir_spec)
	if not base_dirs_read.ok:
		var msg := "解析 modules_v2_base_dir 失败：%s" % base_dirs_read.error
		load_failed.emit(msg)
		return Result.failure(msg)
	var base_dirs: Array[String] = base_dirs_read.value

	var manifests_read := ModulePackageLoaderClass.load_all_from_dirs(base_dirs)
	if not manifests_read.ok:
		var msg2 := "加载模块列表失败：%s" % manifests_read.error
		load_failed.emit(msg2)
		return Result.failure(msg2)
	_available_modules = manifests_read.value

	for mid_val in _available_modules.keys():
		if not (mid_val is String):
			continue
		var mid: String = str(mid_val)
		if mid.begins_with("base_"):
			continue
		_optional_module_ids.append(mid)
	_optional_module_ids.sort()
	_logic.setup(_available_modules, _optional_module_ids)

	_refresh_forced_optional_modules_for_setup_context()
	_build_modules_ui()
	_recompute_modules_and_apply_to_ui()
	return Result.success()

func _build_modules_ui() -> void:
	if _groups_container == null or not is_instance_valid(_groups_container):
		return

	for child in _groups_container.get_children():
		child.queue_free()
	_module_checkboxes.clear()
	_group_select_checkboxes.clear()
	_group_module_ids.clear()
	_group_count_labels.clear()
	_opt_count_label = null
	_opt_short_game_cb = null
	_opt_no_milestones_cb = null
	_opt_first_time_cb = null
	_opt_no_cfo_cb = null
	_opt_no_broadcast_cb = null
	var kept: Array = []
	for btn in _action_buttons:
		if btn != null and is_instance_valid(btn) and btn.get_parent() == _header_row:
			kept.append(btn)
	_action_buttons = kept

	if _show_game_options:
		var bg_opt := _GROUP_BG_COLORS[_GROUP_BG_COLORS.size() - 1]
		_groups_container.add_child(_build_game_options_group_box(bg_opt))

	var groups: Array[Dictionary] = _logic.compute_module_groups()
	for i in range(groups.size()):
		var group: Dictionary = groups[i]
		var group_id := str(group.get("id", "")).strip_edges()
		var title := str(group.get("title", "")).strip_edges()
		var mids: Array[String] = Array(group.get("modules", []), TYPE_STRING, "", null)
		var bg := _GROUP_BG_COLORS[i] if i >= 0 and i < _GROUP_BG_COLORS.size() else _GROUP_BG_COLORS[_GROUP_BG_COLORS.size() - 1]
		_groups_container.add_child(_build_module_group_box(group_id, title, mids, bg))
	_refresh_game_options_ui()

func _build_group_panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.17, 0.13, 0.09, 0.2)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 12
	return sb

func _build_game_options_group_box(bg_color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.name = "GameOptionsGroup"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", _build_group_panel_style(bg_color))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title_label := Label.new()
	title_label.text = "游戏选项"
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.tooltip_text = title_label.text
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_label_dark(title_label)
	header.add_child(title_label)

	_opt_count_label = Label.new()
	_opt_count_label.text = "0/4"
	_opt_count_label.add_theme_font_size_override("font_size", 13)
	UiStylesClass.apply_label_hint_dark(_opt_count_label)
	header.add_child(_opt_count_label)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	box.add_child(inner)

	_opt_short_game_cb = CheckBox.new()
	_opt_short_game_cb.text = "短游戏(没有薪水，银行只破产一次，银行初始资金 75$每人，不使用储备卡)"
	_opt_short_game_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_check_box_field(_opt_short_game_cb)
	_opt_short_game_cb.toggled.connect(_on_short_game_option_toggled)
	inner.add_child(_opt_short_game_cb)

	_opt_no_milestones_cb = CheckBox.new()
	_opt_no_milestones_cb.text = "不使用任何里程碑"
	_opt_no_milestones_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_check_box_field(_opt_no_milestones_cb)
	_opt_no_milestones_cb.toggled.connect(_on_no_milestones_option_toggled)
	inner.add_child(_opt_no_milestones_cb)

	_opt_first_time_cb = CheckBox.new()
	_opt_first_time_cb.text = "初次体验(短游戏 + 不使用任何里程碑)"
	_opt_first_time_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_check_box_field(_opt_first_time_cb)
	_opt_first_time_cb.toggled.connect(_on_first_time_option_toggled)
	inner.add_child(_opt_first_time_cb)

	_opt_no_cfo_cb = CheckBox.new()
	_opt_no_cfo_cb.text = "不使用 CFO 里程碑"
	_opt_no_cfo_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_check_box_field(_opt_no_cfo_cb)
	_opt_no_cfo_cb.toggled.connect(_on_no_cfo_milestone_option_toggled)
	inner.add_child(_opt_no_cfo_cb)

	_opt_no_broadcast_cb = CheckBox.new()
	_opt_no_broadcast_cb.text = "不使用广播里程碑"
	_opt_no_broadcast_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_check_box_field(_opt_no_broadcast_cb)
	_opt_no_broadcast_cb.toggled.connect(_on_no_broadcast_milestone_option_toggled)
	inner.add_child(_opt_no_broadcast_cb)

	return panel

func _refresh_game_options_ui() -> void:
	if not _show_game_options:
		return

	_suppress_game_option_signals = true

	var short_tt := "无薪水；银行只破产一次；银行初始资金 $75/人；自动跳过储备卡选择"
	var no_ms_tt := "本局不触发任何里程碑奖励"
	var first_time_tt := "一键启用：短游戏 + 不使用任何里程碑"
	var no_cfo_tt := "禁用里程碑：首个拥有$100（first_have_100）"
	var no_radio_tt := "禁用里程碑：首个进行电波营销（first_radio）"

	if _opt_short_game_cb != null and is_instance_valid(_opt_short_game_cb):
		_opt_short_game_cb.button_pressed = _opt_short_game
		_opt_short_game_cb.disabled = not _options_editable
		_opt_short_game_cb.tooltip_text = short_tt if _show_tooltips else ""

	if _opt_no_milestones_cb != null and is_instance_valid(_opt_no_milestones_cb):
		_opt_no_milestones_cb.button_pressed = _opt_no_milestones
		_opt_no_milestones_cb.disabled = not _options_editable
		_opt_no_milestones_cb.tooltip_text = no_ms_tt if _show_tooltips else ""

	var is_first_time := _opt_short_game and _opt_no_milestones
	if _opt_first_time_cb != null and is_instance_valid(_opt_first_time_cb):
		_opt_first_time_cb.button_pressed = is_first_time
		_opt_first_time_cb.disabled = not _options_editable
		_opt_first_time_cb.tooltip_text = first_time_tt if _show_tooltips else ""

	var disable_specific := _opt_no_milestones
	if _opt_no_cfo_cb != null and is_instance_valid(_opt_no_cfo_cb):
		_opt_no_cfo_cb.button_pressed = _opt_no_cfo_milestone
		_opt_no_cfo_cb.disabled = (not _options_editable) or disable_specific
		_opt_no_cfo_cb.tooltip_text = no_cfo_tt if _show_tooltips else ""

	if _opt_no_broadcast_cb != null and is_instance_valid(_opt_no_broadcast_cb):
		_opt_no_broadcast_cb.button_pressed = _opt_no_broadcast_milestone
		_opt_no_broadcast_cb.disabled = (not _options_editable) or disable_specific
		_opt_no_broadcast_cb.tooltip_text = no_radio_tt if _show_tooltips else ""

	if _opt_count_label != null and is_instance_valid(_opt_count_label):
		var selected := 0
		var total := 4
		if _opt_short_game:
			selected += 1
		if _opt_no_milestones:
			selected += 1
		if _opt_no_cfo_milestone:
			selected += 1
		if _opt_no_broadcast_milestone:
			selected += 1
		_opt_count_label.text = "%d/%d" % [selected, total]

	_suppress_game_option_signals = false

func _emit_game_options_changed() -> void:
	game_options_changed.emit(get_game_options())

func _on_short_game_option_toggled(pressed: bool) -> void:
	if _suppress_game_option_signals:
		return
	_opt_short_game = bool(pressed)
	_refresh_game_options_ui()
	_emit_game_options_changed()

func _on_no_milestones_option_toggled(pressed: bool) -> void:
	if _suppress_game_option_signals:
		return
	_opt_no_milestones = bool(pressed)
	_refresh_game_options_ui()
	_emit_game_options_changed()

func _on_first_time_option_toggled(pressed: bool) -> void:
	if _suppress_game_option_signals:
		return
	_opt_short_game = bool(pressed)
	_opt_no_milestones = bool(pressed)
	_refresh_game_options_ui()
	_emit_game_options_changed()

func _on_no_cfo_milestone_option_toggled(pressed: bool) -> void:
	if _suppress_game_option_signals:
		return
	_opt_no_cfo_milestone = bool(pressed)
	_refresh_game_options_ui()
	_emit_game_options_changed()

func _on_no_broadcast_milestone_option_toggled(pressed: bool) -> void:
	if _suppress_game_option_signals:
		return
	_opt_no_broadcast_milestone = bool(pressed)
	_refresh_game_options_ui()
	_emit_game_options_changed()

func _build_module_group_box(group_id: String, title: String, module_ids: Array[String], bg_color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", _build_group_panel_style(bg_color))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title_label := Label.new()
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.tooltip_text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_label_dark(title_label)
	header.add_child(title_label)

	# 计数标签 (如 "2/4")
	var count_label := Label.new()
	count_label.text = "0/0"
	count_label.add_theme_font_size_override("font_size", 13)
	UiStylesClass.apply_label_hint_dark(count_label)
	header.add_child(count_label)
	_group_count_labels[group_id] = count_label

	var mids_copy: Array[String] = module_ids.duplicate()
	var select_all_check := CheckBox.new()
	select_all_check.text = "全选"
	select_all_check.tooltip_text = "选中全选本组，取消全不选"
	select_all_check.disabled = not _editable
	UiStylesClass.apply_check_box_field(select_all_check)
	select_all_check.size_flags_horizontal = Control.SIZE_SHRINK_END
	select_all_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	select_all_check.toggled.connect(func(pressed: bool) -> void:
		_on_group_select_toggled(group_id, mids_copy, pressed)
	)
	header.add_child(select_all_check)
	_group_select_checkboxes[group_id] = select_all_check
	_group_module_ids[group_id] = mids_copy.duplicate()
	_action_buttons.append(select_all_check)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	box.add_child(inner)

	for mid in module_ids:
		if not _optional_module_ids.has(mid):
			continue
		var cb := CheckBox.new()
		cb.text = _format_module_label(mid)
		cb.tooltip_text = _format_module_tooltip(mid) if _show_tooltips else ""
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStylesClass.apply_check_box_field(cb)
		var id := mid
		cb.toggled.connect(func(pressed: bool) -> void:
			_on_module_checkbox_toggled(id, pressed)
		)
		inner.add_child(cb)
		_module_checkboxes[mid] = cb

	return panel

func _format_module_label(mid: String) -> String:
	var name := mid
	var manifest_val = _available_modules.get(mid, null)
	if manifest_val is ModuleManifest:
		var manifest: ModuleManifest = manifest_val
		name = str(manifest.name)
	return name

func _format_module_tooltip(mid: String) -> String:
	var manifest_val = _available_modules.get(mid, null)
	if not (manifest_val is ModuleManifest):
		return ""
	var manifest: ModuleManifest = manifest_val
	var parts: Array[String] = []
	if not manifest.dependencies.is_empty():
		parts.append("依赖: %s" % ", ".join(Array(manifest.dependencies, TYPE_STRING, "", null)))
	if not manifest.conflicts.is_empty():
		parts.append("冲突: %s" % ", ".join(Array(manifest.conflicts, TYPE_STRING, "", null)))
	return "\n".join(parts)

func _on_select_all_modules_pressed() -> void:
	for mid in _optional_module_ids:
		_requested_optional_modules[mid] = true
	_recompute_modules_and_apply_to_ui()

func _on_clear_all_modules_pressed() -> void:
	_requested_optional_modules.clear()
	_recompute_modules_and_apply_to_ui()

func _on_group_select_toggled(_group_id: String, module_ids: Array[String], pressed: bool) -> void:
	if _suppress_signals:
		return
	if pressed:
		for mid in module_ids:
			if _optional_module_ids.has(mid):
				_requested_optional_modules[mid] = true
	else:
		for mid2 in module_ids:
			_requested_optional_modules.erase(mid2)
	_recompute_modules_and_apply_to_ui()

func _on_select_group_pressed(module_ids: Array[String]) -> void:
	for mid in module_ids:
		if _optional_module_ids.has(mid):
			_requested_optional_modules[mid] = true
	_recompute_modules_and_apply_to_ui()

func _on_clear_group_pressed(module_ids: Array[String]) -> void:
	for mid in module_ids:
		_requested_optional_modules.erase(mid)
	_recompute_modules_and_apply_to_ui()

func _on_module_checkbox_toggled(module_id: String, pressed: bool) -> void:
	if _suppress_signals:
		return
	if pressed:
		_requested_optional_modules[module_id] = true
	else:
		_requested_optional_modules.erase(module_id)
	_recompute_modules_and_apply_to_ui()

func _recompute_modules_and_apply_to_ui() -> void:
	if _available_modules.is_empty() or _module_checkboxes.is_empty():
		_set_notes("")
		return

	# Setup/RoomConfig：若存在人数上下文，则强制模块可能依赖当前选择（例如 5/6 人 Lobbyists -> New Districts）。
	if _setup_player_count > 0:
		_refresh_forced_optional_modules_for_setup_context()

	var notes: Array[String] = []

	if not _forced_optional_modules.is_empty():
		var forced: Array[String] = []
		for mid_val in _forced_optional_modules.keys():
			var id := str(mid_val).strip_edges()
			if id.is_empty():
				continue
			forced.append(id)
		forced.sort()
		notes.append("已强制启用模块：%s" % ", ".join(forced))

	_apply_optional_module_conflicts(notes)

	var effective_before := _logic.compute_effective_optional_modules(_requested_optional_modules, _forced_optional_modules)
	var removed_base := _logic.compute_removed_base_modules_from_conflicts(effective_before)
	_apply_removed_base_dependency_guard(removed_base, notes)

	var effective := _logic.compute_effective_optional_modules(_requested_optional_modules, _forced_optional_modules)
	_locked_optional_modules = _logic.compute_locked_optional_modules(_requested_optional_modules, _forced_optional_modules)

	_suppress_signals = true
	for mid in _module_checkboxes.keys():
		var cb_val = _module_checkboxes.get(mid, null)
		if not (cb_val is CheckBox) or not is_instance_valid(cb_val):
			continue
		var cb: CheckBox = cb_val

		var id := str(mid)
		cb.button_pressed = effective.has(id)

		var disabled := false
		var tt := _format_module_tooltip(id)
		var removed_dep_reason := _logic.get_removed_base_dependency_reason(id, removed_base)
		if not removed_dep_reason.is_empty():
			disabled = true
			if not tt.is_empty():
				tt += "\n"
			tt += removed_dep_reason
		elif _forced_optional_modules.has(id):
			disabled = true
			if not tt.is_empty():
				tt += "\n"
			var reason := str(_forced_optional_modules.get(id, "")).strip_edges()
			if reason.is_empty():
				reason = "被规则强制启用"
			tt += reason
		elif _locked_optional_modules.has(id):
			disabled = true
			if not tt.is_empty():
				tt += "\n"
			tt += "被依赖，需先取消上游模块"
		cb.disabled = disabled
		if not _editable:
			cb.disabled = true
		cb.tooltip_text = tt if _show_tooltips else ""

	for gid in _group_select_checkboxes.keys():
		var group_cb_val = _group_select_checkboxes.get(gid, null)
		if not (group_cb_val is CheckBox) or not is_instance_valid(group_cb_val):
			continue
		var group_cb: CheckBox = group_cb_val
		var group_modules_val = _group_module_ids.get(gid, [])
		if not (group_modules_val is Array):
			group_cb.button_pressed = false
			group_cb.disabled = true
			continue
		var group_modules: Array = group_modules_val
		var total := 0
		var selected := 0
		for mid_val in group_modules:
			var gid_mid := str(mid_val).strip_edges()
			if gid_mid.is_empty() or not _optional_module_ids.has(gid_mid):
				continue
			total += 1
			if effective.has(gid_mid):
				selected += 1
		group_cb.button_pressed = total > 0 and selected == total
		group_cb.disabled = (not _editable) or total <= 0
		group_cb.tooltip_text = "选中全选本组，取消全不选"
		# 更新计数标签
		var count_lbl_val = _group_count_labels.get(gid, null)
		if count_lbl_val is Label and is_instance_valid(count_lbl_val):
			(count_lbl_val as Label).text = "%d/%d" % [selected, total]
	_suppress_signals = false

	_set_notes("\n".join(notes))
	selection_changed.emit(get_enabled_modules_v2())

func _refresh_forced_optional_modules_for_setup_context() -> void:
	_forced_optional_modules = _logic.compute_required_optional_modules_for_player_count(_setup_player_count, _requested_optional_modules)

func get_required_optional_modules_for_player_count(player_count: int) -> Dictionary:
	return _logic.compute_required_optional_modules_for_player_count(player_count, _requested_optional_modules).duplicate()

func _apply_optional_module_conflicts(notes: Array[String]) -> void:
	var to_remove := _logic.compute_conflicting_requested_modules_to_remove(_requested_optional_modules, _forced_optional_modules)
	var remove_list: Array[String] = []
	for mid_val in to_remove.keys():
		remove_list.append(str(mid_val))
	remove_list.sort()
	for id in remove_list:
		_requested_optional_modules.erase(id)
		notes.append(str(to_remove.get(id, "")))

func _apply_removed_base_dependency_guard(removed_base: Dictionary, notes: Array[String]) -> void:
	var remove_list := _logic.compute_requested_modules_to_remove_due_to_removed_base(removed_base, _requested_optional_modules)
	for mid in remove_list:
		_requested_optional_modules.erase(mid)
		notes.append("已自动取消 %s（依赖被移除的基础模块）" % _logic.get_module_display_name(mid))
