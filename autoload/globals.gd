# 全局变量与配置
# 存储游戏版本、当前配置和运行时状态
extends Node

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const GameConstantsClass = preload("res://core/engine/game_constants.gd")

# 版本信息
const SCHEMA_VERSION := GameStateClass.SCHEMA_VERSION

# 游戏配置（新游戏时设置）
var player_count: int = 2
var enabled_modules_v2: Array[String] = GameDefaultsClass.build_default_enabled_modules_v2()
var modules_v2_base_dir: String = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR # 可用 ';' 分隔多个目录，例如 res://modules;res://modules_test
var language: String = "zh"
var random_seed: int = 0
var reserve_card_selected_by_player: Array[int] = []

# 运行时状态
var current_game_engine = null  # GameEngine 实例
var is_game_active: bool = false

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
]

var player_names: Array[String] = []
var player_color_indices: Array[int] = []  # player_id -> palette index

func get_version() -> String:
	var v = ProjectSettings.get_setting("application/config/version", "")
	var s := str(v).strip_edges()
	if s.is_empty():
		return "0.0.0"
	return s

func _ready() -> void:
	GameLog.info("Globals", "全局配置初始化 v%s" % get_version())
	_load_settings()
	_ensure_player_profiles()

# 加载用户设置
func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		language = config.get_value("game", "language", "zh")
		var mods_val = config.get_value("game", "enabled_modules_v2", null)
		if mods_val is Array and not Array(mods_val).is_empty():
			enabled_modules_v2 = Array(mods_val, TYPE_STRING, "", null)
		var base_dir_val = config.get_value("game", "modules_v2_base_dir", null)
		if base_dir_val is String and not str(base_dir_val).strip_edges().is_empty():
			modules_v2_base_dir = str(base_dir_val).strip_edges()

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

		GameLog.info("Globals", "已加载用户设置")

# 保存用户设置
func save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg") # 允许文件不存在；确保不覆盖 SettingsDialog 写入的其它字段
	config.set_value("game", "language", language)
	config.set_value("game", "enabled_modules_v2", enabled_modules_v2)
	config.set_value("game", "modules_v2_base_dir", modules_v2_base_dir)
	config.set_value("players", "names", player_names)
	config.set_value("players", "color_indices", player_color_indices)
	config.save("user://settings.cfg")
	GameLog.info("Globals", "用户设置已保存")

# 重置游戏配置
func reset_game_config() -> void:
	player_count = 2
	enabled_modules_v2 = GameDefaultsClass.build_default_enabled_modules_v2()
	modules_v2_base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	random_seed = 0
	reserve_card_selected_by_player = []
	is_game_active = false
	current_game_engine = null

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

func get_default_save_path() -> String:
	return "user://savegame.json"

func set_current_game_engine(engine) -> void:
	current_game_engine = engine
	is_game_active = engine != null

func sync_runtime_config_from_engine(engine: GameEngine) -> void:
	if engine == null:
		return
	var state: GameState = engine.get_state()
	if state == null:
		return

	player_count = state.players.size()
	random_seed = int(state.seed)
	modules_v2_base_dir = str(engine.modules_v2_base_dir)

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
