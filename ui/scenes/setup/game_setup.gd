# 游戏设置场景脚本
extends Control

const GameConfigClass = preload("res://core/data/game_config.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")

@onready var player_count_spinbox: SpinBox = $CenterContainer/VBoxContainer/PlayerCountContainer/PlayerCountSpinBox
@onready var seed_edit: LineEdit = $CenterContainer/VBoxContainer/SeedContainer/SeedLineEdit
@onready var root_vbox: VBoxContainer = $CenterContainer/VBoxContainer
@onready var spacer2: Control = $CenterContainer/VBoxContainer/Spacer2

var _extra_tabs: TabContainer = null
var _modules_container: VBoxContainer = null
var _players_container: VBoxContainer = null
var _reserve_container: VBoxContainer = null
var _info_label: Label = null

var _module_checkboxes: Dictionary = {}  # module_id -> CheckBox
var _player_name_edits: Array[LineEdit] = []
var _player_color_options: Array[OptionButton] = []
var _reserve_card_options: Array[OptionButton] = []

var _available_modules: Dictionary = {}  # module_id -> ModuleManifest
var _game_config: GameConfig = null

const PLAYER_COLOR_NAMES: Array[String] = ["红", "蓝", "绿", "黄", "紫"]
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3, 1),
	Color(0.3, 0.6, 0.9, 1),
	Color(0.3, 0.8, 0.4, 1),
	Color(0.9, 0.7, 0.2, 1),
	Color(0.7, 0.4, 0.9, 1),
]

func _ready() -> void:
	GameLog.info("GameSetup", "游戏设置界面已加载")
	# 设置默认值
	player_count_spinbox.value = Globals.player_count
	if Globals.random_seed != 0:
		seed_edit.text = str(Globals.random_seed)

	if not player_count_spinbox.value_changed.is_connected(_on_player_count_changed):
		player_count_spinbox.value_changed.connect(_on_player_count_changed)

	_load_game_config()
	_ensure_extra_tabs()
	_refresh_extra_ui()

func _on_back_pressed() -> void:
	GameLog.info("GameSetup", "返回主菜单")
	SceneManager.go_back()

