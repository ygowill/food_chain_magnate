# 背景音乐管理器
# 管理游戏背景音乐的播放和切换
class_name MusicManager
extends Node

signal track_changed(track_name: String)
signal playback_finished()

# 音乐状态
enum MusicState { STOPPED, PLAYING, PAUSED, FADING }

# 音乐曲目类型
enum MusicTrack {
	NONE,
	MENU,           # 主菜单
	GAME_CALM,      # 游戏中 - 平静
	GAME_INTENSE,   # 游戏中 - 紧张
	GAME_OVER,      # 游戏结束
}

# 单曲模式：暂时不做多 BGM 切换
const SINGLE_TRACK_PATH := "res://ui/audio/music/game_bgm.mp3"
const BOOT_AUTOPLAY_MAX_ATTEMPTS: int = 30
const BOOT_AUTOPLAY_INTERVAL_SEC: float = 0.25
const DEFAULT_MUSIC_VOLUME_LINEAR: float = 0.24 # 默认：主音量 80% * 音乐音量 30%

# 曲目配置
var _track_config: Dictionary = {
	MusicTrack.MENU: { "path": SINGLE_TRACK_PATH, "loop": true, "volume": 0.0 },
	MusicTrack.GAME_CALM: { "path": SINGLE_TRACK_PATH, "loop": true, "volume": 0.0 },
	MusicTrack.GAME_INTENSE: { "path": SINGLE_TRACK_PATH, "loop": true, "volume": 0.0 },
	MusicTrack.GAME_OVER: { "path": SINGLE_TRACK_PATH, "loop": true, "volume": 0.0 },
}

# 播放器
var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _inactive_player: AudioStreamPlayer

# 状态
var _current_state: MusicState = MusicState.STOPPED
var _current_track: MusicTrack = MusicTrack.NONE
var _next_track: MusicTrack = MusicTrack.NONE

# 音量设置
var _master_volume: float = 0.0
var _muted: bool = false

# 淡入淡出
var _fade_duration: float = 1.0
var _fade_tween: Tween = null

# 启动自动播放（增强：重试，避免首帧/音频系统就绪时序问题）
var _boot_autoplay_attempts: int = 0
var _boot_autoplay_active: bool = false

# 单例
static var _instance: MusicManager = null

static func get_instance() -> MusicManager:
	return _instance

func _enter_tree() -> void:
	if _instance == null:
		_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

func _ready() -> void:
	_create_players()
	_load_settings()
	call_deferred("_start_boot_autoplay")

func _start_boot_autoplay() -> void:
	if _is_headless_runtime():
		return
	if not ResourceLoader.exists(SINGLE_TRACK_PATH):
		return
	if _boot_autoplay_active:
		return
	_boot_autoplay_active = true
	_boot_autoplay_attempts = 0
	_boot_autoplay_tick()

func _boot_autoplay_tick() -> void:
	if not _boot_autoplay_active:
		return
	if _is_headless_runtime():
		_boot_autoplay_active = false
		return
	if is_playing():
		_boot_autoplay_active = false
		return

	if not ResourceLoader.exists(SINGLE_TRACK_PATH):
		_boot_autoplay_active = false
		return

	_boot_autoplay_attempts += 1
	play(MusicTrack.MENU, false)

	if is_playing():
		_boot_autoplay_active = false
		return

	if _boot_autoplay_attempts >= BOOT_AUTOPLAY_MAX_ATTEMPTS:
		_boot_autoplay_active = false
		push_warning("MusicManager: BGM 自动播放失败（已重试 %d 次）" % _boot_autoplay_attempts)
		return

	var tree := get_tree()
	if tree == null:
		_boot_autoplay_active = false
		return
	tree.create_timer(BOOT_AUTOPLAY_INTERVAL_SEC).timeout.connect(_boot_autoplay_tick)

func _is_headless_runtime() -> bool:
	# Web 平台在 Godot 4.3+ 默认使用 sample playback（绕过 AudioServer 混音），
	# AudioServer driver 可能为 Dummy，但这不等同于 headless。
	return DisplayServer.get_name() == "headless"

func _create_players() -> void:
	if _player_a != null and is_instance_valid(_player_a) and _player_b != null and is_instance_valid(_player_b):
		if _active_player == null or not is_instance_valid(_active_player):
			_active_player = _player_a
		if _inactive_player == null or not is_instance_valid(_inactive_player):
			_inactive_player = _player_b
		return

	var is_web := OS.has_feature("web")

	_player_a = AudioStreamPlayer.new()
	_player_a.bus = "Music"
	if is_web:
		_player_a.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	_player_a.finished.connect(_on_player_finished.bind(_player_a))
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.bus = "Music"
	if is_web:
		_player_b.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	_player_b.finished.connect(_on_player_finished.bind(_player_b))
	add_child(_player_b)

	_active_player = _player_a
	_inactive_player = _player_b

# === 公共方法 ===

