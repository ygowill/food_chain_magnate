# 房间配置编辑器（Create/Room 共用）
extends VBoxContainer

const ModuleSelectorClass = preload("res://ui/components/module_selector/module_selector.gd")

signal changed()
signal validation_failed(message: String)

var _suppress_signals: bool = false
var _editable: bool = true

var _player_count_spin: SpinBox = null
var _seed_mode_option: OptionButton = null
var _seed_value_spin: SpinBox = null

var _module_selector = null

var _advanced_toggle_btn: Button = null
var _advanced_section: VBoxContainer = null
var _modules_base_dir_edit: LineEdit = null
var _allow_spectators_check: CheckBox = null

var _error_label: Label = null

func _ready() -> void:
	_ensure_ui()

func set_editable(editable: bool) -> void:
	_ensure_ui()
	_editable = editable
	_player_count_spin.editable = editable
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

func set_from_room_config(cfg: Dictionary) -> void:
	_ensure_ui()
	_suppress_signals = true

	var desired := int(cfg.get("desired_player_count", 0))
	if desired > 0:
		_player_count_spin.value = desired

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
		"desired_player_count": _get_spinbox_int_value(_player_count_spin),
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
		# 允许 0，但必须有字段（UI 永远有）
		pass

	if _module_selector == null or not is_instance_valid(_module_selector):
		return Result.failure("模块选择器缺失")
	var r: Result = _module_selector.validate_selection()
	if not r.ok:
		return r

	var desired_player_count := _get_spinbox_int_value(_player_count_spin)
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

func _sync_module_constraints_for_player_count() -> void:
	if _module_selector == null or not is_instance_valid(_module_selector):
		return
	var desired_player_count := _get_spinbox_int_value(_player_count_spin)
	if _module_selector.has_method("set_setup_player_count"):
		_module_selector.call("set_setup_player_count", desired_player_count)

func _ensure_ui() -> void:
	if _player_count_spin != null and is_instance_valid(_player_count_spin):
		return

	add_theme_constant_override("separation", 10)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	add_child(player_row)

	var player_label := Label.new()
	player_label.text = "人数"
	player_row.add_child(player_label)

	_player_count_spin = SpinBox.new()
	_player_count_spin.min_value = Globals.MIN_PLAYERS
	_player_count_spin.max_value = Globals.MAX_PLAYERS
	_player_count_spin.step = 1.0
	_player_count_spin.rounded = true
	_player_count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_count_spin.value_changed.connect(func(_v: float) -> void:
		_sync_module_constraints_for_player_count()
		_emit_changed()
	)
	var pc_le := _player_count_spin.get_line_edit()
	if pc_le != null and is_instance_valid(pc_le):
		pc_le.text_changed.connect(func(_t: String) -> void:
			_sync_module_constraints_for_player_count()
			_emit_changed()
		)
	player_row.add_child(_player_count_spin)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "随机种子"
	seed_row.add_child(seed_label)

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
	seed_row.add_child(_seed_value_spin)

	_module_selector = ModuleSelectorClass.new()
	add_child(_module_selector)
	_module_selector.selection_changed.connect(func(_enabled: Array) -> void:
		_emit_changed()
	)
	_module_selector.load_failed.connect(func(msg: String) -> void:
		_set_error(msg)
	)

	_advanced_toggle_btn = Button.new()
	_advanced_toggle_btn.text = "高级/开发 ▼"
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
	base_dir_row.add_child(base_dir_label)

	_modules_base_dir_edit = LineEdit.new()
	_modules_base_dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modules_base_dir_edit.text_submitted.connect(func(_t: String) -> void:
		_on_modules_base_dir_committed()
	)
	_modules_base_dir_edit.focus_exited.connect(_on_modules_base_dir_committed)
	base_dir_row.add_child(_modules_base_dir_edit)

	_allow_spectators_check = CheckBox.new()
	_allow_spectators_check.text = "允许观战（spectator）"
	_allow_spectators_check.toggled.connect(func(_pressed: bool) -> void:
		_emit_changed()
	)
	_advanced_section.add_child(_allow_spectators_check)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error_label.visible = false
	add_child(_error_label)

	_refresh_seed_editability()
	_sync_module_constraints_for_player_count()

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
