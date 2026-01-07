# 音频系统初始化器
# 在游戏启动时初始化音频总线和音效管理器
class_name AudioSystemInitializer
extends Node

const SoundManagerScene = preload("res://ui/audio/sound_manager.tscn")
const MusicManagerScene = preload("res://ui/audio/music_manager.tscn")

var _sound_manager: Node = null
var _music_manager: Node = null

func _ready() -> void:
	_setup_audio_buses()
	_initialize_managers()

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
	# 创建音效管理器
	if _sound_manager == null:
		_sound_manager = SoundManagerScene.instantiate()
		_sound_manager.name = "SoundManager"
		add_child(_sound_manager)

	# 创建音乐管理器
	if _music_manager == null:
		_music_manager = MusicManagerScene.instantiate()
		_music_manager.name = "MusicManager"
		add_child(_music_manager)

func get_sound_manager() -> Node:
	return _sound_manager

func get_music_manager() -> Node:
	return _music_manager
