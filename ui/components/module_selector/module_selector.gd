# 模块选择面板（复用 Hotseat 的分组/依赖/冲突处理逻辑）
extends VBoxContainer

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")
const ModulePlanBuilderClass = preload("res://core/modules/v2/module_plan_builder.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

signal selection_changed(enabled_modules_v2: Array)
signal notes_changed(text: String)
signal load_failed(message: String)

const MODULE_GROUPS: Array[Dictionary] = [
	{
		"id": "map_expansion",
		"title": "地图扩展（新城区/说客/咖啡）",
		"modules": ["new_districts", "lobbyists", "coffee"],
	},
	{
		"id": "food_and_chefs",
		"title": "新菜系/厨师",
		"modules": ["kimchi", "sushi", "noodles", "fry_chefs"],
	},
	{
		"id": "marketing_expansion",
		"title": "营销扩展",
		"modules": ["mass_marketeers", "rural_marketeers", "gourmet_food_critics"],
	},
	{
		"id": "rules_and_milestones",
		"title": "规则/里程碑变体",
		"modules": ["new_milestones", "hard_choices", "ketchup_mechanism", "reserve_prices"],
	},
	{
		"id": "employee_variants",
		"title": "员工变体",
		"modules": ["movie_stars", "night_shift_managers"],
	},
]

const _GROUP_BG_COLORS: Array[Color] = [
	Color(0.16, 0.24, 0.44, 0.35), # map_expansion
	Color(0.18, 0.42, 0.26, 0.35), # food_and_chefs
	Color(0.44, 0.22, 0.48, 0.35), # marketing_expansion
	Color(0.58, 0.36, 0.18, 0.35), # rules_and_milestones
	Color(0.16, 0.44, 0.44, 0.35), # employee_variants
	Color(0.24, 0.26, 0.32, 0.35), # other
]

var _modules_base_dir_spec: String = ""

var _available_modules: Dictionary = {} # module_id -> ModuleManifest
var _optional_module_ids: Array[String] = []
var _module_checkboxes: Dictionary = {} # module_id -> CheckBox
var _requested_optional_modules: Dictionary = {} # module_id -> true（用户显式选择）
var _locked_optional_modules: Dictionary = {} # module_id -> true（被依赖，禁止取消）
var _forced_optional_modules: Dictionary = {} # module_id -> reason（外部约束强制启用/锁定）

var _suppress_signals: bool = false
var _editable: bool = true

var _header_row: HBoxContainer = null
var _groups_container: GridContainer = null
var _notes_label: Label = null
var _action_buttons: Array[Button] = []

func _ready() -> void:
	_ensure_base_ui()

func set_editable(editable: bool) -> void:
	_ensure_base_ui()
	_editable = editable
	for btn in _action_buttons:
		if btn != null and is_instance_valid(btn):
			btn.disabled = not editable
	_recompute_modules_and_apply_to_ui()

func set_modules_base_dir(base_dir_spec: String) -> Result:
	_ensure_base_ui()
	_modules_base_dir_spec = str(base_dir_spec)
	return _load_modules_and_build_ui()

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
	if _requested_optional_modules.has("new_milestones") or _forced_optional_modules.has("new_milestones"):
		base.erase("base_milestones")

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
	modules_label.text = "模块（分组）"
	modules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_groups_container.add_theme_constant_override("h_separation", 20)
	_groups_container.add_theme_constant_override("v_separation", 20)
	add_child(_groups_container)

	_notes_label = Label.new()
	_notes_label.name = "NotesLabel"
	_notes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_notes_label.visible = false
	add_child(_notes_label)

func _set_notes(text: String) -> void:
	var s := str(text).strip_edges()
	if _notes_label == null or not is_instance_valid(_notes_label):
		return
	_notes_label.text = s
	_notes_label.visible = not s.is_empty()
	notes_changed.emit(s)

func _load_modules_and_build_ui() -> Result:
	_available_modules.clear()
	_optional_module_ids.clear()

	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(_modules_base_dir_spec)
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

	_build_modules_ui()
	_recompute_modules_and_apply_to_ui()
	return Result.success()

func _build_modules_ui() -> void:
	if _groups_container == null or not is_instance_valid(_groups_container):
		return

	for child in _groups_container.get_children():
		child.queue_free()
	_module_checkboxes.clear()
	var kept: Array[Button] = []
	for btn in _action_buttons:
		if btn != null and is_instance_valid(btn) and btn.get_parent() == _header_row:
			kept.append(btn)
	_action_buttons = kept

	var used: Dictionary = {}
	var group_index := 0
	for group_def_val in MODULE_GROUPS:
		if not (group_def_val is Dictionary):
			continue
		var group_def: Dictionary = group_def_val
		var title := str(group_def.get("title", ""))
		var mids: Array[String] = Array(group_def.get("modules", []), TYPE_STRING, "", null)
		var bg := _GROUP_BG_COLORS[group_index] if group_index >= 0 and group_index < _GROUP_BG_COLORS.size() else _GROUP_BG_COLORS[_GROUP_BG_COLORS.size() - 1]
		var box := _build_module_group_box(title, mids, bg)
		_groups_container.add_child(box)
		for mid in mids:
			used[mid] = true
		group_index += 1

	var other: Array[String] = []
	for mid in _optional_module_ids:
		if not used.has(mid):
			other.append(mid)
	if not other.is_empty():
		_groups_container.add_child(_build_module_group_box("其他", other, _GROUP_BG_COLORS[_GROUP_BG_COLORS.size() - 1]))

func _build_group_panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 12
	return sb

func _build_module_group_box(title: String, module_ids: Array[String], bg_color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _build_group_panel_style(bg_color))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)

	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var mids_copy: Array[String] = module_ids.duplicate()

	var select_btn := Button.new()
	select_btn.text = "组选"
	select_btn.disabled = not _editable
	select_btn.custom_minimum_size = Vector2(72, 28)
	select_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStylesClass.apply_button_secondary(select_btn)
	select_btn.pressed.connect(func() -> void:
		_on_select_group_pressed(mids_copy)
	)
	header.add_child(select_btn)
	_action_buttons.append(select_btn)

	var clear_btn := Button.new()
	clear_btn.text = "组不选"
	clear_btn.disabled = not _editable
	clear_btn.custom_minimum_size = Vector2(72, 28)
	clear_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStylesClass.apply_button_secondary(clear_btn)
	clear_btn.pressed.connect(func() -> void:
		_on_clear_group_pressed(mids_copy)
	)
	header.add_child(clear_btn)
	_action_buttons.append(clear_btn)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	box.add_child(inner)

	for mid in module_ids:
		if not _optional_module_ids.has(mid):
			continue
		var cb := CheckBox.new()
		cb.text = _format_module_label(mid)
		cb.tooltip_text = _format_module_tooltip(mid)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	var notes: Array[String] = []
	var new_ms_on := _requested_optional_modules.has("new_milestones") or _forced_optional_modules.has("new_milestones")

	if not _forced_optional_modules.is_empty():
		var forced: Array[String] = []
		for mid_val in _forced_optional_modules.keys():
			var id := str(mid_val).strip_edges()
			if id.is_empty():
				continue
			forced.append(id)
		forced.sort()
		notes.append("已强制启用模块：%s" % ", ".join(forced))

	# 冲突/兼容性规则：new_milestones 优先。
	if new_ms_on:
		if _requested_optional_modules.has("hard_choices"):
			_requested_optional_modules.erase("hard_choices")
			notes.append("已自动取消 Hard Choices（与全新里程碑冲突）")

		var remove_list: Array[String] = []
		for mid_val in _requested_optional_modules.keys():
			var id := str(mid_val)
			if id == "new_milestones":
				continue
			if _depends_on_base_milestones(id):
				remove_list.append(id)
		remove_list.sort()
		for id in remove_list:
			_requested_optional_modules.erase(id)
		if not remove_list.is_empty():
			notes.append("已自动取消依赖基础里程碑的模块：%s" % ", ".join(remove_list))

	var effective := _compute_effective_optional_modules()
	_locked_optional_modules = _compute_locked_optional_modules_from_requested()

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
		if new_ms_on and _depends_on_base_milestones(id):
			disabled = true
			if not tt.is_empty():
				tt += "\n"
			tt += "与“全新里程碑”不兼容（依赖 base_milestones）"
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
		cb.tooltip_text = tt
	_suppress_signals = false

	_set_notes("\n".join(notes))
	selection_changed.emit(get_enabled_modules_v2())

