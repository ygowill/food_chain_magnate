# 游戏设置场景脚本
extends Control

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleSelectorClass = preload("res://ui/components/module_selector/module_selector.gd")
const GameSetupTutorialsControllerClass = preload("res://ui/scenes/setup/controllers/tutorials_controller.gd")
const GameSetupTutorialMatchPresetClass = preload("res://ui/scenes/setup/controllers/tutorial_match_preset.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const GameConfigDialogScene = preload("res://ui/dialogs/game_config_dialog.tscn")
const GearIcon = preload("res://assets/ui/icons/kenney/game/gear.png")

@onready var wall_background: ColorRect = $WallBackground
@onready var vignette_overlay: ColorRect = $VignetteOverlay
@onready var card: PanelContainer = $CenterContainer/ContentCenter/Card
@onready var inner_border: PanelContainer = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder
@onready var root_vbox: VBoxContainer = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer
@onready var left_column: VBoxContainer = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/LeftColumn
@onready var right_column: VBoxContainer = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/MainColumns/RightColumn
@onready var back_button: Button = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/ButtonContainer/BackButton
@onready var advanced_button: Button = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/ButtonContainer/AdvancedButton
@onready var start_button: Button = $CenterContainer/ContentCenter/Card/OuterMargin/InnerBorder/Margin/VBoxContainer/ButtonContainer/StartButton

const PLAYER_COLORS: Array[Color] = [
	Color(0.73, 0.23, 0.18),
	Color(0.22, 0.45, 0.65),
	Color(0.28, 0.55, 0.22),
	Color(0.72, 0.58, 0.20),
	Color(0.55, 0.30, 0.58),
	Color(0.20, 0.55, 0.52),
]

var _selected_player_count: int = 2
var _player_count_buttons: Array[Button] = []
var _seed_edit: LineEdit = null

var _players_container: VBoxContainer = null
var _modules_section: VBoxContainer = null
var _message_label: Label = null
var _game_params_panel: PanelContainer = null

var _player_name_edits: Array[LineEdit] = []
var _player_logo_options: Array[OptionButton] = []
var _player_logo_previews: Array[TextureRect] = []

var _module_selector = null
var _suppress_player_signals: bool = false
var _logo_icons_small: Array[Texture2D] = []
var _logo_piece_ids: Array[String] = []

const LOGO_DISPLAY_NAMES: Dictionary = {
	"restaurant_logo_fried_geese_donkey": "驴肉&烧鹅",
	"restaurant_logo_gluttony_inc_burgers": "饕餮汉堡",
	"restaurant_logo_golden_duck_diner": "金鸭小馆",
	"restaurant_logo_santa_maria_pizza": "圣玛丽亚披萨",
	"restaurant_logo_xango_blues_bar": "尚戈蓝调酒吧",
	"restaurant_logo_sixth_chain": "好味来",
}

var _presets: Array = []
var _preset_option: OptionButton = null
var _suppress_preset_revert: bool = false
var _game_config_dialog = null
var _advanced_game_overrides: Dictionary = {}
var _game_option_overrides: Dictionary = {}
var _tutorials_controller = null

func _ready() -> void:
	GameLog.info("GameSetup", "游戏设置界面已加载")
	UiStylesClass.apply_tiled_texture(wall_background, UiStylesClass.WALL_TEXTURE_PATHS, 3.0, Color(0.93, 0.88, 0.75, 1.0))
	UiStylesClass.apply_vignette(vignette_overlay, 0.45, 0.5)
	UiStylesClass.apply_dialog_surface(card)
	UiStylesClass.apply_poster_inner_border(inner_border)
	UiStylesClass.apply_button_secondary(back_button)
	UiStylesClass.apply_button_secondary(advanced_button)
	UiStylesClass.apply_button_primary(start_button)
	advanced_button.icon = GearIcon
	advanced_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_button.expand_icon = false
	advanced_button.add_theme_constant_override("icon_max_width", 16)
	_update_advanced_button_label()

	_advanced_game_overrides = Globals.game_config_overrides.duplicate(true)
	_game_option_overrides = {}
	_sync_game_config_overrides()

	_selected_player_count = Globals.player_count

	_build_decorative_line()
	_build_game_params_section()
	_build_players_section()
	_build_modules_section()
	_build_message_label()

	_rebuild_player_rows()
	_sync_globals_modules_to_module_selector()
	_sync_player_count_module_constraints()
	_initialize_tutorial_flow()

func _exit_tree() -> void:
	if _tutorials_controller != null and _tutorials_controller.has_method("dispose"):
		_tutorials_controller.dispose()
	_tutorials_controller = null

# ── 装饰分隔线 ──────────────────────────────────────────

func _build_decorative_line() -> void:
	var title_node := root_vbox.get_node_or_null("Title")
	if title_node == null:
		return
	var line := ColorRect.new()
	line.name = "DecorativeLine"
	line.custom_minimum_size = Vector2(320, 2)
	line.color = Color(0.73, 0.23, 0.18, 0.5)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root_vbox.add_child(line)
	root_vbox.move_child(line, title_node.get_index() + 1)

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

# ── 游戏参数区块（玩家数量按钮组 + 种子） ──────────────

func _build_game_params_section() -> void:
	var panel := _build_section_panel()
	_game_params_panel = panel
	left_column.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "游戏参数"
	header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(header)
	vbox.add_child(header)

	# 玩家数量标签
	var count_label := Label.new()
	count_label.text = "玩家数量"
	UiStylesClass.apply_label_hint_dark(count_label)
	vbox.add_child(count_label)

	# 按钮组 [2] [3] [4] [5] [6]
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_player_count_buttons.clear()
	for i in range(2, 7):
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
	vbox.add_child(seed_label)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "留空自动生成"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_seed_edit)
	vbox.add_child(_seed_edit)

	if Globals.random_seed != 0:
		_seed_edit.text = str(Globals.random_seed)

