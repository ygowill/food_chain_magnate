# 游戏音效管理器
# 统一管理所有游戏音效的播放
class_name SoundManager
extends Node

# 音效类别
enum SoundCategory {
	UI,        # 界面音效
	ACTION,    # 动作音效
	EVENT,     # 事件音效
	AMBIENT    # 环境音效
}

# 预定义音效 ID
const SOUND_BUTTON_CLICK := "ui_button_click"
const SOUND_BUTTON_HOVER := "ui_button_hover"
const SOUND_PANEL_OPEN := "ui_panel_open"
const SOUND_PANEL_CLOSE := "ui_panel_close"
const SOUND_CARD_SELECT := "ui_card_select"
const SOUND_CARD_PLACE := "ui_card_place"

const SOUND_RECRUIT := "action_recruit"
const SOUND_TRAIN := "action_train"
const SOUND_FIRE := "action_fire"
const SOUND_MARKETING := "action_marketing"
const SOUND_PRODUCE := "action_produce"
const SOUND_SERVE := "action_serve"
const SOUND_BUILD := "action_build"

const SOUND_TURN_START := "event_turn_start"
const SOUND_PHASE_CHANGE := "event_phase_change"
const SOUND_CASH_GAIN := "event_cash_gain"
const SOUND_CASH_LOSS := "event_cash_loss"
const SOUND_MILESTONE := "event_milestone"
const SOUND_BANK_BREAK := "event_bank_break"
const SOUND_GAME_OVER := "event_game_over"

const SOUND_ERROR := "ui_error"
const SOUND_SUCCESS := "ui_success"
const SOUND_NOTIFICATION := "ui_notification"

