# 游戏流程调试命令（兼容 shim）
# 实际实现位于 `res://ui/debug/debug_commands/game_commands.gd`。
class_name DebugGameCommands
extends RefCounted

const Impl = preload("res://ui/debug/debug_commands/game_commands.gd")

static func register_all(registry: DebugCommandRegistry) -> void:
	Impl.register_all(registry)

