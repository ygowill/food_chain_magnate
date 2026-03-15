# 音频系统初始化器
# 在游戏启动时初始化音频总线和音效管理器
class_name AudioSystemInitializer
extends Node

const SoundManagerScene = preload("res://ui/audio/sound_manager.tscn")
const MusicManagerScene = preload("res://ui/audio/music_manager.tscn")
const SoundManagerClass = preload("res://ui/audio/sound_manager.gd")
const MusicManagerClass = preload("res://ui/audio/music_manager.gd")

var _sound_manager: Node = null
var _music_manager: Node = null
var _audio_unlock_confirmed: bool = false
var _next_probe_msec: int = 0
var _last_playback_pos_sec: float = -1.0
var _stalled_probe_count: int = 0
const WEB_AUDIO_PROBE_INTERVAL_MSEC: int = 600

func _ready() -> void:
	# 注意：作为 Autoload 时，Root 仍可能处于“正在挂载子节点”的阶段，
	# 直接 add_child 会失败。统一延迟一帧初始化可避免启动竞态。
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	_setup_audio_buses()
	_initialize_managers()
	call_deferred("_sync_audio_server_mute_from_settings")
	_ensure_bgm_is_playing()
	_audio_unlock_confirmed = not _is_web_runtime()
	set_process_input(true)
	set_process(_is_web_runtime())

func _notification(what: int) -> void:
	# macOS 下，从 Editor 启动时游戏窗口可能先处于未聚焦状态；
	# 首次点击往往只会聚焦窗口（不会触发 UI pressed 事件），导致“主菜单没声音”。
	# 在获取焦点时再补一次播放，可显著提升首屏体验。
	if what == Node.NOTIFICATION_APPLICATION_FOCUS_IN:
		if _is_web_runtime():
			call_deferred("_on_user_audio_interaction", false)
		else:
			call_deferred("_ensure_bgm_is_playing")

func _setup_audio_buses() -> void:
	# 检查是否已有音频总线配置
	# 如果没有，创建默认总线
	var bus_count := AudioServer.bus_count

	# 查找现有总线
	var has_master := false
	var has_music := false
	var has_sfx := false

	for i in range(bus_count):
		var bus_name := AudioServer.get_bus_name(i)
		match bus_name:
			"Master": has_master = true
			"Music": has_music = true
			"SFX": has_sfx = true

	# 创建缺失的总线
	if not has_music:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")

	if not has_sfx:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

func _initialize_managers() -> void:
	var root := get_tree().root
	if root == null:
		return

	# 重要：SoundManager / MusicManager 需要跨场景持久化，否则切场景会截断正在播放的音效。
	var existing_sm := SoundManagerClass.get_instance()
	if existing_sm != null and is_instance_valid(existing_sm):
		_sound_manager = existing_sm
	else:
		_sound_manager = SoundManagerScene.instantiate()
		_sound_manager.name = "SoundManager"
		root.add_child(_sound_manager)

	var existing_mm := MusicManagerClass.get_instance()
	if existing_mm != null and is_instance_valid(existing_mm):
		_music_manager = existing_mm
	else:
		_music_manager = MusicManagerScene.instantiate()
		_music_manager.name = "MusicManager"
		root.add_child(_music_manager)

func get_sound_manager() -> Node:
	return _sound_manager

func get_music_manager() -> Node:
	return _music_manager

func _ensure_bgm_is_playing(force_restart: bool = false) -> void:
	if _is_headless_runtime():
		return
	var mm := MusicManagerClass.get_instance()
	if mm == null or not is_instance_valid(mm):
		return
	if not force_restart and mm.has_method("is_playing") and bool(mm.call("is_playing")):
		return
	if force_restart and mm.has_method("stop"):
		# Web 平台上自动播放被拦截时，播放器可能处于 playing=true 但实际无声；
		# 交互后强制重播可确保音轨重新排入已解锁的音频上下文。
		mm.call("stop", false)
	if mm.has_method("play"):
		mm.call("play", MusicManagerClass.MusicTrack.MENU, false)

func _process(_delta: float) -> void:
	if _is_headless_runtime() or not _is_web_runtime() or _audio_unlock_confirmed:
		return

	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_probe_msec:
		return
	_next_probe_msec = now_msec + WEB_AUDIO_PROBE_INTERVAL_MSEC

	var mm := MusicManagerClass.get_instance()
	if mm == null or not is_instance_valid(mm):
		return

	var playing := false
	if mm.has_method("is_playing"):
		playing = bool(mm.call("is_playing"))

	if mm.has_method("get_playback_position_sec"):
		var pos_sec := float(mm.call("get_playback_position_sec"))
		if _last_playback_pos_sec >= 0.0 and pos_sec > _last_playback_pos_sec + 0.03:
			_mark_audio_unlock_confirmed()
			return
		_last_playback_pos_sec = pos_sec

	if playing:
		_stalled_probe_count += 1
	else:
		_stalled_probe_count = 0

	if not playing or _stalled_probe_count >= 3:
		_try_unlock_web_audio_context()
		_ensure_bgm_is_playing(true)
		_stalled_probe_count = 0