func _compute_effective_optional_modules() -> Dictionary:
	var effective: Dictionary = {}
	for mid_val2 in _forced_optional_modules.keys():
		effective[str(mid_val2)] = true
	for mid_val in _requested_optional_modules.keys():
		effective[str(mid_val)] = true

	var stack: Array[String] = []
	for mid_val in _requested_optional_modules.keys():
		stack.append(str(mid_val))
	for mid_val3 in _forced_optional_modules.keys():
		stack.append(str(mid_val3))

	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true

		var manifest_val = _available_modules.get(cur, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for dep_val in manifest.dependencies:
			if not (dep_val is String):
				continue
			var dep: String = str(dep_val)
			if dep.begins_with("base_"):
				continue
			effective[dep] = true
			stack.append(dep)

	return effective

func _compute_locked_optional_modules_from_requested() -> Dictionary:
	var locked: Dictionary = {}
	var stack: Array[String] = []
	for mid_val in _requested_optional_modules.keys():
		stack.append(str(mid_val))
	for mid_val2 in _forced_optional_modules.keys():
		stack.append(str(mid_val2))

	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true

		var manifest_val = _available_modules.get(cur, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for dep_val in manifest.dependencies:
			if not (dep_val is String):
				continue
			var dep: String = str(dep_val)
			if dep.begins_with("base_"):
				continue
			locked[dep] = true
			stack.append(dep)

	return locked

func _depends_on_base_milestones(module_id: String) -> bool:
	var stack: Array[String] = [module_id]
	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true

		var manifest_val = _available_modules.get(cur, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for dep_val in manifest.dependencies:
			if not (dep_val is String):
				continue
			var dep: String = str(dep_val)
			if dep == "base_milestones":
				return true
			if dep.begins_with("base_"):
				continue
			stack.append(dep)

	return false
