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
var _module_checkboxes: Dictionary = {} # module_id -> CheckBox
var _requested_optional_modules: Dictionary = {} # module_id -> true（用户显式选择）
var _locked_optional_modules: Dictionary = {} # module_id -> true（被依赖，禁止取消）
var _forced_optional_modules: Dictionary = {} # module_id -> reason（外部约束强制启用/锁定）

var _suppress_signals: bool = false
var _editable: bool = true

var _show_tooltips: bool = true
var _show_notes: bool = true

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

func set_show_notes(show: bool) -> void:
	_ensure_base_ui()
	_show_notes = bool(show)
	_recompute_modules_and_apply_to_ui()

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

	var effective_optional := _compute_effective_optional_modules()
	var removed_base := _compute_removed_base_modules_from_conflicts(effective_optional)
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
	modules_label.text = "模块（分组）"
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
	var kept: Array = []
	for btn in _action_buttons:
		if btn != null and is_instance_valid(btn) and btn.get_parent() == _header_row:
			kept.append(btn)
	_action_buttons = kept

	var groups: Array[Dictionary] = _compute_module_groups()
	for i in range(groups.size()):
		var group: Dictionary = groups[i]
		var group_id := str(group.get("id", "")).strip_edges()
		var title := str(group.get("title", "")).strip_edges()
		var mids: Array[String] = Array(group.get("modules", []), TYPE_STRING, "", null)
		var bg := _GROUP_BG_COLORS[i] if i >= 0 and i < _GROUP_BG_COLORS.size() else _GROUP_BG_COLORS[_GROUP_BG_COLORS.size() - 1]
		_groups_container.add_child(_build_module_group_box(group_id, title, mids, bg))

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

	var effective_before := _compute_effective_optional_modules()
	var removed_base := _compute_removed_base_modules_from_conflicts(effective_before)
	_apply_removed_base_dependency_guard(removed_base, notes)

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
		var removed_dep_reason := _get_removed_base_dependency_reason(id, removed_base)
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

func _depends_on_module(module_id: String, target_id: String) -> bool:
	var target := str(target_id).strip_edges()
	if target.is_empty():
		return false

	var stack: Array[String] = [str(module_id)]
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
			if dep == target:
				return true
			if dep.begins_with("base_"):
				continue
			stack.append(dep)

	return false

func _get_module_ui_dict(module_id: String) -> Dictionary:
	var manifest_val = _available_modules.get(module_id, null)
	if not (manifest_val is ModuleManifest):
		return {}
	var manifest: ModuleManifest = manifest_val
	if not (manifest.provides is Dictionary):
		return {}
	var provides: Dictionary = manifest.provides
	var ui_val = provides.get("ui", null)
	if not (ui_val is Dictionary):
		return {}
	return ui_val

func _get_module_selector_meta(module_id: String) -> Dictionary:
	var ui := _get_module_ui_dict(module_id)
	var ms_val = ui.get("module_selector", null)
	return ms_val if (ms_val is Dictionary) else {}

func _get_module_selector_group_id(module_id: String) -> String:
	var meta := _get_module_selector_meta(module_id)
	var gid := str(meta.get("group_id", "")).strip_edges()
	return gid

func _get_module_selector_group_title(module_id: String) -> String:
	var meta := _get_module_selector_meta(module_id)
	var title := str(meta.get("group_title", "")).strip_edges()
	return title

func _get_module_selector_group_order(module_id: String) -> int:
	var meta := _get_module_selector_meta(module_id)
	return int(meta.get("group_order", 999))

func _get_module_selector_order_in_group(module_id: String) -> int:
	var meta := _get_module_selector_meta(module_id)
	return int(meta.get("order", 999))

func _get_module_display_name(module_id: String) -> String:
	var manifest_val = _available_modules.get(module_id, null)
	if manifest_val is ModuleManifest:
		var manifest: ModuleManifest = manifest_val
		return str(manifest.name).strip_edges()
	return str(module_id).strip_edges()

