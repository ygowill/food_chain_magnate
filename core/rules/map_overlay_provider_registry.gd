# Map Overlay Provider Registry (modules-v2 aware)
# Purpose: keep module-private map_data ->通用 overlay 指令 out of core UI drawing code.
class_name MapOverlayProviderRegistry
extends RefCounted

const _OVERLAY_KEY_PENDING_ROAD_DIRS := "pending_road_connection_dirs_by_pos"
const _OVERLAY_KEY_ROADWORK_MARKERS := "roadworks_marker_world_positions"

static var _providers: Array = [] # Array[{id, callback, priority, source}]
static var _loaded: bool = false

static func reset() -> void:
	_providers = []
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("MapOverlayProviderRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("MapOverlayProviderRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("MapOverlayProviderRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not ruleset.has_method("get_ui_extensions"):
		return Result.failure("MapOverlayProviderRegistry.configure_from_ruleset: ruleset 缺少 get_ui_extensions")

	var ui_extensions = ruleset.get_ui_extensions()
	if ui_extensions == null or not (ui_extensions is Object):
		return Result.failure("MapOverlayProviderRegistry.configure_from_ruleset: ruleset.get_ui_extensions() 返回值类型错误（期望 Object）")

	var provider_items = ui_extensions.get("map_overlay_providers")
	if not (provider_items is Array):
		return Result.failure("MapOverlayProviderRegistry.configure_from_ruleset: ui_extensions.map_overlay_providers 缺失或类型错误（期望 Array）")

	_providers = []

	for i in range(provider_items.size()):
		var item_val = provider_items[i]
		if not (item_val is Dictionary):
			return Result.failure("MapOverlayProviderRegistry: map_overlay_providers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("MapOverlayProviderRegistry: map_overlay_providers[%d].id 类型错误（期望 String）" % i)
		var provider_id: String = str(id_val).strip_edges()
		if provider_id.is_empty():
			return Result.failure("MapOverlayProviderRegistry: map_overlay_providers[%d].id 不能为空" % i)

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("MapOverlayProviderRegistry: map_overlay_providers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("MapOverlayProviderRegistry: map_overlay_providers[%d].callback 无效: %s" % [i, provider_id])

		var prio: int = int(item.get("priority", 100))
		var src: String = str(item.get("source", ""))

		for prev_val in _providers:
			if prev_val is Dictionary and str((prev_val as Dictionary).get("id", "")) == provider_id:
				return Result.failure("MapOverlayProviderRegistry: provider 重复注册: %s" % provider_id)

		_providers.append({
			"id": provider_id,
			"callback": cb,
			"priority": prio,
			"source": src,
		})

	_providers.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)

	return Result.success(_providers.size())

static func get_pending_road_connection_dirs(map_data: Dictionary) -> Dictionary:
	var overlays := _build_overlays(map_data)
	var val = overlays.get(_OVERLAY_KEY_PENDING_ROAD_DIRS, null)
	return val if (val is Dictionary) else {}

static func get_roadworks_marker_world_positions(map_data: Dictionary) -> Array[Vector2i]:
	var overlays := _build_overlays(map_data)
	var val = overlays.get(_OVERLAY_KEY_ROADWORK_MARKERS, null)
	if not (val is Array):
		return []
	var out: Array[Vector2i] = []
	for p in Array(val):
		if p is Vector2i:
			out.append(p)
	return out

static func _build_overlays(map_data: Dictionary) -> Dictionary:
	if not _loaded:
		return {}
	if _providers.is_empty():
		return {}
	if map_data == null or not (map_data is Dictionary):
		return {}

	var pending_dirs_by_pos: Dictionary = {} # Vector2i -> {dir -> true}
	var marker_positions: Array[Vector2i] = []
	var marker_seen: Dictionary = {} # "x,y" -> true

	for i in range(_providers.size()):
		var item_val = _providers[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var cb: Callable = item.get("callback", Callable())
		if not cb.is_valid():
			push_error("MapOverlayProviderRegistry: provider callback 无效: %s" % str(item.get("id", "")))
			continue
		var r = cb.call(map_data)
		if r == null or not (r is Dictionary):
			push_error("MapOverlayProviderRegistry: provider 必须返回 Dictionary: %s" % str(item.get("id", "")))
			continue
		var ov: Dictionary = r

		var pd_val = ov.get(_OVERLAY_KEY_PENDING_ROAD_DIRS, null)
		if pd_val is Dictionary:
			var pd: Dictionary = pd_val
			for pos_val in pd.keys():
				if not (pos_val is Vector2i):
					continue
				var pos: Vector2i = pos_val
				var dirs_val = pd.get(pos_val, null)
				if not (dirs_val is Dictionary):
					continue
				if not pending_dirs_by_pos.has(pos):
					pending_dirs_by_pos[pos] = {}
				var merged: Dictionary = pending_dirs_by_pos[pos]
				for d_val in (dirs_val as Dictionary).keys():
					var d := str(d_val).strip_edges()
					if d.is_empty():
						continue
					merged[d] = true
				pending_dirs_by_pos[pos] = merged

		var mp_val = ov.get(_OVERLAY_KEY_ROADWORK_MARKERS, null)
		if mp_val is Array:
			for p in Array(mp_val):
				if not (p is Vector2i):
					continue
				var pos2: Vector2i = p
				var key := "%d,%d" % [pos2.x, pos2.y]
				if marker_seen.has(key):
					continue
				marker_seen[key] = true
				marker_positions.append(pos2)

	var out := {}
	if not pending_dirs_by_pos.is_empty():
		out[_OVERLAY_KEY_PENDING_ROAD_DIRS] = pending_dirs_by_pos
	if not marker_positions.is_empty():
		out[_OVERLAY_KEY_ROADWORK_MARKERS] = marker_positions
	return out