func play(track: MusicTrack, crossfade: bool = true) -> void:
	if _active_player == null or not is_instance_valid(_active_player) or _inactive_player == null or not is_instance_valid(_inactive_player):
		_create_players()

	if track == _current_track and is_playing():
		return

	if track == MusicTrack.NONE:
		stop(crossfade)
		return

	var config: Dictionary = _track_config.get(track, {})
	if config.is_empty():
		push_warning("MusicManager: 未知曲目: %d" % track)
		return

	var path: String = config.get("path", "")
	if not ResourceLoader.exists(path):
		push_warning("MusicManager: 音乐文件不存在: %s" % path)
		return

	var stream: AudioStream = load(path)
	if stream == null:
		return

	_next_track = track

	if crossfade and _current_state == MusicState.PLAYING:
		_crossfade_to(stream, config)
	else:
		_play_immediate(stream, config)

	track_changed.emit(_get_track_name(track))

func stop(fade_out: bool = true) -> void:
	if _current_state == MusicState.STOPPED:
		return

	if fade_out:
		_fade_out()
	else:
		_stop_immediate()

func pause() -> void:
	if _current_state != MusicState.PLAYING:
		return

	_active_player.stream_paused = true
	_current_state = MusicState.PAUSED

func resume() -> void:
	if _current_state != MusicState.PAUSED:
		return

	_active_player.stream_paused = false
	_current_state = MusicState.PLAYING

func is_playing() -> bool:
	if _active_player == null or not is_instance_valid(_active_player):
		return false
	return _active_player.playing and not _active_player.stream_paused

func get_playback_position_sec() -> float:
	if _active_player == null or not is_instance_valid(_active_player):
		return 0.0
	return float(_active_player.get_playback_position())

func get_current_track() -> MusicTrack:
	return _current_track

# === 音量控制 ===

func set_volume(volume_db: float) -> void:
	_master_volume = clampf(volume_db, -80.0, 6.0)
	_update_player_volumes()
	_save_settings()

func get_volume() -> float:
	return _master_volume

func set_muted(muted: bool) -> void:
	_muted = muted
	_update_player_volumes()
	_save_settings()

func is_muted() -> bool:
	return _muted

# === 内部方法 ===

func _play_immediate(stream: AudioStream, config: Dictionary) -> void:
	_cancel_fade()

	_active_player.stream = stream
	_active_player.volume_db = _calculate_volume(config.get("volume", 0.0))
	_active_player.play()

	_current_track = _next_track
	_current_state = MusicState.PLAYING

func _crossfade_to(stream: AudioStream, config: Dictionary) -> void:
	_cancel_fade()

	# 交换播放器
	var temp := _active_player
	_active_player = _inactive_player
	_inactive_player = temp

	# 设置新播放器
	_active_player.stream = stream
	_active_player.volume_db = -80.0
	_active_player.play()

	# 创建淡入淡出
	_current_state = MusicState.FADING
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)

	var target_volume := _calculate_volume(config.get("volume", 0.0))
	_fade_tween.tween_property(_active_player, "volume_db", target_volume, _fade_duration)
	_fade_tween.tween_property(_inactive_player, "volume_db", -80.0, _fade_duration)

	_fade_tween.finished.connect(_on_crossfade_finished)

func _fade_out() -> void:
	_cancel_fade()

	_current_state = MusicState.FADING
	_fade_tween = create_tween()
	_fade_tween.tween_property(_active_player, "volume_db", -80.0, _fade_duration)
	_fade_tween.finished.connect(_on_fade_out_finished)

func _stop_immediate() -> void:
	_cancel_fade()

	_player_a.stop()
	_player_b.stop()

	_current_track = MusicTrack.NONE
	_current_state = MusicState.STOPPED

func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

func _calculate_volume(base_volume: float) -> float:
	if _muted:
		return -80.0
	return _master_volume + base_volume

func _update_player_volumes() -> void:
	if _current_state != MusicState.PLAYING:
		return

	var config: Dictionary = _track_config.get(_current_track, {})
	var target_volume := _calculate_volume(config.get("volume", 0.0))
	_active_player.volume_db = target_volume

func _get_track_name(track: MusicTrack) -> String:
	match track:
		MusicTrack.NONE: return "none"
		MusicTrack.MENU: return "menu"
		MusicTrack.GAME_CALM: return "game_calm"
		MusicTrack.GAME_INTENSE: return "game_intense"
		MusicTrack.GAME_OVER: return "game_over"
		_: return "unknown"

# === 信号处理 ===

func _on_player_finished(player: AudioStreamPlayer) -> void:
	if player != _active_player:
		return

	var config: Dictionary = _track_config.get(_current_track, {})
	if config.get("loop", false):
		player.play()
	else:
		_current_state = MusicState.STOPPED
		playback_finished.emit()

func _on_crossfade_finished() -> void:
	_inactive_player.stop()
	_current_track = _next_track
	_current_state = MusicState.PLAYING
	_fade_tween = null

func _on_fade_out_finished() -> void:
	_stop_immediate()
	_fade_tween = null

# === 设置持久化 ===

func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://sound_settings.cfg")
	if err != OK:
		_master_volume = linear_to_db(clampf(DEFAULT_MUSIC_VOLUME_LINEAR, 0.0001, 1.0))
		_muted = false
		return

	_master_volume = config.get_value("music", "volume", 0.0)
	_muted = config.get_value("music", "muted", false)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://sound_settings.cfg")  # 加载现有设置

	config.set_value("music", "volume", _master_volume)
	config.set_value("music", "muted", _muted)

	config.save("user://sound_settings.cfg")
