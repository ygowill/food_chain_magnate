class_name SoundManagerLocalInputGateTest
extends RefCounted

const SoundManagerClass = preload("res://ui/audio/sound_manager.gd")

static func run() -> Result:
	var manager = SoundManagerClass.new()
	if manager == null or not is_instance_valid(manager):
		return Result.failure("无法创建 SoundManager")

	manager._record_local_input(1000)
	if not manager._has_recent_local_input(1100):
		_safe_free(manager)
		return Result.failure("最近本地输入应在 100ms 内保持有效")
	if manager._has_recent_local_input(1301):
		_safe_free(manager)
		return Result.failure("最近本地输入超过阈值后应失效")

	_safe_free(manager)
	return Result.success()

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
