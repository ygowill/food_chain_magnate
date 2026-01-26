# 状态相关调试命令（兼容 shim）
# 实际实现位于 `res://ui/debug/debug_commands/state_commands.gd`。
class_name DebugStateCommands
extends RefCounted

const Impl = preload("res://ui/debug/debug_commands/state_commands.gd")

static func register_all(registry: DebugCommandRegistry) -> void:
	Impl.register_all(registry)