func _on_start_pressed() -> void:
	# 保存设置
	Globals.player_count = int(player_count_spinbox.value)

	# 处理随机种子
	if seed_edit.text.is_empty():
		Globals.generate_seed()
		GameLog.info("GameSetup", "生成随机种子: %d" % Globals.random_seed)
	else:
		Globals.random_seed = seed_edit.text.to_int()
		GameLog.info("GameSetup", "使用指定种子: %d" % Globals.random_seed)

	_apply_module_selection_to_globals()
	_apply_player_profiles_to_globals()
	_apply_reserve_card_selection_to_globals()
	Globals.save_settings()

	GameLog.info("GameSetup", "开始游戏 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])

	# 进入游戏场景
	Globals.set_current_game_engine(null)
	SceneManager.goto_game()

func _on_player_count_changed(_value: float) -> void:
	_refresh_extra_ui()

func _load_game_config() -> void:
	var cfg_read := GameConfigClass.load_default()
	if not cfg_read.ok:
		GameLog.warn("GameSetup", "加载 GameConfig 失败（将使用默认储备卡 UI 兜底）: %s" % cfg_read.error)
		return
	_game_config = cfg_read.value

func _ensure_extra_tabs() -> void:
	if _extra_tabs != null and is_instance_valid(_extra_tabs):
		return
	if root_vbox == null:
		return
	if spacer2 == null:
		return

	_extra_tabs = TabContainer.new()
	_extra_tabs.name = "ExtraTabs"
	_extra_tabs.custom_minimum_size = Vector2(680, 320)

	root_vbox.add_child(_extra_tabs)
	root_vbox.move_child(_extra_tabs, spacer2.get_index())

	var modules_page := VBoxContainer.new()
	modules_page.name = "ModulesPage"
	_extra_tabs.add_child(modules_page)
	_extra_tabs.set_tab_title(_extra_tabs.get_tab_count() - 1, "模块")
	_modules_container = _build_scroll_section(modules_page, "选择要启用的扩展模块（基础 base_* 模块始终启用）")

	var players_page := VBoxContainer.new()
	players_page.name = "PlayersPage"
	_extra_tabs.add_child(players_page)
	_extra_tabs.set_tab_title(_extra_tabs.get_tab_count() - 1, "玩家")
	_players_container = _build_scroll_section(players_page, "设置玩家名称与颜色")

	var reserve_page := VBoxContainer.new()
	reserve_page.name = "ReservePage"
	_extra_tabs.add_child(reserve_page)
	_extra_tabs.set_tab_title(_extra_tabs.get_tab_count() - 1, "储备卡")
	_reserve_container = _build_scroll_section(reserve_page, "每位玩家选择一张银行储备卡（规则：秘密选择；此处为同屏配置）")

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.text = "提示：初始餐厅放置将从“顺序轨最后一位”开始逆序进行。"
	root_vbox.add_child(_info_label)
	root_vbox.move_child(_info_label, spacer2.get_index())

func _build_scroll_section(parent: Control, header_text: String) -> VBoxContainer:
	var header := Label.new()
	header.text = header_text
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	parent.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	return inner

func _refresh_extra_ui() -> void:
	_rebuild_modules_list()
	_rebuild_player_rows()
	_rebuild_reserve_rows()

func _rebuild_modules_list() -> void:
	if _modules_container == null or not is_instance_valid(_modules_container):
		return

	for child in _modules_container.get_children():
		child.queue_free()
	_module_checkboxes.clear()
	_available_modules.clear()

	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(Globals.modules_v2_base_dir)
	if not base_dirs_read.ok:
		GameLog.warn("GameSetup", "解析 modules_v2_base_dir 失败: %s" % base_dirs_read.error)
		return
	var base_dirs: Array[String] = base_dirs_read.value

	var manifests_read := ModulePackageLoaderClass.load_all_from_dirs(base_dirs)
	if not manifests_read.ok:
		GameLog.warn("GameSetup", "加载模块列表失败: %s" % manifests_read.error)
		return
	_available_modules = manifests_read.value

	var optional_ids: Array[String] = []
	for mid_val in _available_modules.keys():
		if not (mid_val is String):
			continue
		var mid: String = str(mid_val)
		if mid.begins_with("base_"):
			continue
		optional_ids.append(mid)
	optional_ids.sort()

	for mid in optional_ids:
		var name := mid
		var deps: Array[String] = []
		var manifest_val = _available_modules.get(mid, null)
		if manifest_val is ModuleManifest:
			var manifest: ModuleManifest = manifest_val
			name = str(manifest.name)
			deps = Array(manifest.dependencies, TYPE_STRING, "", null)

		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [name, mid]
		cb.button_pressed = Globals.enabled_modules_v2.has(mid)
		if not deps.is_empty():
			cb.tooltip_text = "依赖: %s" % ", ".join(deps)
		_modules_container.add_child(cb)
		_module_checkboxes[mid] = cb

func _rebuild_player_rows() -> void:
	if _players_container == null or not is_instance_valid(_players_container):
		return

	for child in _players_container.get_children():
		child.queue_free()
	_player_name_edits.clear()
	_player_color_options.clear()

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

		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(18, 18)
		row.add_child(color_rect)

		var color_opt := OptionButton.new()
		color_opt.custom_minimum_size = Vector2(110, 0)
		for i in range(min(PLAYER_COLOR_NAMES.size(), PLAYER_COLORS.size())):
			color_opt.add_item(PLAYER_COLOR_NAMES[i])
		var default_idx := Globals.get_player_color_index(pid)
		default_idx = clamp(default_idx, 0, PLAYER_COLORS.size() - 1)
		color_opt.select(default_idx)
		color_rect.color = PLAYER_COLORS[default_idx]
		color_opt.item_selected.connect(func(idx: int):
			if idx >= 0 and idx < PLAYER_COLORS.size():
				color_rect.color = PLAYER_COLORS[idx]
		)
		row.add_child(color_opt)
		_player_color_options.append(color_opt)

func _rebuild_reserve_rows() -> void:
	if _reserve_container == null or not is_instance_valid(_reserve_container):
		return

	for child in _reserve_container.get_children():
		child.queue_free()
	_reserve_card_options.clear()

	var cards: Array[Dictionary] = []
	var default_selected := 0
	if _game_config != null:
		cards = _game_config.build_reserve_cards()
		default_selected = int(_game_config.player_reserve_card_selected)
	else:
		cards = [
			{"type": 5, "cash": 50, "ceo_slots": 2},
			{"type": 10, "cash": 100, "ceo_slots": 3},
			{"type": 20, "cash": 150, "ceo_slots": 4},
		]
		default_selected = 1

	var count := int(player_count_spinbox.value)
	for pid in range(count):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		_reserve_container.add_child(row)

		var label := Label.new()
		label.text = "玩家 %d" % (pid + 1)
		label.custom_minimum_size = Vector2(70, 0)
		row.add_child(label)

		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(360, 0)
		for i in range(cards.size()):
			var c: Dictionary = cards[i]
			var t: int = int(c.get("type", 0))
			var cash: int = int(c.get("cash", 0))
			var slots: int = int(c.get("ceo_slots", 0))
			opt.add_item("类型 %d：+$%d，CEO 卡槽=%d" % [t, cash, slots])

		var selected := default_selected
		if Globals.reserve_card_selected_by_player.size() == count:
			selected = int(Globals.reserve_card_selected_by_player[pid])
		selected = clamp(selected, 0, max(0, cards.size() - 1))
		opt.select(selected)

		row.add_child(opt)
		_reserve_card_options.append(opt)

func _apply_module_selection_to_globals() -> void:
	var requested: Array[String] = GameDefaultsClass.build_default_enabled_modules_v2()
	for mid in _module_checkboxes.keys():
		var cb_val = _module_checkboxes[mid]
		if cb_val is CheckBox and is_instance_valid(cb_val) and cb_val.button_pressed:
			requested.append(str(mid))
	Globals.enabled_modules_v2 = Array(requested, TYPE_STRING, "", null)

func _apply_player_profiles_to_globals() -> void:
	var count := int(player_count_spinbox.value)
	for pid in range(count):
		if pid < _player_name_edits.size() and is_instance_valid(_player_name_edits[pid]):
			Globals.set_player_name(pid, str(_player_name_edits[pid].text))
		if pid < _player_color_options.size() and is_instance_valid(_player_color_options[pid]):
			Globals.set_player_color_index(pid, int(_player_color_options[pid].selected))

func _apply_reserve_card_selection_to_globals() -> void:
	var count := int(player_count_spinbox.value)
	var out: Array[int] = []
	for pid in range(count):
		if pid < _reserve_card_options.size() and is_instance_valid(_reserve_card_options[pid]):
			out.append(int(_reserve_card_options[pid].selected))
		else:
			out.append(0)
	Globals.reserve_card_selected_by_player = out
