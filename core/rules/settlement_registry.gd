# 阶段结算注册表（模块化结算，Fail Fast）
# 说明：
# - primary：每个 (phase, point) 必须且只能有 1 个
# - extension：可选的额外步骤；按 priority 排序，且以 100 作为 primary 的“分界线”
class_name SettlementRegistry
extends RefCounted

enum Point {
	ENTER,
	EXIT,
}

var _primary: Dictionary = {}     # slot_key -> {callback, source}
var _extensions: Dictionary = {}  # slot_key -> Array[{callback, priority, source}]

func reset() -> void:
	_primary.clear()
	_extensions.clear()

func has_primary(phase: int, point: int) -> bool:
	return _primary.has(_slot_key(phase, point))

func register_primary(phase: int, point: int, callback: Callable, source_module_id: String = "") -> Result:
	if not callback.is_valid():
		return Result.failure("SettlementRegistry: primary callback 无效")
	var key := _slot_key(phase, point)
	if _primary.has(key):
		var prev: Dictionary = _primary[key]
		var prev_src: String = str(prev.get("source", ""))
		return Result.failure("SettlementRegistry: primary settlement 重复注册: %s (prev=%s, new=%s)" % [key, prev_src, source_module_id])
	_primary[key] = {
		"callback": callback,
		"source": source_module_id,
	}
	return Result.success()

func register_extension(
	phase: int,
	point: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if not callback.is_valid():
		return Result.failure("SettlementRegistry: extension callback 无效")
	var key := _slot_key(phase, point)
	if not _extensions.has(key):
		_extensions[key] = []
	var list: Array = _extensions[key]
	list.append({
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	_extensions[key] = list
	return Result.success()

func run(phase: int, point: int, state: GameState, phase_manager) -> Result:
	var key := _slot_key(phase, point)
	if not _primary.has(key):
		return Result.failure("SettlementRegistry: 缺少 primary settlement: %s" % key)
	var primary: Dictionary = _primary[key]

	var extensions: Array = []
	if _extensions.has(key):
		extensions = _extensions[key]
		extensions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: int = int(a.get("priority", 100))
			var pb: int = int(b.get("priority", 100))
			if pa != pb:
				return pa < pb
			var sa: String = str(a.get("source", ""))
			var sb: String = str(b.get("source", ""))
			return sa < sb
		)

	var all_warnings: Array[String] = []

	# priority < 100：primary 之前
	for ext_val in extensions:
		var ext: Dictionary = ext_val
		var prio: int = int(ext.get("priority", 100))
		if prio >= 100:
			break
		var cb: Callable = ext.get("callback", Callable())
		var r = cb.call(state, phase_manager)
		if r is Result:
			var rr: Result = r
			if not rr.ok:
				return Result.failure("SettlementRegistry: extension settlement 失败: %s" % rr.error)
			all_warnings.append_array(rr.warnings)

	# primary
	var primary_cb: Callable = primary.get("callback", Callable())
	var primary_result = primary_cb.call(state, phase_manager)
	if primary_result is Result:
		var pr: Result = primary_result
		if not pr.ok:
			return Result.failure("SettlementRegistry: primary settlement 失败: %s" % pr.error)
		all_warnings.append_array(pr.warnings)

	# priority >= 100：primary 之后
	for ext_val in extensions:
		var ext: Dictionary = ext_val
		var prio: int = int(ext.get("priority", 100))
		if prio < 100:
			continue
		var cb: Callable = ext.get("callback", Callable())
		var r = cb.call(state, phase_manager)
		if r is Result:
			var rr: Result = r
			if not rr.ok:
				return Result.failure("SettlementRegistry: extension settlement 失败: %s" % rr.error)
			all_warnings.append_array(rr.warnings)

	return Result.success().with_warnings(all_warnings)

static func _slot_key(phase: int, point: int) -> String:
	return "%d:%d" % [phase, point]

