# 全局变量与配置
# 存储游戏版本、当前配置和运行时状态
extends Node

signal audio_muted_changed(muted: bool)

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const GameConstantsClass = preload("res://core/engine/game_constants.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const SoundManagerClass = preload("res://ui/audio/sound_manager.gd")
const MusicManagerClass = preload("res://ui/audio/music_manager.gd")
const FALLBACK_FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

# 版本信息
const SCHEMA_VERSION := GameStateClass.SCHEMA_VERSION

# 游戏配置（新游戏时设置）
var player_count: int = 2
var enabled_modules_v2: Array[String] = GameDefaultsClass.build_default_enabled_modules_v2()
var modules_v2_base_dir: String = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR # 可用 ';' 分隔多个目录，例如 res://modules;res://modules_test
var language: String = "zh"
var random_seed: int = 0
var reserve_card_selected_by_player: Array[int] = []

# 高级游戏配置覆盖（GameConfigDialog 设置）
var game_config_overrides: Dictionary = {}

# 游戏选项覆盖（ModuleSelector/Setup 的“游戏选项”预设）
var game_option_overrides: Dictionary = {}

# 运行时状态
var current_game_engine = null  # GameEngine 实例
var is_game_active: bool = false
var pending_replay_file_path: String = "" # 主菜单选择回放文件后，用于进入 Game 场景自动打开回放播放器
var tutorial_pending_setup_tour: bool = false
var tutorial_pending_game_ui_tour: bool = false
var tutorial_pending_flow_tutorial: bool = false
var tutorial_match_enabled: bool = false

# 玩家数范围
const MIN_PLAYERS := GameConstantsClass.MIN_PLAYERS
const MAX_PLAYERS := GameConstantsClass.MAX_PLAYERS

# 玩家外观/命名（用户设置）
const PLAYER_COLOR_PALETTE: Array[Color] = [
	Color(0.9, 0.3, 0.3, 1),  # 红
	Color(0.3, 0.6, 0.9, 1),  # 蓝
	Color(0.3, 0.8, 0.4, 1),  # 绿
	Color(0.9, 0.7, 0.2, 1),  # 黄
	Color(0.7, 0.4, 0.9, 1),  # 紫
	Color(0.95, 0.5, 0.15, 1),  # 橙
]
const DEFAULT_RESTAURANT_LOGO_COUNT := 6

var player_names: Array[String] = []
var player_color_indices: Array[int] = []  # player_id -> palette index
var player_restaurant_logo_choices: Array[int] = []  # player_id -> logo_id（-1=随机）

# UI/游戏设置（SettingsDialog）
var ui_scale: float = 1.0
var ui_layout_version: int = 2 # 仅支持新布局（v2）
var display_fullscreen: bool = false
var display_vsync: bool = true
var display_resolution: Vector2i = Vector2i(1920, 1080)
var confirm_actions: bool = true
var show_hints: bool = true
var animation_speed: float = 1.0
var replay_load_playable: bool = false # 载入回放后直接进入可操作模式（非只读回放）
var show_tile_ids: bool = false
var show_cell_hover_tooltip: bool = false
var font_scale: float = 1.1
var log_font_scale: float = 1.35

var _base_fallback_font_size: int = 16

func get_version() -> String:
	var v = ProjectSettings.get_setting("application/config/version", "")
	var s := str(v).strip_edges()
	if s.is_empty():
		return "0.0.0"
	return s

func _ready() -> void:
	_apply_fallback_font()
	_base_fallback_font_size = int(ThemeDB.fallback_font_size)
	GameLog.info("Globals", "全局配置初始化 v%s" % get_version())
	_load_settings()
	_ensure_player_profiles()
	_apply_display_settings()
	_apply_ui_scale()
	_apply_font_scale()

func _apply_fallback_font() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fallback_font: Font = load(FALLBACK_FONT_PATH)
	if fallback_font == null:
		return
	ThemeDB.fallback_font = fallback_font
	var default_theme := ThemeDB.get_default_theme()
	if default_theme != null:
		default_theme.set_default_font(fallback_font)
	_log_font_probe()

func _log_font_probe() -> void:
	if ThemeDB.fallback_font == null:
		return
	var font := ThemeDB.fallback_font
	var supports_lock := font.has_char(0x1F512)
	var supports_grin := font.has_char(0x1F600)
	var supports_bullet := font.has_char(0x2022)
	var supports_circle := font.has_char(0x25CF)
	GameLog.info("Globals", "Font probe: lock=%s grin=%s bullet=%s circle=%s" % [supports_lock, supports_grin, supports_bullet, supports_circle])

# 加载用户设置
func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		language = config.get_value("game", "language", "zh")
		display_fullscreen = bool(config.get_value("display", "fullscreen", display_fullscreen))
		display_vsync = bool(config.get_value("display", "vsync", display_vsync))
		var res_val = config.get_value("display", "resolution", display_resolution)
		if res_val is Vector2i:
			display_resolution = res_val
		elif res_val is Vector2:
			display_resolution = Vector2i(int((res_val as Vector2).x), int((res_val as Vector2).y))
		ui_scale = float(config.get_value("display", "ui_scale", 1.0))
		show_tile_ids = bool(config.get_value("display", "show_tile_ids", false))
		show_cell_hover_tooltip = bool(config.get_value("display", "show_cell_hover_tooltip", false))
		font_scale = clampf(float(config.get_value("display", "font_scale", font_scale)), 0.5, 2.0)
		log_font_scale = clampf(float(config.get_value("display", "log_font_scale", log_font_scale)), 0.5, 3.0)
		confirm_actions = bool(config.get_value("game", "confirm_actions", true))
		show_hints = bool(config.get_value("game", "show_hints", true))
		animation_speed = float(config.get_value("game", "animation_speed", 1.0))
		replay_load_playable = bool(config.get_value("game", "replay_load_playable", false))

		var mods_val = config.get_value("game", "enabled_modules_v2", null)
		if mods_val is Array and not Array(mods_val).is_empty():
			enabled_modules_v2 = Array(mods_val, TYPE_STRING, "", null)
		var base_dir_val = config.get_value("game", "modules_v2_base_dir", null)
		if base_dir_val is String and not str(base_dir_val).strip_edges().is_empty():
			modules_v2_base_dir = _normalize_modules_base_dir(str(base_dir_val))

		var names_val = config.get_value("players", "names", null)
		if names_val is Array:
			player_names = Array(names_val, TYPE_STRING, "", null)
		var colors_val = config.get_value("players", "color_indices", null)
		if colors_val is Array:
			player_color_indices = []
			for i in range(min(Array(colors_val).size(), MAX_PLAYERS)):
				var v = Array(colors_val)[i]
				if v is int or v is float:
					player_color_indices.append(int(v))

		var logos_val = config.get_value("players", "restaurant_logo_choices", null)
		if logos_val is Array:
			player_restaurant_logo_choices = []
			for i in range(min(Array(logos_val).size(), MAX_PLAYERS)):
				var v = Array(logos_val)[i]
				if v is int or v is float:
					player_restaurant_logo_choices.append(int(v))

		GameLog.info("Globals", "已加载用户设置")
	# 强制新布局（v2），忽略历史配置值（issue_tracker #60）。
	ui_layout_version = 2

func _apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return

	if display_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if display_resolution.x > 0 and display_resolution.y > 0:
			DisplayServer.window_set_size(display_resolution)

	if display_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _apply_ui_scale() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	if get_tree().root is Window:
		var w: Window = get_tree().root
		w.content_scale_factor = clampf(ui_scale, 0.5, 2.0)

func _apply_font_scale() -> void:
	var s := clampf(font_scale, 0.5, 2.0)
	ThemeDB.fallback_font_size = maxi(1, int(round(float(_base_fallback_font_size) * s)))

func apply_font_scale() -> void:
	_apply_font_scale()

func get_scaled_font_size(base_size: int) -> int:
	return maxi(1, int(round(float(base_size) * clampf(font_scale, 0.5, 2.0))))

func get_log_font_size(base_size: int) -> int:
	return maxi(1, int(round(float(base_size) * clampf(log_font_scale, 0.5, 3.0))))

# 音频设置快捷操作（主菜单/游戏内一键静音）
func is_audio_muted() -> bool:
	var muted := false
	var sm := SoundManagerClass.get_instance()
	if sm != null and is_instance_valid(sm):
		muted = muted or bool(sm.is_muted())
	var mm := MusicManagerClass.get_instance()
	if mm != null and is_instance_valid(mm):
		muted = muted or bool(mm.is_muted())
	if sm != null or mm != null:
		return muted

	var config := ConfigFile.new()
	if config.load("user://sound_settings.cfg") == OK:
		return bool(config.get_value("mix", "mute", false))
	return false

func set_audio_muted(muted: bool) -> void:
	var target := bool(muted)
	var prev := is_audio_muted()

	var config := ConfigFile.new()
	config.load("user://sound_settings.cfg") # 允许文件不存在；保留其它系统写入的设置
	# 确保 mix/music 关键字段存在（避免仅写入 mute 导致下次启动音量回退到 100%）
	if not config.has_section_key("mix", "master_volume"):
		config.set_value("mix", "master_volume", 0.8)
	if not config.has_section_key("mix", "music_volume"):
		config.set_value("mix", "music_volume", 0.3)
	if not config.has_section_key("mix", "sfx_volume"):
		config.set_value("mix", "sfx_volume", 0.8)
	if not config.has_section_key("music", "volume"):
		var master := float(config.get_value("mix", "master_volume", 0.8))
		var music := float(config.get_value("mix", "music_volume", 0.3))
		config.set_value("music", "volume", linear_to_db(clampf(master * music, 0.0001, 1.0)))
	config.set_value("mix", "mute", target)
	config.set_value("audio", "muted", target)
	config.set_value("music", "muted", target)
	config.save("user://sound_settings.cfg")

	var sm := SoundManagerClass.get_instance()
	if sm != null and is_instance_valid(sm):
		sm.set_muted(target)
	var mm := MusicManagerClass.get_instance()
	if mm != null and is_instance_valid(mm):
		mm.set_muted(target)

	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, target)

	if prev != target:
		audio_muted_changed.emit(target)