func _compute_module_groups() -> Array[Dictionary]:
	var groups_by_id: Dictionary = {} # group_id -> {id, title, order, modules}
	for mid in _optional_module_ids:
		var group_id := _get_module_selector_group_id(mid)
		var group_title := _get_module_selector_group_title(mid)
		var group_order := _get_module_selector_group_order(mid)

		if group_id.is_empty():
			group_id = "other"
			group_title = "其他" if group_title.is_empty() else group_title
			group_order = 9999
		elif group_title.is_empty():
			group_title = group_id

		if not groups_by_id.has(group_id):
			groups_by_id[group_id] = {
				"id": group_id,
				"title": group_title,
				"order": group_order,
				"modules": [],
			}
		var g: Dictionary = groups_by_id[group_id]
		var arr: Array[String] = Array(g.get("modules", []), TYPE_STRING, "", null)
		arr.append(mid)
		g["modules"] = arr
		groups_by_id[group_id] = g

	var out: Array[Dictionary] = []
	for gid in groups_by_id.keys():
		out.append(groups_by_id[gid])

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ao := int(a.get("order", 9999))
		var bo := int(b.get("order", 9999))
		if ao != bo:
			return ao < bo
		return str(a.get("title", "")) < str(b.get("title", ""))
	)

	for i in range(out.size()):
		var g: Dictionary = out[i]
		var mids: Array[String] = Array(g.get("modules", []), TYPE_STRING, "", null)
		mids.sort_custom(func(a: String, b: String) -> bool:
			var ao := _get_module_selector_order_in_group(a)
			var bo := _get_module_selector_order_in_group(b)
			if ao != bo:
				return ao < bo
			return _get_module_display_name(a) < _get_module_display_name(b)
		)
		g["modules"] = mids
		out[i] = g

	return out

func _refresh_forced_optional_modules_for_setup_context() -> void:
	_forced_optional_modules = _compute_required_optional_modules_for_player_count(_setup_player_count)

func get_required_optional_modules_for_player_count(player_count: int) -> Dictionary:
	return _compute_required_optional_modules_for_player_count(player_count).duplicate()

func _compute_required_optional_modules_for_player_count(player_count: int) -> Dictionary:
	# 基于 module.json 提供的 setup_constraints 计算强制模块列表。
	# 支持两类约束：
	# - setup_constraints.required_player_counts：指定人数下强制启用该模块本身（与选择无关）。
	# - setup_constraints.requires_optional_modules：当该模块启用且人数匹配时，强制启用其它可选模块（依赖当前选择）。
	var out: Dictionary = {}
	if _available_modules.is_empty():
		return out
	var count := int(player_count)
	if count <= 0:
		return out

	# 1) 人数固定必需模块：required_player_counts
	for mid in _optional_module_ids:
		var ui := _get_module_ui_dict(mid)
		var setup_val = ui.get("setup_constraints", null)
		if not (setup_val is Dictionary):
			continue
		var setup: Dictionary = setup_val
		var counts_val = setup.get("required_player_counts", null)
		if not (counts_val is Array):
			continue

		var required := false
		for c in Array(counts_val):
			if int(c) == count:
				required = true
				break
		if not required:
			continue

		var reason := str(setup.get("reason", "")).strip_edges()
		if reason.is_empty():
			reason = "%d 人局强制启用 %s 模块。" % [count, _get_module_display_name(mid)]
		out[mid] = reason

	# 2) 条件必需模块：requires_optional_modules（当某模块启用且人数匹配时，强制启用其它模块）
	# schema:
	# setup_constraints.requires_optional_modules = [
	#   {
	#     "required_player_counts": [5, 6], # 可选；缺省表示任意人数
	#     "module_ids": ["some_optional_module_id"],
	#     "reason": "..."
	#   }
	# ]
	var selected: Dictionary = {}
	var queue: Array[String] = []

	for mid_val in _requested_optional_modules.keys():
		var id := str(mid_val).strip_edges()
		if id.is_empty():
			continue
		if selected.has(id):
			continue
		selected[id] = true
		queue.append(id)

	for mid_val2 in out.keys():
		var id2 := str(mid_val2).strip_edges()
		if id2.is_empty():
			continue
		if selected.has(id2):
			continue
		selected[id2] = true
		queue.append(id2)

	var visited: Dictionary = {}
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true

		var ui2 := _get_module_ui_dict(cur)
		var setup_val2 = ui2.get("setup_constraints", null)
		if not (setup_val2 is Dictionary):
			continue
		var setup2: Dictionary = setup_val2

		var reqs_val = setup2.get("requires_optional_modules", null)
		if not (reqs_val is Array):
			continue

		for rule_val in Array(reqs_val):
			if not (rule_val is Dictionary):
				continue
			var rule: Dictionary = rule_val

			var counts_val2 = rule.get("required_player_counts", null)
			if counts_val2 != null:
				if not (counts_val2 is Array):
					continue
				var ok_count := false
				for c2 in Array(counts_val2):
					if int(c2) == count:
						ok_count = true
						break
				if not ok_count:
					continue

			var module_ids_val = rule.get("module_ids", null)
			if not (module_ids_val is Array):
				continue

			var reason2 := str(rule.get("reason", "")).strip_edges()
			if reason2.is_empty():
				reason2 = "%d 人局启用 %s 时需要额外模块。" % [count, _get_module_display_name(cur)]

			for req_mid_val in Array(module_ids_val):
				var req_mid := str(req_mid_val).strip_edges()
				if req_mid.is_empty():
					continue
				if req_mid.begins_with("base_"):
					continue
				if not _optional_module_ids.has(req_mid):
					continue
				if not out.has(req_mid):
					out[req_mid] = reason2
				if selected.has(req_mid):
					continue
				selected[req_mid] = true
				queue.append(req_mid)

	return out

