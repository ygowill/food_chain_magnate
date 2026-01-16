# StateSchemaRegistry（模块扩展面：state.map/state.round_state schema）
# 目前主要用于声明“哪些 Dictionary 的 key 需要按 int 归一化”（为存档/读档稳定性服务）。
class_name StateSchemaRegistry
extends RefCounted

static var _int_key_dict_schemas: Array = [] # Array[{id, root, path, priority, source}]
static var _loaded: bool = false

static func reset() -> void:
	_int_key_dict_schemas = []
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("StateSchemaRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("StateSchemaRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("StateSchemaRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.state_int_key_dict_schemas is Array):
		return Result.failure("StateSchemaRegistry.configure_from_ruleset: ruleset.state_int_key_dict_schemas 缺失或类型错误（期望 Array）")

	for i in range(ruleset.state_int_key_dict_schemas.size()):
		var item_val = ruleset.state_int_key_dict_schemas[i]
		if not (item_val is Dictionary):
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d].id 类型错误（期望 String）" % i)
		var schema_id: String = str(id_val)
		if schema_id.is_empty():
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d].id 不能为空" % i)

		var root_val = item.get("root", null)
		if not (root_val is String):
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d].root 类型错误（期望 String）" % i)
		var root: String = str(root_val)
		if root != "map" and root != "round_state":
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d].root 不支持: %s" % [i, root])

		var path_val = item.get("path", null)
		if not (path_val is Array):
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d].path 类型错误（期望 Array[String]）" % i)
		var path_any: Array = path_val
		if path_any.is_empty():
			return Result.failure("StateSchemaRegistry: state_int_key_dict_schemas[%d].path 不能为空" % i)
		var path: Array[String] = []
		for j in range(path_any.size()):
			var seg_val = path_any[j]
			if not (seg_val is String):
				return Result.failure("StateSchemaRegistry: %s.path[%d] 类型错误（期望 String）" % [schema_id, j])
			var seg: String = str(seg_val)
			if seg.is_empty():
				return Result.failure("StateSchemaRegistry: %s.path[%d] 不能为空" % [schema_id, j])
			path.append(seg)

		var prio: int = int(item.get("priority", 100))
		var src: String = str(item.get("source", ""))

		for prev_val in _int_key_dict_schemas:
			if prev_val is Dictionary and str((prev_val as Dictionary).get("id", "")) == schema_id:
				return Result.failure("StateSchemaRegistry: schema 重复注册: %s" % schema_id)

		_int_key_dict_schemas.append({
			"id": schema_id,
			"root": root,
			"path": path,
			"priority": prio,
			"source": src,
		})

	_int_key_dict_schemas.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)

	return Result.success(_int_key_dict_schemas.size())

static func get_int_key_dict_schemas() -> Array:
	return _int_key_dict_schemas.duplicate(true)

# 将指定 root 下已注册的“int-key Dictionary schema”应用到容器（就地修改）。
# 用于：从 JSON-safe 反序列化后，把 "0"/"1" 这类数字字符串 key 归一化回 int key。
static func normalize_int_key_dicts_in_container(root: String, container: Dictionary, path_prefix: String) -> Result:
	if not _loaded:
		# 允许在非模块系统场景（纯 GameState.from_dict）下直接跳过
		return Result.success(container)
	if root != "map" and root != "round_state":
		return Result.failure("StateSchemaRegistry.normalize_int_key_dicts_in_container: root 不支持: %s" % root)
	if container == null or not (container is Dictionary):
		return Result.failure("StateSchemaRegistry.normalize_int_key_dicts_in_container: container 类型错误（期望 Dictionary）")
	if path_prefix.is_empty():
		return Result.failure("StateSchemaRegistry.normalize_int_key_dicts_in_container: path_prefix 不能为空")

	for item_val in _int_key_dict_schemas:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("root", "")) != root:
			continue
		var schema_id: String = str(item.get("id", ""))
		var path_any = item.get("path", null)
		if not (path_any is Array):
			return Result.failure("StateSchemaRegistry: %s.path 类型错误（期望 Array[String]）" % schema_id)
		var path: Array[String] = []
		for seg_val in path_any:
			path.append(str(seg_val))
		var apply_r := _normalize_int_key_dict_at_path(container, path, path_prefix, schema_id)
		if not apply_r.ok:
			return apply_r

	return Result.success(container)

