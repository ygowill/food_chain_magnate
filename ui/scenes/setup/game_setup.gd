# 游戏设置场景脚本
extends Control

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")
const ModulePlanBuilderClass = preload("res://core/modules/v2/module_plan_builder.gd")

@onready var player_count_spinbox: SpinBox = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/LeftColumn/PlayerCountContainer/PlayerCountSpinBox
@onready var seed_edit: LineEdit = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/LeftColumn/SeedContainer/SeedLineEdit
@onready var root_vbox: VBoxContainer = $CenterContainer/ContentCenter/VBoxContainer
@onready var spacer2: Control = $CenterContainer/ContentCenter/VBoxContainer/Spacer2
@onready var left_column: VBoxContainer = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/LeftColumn
@onready var right_column: VBoxContainer = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/RightColumn

var _players_section: VBoxContainer = null
var _players_container: VBoxContainer = null
var _modules_section: VBoxContainer = null
var _modules_groups_container: GridContainer = null
var _message_label: Label = null
var _info_label: Label = null

var _player_name_edits: Array[LineEdit] = []
var _player_logo_options: Array[OptionButton] = []
var _player_logo_previews: Array[TextureRect] = []

var _available_modules: Dictionary = {}  # module_id -> ModuleManifest
var _optional_module_ids: Array[String] = []
var _module_checkboxes: Dictionary = {}  # module_id -> CheckBox
var _requested_optional_modules: Dictionary = {}  # module_id -> true（用户显式选择）
var _locked_optional_modules: Dictionary = {}  # module_id -> true（被依赖，禁止取消）

var _suppress_module_signals: bool = false
var _suppress_player_signals: bool = false

var _logo_icons_small: Array[Texture2D] = []

const RESTAURANT_LOGO_TEXTURE_PATHS: Array[String] = [
	"res://modules/base_pieces/assets/map/logos/fried_geese_donkey.png",
	"res://modules/base_pieces/assets/map/logos/gluttony_inc_burgers.png",
	"res://modules/base_pieces/assets/map/logos/golden_duck_diner.png",
	"res://modules/base_pieces/assets/map/logos/santa_maria_pizza.png",
	"res://modules/base_pieces/assets/map/logos/xango_blues_bar.png",
]

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

func _ready() -> void:
	GameLog.info("GameSetup", "游戏设置界面已加载")

	player_count_spinbox.value = Globals.player_count
	if Globals.random_seed != 0:
		seed_edit.text = str(Globals.random_seed)

	if not player_count_spinbox.value_changed.is_connected(_on_player_count_changed):
		player_count_spinbox.value_changed.connect(_on_player_count_changed)

	_ensure_sections()
	_ensure_logo_icons_cache()
	_seed_requested_modules_from_globals()
	_load_modules()
	_rebuild_player_rows()
	_recompute_modules_and_apply_to_ui()

func _on_back_pressed() -> void:
	GameLog.info("GameSetup", "返回上一场景")
	SceneManager.go_back()