func _apply_optional_module_conflicts(notes: Array[String]) -> void:
	# 只自动取消“用户显式选择”的模块；forced/依赖锁定模块不自动取消（避免越权）
	var effective := _compute_effective_optional_modules()
	var to_remove: Dictionary = {} # module_id -> reason

	for a_id_val in effective.keys():
		var a_id := str(a_id_val)
		var a_manifest_val = _available_modules.get(a_id, null)
		if not (a_manifest_val is ModuleManifest):
			continue
		var a_manifest: ModuleManifest = a_manifest_val
		var a_pri := int(a_manifest.priority)
		var conflicts: Array[String] = Array(a_manifest.conflicts, TYPE_STRING, "", null)
		for b_id in conflicts:
			if not effective.has(b_id):
				continue
			if _forced_optional_modules.has(b_id):
				continue
			if not _requested_optional_modules.has(b_id):
				continue
			if _forced_optional_modules.has(a_id):
				to_remove[b_id] = "已自动取消 %s（与 %s 冲突）" % [_get_module_display_name(b_id), _get_module_display_name(a_id)]
				continue
			var b_manifest_val = _available_modules.get(b_id, null)
			var b_pri := int((b_manifest_val as ModuleManifest).priority) if (b_manifest_val is ModuleManifest) else 100
			if a_pri >= b_pri:
				to_remove[b_id] = "已自动取消 %s（与 %s 冲突）" % [_get_module_display_name(b_id), _get_module_display_name(a_id)]

	var remove_list: Array[String] = []
	for mid_val in to_remove.keys():
		remove_list.append(str(mid_val))
	remove_list.sort()
	for id in remove_list:
		_requested_optional_modules.erase(id)
		notes.append(str(to_remove.get(id, "")))

func _compute_removed_base_modules_from_conflicts(effective_optional: Dictionary) -> Dictionary:
	# base_module_id -> source_module_id（哪个 optional 模块声明了该冲突）
	var removed: Dictionary = {}
	for mid_val in effective_optional.keys():
		var mid := str(mid_val)
		var manifest_val = _available_modules.get(mid, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for c_val in manifest.conflicts:
			if not (c_val is String):
				continue
			var c := str(c_val).strip_edges()
			if c.is_empty():
				continue
			if c.begins_with("base_"):
				removed[c] = mid
	return removed

func _apply_removed_base_dependency_guard(removed_base: Dictionary, notes: Array[String]) -> void:
	if removed_base.is_empty():
		return
	var remove_list: Array[String] = []
	for mid_val in _requested_optional_modules.keys():
		var mid := str(mid_val)
		for base_id_val in removed_base.keys():
			var base_id := str(base_id_val)
			if _depends_on_module(mid, base_id):
				remove_list.append(mid)
				break
	remove_list.sort()
	for mid in remove_list:
		_requested_optional_modules.erase(mid)
		notes.append("已自动取消 %s（依赖被移除的基础模块）" % _get_module_display_name(mid))

func _get_removed_base_dependency_reason(module_id: String, removed_base: Dictionary) -> String:
	if removed_base.is_empty():
		return ""
	var deps: Array[String] = []
	for base_id_val in removed_base.keys():
		var base_id := str(base_id_val)
		if _depends_on_module(module_id, base_id):
			deps.append(base_id)
	deps.sort()
	if deps.is_empty():
		return ""
	return "与当前选择不兼容（依赖: %s）" % ", ".join(deps)