static func _normalize_int_key_dict_at_path(root_container: Dictionary, path: Array[String], path_prefix: String, schema_id: String) -> Result:
	if path == null or path.is_empty():
		return Result.failure("StateSchemaRegistry: %s.path 不能为空" % schema_id)

	var container: Dictionary = root_container
	var current_path: String = path_prefix
	for i in range(path.size()):
		var seg: String = str(path[i])
		if seg.is_empty():
			return Result.failure("StateSchemaRegistry: %s.path[%d] 不能为空" % [schema_id, i])

		current_path = "%s.%s" % [current_path, seg]

		if not container.has(seg):
			# 缺失字段：允许（部分模块字段是条件写入的）
			return Result.success()

		var val = container.get(seg, null)
		if i < path.size() - 1:
			if not (val is Dictionary):
				return Result.failure("StateSchemaRegistry: %s: %s 类型错误（期望 Dictionary）" % [schema_id, current_path])
			container = val
			continue

		# leaf
		if not (val is Dictionary):
			return Result.failure("StateSchemaRegistry: %s: %s 类型错误（期望 Dictionary）" % [schema_id, current_path])
		var dict_val: Dictionary = val
		var norm_read := _normalize_int_key_dict(dict_val, current_path, schema_id)
		if not norm_read.ok:
			return norm_read
		container[seg] = norm_read.value
		return Result.success()

	return Result.success()

static func _normalize_int_key_dict(value: Dictionary, path: String, schema_id: String) -> Result:
	var out := {}
	for k in value.keys():
		var pid: int
		if k is int:
			pid = int(k)
		elif k is String:
			var ks: String = str(k)
			if not ks.is_valid_int():
				return Result.failure("StateSchemaRegistry: %s: %s key 必须为数字字符串或 int，实际: %s" % [schema_id, path, str(k)])
			pid = ks.to_int()
		else:
			return Result.failure("StateSchemaRegistry: %s: %s key 类型错误（期望数字字符串或 int），实际: %s" % [schema_id, path, typeof(k)])

		if pid < 0:
			return Result.failure("StateSchemaRegistry: %s: %s key 不能为负数: %d" % [schema_id, path, pid])
		if out.has(pid):
			return Result.failure("StateSchemaRegistry: %s: %s key 重复（归一化后冲突）: %d" % [schema_id, path, pid])
		out[pid] = value.get(k, null)

	return Result.success(out)

# 检测“模块自有字段”下是否仍存在 string 玩家 key（"0"/"1"...）。
# 目的：防止模块新增 per-player Dict 后忘记注册 int-key schema，导致读档后 key 类型漂移。
#
# 约定（仅告警，不改写状态）：
# - 仅扫描 module-owned 字段（key == module_id 或以 "module_id_" 开头）。
# - 仅匹配玩家 id 范围内的数字字符串 key（0..player_count-1），以避免误报。
static func warn_if_module_owned_has_string_player_keys(
	modules: Array[String],
	root: String,
	container: Dictionary,
	player_count: int,
	path_prefix: String
) -> Result:
	if not _loaded:
		return Result.success()
	if modules == null:
		return Result.failure("StateSchemaRegistry.warn_if_module_owned_has_string_player_keys: modules 为空")
	if root != "map" and root != "round_state":
		return Result.failure("StateSchemaRegistry.warn_if_module_owned_has_string_player_keys: root 不支持: %s" % root)
	if container == null or not (container is Dictionary):
		return Result.failure("StateSchemaRegistry.warn_if_module_owned_has_string_player_keys: container 类型错误（期望 Dictionary）")
	if player_count < 0:
		return Result.failure("StateSchemaRegistry.warn_if_module_owned_has_string_player_keys: player_count 不能为负数: %d" % player_count)
	if path_prefix.is_empty():
		return Result.failure("StateSchemaRegistry.warn_if_module_owned_has_string_player_keys: path_prefix 不能为空")

	if modules.is_empty() or player_count == 0:
		return Result.success()

	var warnings: Array[String] = []
	for k in container.keys():
		if not (k is String):
			continue
		var key: String = str(k)
		if key.is_empty():
			continue
		var module_id := _match_module_id(modules, key)
		if module_id.is_empty():
			continue

		var v = container.get(key, null)
		_scan_for_string_player_keys(v, "%s.%s" % [path_prefix, key], module_id, player_count, warnings)

	return Result.success().with_warnings(warnings)

static func _match_module_id(modules: Array[String], key: String) -> String:
	for mid_val in modules:
		if not (mid_val is String):
			continue
		var mid: String = str(mid_val)
		if mid.is_empty():
			continue
		if key == mid or key.begins_with("%s_" % mid):
			return mid
	return ""

static func _scan_for_string_player_keys(value, path: String, module_id: String, player_count: int, warnings: Array[String]) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			if _has_string_player_key(d, player_count):
				warnings.append("StateSchemaRegistry: %s 存在字符串玩家 key（可能缺少 schema 注册）: %s" % [module_id, path])
				return
			for dk in d.keys():
				_scan_for_string_player_keys(d.get(dk, null), "%s.%s" % [path, str(dk)], module_id, player_count, warnings)
		TYPE_ARRAY:
			var arr: Array = value
			for i in range(arr.size()):
				_scan_for_string_player_keys(arr[i], "%s[%d]" % [path, i], module_id, player_count, warnings)
		_:
			return

static func _has_string_player_key(d: Dictionary, player_count: int) -> bool:
	for k in d.keys():
		if not (k is String):
			continue
		var ks: String = str(k)
		if not ks.is_valid_int():
			continue
		var pid: int = ks.to_int()
		if pid >= 0 and pid < player_count:
			return true
	return false