func _on_player_count_button_pressed(count: int) -> void:
	_selected_player_count = count
	_update_player_count_button_styles()
	_sync_player_count_module_constraints()
	_rebuild_player_rows()

func _update_player_count_button_styles() -> void:
	for i in range(_player_count_buttons.size()):
		var btn := _player_count_buttons[i]
		var count := i + 2
		if count == _selected_player_count:
			UiStylesClass.apply_button_primary(btn)
		else:
			UiStylesClass.apply_button_secondary(btn)

# ── 玩家配置区块 ────────────────────────────────────────

func _build_players_section() -> void:
	var panel := _build_section_panel()
	left_column.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "玩家配置"
	header.add_theme_font_size_override("font_size", 16)
	UiStylesClass.apply_label_dark(header)
	vbox.add_child(header)

	_players_container = VBoxContainer.new()
	_players_container.name = "PlayersContainer"
	_players_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_players_container)

# ── 模块选择区块 ────────────────────────────────────────

func _build_modules_section() -> void:
	_modules_section = VBoxContainer.new()
	_modules_section.name = "ModulesSection"
	_modules_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modules_section.add_theme_constant_override("separation", 6)
	right_column.add_child(_modules_section)

	_load_presets()
	if not _presets.is_empty():
		_build_preset_row()

	_ensure_module_selector()

func _build_message_label() -> void:
	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.visible = false
	UiStylesClass.apply_label_error(_message_label)
	var btn_container := root_vbox.get_node_or_null("ButtonContainer")
	root_vbox.add_child(_message_label)
	if btn_container != null:
		root_vbox.move_child(_message_label, btn_container.get_index())

# ── 导航与启动 ──────────────────────────────────────────

func _on_back_pressed() -> void:
	GameLog.info("GameSetup", "返回上一场景")
	SceneManager.go_back()

func _on_advanced_pressed() -> void:
	if _game_config_dialog == null or not is_instance_valid(_game_config_dialog):
		_game_config_dialog = GameConfigDialogScene.instantiate()
		add_child(_game_config_dialog)
		_game_config_dialog.config_confirmed.connect(_on_game_config_confirmed)
	_game_config_dialog.load_overrides(_advanced_game_overrides)
	_game_config_dialog.open()

func _on_game_config_confirmed(overrides: Dictionary) -> void:
	_advanced_game_overrides = overrides.duplicate(true)
	_sync_game_config_overrides()

func _update_advanced_button_label() -> void:
	if advanced_button == null or not is_instance_valid(advanced_button):
		return
	if Globals.game_config_overrides.is_empty():
		advanced_button.text = "高级选项"
	else:
		advanced_button.text = "高级选项（已设）"

func _sync_game_config_overrides() -> void:
	Globals.game_config_overrides = _advanced_game_overrides.duplicate(true)
	Globals.game_option_overrides = _game_option_overrides.duplicate(true)
	_update_advanced_button_label()

