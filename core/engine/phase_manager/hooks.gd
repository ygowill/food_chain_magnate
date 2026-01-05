# PhaseManager：钩子注册与运行
# 负责：phase/sub_phase 的 BEFORE/AFTER ENTER/EXIT hooks 存储与调度。
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

# phase -> hook_type -> Array[{callback, priority, source}]
var _phase_hooks: Dictionary = {}
var _sub_phase_hooks: Dictionary = {}
var _sub_phase_hooks_by_name: Dictionary = {}
var _hook_types: Array = []

func _init(phase_ids: Array, sub_phase_ids: Array, hook_types: Array) -> void:
	_hook_types = hook_types.duplicate()

	for phase in phase_ids:
		_phase_hooks[phase] = {}
		for hook_type in _hook_types:
			_phase_hooks[phase][hook_type] = []

	for sub_phase in sub_phase_ids:
		_sub_phase_hooks[sub_phase] = {}
		for hook_type in _hook_types:
			_sub_phase_hooks[sub_phase][hook_type] = []

func register_phase_hook(
	phase: int,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source: String = ""
) -> void:
	if not _phase_hooks.has(phase):
		GameLog.warn("PhaseManager", "未知阶段: %d" % phase)
		return

	var hook := {
		"callback": callback,
		"priority": priority,
		"source": source
	}

	_phase_hooks[phase][hook_type].append(hook)
	_phase_hooks[phase][hook_type].sort_custom(func(a, b):
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		return str(a.source) < str(b.source)
	)

	if DebugFlags.verbose_logging:
		GameLog.debug("PhaseManager", "注册阶段钩子: %s %s (优先级: %d)" % [
			DefsClass.PHASE_NAMES.get(phase, "?"),
			_hook_type_name(hook_type),
			priority
		])

func register_sub_phase_hook(
	sub_phase: int,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source: String = ""
) -> void:
	if not _sub_phase_hooks.has(sub_phase):
		GameLog.warn("PhaseManager", "未知子阶段: %d" % sub_phase)
		return

	var hook := {
		"callback": callback,
		"priority": priority,
		"source": source
	}

	_sub_phase_hooks[sub_phase][hook_type].append(hook)
	_sub_phase_hooks[sub_phase][hook_type].sort_custom(func(a, b):
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		return str(a.source) < str(b.source)
	)

func register_sub_phase_hook_by_name(
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source: String = ""
) -> void:
	if sub_phase_name.is_empty():
		GameLog.warn("PhaseManager", "未知子阶段名: <empty>")
		return

	if not _sub_phase_hooks_by_name.has(sub_phase_name):
		_sub_phase_hooks_by_name[sub_phase_name] = {}
		for t in _hook_types:
			_sub_phase_hooks_by_name[sub_phase_name][t] = []

	var hook := {
		"callback": callback,
		"priority": priority,
		"source": source
	}

	_sub_phase_hooks_by_name[sub_phase_name][hook_type].append(hook)
	_sub_phase_hooks_by_name[sub_phase_name][hook_type].sort_custom(func(a, b):
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		return str(a.source) < str(b.source)
	)

func unregister_hook(phase: int, hook_type: int, callback: Callable) -> bool:
	if not _phase_hooks.has(phase):
		return false

	var hooks: Array = _phase_hooks[phase][hook_type]
	for i in range(hooks.size() - 1, -1, -1):
		if hooks[i].callback == callback:
			hooks.remove_at(i)
			return true
	return false

func run_phase_hooks(phase: int, hook_type: int, state: GameState) -> Result:
	if not _phase_hooks.has(phase):
		return Result.success()
	return _run_hooks(_phase_hooks[phase][hook_type], state)

func run_sub_phase_hooks(sub_phase: int, hook_type: int, state: GameState) -> Result:
	if not _sub_phase_hooks.has(sub_phase):
		return Result.success()
	return _run_hooks(_sub_phase_hooks[sub_phase][hook_type], state)

func run_sub_phase_hooks_by_name(sub_phase_name: String, hook_type: int, state: GameState) -> Result:
	if sub_phase_name.is_empty():
		return Result.success()
	if not _sub_phase_hooks_by_name.has(sub_phase_name):
		return Result.success()
	return _run_hooks(_sub_phase_hooks_by_name[sub_phase_name][hook_type], state)

func dump() -> String:
	var output := "=== PhaseManager ===\n"
	output += "Registered Phase Hooks:\n"

	for phase in _phase_hooks:
		var phase_name: String = DefsClass.PHASE_NAMES.get(phase, "?")
		var hook_counts := []
		for hook_type in _hook_types:
			var count: int = _phase_hooks[phase][hook_type].size()
			if count > 0:
				hook_counts.append("%s:%d" % [_hook_type_name(hook_type), count])

		if hook_counts.size() > 0:
			output += "  %s: %s\n" % [phase_name, ", ".join(hook_counts)]

	output += "Registered SubPhase Hooks:\n"
	for sub_phase in _sub_phase_hooks:
		var sub_name: String = DefsClass.SUB_PHASE_NAMES.get(sub_phase, "?")
		var hook_counts := []
		for hook_type in _hook_types:
			var count: int = _sub_phase_hooks[sub_phase][hook_type].size()
			if count > 0:
				hook_counts.append("%s:%d" % [_hook_type_name(hook_type), count])

		if hook_counts.size() > 0:
			output += "  %s: %s\n" % [sub_name, ", ".join(hook_counts)]

	if not _sub_phase_hooks_by_name.is_empty():
		output += "Registered Custom SubPhase Hooks:\n"
		var names: Array = _sub_phase_hooks_by_name.keys()
		names.sort()
		for name_val in names:
			var name: String = str(name_val)
			var hook_counts2 := []
			for hook_type in _hook_types:
				var count2: int = int((_sub_phase_hooks_by_name[name][hook_type] as Array).size())
				if count2 > 0:
					hook_counts2.append("%s:%d" % [_hook_type_name(hook_type), count2])
			if hook_counts2.size() > 0:
				output += "  %s: %s\n" % [name, ", ".join(hook_counts2)]

	return output

static func _run_hooks(hooks: Array, state: GameState) -> Result:
	var warnings: Array[String] = []
	for hook in hooks:
		var result = hook.callback.call(state)
		if result is Result:
			if not result.ok:
				return result
			warnings.append_array(result.warnings)
	return Result.success().with_warnings(warnings)

static func _hook_type_name(hook_type: int) -> String:
	match hook_type:
		0: return "BEFORE_ENTER"
		1: return "AFTER_ENTER"
		2: return "BEFORE_EXIT"
		3: return "AFTER_EXIT"
		_: return "UNKNOWN"
