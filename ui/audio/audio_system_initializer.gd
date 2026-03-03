# 音频系统初始化器
# 在游戏启动时初始化音频总线和音效管理器
class_name AudioSystemInitializer
extends Node

const SoundManagerScene = preload("res://ui/audio/sound_manager.tscn")
const MusicManagerScene = preload("res://ui/audio/music_manager.tscn")

var _sound_manager: Node = null
var _music_manager: Node = null
var _interaction_bootstrap_done: bool = false

func _ready() -> void:
	# 注意：作为 Autoload 时，Root 仍可能处于“正在挂载子节点”的阶段，
	# 直接 add_child 会失败。统一延迟一帧初始化可避免启动竞态。
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	_setup_audio_buses()
	_initialize_managers()
	_ensure_bgm_is_playing()
	set_process_input(true)

func _notification(what: int) -> void:
	# macOS 下，从 Editor 启动时游戏窗口可能先处于未聚焦状态；
	# 首次点击往往只会聚焦窗口（不会触发 UI pressed 事件），导致“主菜单没声音”。
	# 在获取焦点时再补一次播放，可显著提升首屏体验。
	if what == Node.NOTIFICATION_APPLICATION_FOCUS_IN:
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
	var existing_sm := SoundManager.get_instance()
	if existing_sm != null and is_instance_valid(existing_sm):
		_sound_manager = existing_sm
	else:
		_sound_manager = SoundManagerScene.instantiate()
		_sound_manager.name = "SoundManager"
		root.add_child(_sound_manager)

	var existing_mm := MusicManager.get_instance()
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
	var mm := MusicManager.get_instance()
	if mm == null or not is_instance_valid(mm):
		return
	if not force_restart and mm.has_method("is_playing") and bool(mm.call("is_playing")):
		return
	if force_restart and mm.has_method("stop"):
		# Web 平台上自动播放被拦截时，播放器可能处于 playing=true 但实际无声；
		# 交互后强制重播可确保音轨重新排入已解锁的音频上下文。
		mm.call("stop", false)
	if mm.has_method("play"):
		mm.call("play", MusicManager.MusicTrack.MENU, false)

func _input(event: InputEvent) -> void:
	if _is_headless_runtime():
		return
	if _interaction_bootstrap_done:
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

	# 用第一次用户交互兜底触发 BGM 播放（Web 需要显式解锁音频上下文）。
	_interaction_bootstrap_done = true
	_try_unlock_web_audio_context()
	set_process_input(false)
	_ensure_bgm_is_playing(true)

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

func _is_web_runtime() -> bool:
	return OS.has_feature("web")

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy"