func toggle_audio_muted() -> bool:
	var next := not is_audio_muted()
	set_audio_muted(next)
	return next

# 保存用户设置
func save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg") # 允许文件不存在；确保不覆盖 SettingsDialog 写入的其它字段
	config.set_value("game", "language", language)
	config.set_value("game", "enabled_modules_v2", enabled_modules_v2)
	modules_v2_base_dir = _normalize_modules_base_dir(modules_v2_base_dir)
	config.set_value("game", "modules_v2_base_dir", modules_v2_base_dir)
	config.set_value("players", "names", player_names)
	config.set_value("players", "color_indices", player_color_indices)
	config.set_value("players", "restaurant_logo_choices", player_restaurant_logo_choices)
	config.save("user://settings.cfg")
	GameLog.info("Globals", "用户设置已保存")

func is_tutorial_runtime_enabled() -> bool:
	return (
		tutorial_pending_setup_tour
		or tutorial_pending_game_ui_tour
		or tutorial_pending_flow_tutorial
		or tutorial_match_enabled
	)

func clear_tutorial_runtime_flags() -> void:
	tutorial_pending_setup_tour = false
	tutorial_pending_game_ui_tour = false
	tutorial_pending_flow_tutorial = false
	tutorial_match_enabled = false

# 重置游戏配置
func reset_game_config() -> void:
	if current_game_engine != null and current_game_engine.has_method("dispose"):
		current_game_engine.dispose()
	player_count = 2
	enabled_modules_v2 = GameDefaultsClass.build_default_enabled_modules_v2()
	modules_v2_base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	random_seed = 0
	reserve_card_selected_by_player = []
	is_game_active = false
	current_game_engine = null
	clear_tutorial_runtime_flags()

