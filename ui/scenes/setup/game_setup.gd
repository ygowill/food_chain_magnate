# 游戏设置场景脚本
extends Control

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleSelectorClass = preload("res://ui/components/module_selector/module_selector.gd")

@onready var player_count_spinbox: SpinBox = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/LeftColumn/PlayerCountContainer/PlayerCountSpinBox
@onready var seed_edit: LineEdit = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/LeftColumn/SeedContainer/SeedLineEdit
@onready var root_vbox: VBoxContainer = $CenterContainer/ContentCenter/VBoxContainer
@onready var spacer2: Control = $CenterContainer/ContentCenter/VBoxContainer/Spacer2
@onready var left_column: VBoxContainer = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/LeftColumn
@onready var right_column: VBoxContainer = $CenterContainer/ContentCenter/VBoxContainer/MainColumns/RightColumn

var _players_section: VBoxContainer = null
var _players_container: VBoxContainer = null
var _modules_section: VBoxContainer = null
var _message_label: Label = null
var _info_label: Label = null

var _player_name_edits: Array[LineEdit] = []
var _player_logo_options: Array[OptionButton] = []
var _player_logo_previews: Array[TextureRect] = []

var _module_selector = null
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
	_ensure_module_selector()
	_rebuild_player_rows()
	_sync_globals_modules_to_module_selector()

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
	_ensure_module_selector()

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

func _ensure_module_selector() -> void:
	if _modules_section == null or not is_instance_valid(_modules_section):
		return
	if _module_selector != null and is_instance_valid(_module_selector):
		return
	_module_selector = ModuleSelectorClass.new()
	_modules_section.add_child(_module_selector)
	_module_selector.notes_changed.connect(func(text: String) -> void:
		_set_message(text)
	)
	_module_selector.load_failed.connect(func(msg: String) -> void:
		_set_message(msg)
	)

func _sync_globals_modules_to_module_selector() -> void:
	if _module_selector == null or not is_instance_valid(_module_selector):
		return
	var base_dir := str(Globals.modules_v2_base_dir)
	var lr: Result = _module_selector.set_modules_base_dir(base_dir)
	if not lr.ok:
		_set_message("加载模块列表失败：%s" % lr.error)
		return
	_module_selector.set_initial_enabled_modules_v2(Array(Globals.enabled_modules_v2, TYPE_STRING, "", null))

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

func _apply_module_selection_to_globals() -> bool:
	if _module_selector == null or not is_instance_valid(_module_selector):
		_set_message("模块选择器未初始化，无法开始游戏。")
		return false
	var vr: Result = _module_selector.validate_selection()
	if not vr.ok:
		_set_message("模块选择无效：%s" % vr.error)
		return false
	var enabled: Array[String] = _module_selector.get_enabled_modules_v2()
	Globals.enabled_modules_v2 = Array(enabled, TYPE_STRING, "", null)
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
