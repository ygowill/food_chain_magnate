# 放置冲突查询注册表（模块化，Fail Fast）
# 用途：消除“模块 A 读取模块 B 的 state.map/state.round_state 私有结构”这类隐式耦合。
# 约定：provider 回调必须返回 Result.value = Array[String]（冲突 id 列表）。
class_name PlacementConflictRegistry
extends RefCounted

const RulesRegistryBundleClass = preload("res://core/engine/game_engine/rules_registry_bundle.gd")

static var _current_bundle = RulesRegistryBundleClass.new()

static func _get_bundle():
	if _current_bundle == null:
		_current_bundle = RulesRegistryBundleClass.new()
	return _current_bundle

static func _resolve_bundle(bundle = null):
	if bundle != null:
		return bundle
	return _get_bundle()

static func set_current_bundle(bundle) -> void:
	_current_bundle = bundle if bundle != null else RulesRegistryBundleClass.new()

static func reset_current_bundle() -> void:
	_current_bundle = RulesRegistryBundleClass.new()

static func reset() -> void:
	var target = _get_bundle()
	target.placement_conflict_providers = []
	target.placement_conflict_loaded = true

static func is_loaded() -> bool:
	return bool(_get_bundle().placement_conflict_loaded)

static func get_provider_ids() -> Array[String]:
	if not is_loaded():
		return []
	var ids: Array[String] = []
	for item_val in _get_bundle().placement_conflict_providers:
		if item_val is Dictionary:
			var provider_id := str((item_val as Dictionary).get("id", "")).strip_edges()
			if not provider_id.is_empty():
				ids.append(provider_id)
	return ids

static func configure_from_ruleset(ruleset, bundle = null) -> Result:
	if not is_loaded() and bundle == null:
		return Result.failure("PlacementConflictRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("PlacementConflictRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("PlacementConflictRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.placement_conflict_providers is Array):
		return Result.failure("PlacementConflictRegistry.configure_from_ruleset: ruleset.placement_conflict_providers 缺失或类型错误（期望 Array）")

	var target = _resolve_bundle(bundle)
	target.placement_conflict_providers = []
	target.placement_conflict_loaded = true

	for i in range(ruleset.placement_conflict_providers.size()):
		var item_val = ruleset.placement_conflict_providers[i]
		if not (item_val is Dictionary):
			return Result.failure("PlacementConflictRegistry: placement_conflict_providers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("PlacementConflictRegistry: placement_conflict_providers[%d].id 类型错误（期望 String）" % i)
		var provider_id: String = str(id_val)
		if provider_id.is_empty():
			return Result.failure("PlacementConflictRegistry: placement_conflict_providers[%d].id 不能为空" % i)

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("PlacementConflictRegistry: placement_conflict_providers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("PlacementConflictRegistry: placement_conflict_providers[%d].callback 无效: %s" % [i, provider_id])

		var prio: int = int(item.get("priority", 100))
		var src: String = str(item.get("source", ""))

		for prev_val in target.placement_conflict_providers:
			if prev_val is Dictionary and str((prev_val as Dictionary).get("id", "")) == provider_id:
				return Result.failure("PlacementConflictRegistry: provider 重复注册: %s" % provider_id)

		target.placement_conflict_providers.append({
			"id": provider_id,
			"callback": cb,
			"priority": prio,
			"source": src,
		})

		target.placement_conflict_providers.sort_custom(func(a, b) -> bool:
			if int(a.priority) != int(b.priority):
				return int(a.priority) < int(b.priority)
			if str(a.id) != str(b.id):
				return str(a.id) < str(b.id)
			return str(a.source) < str(b.source)
		)

	return Result.success(target.placement_conflict_providers.size())

static func get_conflicts_at_world_pos(state: GameState, world_pos: Vector2i, ctx: Dictionary = {}) -> Result:
	if not is_loaded():
		return Result.failure("PlacementConflictRegistry 未初始化")
	if _get_bundle().placement_conflict_providers.is_empty():
		return Result.success([])
	if state == null:
		return Result.failure("PlacementConflictRegistry.get_conflicts_at_world_pos: state 为空")

	var warnings: Array[String] = []
	var seen := {}
	var out: Array[String] = []
	for i in range(_get_bundle().placement_conflict_providers.size()):
		var item_val = _get_bundle().placement_conflict_providers[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var provider_id := str(item.get("id", ""))
		var cb: Callable = item.get("callback", Callable())
		if not cb.is_valid():
			return Result.failure("PlacementConflictRegistry: provider callback 无效: %s" % provider_id)

		var r = cb.call(state, world_pos, ctx)
		if not (r is Result):
			return Result.failure("PlacementConflictRegistry: provider 必须返回 Result: %s" % provider_id)
		var rr: Result = r
		if not rr.ok:
			return Result.failure("PlacementConflictRegistry: provider 失败: %s: %s" % [provider_id, rr.error])
		warnings.append_array(rr.warnings)

		var list_val = rr.value
		if list_val == null:
			continue
		if not (list_val is Array):
			return Result.failure("PlacementConflictRegistry: provider 返回值类型错误（期望 Array[String]）: %s" % provider_id)
		var list: Array = list_val
		for j in range(list.size()):
			var cid_val = list[j]
			if not (cid_val is String):
				return Result.failure("PlacementConflictRegistry: provider[%s] conflicts[%d] 类型错误（期望 String）" % [provider_id, j])
			var cid: String = str(cid_val)
			if cid.is_empty():
				return Result.failure("PlacementConflictRegistry: provider[%s] conflicts[%d] 不能为空" % [provider_id, j])
			if seen.has(cid):
				continue
			seen[cid] = true
			out.append(cid)

	out.sort()
	return Result.success(out).with_warnings(warnings)

static func has_conflict(state: GameState, world_pos: Vector2i, conflict_id: String, ctx: Dictionary = {}) -> Result:
	if conflict_id.is_empty():
		return Result.failure("PlacementConflictRegistry.has_conflict: conflict_id 不能为空")
	var r := get_conflicts_at_world_pos(state, world_pos, ctx)
	if not r.ok:
		return r
	var ids: Array = r.value
	return Result.success(ids.has(conflict_id)).with_warnings(r.warnings)