# 生成新的随机种子
func generate_seed() -> int:
	random_seed = randi()
	return random_seed

# 获取游戏信息
func get_game_info() -> Dictionary:
	return {
		"version": get_version(),
		"schema_version": SCHEMA_VERSION,
		"player_count": player_count,
		"enabled_modules_v2": enabled_modules_v2,
		"modules_v2_base_dir": modules_v2_base_dir,
		"random_seed": random_seed,
		"is_game_active": is_game_active
	}

func apply_online_room_state(room_state: Dictionary) -> void:
	if room_state == null or room_state.is_empty():
		return
	var players_val = room_state.get("players", null)
	if not (players_val is Array):
		return
	var players: Array = Array(players_val)
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = Dictionary(p_val)
		var pid := int(p.get("seat_index", -1))
		if pid < 0:
			continue
		set_player_name(pid, str(p.get("name", "")))
		set_player_color_index(pid, int(p.get("color_index", 0)))
		set_player_restaurant_logo_choice(pid, int(p.get("restaurant_logo_id", -1)))

func get_default_save_path() -> String:
	return "user://savegame.json"

func set_current_game_engine(engine) -> void:
	current_game_engine = engine
	is_game_active = engine != null

func sync_runtime_config_from_engine(engine) -> void:
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	player_count = state.players.size()
	random_seed = int(state.seed)
	modules_v2_base_dir = _normalize_modules_base_dir(str(engine.modules_v2_base_dir))

	# enabled_modules_v2：使用存档中的完整模块计划（便于 UI/调试展示；新游戏依然由 GameSetup 控制）
	if state.modules is Array:
		enabled_modules_v2 = Array(state.modules, TYPE_STRING, "", null)

	# reserve_card_selected_by_player：用于后续“新游戏/回放”入口展示
	reserve_card_selected_by_player = []
	for i in range(state.players.size()):
		var p_val = state.players[i]
		if p_val is Dictionary:
			reserve_card_selected_by_player.append(int(Dictionary(p_val).get("reserve_card_selected", 0)))