func _on_start_pressed() -> void:
	_set_message("")

	if _tutorials_controller != null and _tutorials_controller.has_method("should_apply_tutorial_match_preset_on_start"):
		if bool(_tutorials_controller.should_apply_tutorial_match_preset_on_start()):
			_apply_tutorial_match_preset()

	_sync_game_config_overrides()

	Globals.player_count = _selected_player_count

	if _seed_edit == null or _seed_edit.text.is_empty():
		Globals.generate_seed()
		GameLog.info("GameSetup", "生成随机种子: %d" % Globals.random_seed)
	else:
		Globals.random_seed = _seed_edit.text.to_int()
		GameLog.info("GameSetup", "使用指定种子: %d" % Globals.random_seed)

	if not _apply_module_selection_to_globals():
		return

	_apply_player_profiles_to_globals()
	if _tutorials_controller != null and _tutorials_controller.has_method("sync_start_flags"):
		_tutorials_controller.sync_start_flags()
	Globals.save_settings()

	GameLog.info("GameSetup", "开始游戏 - 玩家数: %d, 种子: %d" % [
		Globals.player_count,
		Globals.random_seed
	])

	if SceneManager != null and SceneManager.has_method("show_loading"):
		SceneManager.show_loading("正在开始新游戏...")
		await get_tree().process_frame

	Globals.set_current_game_engine(null)
	SceneManager.goto_game()

func _initialize_tutorial_flow() -> void:
	_tutorials_controller = GameSetupTutorialsControllerClass.new(
		self,
		_game_params_panel,
		_modules_section,
		start_button,
		Callable(self, "_get_module_selector_tutorial_targets"),
		Callable(self, "_apply_tutorial_match_preset")
	)
	_tutorials_controller.initialize()

func _apply_tutorial_match_preset() -> void:
	var preset := GameSetupTutorialMatchPresetClass.build_preset()
	var target_player_count := clampi(int(preset.get("player_count", _selected_player_count)), Globals.MIN_PLAYERS, Globals.MAX_PLAYERS)
	if target_player_count != _selected_player_count:
		_on_player_count_button_pressed(target_player_count)

	if _seed_edit != null and is_instance_valid(_seed_edit):
		_seed_edit.text = str(int(preset.get("seed", 0)))

	var enabled_modules_val = preset.get("enabled_modules_v2", null)
	if enabled_modules_val is Array:
		var enabled_modules := Array(enabled_modules_val, TYPE_STRING, "", null)
		if _module_selector != null and is_instance_valid(_module_selector) and _module_selector.has_method("set_initial_enabled_modules_v2"):
			_module_selector.call("set_initial_enabled_modules_v2", enabled_modules)

	var patch: Dictionary = {}
	var patch_val = preset.get("game_option_overrides", null)
	if patch_val is Dictionary:
		patch = Dictionary(patch_val).duplicate(true)
	_game_option_overrides = patch
	if _module_selector != null and is_instance_valid(_module_selector) and _module_selector.has_method("set_game_options_from_overrides_patch"):
		_module_selector.call("set_game_options_from_overrides_patch", patch)
	_sync_game_config_overrides()
	_set_message("已应用教学局预设：2 人、固定种子、简化规则。")

func _get_module_selector_tutorial_targets() -> Dictionary:
	var module_targets: Dictionary = {}
	if _module_selector != null and is_instance_valid(_module_selector) and _module_selector.has_method("get_tutorial_targets"):
		var val = _module_selector.call("get_tutorial_targets")
		if val is Dictionary:
			module_targets = val
	return module_targets

# ── 消息提示 ────────────────────────────────────────────

func _set_message(text: String) -> void:
	if _message_label == null or not is_instance_valid(_message_label):
		return
	var s := str(text).strip_edges()
	_message_label.text = s
	_message_label.visible = not s.is_empty()

# ── 模块选择器 ──────────────────────────────────────────

