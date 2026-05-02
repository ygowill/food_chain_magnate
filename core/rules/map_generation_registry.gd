# 地图生成注册表（Strict Mode）
# 说明：
# - 生成规则由模块在 rules/entry.gd 中注册
# - 必须且只能有 1 个 primary generator（缺失/重复 => init fail）
class_name MapGenerationRegistry
extends RefCounted

var _primary_callback: Callable = Callable()
var _primary_module_id: String = ""
var _candidate_selector_callback: Callable = Callable()
var _candidate_selector_module_id: String = ""

func clear() -> void:
	_primary_callback = Callable()
	_primary_module_id = ""
	_candidate_selector_callback = Callable()
	_candidate_selector_module_id = ""

func has_primary() -> bool:
	return _primary_callback.is_valid()

func register_primary(callback: Callable, source_module_id: String) -> Result:
	if not callback.is_valid():
		return Result.failure("MapGenerationRegistry: callback 无效")
	if source_module_id.is_empty():
		return Result.failure("MapGenerationRegistry: source_module_id 不能为空")

	if _primary_callback.is_valid():
		return Result.failure("MapGenerationRegistry: primary generator 重复注册: prev=%s new=%s" % [_primary_module_id, source_module_id])

	_primary_callback = callback
	_primary_module_id = source_module_id
	return Result.success()

func register_candidate_selector(callback: Callable, source_module_id: String) -> Result:
	if not callback.is_valid():
		return Result.failure("MapGenerationRegistry: candidate selector callback 无效")
	if source_module_id.is_empty():
		return Result.failure("MapGenerationRegistry: candidate selector source_module_id 不能为空")

	if _candidate_selector_callback.is_valid():
		return Result.failure("MapGenerationRegistry: candidate selector 重复注册: prev=%s new=%s" % [_candidate_selector_module_id, source_module_id])

	_candidate_selector_callback = callback
	_candidate_selector_module_id = source_module_id
	return Result.success()

func generate_map_def(player_count: int, catalog, map_option, rng_manager) -> Result:
	if not has_primary():
		return Result.failure("MapGenerationRegistry: 缺少 primary map generator")
	if _candidate_selector_callback.is_valid():
		return _candidate_selector_callback.call(player_count, catalog, map_option, rng_manager, _primary_callback)
	return _primary_callback.call(player_count, catalog, map_option, rng_manager)