func _ensure_player_profiles() -> void:
	# 补齐名称
	if player_names.size() < MAX_PLAYERS:
		for i in range(player_names.size(), MAX_PLAYERS):
			player_names.append("玩家 %d" % (i + 1))
	elif player_names.size() > MAX_PLAYERS:
		player_names = player_names.slice(0, MAX_PLAYERS)

	# 补齐颜色索引
	if player_color_indices.size() < MAX_PLAYERS:
		for i in range(player_color_indices.size(), MAX_PLAYERS):
			player_color_indices.append(i % PLAYER_COLOR_PALETTE.size())
	elif player_color_indices.size() > MAX_PLAYERS:
		player_color_indices = player_color_indices.slice(0, MAX_PLAYERS)

	# 补齐餐厅 Logo 选择（-1=随机）
	if player_restaurant_logo_choices.size() < MAX_PLAYERS:
		for i in range(player_restaurant_logo_choices.size(), MAX_PLAYERS):
			player_restaurant_logo_choices.append(-1)
	elif player_restaurant_logo_choices.size() > MAX_PLAYERS:
		player_restaurant_logo_choices = player_restaurant_logo_choices.slice(0, MAX_PLAYERS)
	for i in range(player_restaurant_logo_choices.size()):
		var v := int(player_restaurant_logo_choices[i])
		if v < -1 or v >= DEFAULT_RESTAURANT_LOGO_COUNT:
			player_restaurant_logo_choices[i] = -1

func _normalize_modules_base_dir(spec: String) -> String:
	var s := str(spec).strip_edges()
	if s.is_empty():
		return GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	var read = ModuleDirSpecClass.parse_base_dirs(s)
	if read.ok:
		return s
	GameLog.warn("Globals", "modules_v2_base_dir 非 res:// 目录，已回退默认: %s" % s)
	return GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR

func set_player_name(player_id: int, name: String) -> void:
	_ensure_player_profiles()
	if player_id < 0 or player_id >= MAX_PLAYERS:
		return
	var s := str(name).strip_edges()
	if s.is_empty():
		s = "玩家 %d" % (player_id + 1)
	player_names[player_id] = s

func set_player_color_index(player_id: int, palette_index: int) -> void:
	_ensure_player_profiles()
	if player_id < 0 or player_id >= MAX_PLAYERS:
		return
	player_color_indices[player_id] = clamp(palette_index, 0, PLAYER_COLOR_PALETTE.size() - 1)

func get_player_color_index(player_id: int) -> int:
	_ensure_player_profiles()
	if player_id < 0 or player_id >= player_color_indices.size():
		return 0
	return int(player_color_indices[player_id])

func set_player_restaurant_logo_choice(player_id: int, logo_choice: int) -> void:
	_ensure_player_profiles()
	if player_id < 0 or player_id >= MAX_PLAYERS:
		return
	var v := int(logo_choice)
	if v < -1 or v >= DEFAULT_RESTAURANT_LOGO_COUNT:
		v = -1
	player_restaurant_logo_choices[player_id] = v

func get_player_restaurant_logo_choice(player_id: int) -> int:
	_ensure_player_profiles()
	if player_id < 0 or player_id >= player_restaurant_logo_choices.size():
		return -1
	return int(player_restaurant_logo_choices[player_id])

# 获取玩家颜色
func get_player_color(player_id: int) -> Color:
	_ensure_player_profiles()
	if player_id >= 0 and player_id < MAX_PLAYERS:
		var idx := get_player_color_index(player_id)
		if idx >= 0 and idx < PLAYER_COLOR_PALETTE.size():
			return PLAYER_COLOR_PALETTE[idx]
	return Color.WHITE

# 获取玩家名称
func get_player_name(player_id: int) -> String:
	_ensure_player_profiles()
	if player_id >= 0 and player_id < player_names.size():
		return str(player_names[player_id])
	return "玩家 %d" % (player_id + 1)

func get_player_name_compact(player_id: int) -> String:
	var pid := int(player_id)
	var name := str(get_player_name(pid)).strip_edges()
	var default_name := "玩家 %d" % (pid + 1)
	if name == default_name:
		return "玩家%d" % (pid + 1)
	return name
