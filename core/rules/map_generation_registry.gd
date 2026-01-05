# 地图生成注册表（Strict Mode）
# 说明：
# - 生成规则由模块在 rules/entry.gd 中注册
# - 必须且只能有 1 个 primary generator（缺失/重复 => init fail）
class_name MapGenerationRegistry
extends RefCounted

var _primary_callback: Callable = Callable()
var _primary_module_id: String = ""

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

func generate_map_def(player_count: int, catalog, map_option, rng_manager) -> Result:
	if not has_primary():
		return Result.failure("MapGenerationRegistry: 缺少 primary map generator")
	return _primary_callback.call(player_count, catalog, map_option, rng_manager)

