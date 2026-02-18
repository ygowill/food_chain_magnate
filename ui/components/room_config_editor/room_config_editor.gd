# 房间配置编辑器（Create/Room 共用）— 双栏布局 + 按钮组 + 预设方案
extends VBoxContainer

const ModuleSelectorClass = preload("res://ui/components/module_selector/module_selector.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

signal changed()
signal validation_failed(message: String)

var _suppress_signals: bool = false
var _editable: bool = true

var _selected_player_count: int = 2
var _player_count_buttons: Array[Button] = []

var _seed_mode_option: OptionButton = null
var _seed_value_spin: SpinBox = null

var _module_selector = null

var _advanced_toggle_btn: Button = null
var _advanced_section: VBoxContainer = null
var _modules_base_dir_edit: LineEdit = null
var _allow_spectators_check: CheckBox = null

var _error_label: Label = null

var _presets: Array = []
var _preset_option: OptionButton = null
var _suppress_preset_revert: bool = false

func _ready() -> void:
	_ensure_ui()

func set_editable(editable: bool) -> void:
	_ensure_ui()
	_editable = editable
	for btn in _player_count_buttons:
		if btn != null and is_instance_valid(btn):
			btn.disabled = not editable
	_seed_mode_option.disabled = not editable
	_refresh_seed_editability()
	if _modules_base_dir_edit != null and is_instance_valid(_modules_base_dir_edit):
		_modules_base_dir_edit.editable = editable
	if _allow_spectators_check != null and is_instance_valid(_allow_spectators_check):
		_allow_spectators_check.disabled = not editable
	if _module_selector != null and is_instance_valid(_module_selector):
		var prev := _suppress_signals
		_suppress_signals = true
		_module_selector.set_editable(editable)
		_suppress_signals = prev
	if _preset_option != null and is_instance_valid(_preset_option):
		_preset_option.disabled = not editable

func set_from_room_config(cfg: Dictionary) -> void:
	_ensure_ui()
	_suppress_signals = true

	var desired := int(cfg.get("desired_player_count", 0))
	if desired >= Globals.MIN_PLAYERS and desired <= Globals.MAX_PLAYERS:
		_selected_player_count = desired
		_update_player_count_button_styles()

	var seed_mode := str(cfg.get("seed_mode", "random")).strip_edges()
	_select_seed_mode_value(seed_mode)
	_seed_value_spin.value = int(cfg.get("seed", 0))
	_refresh_seed_editability()

	var base_dir := str(cfg.get("modules_v2_base_dir", "")).strip_edges()
	if not base_dir.is_empty():
		_modules_base_dir_edit.text = base_dir

	var allow_spectators := bool(cfg.get("allow_spectators", true))
	_allow_spectators_check.button_pressed = allow_spectators

	if _module_selector != null and is_instance_valid(_module_selector):
		if not base_dir.is_empty():
			_module_selector.set_modules_base_dir(base_dir)
		var enabled_val = cfg.get("enabled_modules_v2", [])
		if enabled_val is Array:
			_module_selector.set_initial_enabled_modules_v2(Array(enabled_val))

	_sync_module_constraints_for_player_count()

	_suppress_signals = false
	_clear_error()

func get_config_patch() -> Dictionary:
	_ensure_ui()
	var seed_mode := _get_seed_mode_value()
	var enabled_modules: Array = []
	if _module_selector != null and is_instance_valid(_module_selector):
		enabled_modules = _module_selector.get_enabled_modules_v2()
	return {
		"desired_player_count": _selected_player_count,
		"seed_mode": seed_mode,
		"seed": _get_spinbox_int_value(_seed_value_spin),
		"enabled_modules_v2": enabled_modules,
		"modules_v2_base_dir": str(_modules_base_dir_edit.text).strip_edges(),
		"allow_spectators": bool(_allow_spectators_check.button_pressed),
	}

func validate() -> Result:
	_clear_error()
	var base_dir := str(_modules_base_dir_edit.text).strip_edges()
	if base_dir.is_empty():
		return Result.failure("modules_v2_base_dir 不能为空")

	var seed_mode := _get_seed_mode_value()
	if seed_mode == "fixed":
		pass

	if _module_selector == null or not is_instance_valid(_module_selector):
		return Result.failure("模块选择器缺失")
	var r: Result = _module_selector.validate_selection()
	if not r.ok:
		return r

	var desired_player_count := _selected_player_count
	if _module_selector.has_method("get_required_optional_modules_for_player_count"):
		var req_val = _module_selector.call("get_required_optional_modules_for_player_count", desired_player_count)
		if req_val is Dictionary:
			var required: Dictionary = req_val
			var enabled: Array = _module_selector.get_enabled_modules_v2()
			for mid_val in required.keys():
				var mid := str(mid_val)
				if mid.is_empty():
					continue
				if not enabled.has(mid):
					var reason := str(required.get(mid, "")).strip_edges()
					if reason.is_empty():
						reason = "缺少必需模块: %s" % mid
					return Result.failure(reason)
	return Result.success()

func _load_default_modules() -> void:
	if _module_selector == null or not is_instance_valid(_module_selector):
		return
	var base_dir := str(Globals.modules_v2_base_dir)
	if base_dir.is_empty():
		return
	if _modules_base_dir_edit != null and is_instance_valid(_modules_base_dir_edit):
		_modules_base_dir_edit.text = base_dir
	var r: Result = _module_selector.set_modules_base_dir(base_dir)
	if not r.ok:
		_set_error("加载模块列表失败：%s" % r.error)
		return
	_module_selector.set_initial_enabled_modules_v2(Array(Globals.enabled_modules_v2, TYPE_STRING, "", null))

func _sync_module_constraints_for_player_count() -> void:
	if _module_selector == null or not is_instance_valid(_module_selector):
		return
	if _module_selector.has_method("set_setup_player_count"):
		_module_selector.call("set_setup_player_count", _selected_player_count)

# ── 区块面板构建器 ──────────────────────────────────────

func _build_section_panel(bg_color: Color = Color(0.95, 0.91, 0.83, 0.55)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(0.17, 0.13, 0.09, 0.15)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 16
	style.content_margin_top = 14
	style.content_margin_right = 16
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ── UI 构建 ──────────────────────────────────────

func _ensure_ui() -> void:
	if _seed_mode_option != null and is_instance_valid(_seed_mode_option):
		return

	add_theme_constant_override("separation", 10)

	# ── 双栏主布局 ──
	var main_columns := HBoxContainer.new()
	main_columns.add_theme_constant_override("separation", 40)
	main_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_columns)

	# ── 左栏：游戏参数 ──
	var left_column := VBoxContainer.new()
	left_column.custom_minimum_size = Vector2(400, 0)
	left_column.add_theme_constant_override("separation", 10)
	main_columns.add_child(left_column)

	var params_panel := _build_section_panel()
	left_column.add_child(params_panel)

	var params_vbox := VBoxContainer.new()
	params_vbox.add_theme_constant_override("separation", 14)
	params_panel.add_child(params_vbox)

	var params_header := Label.new()
	params_header.text = "游戏参数"
	params_header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(params_header)
	params_vbox.add_child(params_header)

	# 玩家数量按钮组
	var count_label := Label.new()
	count_label.text = "玩家数量"
	UiStylesClass.apply_label_hint_dark(count_label)
	params_vbox.add_child(count_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	params_vbox.add_child(btn_row)

	_player_count_buttons.clear()
	for i in range(Globals.MIN_PLAYERS, Globals.MAX_PLAYERS + 1):
		var btn := Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(52, 40)
		var count := i
		btn.pressed.connect(func() -> void:
			_on_player_count_button_pressed(count)
		)
		btn_row.add_child(btn)
		_player_count_buttons.append(btn)
	_update_player_count_button_styles()

	# 随机种子
	var seed_label := Label.new()
	seed_label.text = "随机种子"
	UiStylesClass.apply_label_hint_dark(seed_label)
	params_vbox.add_child(seed_label)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	params_vbox.add_child(seed_row)

	_seed_mode_option = OptionButton.new()
	_seed_mode_option.add_item("随机", 0)
	_seed_mode_option.set_item_metadata(0, "random")
	_seed_mode_option.add_item("固定", 1)
	_seed_mode_option.set_item_metadata(1, "fixed")
	_seed_mode_option.item_selected.connect(func(_idx: int) -> void:
		if _suppress_signals:
			return
		_refresh_seed_editability()
		_emit_changed()
	)
	UiStylesClass.apply_option_button_field(_seed_mode_option)
	seed_row.add_child(_seed_mode_option)

	_seed_value_spin = SpinBox.new()
	_seed_value_spin.min_value = 0.0
	_seed_value_spin.max_value = 2147483647.0
	_seed_value_spin.step = 1.0
	_seed_value_spin.rounded = true
	_seed_value_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_value_spin.value_changed.connect(func(_v: float) -> void:
		_emit_changed()
	)
	var seed_le := _seed_value_spin.get_line_edit()
	if seed_le != null and is_instance_valid(seed_le):
		seed_le.text_changed.connect(func(_t: String) -> void:
			_emit_changed()
		)
	UiStylesClass.apply_spin_box_field(_seed_value_spin)
	seed_row.add_child(_seed_value_spin)

	# ── 右栏：预设方案 + 模块选择 ──
	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 6)
	main_columns.add_child(right_column)

	_load_presets()
	if not _presets.is_empty():
		_build_preset_row(right_column)

	_module_selector = ModuleSelectorClass.new()
	right_column.add_child(_module_selector)
	_module_selector.selection_changed.connect(func(_enabled: Array) -> void:
		if _suppress_preset_revert:
			return
		_revert_preset_to_custom()
		_emit_changed()
	)
	_module_selector.load_failed.connect(func(msg: String) -> void:
		_set_error(msg)
	)

	# ── 高级/开发区域 ──
	_advanced_toggle_btn = Button.new()
	_advanced_toggle_btn.text = "高级/开发 ▼"
	UiStylesClass.apply_button_secondary(_advanced_toggle_btn)
	_advanced_toggle_btn.pressed.connect(_on_toggle_advanced_pressed)
	add_child(_advanced_toggle_btn)

	_advanced_section = VBoxContainer.new()
	_advanced_section.visible = false
	_advanced_section.add_theme_constant_override("separation", 8)
	add_child(_advanced_section)

	var base_dir_row := HBoxContainer.new()
	base_dir_row.add_theme_constant_override("separation", 8)
	_advanced_section.add_child(base_dir_row)

	var base_dir_label := Label.new()
	base_dir_label.text = "Modules Dir"
	UiStylesClass.apply_label_dark(base_dir_label)
	base_dir_row.add_child(base_dir_label)

	_modules_base_dir_edit = LineEdit.new()
	_modules_base_dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modules_base_dir_edit.text_submitted.connect(func(_t: String) -> void:
		_on_modules_base_dir_committed()
	)
	_modules_base_dir_edit.focus_exited.connect(_on_modules_base_dir_committed)
	UiStylesClass.apply_line_edit_field(_modules_base_dir_edit)
	base_dir_row.add_child(_modules_base_dir_edit)

	_allow_spectators_check = CheckBox.new()
	_allow_spectators_check.text = "允许观战（spectator）"
	_allow_spectators_check.toggled.connect(func(_pressed: bool) -> void:
		_emit_changed()
	)
	UiStylesClass.apply_check_box_field(_allow_spectators_check)
	_advanced_section.add_child(_allow_spectators_check)

	# ── 错误标签 ──
	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error_label.visible = false
	UiStylesClass.apply_label_error(_error_label)
	add_child(_error_label)

	_refresh_seed_editability()
	_load_default_modules()
	_sync_module_constraints_for_player_count()

# ── 玩家数量按钮组 ──

func _on_player_count_button_pressed(count: int) -> void:
	_selected_player_count = count
	_update_player_count_button_styles()
	_sync_module_constraints_for_player_count()
	_emit_changed()

func _update_player_count_button_styles() -> void:
	for i in range(_player_count_buttons.size()):
		var btn := _player_count_buttons[i]
		var count := i + Globals.MIN_PLAYERS
		if count == _selected_player_count:
			UiStylesClass.apply_button_primary(btn)
		else:
			UiStylesClass.apply_button_secondary(btn)

# ── 预设方案 ──

func _load_presets() -> void:
	var path := "res://data/config/module_presets.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return
	var data = json.data
	if not (data is Dictionary) or not data.has("presets"):
		return
	_presets = Array(data["presets"])

func _build_preset_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var label := Label.new()
	label.text = "预设方案"
	UiStylesClass.apply_label_hint_dark(label)
	row.add_child(label)

	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.add_item("自定义")
	for preset in _presets:
		if preset is Dictionary:
			_preset_option.add_item(str(preset.get("name", "")))
	UiStylesClass.apply_option_button_field(_preset_option)
	_preset_option.item_selected.connect(_on_preset_selected)
	row.add_child(_preset_option)

func _on_preset_selected(idx: int) -> void:
	if idx <= 0:
		if _module_selector != null and is_instance_valid(_module_selector):
			_module_selector.set_editable(true and _editable)
		return
	var preset_idx := idx - 1
	if preset_idx < 0 or preset_idx >= _presets.size():
		return
	var preset: Dictionary = _presets[preset_idx]
	var module_ids: Array[String] = _resolve_preset_modules(preset)

	if _module_selector != null and is_instance_valid(_module_selector):
		_suppress_preset_revert = true
		_module_selector.set_editable(true)
		_module_selector.set_initial_enabled_modules_v2(module_ids)
		_module_selector.set_editable(false)
		_suppress_preset_revert = false
	_emit_changed()

func _resolve_preset_modules(preset: Dictionary) -> Array[String]:
	if preset.has("all_except") and preset.get("all_except") is Array:
		var except_list: Array = Array(preset.get("all_except", []))
		var all_optional: Array[String] = []
		if _module_selector != null and is_instance_valid(_module_selector) and "_optional_module_ids" in _module_selector:
			all_optional = Array(_module_selector._optional_module_ids, TYPE_STRING, "", null)
		var out: Array[String] = []
		for mid in all_optional:
			if not except_list.has(mid):
				out.append(mid)
		return out

	var raw: Array = Array(preset.get("modules", []))
	var out: Array[String] = []
	for val in raw:
		var id := str(val).strip_edges()
		if not id.is_empty():
			out.append(id)
	return out

func _revert_preset_to_custom() -> void:
	if _preset_option == null or not is_instance_valid(_preset_option):
		return
	if _preset_option.selected != 0:
		_preset_option.select(0)
		if _module_selector != null and is_instance_valid(_module_selector):
			_module_selector.set_editable(true and _editable)

# ── 高级区域 ──

func _on_toggle_advanced_pressed() -> void:
	if _advanced_section == null or not is_instance_valid(_advanced_section):
		return
	_advanced_section.visible = not _advanced_section.visible
	_advanced_toggle_btn.text = "高级/开发 ▲" if _advanced_section.visible else "高级/开发 ▼"

func _on_modules_base_dir_committed() -> void:
	if _suppress_signals:
		return
	if _module_selector == null or not is_instance_valid(_module_selector):
		return
	var spec := str(_modules_base_dir_edit.text).strip_edges()
	if spec.is_empty():
		return

	var prev_enabled: Array = _module_selector.get_enabled_modules_v2()
	var r: Result = _module_selector.set_modules_base_dir(spec)
	if not r.ok:
		_set_error(r.error)
		return
	_module_selector.set_initial_enabled_modules_v2(prev_enabled)
	_emit_changed()

# ── 种子相关 ──

func _refresh_seed_editability() -> void:
	var seed_mode := _get_seed_mode_value()
	_seed_value_spin.editable = _editable and seed_mode == "fixed"

func _get_seed_mode_value() -> String:
	var idx := _seed_mode_option.selected
	var meta = _seed_mode_option.get_item_metadata(idx)
	var v := str(meta).strip_edges()
	return v if not v.is_empty() else "random"

func _get_spinbox_int_value(spin: SpinBox) -> int:
	if spin == null or not is_instance_valid(spin):
		return 0
	var v := int(spin.value)
	var le := spin.get_line_edit()
	if le != null and is_instance_valid(le):
		var t := str(le.text).strip_edges()
		if t.is_valid_int():
			v = int(t)
	return clampi(v, int(spin.min_value), int(spin.max_value))

func _select_seed_mode_value(value: String) -> void:
	for i in range(_seed_mode_option.item_count):
		var meta = _seed_mode_option.get_item_metadata(i)
		if str(meta) == value:
			_seed_mode_option.select(i)
			return
	_seed_mode_option.select(0)

# ── 信号 ──

func _emit_changed() -> void:
	if _suppress_signals:
		return
	changed.emit()

func _set_error(message: String) -> void:
	var s := str(message).strip_edges()
	if _error_label == null or not is_instance_valid(_error_label):
		return
	_error_label.text = s
	_error_label.visible = not s.is_empty()
	validation_failed.emit(s)

func _clear_error() -> void:
	if _error_label == null or not is_instance_valid(_error_label):
		return
	_error_label.text = ""
	_error_label.visible = false