func _on_start_pressed() -> void:
	_set_message("")

	Globals.player_count = int(player_count_spinbox.value)

	# 处理随机种子
	if seed_edit.text.is_empty():
		Globals.generate_seed()
		GameLog.info("GameSetup", "生成随机种子: %d" % Globals.random_seed)
	else:
		Globals.random_seed = seed_edit.text.to_int()
		GameLog.info("GameSetup", "使用指定种子: %d" % Globals.random_seed)

	# 同步 UI 状态 -> Globals
	if not _apply_module_selection_to_globals():
		return
	_apply_player_profiles_to_globals()
	Globals.save_settings()

	GameLog.info("GameSetup", "开始游戏 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])

	# 初始化新游戏（生成地图/模块装配）可能耗时：提前显示加载遮罩
	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在开始新游戏...")
		await get_tree().process_frame

	Globals.set_current_game_engine(null)
	SceneManager.goto_game()

func _on_player_count_changed(_value: float) -> void:
	_rebuild_player_rows()

func _ensure_sections() -> void:
	if _players_section != null and is_instance_valid(_players_section):
		return
	if root_vbox == null or spacer2 == null:
		return
	if left_column == null or right_column == null:
		return

	_players_section = VBoxContainer.new()
	_players_section.name = "PlayersSection"
	_players_section.add_theme_constant_override("separation", 8)
	left_column.add_child(_players_section)

	var players_header := Label.new()
	players_header.text = "玩家设置（与玩家数量联动）"
	players_header.autowrap_mode = TextServer.AUTOWRAP_WORD
	players_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_section.add_child(players_header)

	_players_container = VBoxContainer.new()
	_players_container.name = "PlayersContainer"
	_players_container.add_theme_constant_override("separation", 6)
	_players_section.add_child(_players_container)

	_modules_section = VBoxContainer.new()
	_modules_section.name = "ModulesSection"
	_modules_section.add_theme_constant_override("separation", 6)
	right_column.add_child(_modules_section)

	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.add_theme_constant_override("separation", 10)
	_modules_section.add_child(header_row)

	var modules_label := Label.new()
	modules_label.text = "模块（分组）"
	modules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(modules_label)

	var select_all_btn := Button.new()
	select_all_btn.text = "全选"
	select_all_btn.pressed.connect(_on_select_all_modules_pressed)
	header_row.add_child(select_all_btn)

	var clear_all_btn := Button.new()
	clear_all_btn.text = "全不选"
	clear_all_btn.pressed.connect(_on_clear_all_modules_pressed)
	header_row.add_child(clear_all_btn)

	_modules_groups_container = GridContainer.new()
	_modules_groups_container.name = "ModulesGroups"
	_modules_groups_container.columns = 2
	_modules_groups_container.add_theme_constant_override("h_separation", 20)
	_modules_groups_container.add_theme_constant_override("v_separation", 20)
	_modules_section.add_child(_modules_groups_container)

	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.visible = false
	root_vbox.add_child(_message_label)
	root_vbox.move_child(_message_label, spacer2.get_index())

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.text = "提示：储备卡将在进入游戏后由每位玩家秘密选择（全员完成后才进入起始餐厅放置）。"
	root_vbox.add_child(_info_label)
	root_vbox.move_child(_info_label, spacer2.get_index())

func _set_message(text: String) -> void:
	if _message_label == null or not is_instance_valid(_message_label):
		return
	var s := str(text).strip_edges()
	_message_label.text = s
	_message_label.visible = not s.is_empty()

func _seed_requested_modules_from_globals() -> void:
	_requested_optional_modules.clear()
	for mid_val in Globals.enabled_modules_v2:
		var id := str(mid_val)
		if id.begins_with("base_"):
			continue
		_requested_optional_modules[id] = true

func _load_modules() -> void:
	_available_modules.clear()
	_optional_module_ids.clear()

	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(Globals.modules_v2_base_dir)
	if not base_dirs_read.ok:
		_set_message("解析 modules_v2_base_dir 失败：%s" % base_dirs_read.error)
		return
	var base_dirs: Array[String] = base_dirs_read.value

	var manifests_read := ModulePackageLoaderClass.load_all_from_dirs(base_dirs)
	if not manifests_read.ok:
		_set_message("加载模块列表失败：%s" % manifests_read.error)
		return
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

func _rebuild_player_rows() -> void:
	if _players_container == null or not is_instance_valid(_players_container):
		return

	_ensure_logo_icons_cache()

	for child in _players_container.get_children():
		child.queue_free()
	_player_name_edits.clear()
	_player_logo_options.clear()
	_player_logo_previews.clear()

	var count := int(player_count_spinbox.value)
	for pid in range(count):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		_players_container.add_child(row)

		var label := Label.new()
		label.text = "玩家 %d" % (pid + 1)
		label.custom_minimum_size = Vector2(70, 0)
		row.add_child(label)

		var name_edit := LineEdit.new()
		name_edit.custom_minimum_size = Vector2(160, 0)
		name_edit.placeholder_text = "玩家名称"
		name_edit.text = Globals.get_player_name(pid)
		row.add_child(name_edit)
		_player_name_edits.append(name_edit)

		var logo_preview := TextureRect.new()
		logo_preview.custom_minimum_size = Vector2(20, 20)
		logo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(logo_preview)
		_player_logo_previews.append(logo_preview)

		var logo_opt := OptionButton.new()
		logo_opt.custom_minimum_size = Vector2(180, 0)
		logo_opt.add_item("随机")
		for i in range(min(RESTAURANT_LOGO_TEXTURE_PATHS.size(), 5)):
			var icon_tex := _logo_icons_small[i] if i < _logo_icons_small.size() else null
			if icon_tex != null:
				logo_opt.add_icon_item(icon_tex, "店铺 %d" % (i + 1))
			else:
				logo_opt.add_item("店铺 %d" % (i + 1))

		var choice := Globals.get_player_restaurant_logo_choice(pid)
		if choice >= 0 and choice < RESTAURANT_LOGO_TEXTURE_PATHS.size():
			logo_opt.select(choice + 1)
		else:
			logo_opt.select(0)

		logo_opt.item_selected.connect(func(_idx: int) -> void:
			if _suppress_player_signals:
				return
			_refresh_player_logo_unique_constraints()
		)
		row.add_child(logo_opt)
		_player_logo_options.append(logo_opt)

	_refresh_player_logo_unique_constraints()

func _refresh_player_logo_unique_constraints() -> void:
	if _player_logo_options.is_empty():
		return

	_suppress_player_signals = true

	var used_by: Dictionary = {} # logo_id -> player_id
	var dup_pids: Array[int] = []
	for pid in range(_player_logo_options.size()):
		var opt := _player_logo_options[pid]
		if opt == null or not is_instance_valid(opt):
			continue
		var choice := int(opt.selected) - 1
		if choice < 0:
			continue
		if used_by.has(choice):
			dup_pids.append(pid)
		else:
			used_by[choice] = pid

	# 若从 settings 恢复时存在重复选择，后面的玩家自动回退到“随机”。
	for pid in dup_pids:
		if pid >= 0 and pid < _player_logo_options.size() and is_instance_valid(_player_logo_options[pid]):
			_player_logo_options[pid].select(0)

	_suppress_player_signals = false

	for pid in range(_player_logo_options.size()):
		var opt := _player_logo_options[pid]
		var preview := _player_logo_previews[pid] if pid < _player_logo_previews.size() else null
		if opt == null or not is_instance_valid(opt):
			continue

		var popup := opt.get_popup()
		var current_choice := int(opt.selected) - 1
		for logo_id in range(min(RESTAURANT_LOGO_TEXTURE_PATHS.size(), 5)):
			var idx := logo_id + 1
			var taken := used_by.has(logo_id) and int(used_by[logo_id]) != pid
			if popup != null:
				popup.set_item_disabled(idx, taken)

		if preview != null and is_instance_valid(preview):
			if current_choice >= 0 and current_choice < RESTAURANT_LOGO_TEXTURE_PATHS.size():
				var small_tex: Texture2D = _logo_icons_small[current_choice] if current_choice < _logo_icons_small.size() else null
				if small_tex != null:
					preview.texture = small_tex
				else:
					var tex_val = load(RESTAURANT_LOGO_TEXTURE_PATHS[current_choice])
					preview.texture = tex_val as Texture2D
			else:
				preview.texture = null

func _ensure_logo_icons_cache() -> void:
	if not _logo_icons_small.is_empty():
		return

	for path in RESTAURANT_LOGO_TEXTURE_PATHS:
		var tex_val = load(path)
		var tex := tex_val as Texture2D
		_logo_icons_small.append(_scale_texture_square(tex, 20))

func _scale_texture_square(tex: Texture2D, size_px: int) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img.resize(size_px, size_px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _build_modules_ui() -> void:
	if _modules_groups_container == null or not is_instance_valid(_modules_groups_container):
		return

	for child in _modules_groups_container.get_children():
		child.queue_free()
	_module_checkboxes.clear()

	var used: Dictionary = {}
	for group_def_val in MODULE_GROUPS:
		if not (group_def_val is Dictionary):
			continue
		var group_def: Dictionary = group_def_val
		var title := str(group_def.get("title", ""))
		var mids: Array[String] = Array(group_def.get("modules", []), TYPE_STRING, "", null)
		var box := _build_module_group_box(title, mids)
		_modules_groups_container.add_child(box)
		for mid in mids:
			used[mid] = true

	var other: Array[String] = []
	for mid in _optional_module_ids:
		if not used.has(mid):
			other.append(mid)
	if not other.is_empty():
		_modules_groups_container.add_child(_build_module_group_box("其他", other))

func _build_module_group_box(title: String, module_ids: Array[String]) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)

	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var mids_copy: Array[String] = module_ids.duplicate()

	var select_btn := Button.new()
	select_btn.text = "组选"
	select_btn.pressed.connect(func() -> void:
		_on_select_group_pressed(mids_copy)
	)
	header.add_child(select_btn)

	var clear_btn := Button.new()
	clear_btn.text = "组不选"
	clear_btn.pressed.connect(func() -> void:
		_on_clear_group_pressed(mids_copy)
	)
	header.add_child(clear_btn)

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

	return box

func _format_module_label(mid: String) -> String:
	var name := mid
	var manifest_val = _available_modules.get(mid, null)
	if manifest_val is ModuleManifest:
		var manifest: ModuleManifest = manifest_val
		name = str(manifest.name)
	return "%s (%s)" % [name, mid]

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
	if _suppress_module_signals:
		return
	if pressed:
		_requested_optional_modules[module_id] = true
	else:
		_requested_optional_modules.erase(module_id)
	_recompute_modules_and_apply_to_ui()

func _recompute_modules_and_apply_to_ui() -> void:
	if _available_modules.is_empty() or _module_checkboxes.is_empty():
		return

	var notes: Array[String] = []
	var new_ms_on := _requested_optional_modules.has("new_milestones")

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

	_suppress_module_signals = true
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
		elif _locked_optional_modules.has(id):
			disabled = true
			if not tt.is_empty():
				tt += "\n"
			tt += "被依赖，需先取消上游模块"
		cb.disabled = disabled
		cb.tooltip_text = tt
	_suppress_module_signals = false

	_set_message("\n".join(notes))

func _compute_effective_optional_modules() -> Dictionary:
	var effective: Dictionary = {}
	for mid_val in _requested_optional_modules.keys():
		effective[str(mid_val)] = true

	var stack: Array[String] = []
	for mid_val in _requested_optional_modules.keys():
		stack.append(str(mid_val))

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

func _apply_module_selection_to_globals() -> bool:
	if _available_modules.is_empty():
		_set_message("模块列表为空，无法开始游戏。")
		return false

	var base: Array[String] = GameDefaultsClass.build_default_enabled_modules_v2()
	if _requested_optional_modules.has("new_milestones"):
		base.erase("base_milestones")

	var requested: Array[String] = []
	for mid_val in _requested_optional_modules.keys():
		var id := str(mid_val)
		if id.is_empty() or id.begins_with("base_"):
			continue
		requested.append(id)
	requested.sort()

	var out: Array[String] = []
	out.append_array(base)
	out.append_array(requested)
	out = Array(out, TYPE_STRING, "", null)

	var plan_read := ModulePlanBuilderClass.build_plan(_available_modules, out)
	if not plan_read.ok:
		_set_message("模块选择无效：%s" % plan_read.error)
		return false

	Globals.enabled_modules_v2 = out
	return true

func _apply_player_profiles_to_globals() -> void:
	var count := int(player_count_spinbox.value)
	for pid in range(count):
		if pid < _player_name_edits.size() and is_instance_valid(_player_name_edits[pid]):
			Globals.set_player_name(pid, str(_player_name_edits[pid].text))
		if pid < _player_logo_options.size() and is_instance_valid(_player_logo_options[pid]):
			var sel := int(_player_logo_options[pid].selected)
			var choice := sel - 1 # 0=随机
			Globals.set_player_restaurant_logo_choice(pid, choice)