func _ensure_module_selector() -> void:
	if _modules_section == null or not is_instance_valid(_modules_section):
		return
	if _module_selector != null and is_instance_valid(_module_selector):
		return
	_module_selector = ModuleSelectorClass.new()
	_modules_section.add_child(_module_selector)
	if _module_selector.has_method("set_show_tooltips"):
		_module_selector.call("set_show_tooltips", false)
	if _module_selector.has_method("set_show_notes"):
		_module_selector.call("set_show_notes", false)
	if _module_selector.has_method("set_show_game_options"):
		_module_selector.call("set_show_game_options", true)
	_module_selector.load_failed.connect(func(msg: String) -> void:
		_set_message(msg)
	)
	_module_selector.selection_changed.connect(func(_modules: Array) -> void:
		if _suppress_preset_revert:
			return
		_revert_preset_to_custom()
	)
	if _module_selector.has_signal("game_options_changed"):
		_module_selector.game_options_changed.connect(func(_opts: Dictionary) -> void:
			_game_option_overrides = {}
			if _module_selector != null and is_instance_valid(_module_selector) and _module_selector.has_method("get_game_config_overrides_patch"):
				var v = _module_selector.call("get_game_config_overrides_patch")
				if v is Dictionary:
					_game_option_overrides = (v as Dictionary).duplicate(true)
			_sync_game_config_overrides()
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

func _sync_player_count_module_constraints() -> void:
	if _module_selector == null or not is_instance_valid(_module_selector):
		return
	if _module_selector.has_method("set_setup_player_count"):
		_module_selector.call("set_setup_player_count", _selected_player_count)

# ── 模块预设 ──────────────────────────────────────────

func _load_presets() -> void:
	var path := "res://data/config/module_presets.json"
	if not FileAccess.file_exists(path):
		GameLog.warn("GameSetup", "预设配置文件不存在: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLog.warn("GameSetup", "无法打开预设配置文件: %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		GameLog.warn("GameSetup", "解析预设配置文件失败: %s" % json.get_error_message())
		return
	var data = json.data
	if not (data is Dictionary) or not data.has("presets"):
		return
	_presets = Array(data["presets"])

func _build_preset_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modules_section.add_child(row)

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
			if _module_selector.has_method("set_modules_editable"):
				_module_selector.call("set_modules_editable", true)
			else:
				_module_selector.set_editable(true)
		return
	var preset_idx := idx - 1
	if preset_idx < 0 or preset_idx >= _presets.size():
		return
	var preset: Dictionary = _presets[preset_idx]
	var module_ids: Array[String] = _resolve_preset_modules(preset)

	if _module_selector != null and is_instance_valid(_module_selector):
		_suppress_preset_revert = true
		if _module_selector.has_method("set_modules_editable"):
			_module_selector.call("set_modules_editable", true)
		else:
			_module_selector.set_editable(true)
		_module_selector.set_initial_enabled_modules_v2(module_ids)
		if _module_selector.has_method("set_modules_editable"):
			_module_selector.call("set_modules_editable", false)
		else:
			_module_selector.set_editable(false)
		_suppress_preset_revert = false

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
			if _module_selector.has_method("set_modules_editable"):
				_module_selector.call("set_modules_editable", true)
			else:
				_module_selector.set_editable(true)

# ── 玩家行重建（卡片布局） ──────────────────────────────

func _rebuild_player_rows() -> void:
	if _players_container == null or not is_instance_valid(_players_container):
		return

	_ensure_logo_icons_cache()
	var logo_count := _logo_icons_small.size()

	for child in _players_container.get_children():
		child.queue_free()
	_player_name_edits.clear()
	_player_logo_options.clear()
	_player_logo_previews.clear()

	var count := _selected_player_count
	for pid in range(count):
		_players_container.add_child(_build_player_card(pid, logo_count))

	_refresh_player_logo_unique_constraints()

func _build_player_card(pid: int, logo_count: int) -> Control:
	var player_color := PLAYER_COLORS[pid] if pid < PLAYER_COLORS.size() else PLAYER_COLORS[0]

	# 卡片外壳（紧凑单行）
	var card_panel := PanelContainer.new()
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.95, 0.90, 0.80, 0.5)
	card_style.border_color = Color(0.17, 0.13, 0.09, 0.12)
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.content_margin_left = 0
	card_style.content_margin_top = 0
	card_style.content_margin_right = 0
	card_style.content_margin_bottom = 0
	card_panel.add_theme_stylebox_override("panel", card_style)
	card_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	# 横向：色彩条 + 单行内容
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	card_panel.add_child(row)

	var color_bar := ColorRect.new()
	color_bar.custom_minimum_size = Vector2(4, 0)
	color_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_bar.color = player_color
	row.add_child(color_bar)

	# 内容行（带内边距）
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_top", 6)
	content_margin.add_theme_constant_override("margin_right", 10)
	content_margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(content_margin)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 8)
	content_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content_margin.add_child(content_row)

	# 玩家编号
	var label := Label.new()
	label.text = "P%d" % (pid + 1)
	label.custom_minimum_size = Vector2(32, 0)
	UiStylesClass.apply_label_dark(label)
	content_row.add_child(label)

	# 名称输入
	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.placeholder_text = "名称"
	name_edit.text = Globals.get_player_name(pid)
	UiStylesClass.apply_line_edit_field(name_edit)
	content_row.add_child(name_edit)
	_player_name_edits.append(name_edit)

	# logo 预览
	var logo_preview := TextureRect.new()
	logo_preview.custom_minimum_size = Vector2(28, 28)
	logo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content_row.add_child(logo_preview)
	_player_logo_previews.append(logo_preview)

	# logo 选择
	var logo_opt := OptionButton.new()
	logo_opt.custom_minimum_size = Vector2(200, 0)
	logo_opt.add_item("随机")
	for i in range(logo_count):
		var icon_tex := _logo_icons_small[i] if i < _logo_icons_small.size() else null
		var logo_name := _get_logo_display_name(i)
		if icon_tex != null:
			logo_opt.add_icon_item(icon_tex, logo_name)
		else:
			logo_opt.add_item(logo_name)

	var choice := Globals.get_player_restaurant_logo_choice(pid)
	if choice >= 0 and choice < logo_count:
		logo_opt.select(choice + 1)
	else:
		logo_opt.select(0)

	logo_opt.item_selected.connect(func(_idx: int) -> void:
		if _suppress_player_signals:
			return
		_refresh_player_logo_unique_constraints()
	)
	UiStylesClass.apply_option_button_field(logo_opt)
	content_row.add_child(logo_opt)
	_player_logo_options.append(logo_opt)

	return card_panel

