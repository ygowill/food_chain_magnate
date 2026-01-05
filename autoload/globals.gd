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

# 运行时状态
var current_game_engine = null  # GameEngine 实例
var is_game_active: bool = false

# 玩家数范围
const MIN_PLAYERS := GameConstantsClass.MIN_PLAYERS
const MAX_PLAYERS := GameConstantsClass.MAX_PLAYERS

func get_version() -> String:
	var v = ProjectSettings.get_setting("application/config/version", "")
	var s := str(v).strip_edges()
	if s.is_empty():
		return "0.0.0"
	return s

func _ready() -> void:
	GameLog.info("Globals", "全局配置初始化 v%s" % get_version())
	_load_settings()

# 加载用户设置
func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		language = config.get_value("game", "language", "zh")
		GameLog.info("Globals", "已加载用户设置")

# 保存用户设置
func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "language", language)
	config.save("user://settings.cfg")
	GameLog.info("Globals", "用户设置已保存")

# 重置游戏配置
func reset_game_config() -> void:
	player_count = 2
	enabled_modules_v2 = GameDefaultsClass.build_default_enabled_modules_v2()
	modules_v2_base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	random_seed = 0
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

# 获取玩家颜色
func get_player_color(player_id: int) -> Color:
	const PLAYER_COLORS := [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.YELLOW,
		Color.PURPLE
	]
	if player_id >= 0 and player_id < PLAYER_COLORS.size():
		return PLAYER_COLORS[player_id]
	return Color.WHITE

# 获取玩家名称（占位，后续可自定义）
func get_player_name(player_id: int) -> String:
	return "玩家 %d" % (player_id + 1)