# 音效配置
var _sound_config: Dictionary = {
	# UI 音效
	SOUND_BUTTON_CLICK: { "category": SoundCategory.UI, "volume": 0.0, "pitch_variance": 0.05 },
	SOUND_BUTTON_HOVER: { "category": SoundCategory.UI, "volume": -6.0, "pitch_variance": 0.0 },
	SOUND_PANEL_OPEN: { "category": SoundCategory.UI, "volume": -3.0, "pitch_variance": 0.0 },
	SOUND_PANEL_CLOSE: { "category": SoundCategory.UI, "volume": -3.0, "pitch_variance": 0.0 },
	SOUND_CARD_SELECT: { "category": SoundCategory.UI, "volume": -3.0, "pitch_variance": 0.1 },
	SOUND_CARD_PLACE: { "category": SoundCategory.UI, "volume": 0.0, "pitch_variance": 0.05 },

	# 动作音效
	SOUND_RECRUIT: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_TRAIN: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_FIRE: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_MARKETING: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_PRODUCE: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_SERVE: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_BUILD: { "category": SoundCategory.ACTION, "volume": 0.0, "pitch_variance": 0.0 },

	# 事件音效
	SOUND_TURN_START: { "category": SoundCategory.EVENT, "volume": -3.0, "pitch_variance": 0.0 },
	SOUND_PHASE_CHANGE: { "category": SoundCategory.EVENT, "volume": -6.0, "pitch_variance": 0.0 },
	SOUND_CASH_GAIN: { "category": SoundCategory.EVENT, "volume": 0.0, "pitch_variance": 0.1 },
	SOUND_CASH_LOSS: { "category": SoundCategory.EVENT, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_MILESTONE: { "category": SoundCategory.EVENT, "volume": 3.0, "pitch_variance": 0.0 },
	SOUND_BANK_BREAK: { "category": SoundCategory.EVENT, "volume": 3.0, "pitch_variance": 0.0 },
	SOUND_GAME_OVER: { "category": SoundCategory.EVENT, "volume": 0.0, "pitch_variance": 0.0 },

	# 反馈音效
	SOUND_ERROR: { "category": SoundCategory.UI, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_SUCCESS: { "category": SoundCategory.UI, "volume": 0.0, "pitch_variance": 0.0 },
	SOUND_NOTIFICATION: { "category": SoundCategory.UI, "volume": -3.0, "pitch_variance": 0.0 },
}

# 音量设置（dB）
var _master_volume: float = 0.0
var _category_volumes: Dictionary = {
	SoundCategory.UI: 0.0,
	SoundCategory.ACTION: 0.0,
	SoundCategory.EVENT: 0.0,
	SoundCategory.AMBIENT: -6.0,
}

# 是否静音
var _muted: bool = false
var _category_muted: Dictionary = {
	SoundCategory.UI: false,
	SoundCategory.ACTION: false,
	SoundCategory.EVENT: false,
	SoundCategory.AMBIENT: false,
}

# 音效资源缓存
var _sound_cache: Dictionary = {}  # sound_id -> AudioStream

# 音效播放器池
var _player_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE: int = 8
var _current_player_index: int = 0

# 单例
static var _instance: SoundManager = null

static func get_instance() -> SoundManager:
	return _instance

func _enter_tree() -> void:
	if _instance == null:
		_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

func _ready() -> void:
	_create_player_pool()
	_load_settings()

func _create_player_pool() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_player_pool.append(player)

# === 公共方法 ===

func play(sound_id: String) -> void:
	if _muted:
		return

	var config: Dictionary = _sound_config.get(sound_id, {})
	if config.is_empty():
		push_warning("SoundManager: 未知音效 ID: %s" % sound_id)
		return

	var category: SoundCategory = config.get("category", SoundCategory.UI)
	if _category_muted.get(category, false):
		return

	var stream := _get_or_load_stream(sound_id)
	if stream == null:
		return

	var player := _get_available_player()
	if player == null:
		return

	player.stream = stream

	# 计算最终音量
	var base_volume: float = config.get("volume", 0.0)
	var category_volume: float = _category_volumes.get(category, 0.0)
	player.volume_db = _master_volume + category_volume + base_volume

	# 应用音高变化
	var pitch_variance: float = config.get("pitch_variance", 0.0)
	if pitch_variance > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	else:
		player.pitch_scale = 1.0

	player.play()

func play_ui_click() -> void:
	play(SOUND_BUTTON_CLICK)

func play_ui_hover() -> void:
	play(SOUND_BUTTON_HOVER)

func play_action(action_id: String) -> void:
	# 根据动作 ID 映射到音效
	match action_id:
		"recruit":
			play(SOUND_RECRUIT)
		"train":
			play(SOUND_TRAIN)
		"fire":
			play(SOUND_FIRE)
		"initiate_marketing":
			play(SOUND_MARKETING)
		"produce_food", "procure_drinks":
			play(SOUND_PRODUCE)
		"serve_customer":
			play(SOUND_SERVE)
		"place_restaurant", "place_house":
			play(SOUND_BUILD)

func play_event(event_type: String) -> void:
	match event_type:
		"turn_start":
			play(SOUND_TURN_START)
		"phase_change":
			play(SOUND_PHASE_CHANGE)
		"cash_gain":
			play(SOUND_CASH_GAIN)
		"cash_loss":
			play(SOUND_CASH_LOSS)
		"milestone":
			play(SOUND_MILESTONE)
		"bank_break":
			play(SOUND_BANK_BREAK)
		"game_over":
			play(SOUND_GAME_OVER)

func play_feedback(success: bool) -> void:
	if success:
		play(SOUND_SUCCESS)
	else:
		play(SOUND_ERROR)

# === 音量控制 ===

func set_master_volume(volume_db: float) -> void:
	_master_volume = clampf(volume_db, -80.0, 6.0)
	_save_settings()

func get_master_volume() -> float:
	return _master_volume

func set_category_volume(category: SoundCategory, volume_db: float) -> void:
	_category_volumes[category] = clampf(volume_db, -80.0, 6.0)
	_save_settings()

func get_category_volume(category: SoundCategory) -> float:
	return _category_volumes.get(category, 0.0)

func set_muted(muted: bool) -> void:
	_muted = muted
	_save_settings()

func is_muted() -> bool:
	return _muted

func set_category_muted(category: SoundCategory, muted: bool) -> void:
	_category_muted[category] = muted
	_save_settings()

func is_category_muted(category: SoundCategory) -> bool:
	return _category_muted.get(category, false)

# === 内部方法 ===

func _get_available_player() -> AudioStreamPlayer:
	# 寻找空闲播放器
	for i in range(POOL_SIZE):
		var index := (_current_player_index + i) % POOL_SIZE
		var player: AudioStreamPlayer = _player_pool[index]
		if not player.playing:
			_current_player_index = (index + 1) % POOL_SIZE
			return player

	# 所有播放器都在使用，使用最老的那个
	_current_player_index = (_current_player_index + 1) % POOL_SIZE
	return _player_pool[_current_player_index]

func _get_or_load_stream(sound_id: String) -> AudioStream:
	if _sound_cache.has(sound_id):
		return _sound_cache[sound_id]

	# 尝试加载音效文件
	var path := "res://ui/audio/sfx/%s.wav" % sound_id
	if not ResourceLoader.exists(path):
		path = "res://ui/audio/sfx/%s.ogg" % sound_id
	if not ResourceLoader.exists(path):
		path = "res://ui/audio/sfx/%s.mp3" % sound_id

	if not ResourceLoader.exists(path):
		# 使用占位音效（静音）
		return null

	var stream: AudioStream = load(path)
	if stream != null:
		_sound_cache[sound_id] = stream

	return stream

func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://sound_settings.cfg")
	if err != OK:
		return

	_master_volume = config.get_value("audio", "master_volume", 0.0)
	_muted = config.get_value("audio", "muted", false)

	for category in SoundCategory.values():
		var key := "category_%d_volume" % category
		_category_volumes[category] = config.get_value("audio", key, 0.0)
		var mute_key := "category_%d_muted" % category
		_category_muted[category] = config.get_value("audio", mute_key, false)

func _save_settings() -> void:
	var config := ConfigFile.new()

	config.set_value("audio", "master_volume", _master_volume)
	config.set_value("audio", "muted", _muted)

	for category in SoundCategory.values():
		var key := "category_%d_volume" % category
		config.set_value("audio", key, _category_volumes.get(category, 0.0))
		var mute_key := "category_%d_muted" % category
		config.set_value("audio", mute_key, _category_muted.get(category, false))

	config.save("user://sound_settings.cfg")

# === 预加载 ===

func preload_sounds(sound_ids: Array[String]) -> void:
	for sound_id in sound_ids:
		_get_or_load_stream(sound_id)

func preload_all_ui_sounds() -> void:
	preload_sounds([
		SOUND_BUTTON_CLICK,
		SOUND_BUTTON_HOVER,
		SOUND_PANEL_OPEN,
		SOUND_PANEL_CLOSE,
		SOUND_CARD_SELECT,
		SOUND_CARD_PLACE,
		SOUND_ERROR,
		SOUND_SUCCESS,
		SOUND_NOTIFICATION,
	])