# ── logo 唯一性约束 ─────────────────────────────────────

func _refresh_player_logo_unique_constraints() -> void:
	if _player_logo_options.is_empty():
		return

	_suppress_player_signals = true
	_ensure_logo_icons_cache()
	var logo_count := _logo_icons_small.size()

	var used_by: Dictionary = {}
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
		for logo_id in range(logo_count):
			var idx := logo_id + 1
			var taken := used_by.has(logo_id) and int(used_by[logo_id]) != pid
			if popup != null:
				popup.set_item_disabled(idx, taken)

		if preview != null and is_instance_valid(preview):
			if current_choice >= 0 and current_choice < logo_count:
				var small_tex: Texture2D = _logo_icons_small[current_choice] if current_choice < _logo_icons_small.size() else null
				preview.texture = small_tex
			else:
				preview.texture = null

# ── logo 图标缓存 ──────────────────────────────────────

func _ensure_logo_icons_cache() -> void:
	if not _logo_icons_small.is_empty():
		return

	var base_dir := str(Globals.modules_v2_base_dir)
	var modules: Array[String] = ["base_pieces"]
	var read: Result = MapSkinBuilderClass.build_for_modules(base_dir, modules, 40)
	if not read.ok:
		GameLog.warn("GameSetup", "加载餐厅 Logo 贴图失败: %s" % read.error)
		return
	var skin = read.value
	if skin == null or not skin.has_method("get_piece_texture") or not skin.has_method("get_restaurant_logo_piece_ids"):
		GameLog.warn("GameSetup", "加载餐厅 Logo 贴图失败：skin 类型错误")
		return

	var logo_ids = skin.get_restaurant_logo_piece_ids()
	if not (logo_ids is Array) or (logo_ids as Array).is_empty():
		GameLog.warn("GameSetup", "加载餐厅 Logo 贴图失败：缺少 restaurant_logo_piece_ids")
		return

	for piece_id_val in (logo_ids as Array):
		var piece_id := str(piece_id_val).strip_edges()
		if piece_id.is_empty():
			_logo_icons_small.append(null)
			_logo_piece_ids.append("")
			continue
		var tex: Texture2D = skin.get_piece_texture(piece_id)
		_logo_icons_small.append(_scale_texture_square(tex, 20))
		_logo_piece_ids.append(piece_id)

func _scale_texture_square(tex: Texture2D, size_px: int) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img.resize(size_px, size_px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _get_logo_display_name(index: int) -> String:
	if index >= 0 and index < _logo_piece_ids.size():
		var piece_id := _logo_piece_ids[index]
		if LOGO_DISPLAY_NAMES.has(piece_id):
			return str(LOGO_DISPLAY_NAMES[piece_id])
	return "店铺 %d" % (index + 1)

# ── Globals 同步 ────────────────────────────────────────

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
	var count := _selected_player_count
	for pid in range(count):
		if pid < _player_name_edits.size() and is_instance_valid(_player_name_edits[pid]):
			Globals.set_player_name(pid, str(_player_name_edits[pid].text))
		if pid < _player_logo_options.size() and is_instance_valid(_player_logo_options[pid]):
			var sel := int(_player_logo_options[pid].selected)
			var choice := sel - 1
			Globals.set_player_restaurant_logo_choice(pid, choice)
