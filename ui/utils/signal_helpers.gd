# UI 信号连接辅助
# 用途：消除重复的 is_instance_valid + has_signal + is_connected 样板，并避免重复连接。
class_name UiSignalHelpers
extends RefCounted

static func safe_connect(obj: Object, signal_name, callback: Callable) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var sig: StringName = signal_name if (signal_name is StringName) else StringName(str(signal_name))
	if not obj.has_signal(sig):
		return false
	if obj.is_connected(sig, callback):
		return true
	return obj.connect(sig, callback) == OK