func _input(event: InputEvent) -> void:
	if _is_headless_runtime():
		return
	if event == null:
		return

	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if not e.pressed:
			return
	elif event is InputEventKey:
		var e := event as InputEventKey
		if not e.pressed:
			return
	elif event is InputEventJoypadButton:
		var e := event as InputEventJoypadButton
		if not e.pressed:
			return
	elif event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if not e.pressed:
			return
	else:
		return

	# 用户交互兜底：在浏览器手势阶段显式恢复音频上下文，并强制重播一次。
	_on_user_audio_interaction(true)

func _on_user_audio_interaction(force_restart: bool = true) -> void:
	if _is_headless_runtime():
		return
	if _is_web_runtime():
		_try_unlock_web_audio_context()
		_sync_audio_server_mute_from_settings()
		_ensure_bgm_is_playing(force_restart)
		_next_probe_msec = 0
		return
	_ensure_bgm_is_playing(false)

func _try_unlock_web_audio_context() -> void:
	if not _is_web_runtime():
		return
	# 尽量兼容不同导出模板：恢复 Godot 挂载的上下文；若不可见则创建一次解锁上下文。
	JavaScriptBridge.eval("""
		(function () {
			try {
				var resumed = false;
				var candidates = [];
				if (typeof window !== "object") {
					return false;
				}
				if (typeof window.__fcm_web_audio_unlock === "function") {
					try {
						window.__fcm_web_audio_unlock();
						resumed = true;
					} catch (_err_fcm0) {}
				}
				if (window.__fcm_web_audio) {
					try {
						if (window.__fcm_web_audio.last_ctx) {
							candidates.push(window.__fcm_web_audio.last_ctx);
						}
						if (Array.isArray(window.__fcm_web_audio.contexts)) {
							for (var j = 0; j < window.__fcm_web_audio.contexts.length; j += 1) {
								candidates.push(window.__fcm_web_audio.contexts[j]);
							}
						}
					} catch (_err_fcm1) {}
				}
				if (window.Module && typeof window.Module._godot_audio_resume === "function") {
					try {
						window.Module._godot_audio_resume();
						resumed = true;
					} catch (_err0) {}
				}
				if (window.GodotAudio && window.GodotAudio.ctx) {
					candidates.push(window.GodotAudio.ctx);
				}
				if (window.Module && window.Module.GodotAudio && window.Module.GodotAudio.ctx) {
					candidates.push(window.Module.GodotAudio.ctx);
				}
				if (window.__godotAudioContext) {
					candidates.push(window.__godotAudioContext);
				}
				for (var i = 0; i < candidates.length; i += 1) {
					var ctx = candidates[i];
					if (!ctx || typeof ctx.resume !== "function" || ctx.state === "running") {
						continue;
					}
					try {
						var p = ctx.resume();
						if (p && typeof p.catch === "function") {
							p.catch(function () {});
						}
						resumed = true;
					} catch (_err1) {}
				}
				var CtxCtor = window.AudioContext || window.webkitAudioContext;
				if (!resumed && CtxCtor) {
					try {
						if (!window.__fcm_audio_unlock_ctx) {
							window.__fcm_audio_unlock_ctx = new CtxCtor();
						}
						var unlock_ctx = window.__fcm_audio_unlock_ctx;
						if (unlock_ctx && typeof unlock_ctx.resume === "function" && unlock_ctx.state !== "running") {
							var p2 = unlock_ctx.resume();
							if (p2 && typeof p2.catch === "function") {
								p2.catch(function () {});
							}
						}
					} catch (_err2) {}
				}
				return true;
			} catch (_err3) {
				return false;
			}
		})();
	""")

func _mark_audio_unlock_confirmed() -> void:
	_audio_unlock_confirmed = true
	set_process(false)
	set_process_input(false)

func _sync_audio_server_mute_from_settings() -> void:
	if _is_headless_runtime():
		return

	var muted := false

	var sm := SoundManagerClass.get_instance()
	if sm != null and is_instance_valid(sm) and sm.has_method("is_muted"):
		muted = muted or bool(sm.call("is_muted"))

	var mm := MusicManagerClass.get_instance()
	if mm != null and is_instance_valid(mm) and mm.has_method("is_muted"):
		muted = muted or bool(mm.call("is_muted"))

	# 若管理器尚未就绪，则退回读取配置。
	if sm == null and mm == null:
		var cfg := ConfigFile.new()
		if cfg.load("user://sound_settings.cfg") == OK:
			muted = bool(cfg.get_value("mix", "mute", false))

	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, muted)
		if not muted:
			# 部分 Web 环境/模板下可能出现 Master 总线被错误衰减的情况；
			# 这里强制恢复到 0dB，避免“看起来没静音但实际无声”。
			AudioServer.set_bus_volume_db(master_idx, 0.0)

func _is_web_runtime() -> bool:
	return OS.has_feature("web")

func _is_headless_runtime() -> bool:
	# Web 平台在 Godot 4.3+ 默认使用 sample playback（绕过 AudioServer 混音），
	# AudioServer driver 可能为 Dummy，但这不等同于 headless。
	return DisplayServer.get_name() == "headless"
