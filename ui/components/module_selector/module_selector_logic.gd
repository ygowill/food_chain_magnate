# ModuleSelector：拆分出的纯逻辑（分组/依赖/冲突/Setup 约束）
# 注意：该文件不依赖 Node/Control，仅处理 manifest 与 id 集合。
extends RefCounted

var _available_modules: Dictionary = {} # module_id -> ModuleManifest
var _optional_module_ids: Array[String] = []

func setup(available_modules: Dictionary, optional_module_ids: Array[String]) -> void:
	_available_modules = available_modules
	_optional_module_ids = Array(optional_module_ids, TYPE_STRING, "", null)

func get_module_display_name(module_id: String) -> String:
	var id := str(module_id).strip_edges()
	if id.is_empty():
		return ""
	var manifest_val = _available_modules.get(id, null)
	if manifest_val is ModuleManifest:
		var manifest: ModuleManifest = manifest_val
		return str(manifest.name).strip_edges()
	return id

func _get_module_ui_dict(module_id: String) -> Dictionary:
	var manifest_val = _available_modules.get(module_id, null)
	if not (manifest_val is ModuleManifest):
		return {}
	var manifest: ModuleManifest = manifest_val
	if not (manifest.provides is Dictionary):
		return {}
	var provides: Dictionary = manifest.provides
	var ui_val = provides.get("ui", null)
	if not (ui_val is Dictionary):
		return {}
	return ui_val

func _get_module_selector_meta(module_id: String) -> Dictionary:
	var ui := _get_module_ui_dict(module_id)
	var ms_val = ui.get("module_selector", null)
	return ms_val if (ms_val is Dictionary) else {}

func _get_module_selector_group_id(module_id: String) -> String:
	var meta := _get_module_selector_meta(module_id)
	return str(meta.get("group_id", "")).strip_edges()

func _get_module_selector_group_title(module_id: String) -> String:
	var meta := _get_module_selector_meta(module_id)
	return str(meta.get("group_title", "")).strip_edges()

func _get_module_selector_group_order(module_id: String) -> int:
	var meta := _get_module_selector_meta(module_id)
	return int(meta.get("group_order", 999))

func _get_module_selector_order_in_group(module_id: String) -> int:
	var meta := _get_module_selector_meta(module_id)
	return int(meta.get("order", 999))

func compute_module_groups() -> Array[Dictionary]:
	var groups_by_id: Dictionary = {} # group_id -> {id, title, order, modules}
	for mid in _optional_module_ids:
		var group_id := _get_module_selector_group_id(mid)
		var group_title := _get_module_selector_group_title(mid)
		var group_order := _get_module_selector_group_order(mid)

		if group_id.is_empty():
			group_id = "other"
			group_title = "其他" if group_title.is_empty() else group_title
			group_order = 9999
		elif group_title.is_empty():
			group_title = group_id

		if not groups_by_id.has(group_id):
			groups_by_id[group_id] = {
				"id": group_id,
				"title": group_title,
				"order": group_order,
				"modules": [],
			}
		var g: Dictionary = groups_by_id[group_id]
		var arr: Array[String] = Array(g.get("modules", []), TYPE_STRING, "", null)
		arr.append(mid)
		g["modules"] = arr
		groups_by_id[group_id] = g

	var out: Array[Dictionary] = []
	for gid in groups_by_id.keys():
		out.append(groups_by_id[gid])

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ao := int(a.get("order", 9999))
		var bo := int(b.get("order", 9999))
		if ao != bo:
			return ao < bo
		return str(a.get("title", "")) < str(b.get("title", ""))
	)

	for i in range(out.size()):
		var g2: Dictionary = out[i]
		var mids: Array[String] = Array(g2.get("modules", []), TYPE_STRING, "", null)
		mids.sort_custom(func(a: String, b: String) -> bool:
			var ao := _get_module_selector_order_in_group(a)
			var bo := _get_module_selector_order_in_group(b)
			if ao != bo:
				return ao < bo
			return get_module_display_name(a) < get_module_display_name(b)
		)
		g2["modules"] = mids
		out[i] = g2

	return out

func compute_effective_optional_modules(requested_optional_modules: Dictionary, forced_optional_modules: Dictionary) -> Dictionary:
	var effective: Dictionary = {}
	for mid_val2 in forced_optional_modules.keys():
		effective[str(mid_val2)] = true
	for mid_val in requested_optional_modules.keys():
		effective[str(mid_val)] = true

	var stack: Array[String] = []
	for mid_val3 in requested_optional_modules.keys():
		stack.append(str(mid_val3))
	for mid_val4 in forced_optional_modules.keys():
		stack.append(str(mid_val4))

	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true

		var manifest_val = _available_modules.get(cur, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for dep_val in manifest.dependencies:
			if not (dep_val is String):
				continue
			var dep: String = str(dep_val)
			if dep.begins_with("base_"):
				continue
			effective[dep] = true
			stack.append(dep)

	return effective

func compute_locked_optional_modules(requested_optional_modules: Dictionary, forced_optional_modules: Dictionary) -> Dictionary:
	var locked: Dictionary = {}
	var stack: Array[String] = []
	for mid_val in requested_optional_modules.keys():
		stack.append(str(mid_val))
	for mid_val2 in forced_optional_modules.keys():
		stack.append(str(mid_val2))

	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true

		var manifest_val = _available_modules.get(cur, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for dep_val in manifest.dependencies:
			if not (dep_val is String):
				continue
			var dep: String = str(dep_val)
			if dep.begins_with("base_"):
				continue
			locked[dep] = true
			stack.append(dep)

	return locked

func _depends_on_module(module_id: String, target_id: String) -> bool:
	var target := str(target_id).strip_edges()
	if target.is_empty():
		return false

	var stack: Array[String] = [str(module_id)]
	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true

		var manifest_val = _available_modules.get(cur, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for dep_val in manifest.dependencies:
			if not (dep_val is String):
				continue
			var dep: String = str(dep_val)
			if dep == target:
				return true
			if dep.begins_with("base_"):
				continue
			stack.append(dep)

	return false

func compute_conflicting_requested_modules_to_remove(requested_optional_modules: Dictionary, forced_optional_modules: Dictionary) -> Dictionary:
	# 只自动取消“用户显式选择”的模块；forced/依赖锁定模块不自动取消（避免越权）
	var effective := compute_effective_optional_modules(requested_optional_modules, forced_optional_modules)
	var to_remove: Dictionary = {} # module_id -> reason

	for a_id_val in effective.keys():
		var a_id := str(a_id_val)
		var a_manifest_val = _available_modules.get(a_id, null)
		if not (a_manifest_val is ModuleManifest):
			continue
		var a_manifest: ModuleManifest = a_manifest_val
		var a_pri := int(a_manifest.priority)
		var conflicts: Array[String] = Array(a_manifest.conflicts, TYPE_STRING, "", null)
		for b_id in conflicts:
			if not effective.has(b_id):
				continue
			if forced_optional_modules.has(b_id):
				continue
			if not requested_optional_modules.has(b_id):
				continue
			if forced_optional_modules.has(a_id):
				to_remove[b_id] = "已自动取消 %s（与 %s 冲突）" % [get_module_display_name(b_id), get_module_display_name(a_id)]
				continue
			var b_manifest_val = _available_modules.get(b_id, null)
			var b_pri := int((b_manifest_val as ModuleManifest).priority) if (b_manifest_val is ModuleManifest) else 100
			if a_pri >= b_pri:
				to_remove[b_id] = "已自动取消 %s（与 %s 冲突）" % [get_module_display_name(b_id), get_module_display_name(a_id)]

	return to_remove

func compute_removed_base_modules_from_conflicts(effective_optional: Dictionary) -> Dictionary:
	# base_module_id -> source_module_id（哪个 optional 模块声明了该冲突）
	var removed: Dictionary = {}
	for mid_val in effective_optional.keys():
		var mid := str(mid_val)
		var manifest_val = _available_modules.get(mid, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		for c_val in manifest.conflicts:
			if not (c_val is String):
				continue
			var c := str(c_val).strip_edges()
			if c.is_empty():
				continue
			if c.begins_with("base_"):
				removed[c] = mid
	return removed

func compute_requested_modules_to_remove_due_to_removed_base(removed_base: Dictionary, requested_optional_modules: Dictionary) -> Array[String]:
	if removed_base.is_empty():
		return []
	var remove_list: Array[String] = []
	for mid_val in requested_optional_modules.keys():
		var mid := str(mid_val)
		for base_id_val in removed_base.keys():
			var base_id := str(base_id_val)
			if _depends_on_module(mid, base_id):
				remove_list.append(mid)
				break
	remove_list.sort()
	return remove_list

func get_removed_base_dependency_reason(module_id: String, removed_base: Dictionary) -> String:
	if removed_base.is_empty():
		return ""
	var deps: Array[String] = []
	for base_id_val in removed_base.keys():
		var base_id := str(base_id_val)
		if _depends_on_module(module_id, base_id):
			deps.append(base_id)
	deps.sort()
	if deps.is_empty():
		return ""
	return "与当前选择不兼容（依赖: %s）" % ", ".join(deps)

func compute_required_optional_modules_for_player_count(player_count: int, requested_optional_modules: Dictionary) -> Dictionary:
	# 基于 module.json 提供的 setup_constraints 计算强制模块列表。
	# 支持两类约束：
	# - setup_constraints.required_player_counts：指定人数下强制启用该模块本身（与选择无关）。
	# - setup_constraints.requires_optional_modules：当该模块启用且人数匹配时，强制启用其它可选模块（依赖当前选择）。
	var out: Dictionary = {}
	if _available_modules.is_empty():
		return out
	var count := int(player_count)
	if count <= 0:
		return out

	# 1) 人数固定必需模块：required_player_counts
	for mid in _optional_module_ids:
		var ui := _get_module_ui_dict(mid)
		var setup_val = ui.get("setup_constraints", null)
		if not (setup_val is Dictionary):
			continue
		var setup: Dictionary = setup_val
		var counts_val = setup.get("required_player_counts", null)
		if not (counts_val is Array):
			continue

		var required := false
		for c in Array(counts_val):
			if int(c) == count:
				required = true
				break
		if not required:
			continue

		var reason := str(setup.get("reason", "")).strip_edges()
		if reason.is_empty():
			reason = "%d 人局强制启用 %s 模块。" % [count, get_module_display_name(mid)]
		out[mid] = reason

	# 2) 条件必需模块：requires_optional_modules（当某模块启用且人数匹配时，强制启用其它模块）
	# schema:
	# setup_constraints.requires_optional_modules = [
	#   {
	#     "required_player_counts": [5, 6], # 可选；缺省表示任意人数
	#     "module_ids": ["some_optional_module_id"],
	#     "reason": "..."
	#   }
	# ]
	var selected: Dictionary = {}
	var queue: Array[String] = []

	for mid_val in requested_optional_modules.keys():
		var id := str(mid_val).strip_edges()
		if id.is_empty():
			continue
		if selected.has(id):
			continue
		selected[id] = true
		queue.append(id)

	for mid_val2 in out.keys():
		var id2 := str(mid_val2).strip_edges()
		if id2.is_empty():
			continue
		if selected.has(id2):
			continue
		selected[id2] = true
		queue.append(id2)

	var visited: Dictionary = {}
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true

		var ui2 := _get_module_ui_dict(cur)
		var setup_val2 = ui2.get("setup_constraints", null)
		if not (setup_val2 is Dictionary):
			continue
		var setup2: Dictionary = setup_val2

		var reqs_val = setup2.get("requires_optional_modules", null)
		if not (reqs_val is Array):
			continue

		for rule_val in Array(reqs_val):
			if not (rule_val is Dictionary):
				continue
			var rule: Dictionary = rule_val

			var counts_val2 = rule.get("required_player_counts", null)
			if counts_val2 != null:
				if not (counts_val2 is Array):
					continue
				var ok_count := false
				for c2 in Array(counts_val2):
					if int(c2) == count:
						ok_count = true
						break
				if not ok_count:
					continue

			var module_ids_val = rule.get("module_ids", null)
			if not (module_ids_val is Array):
				continue

			var reason2 := str(rule.get("reason", "")).strip_edges()
			if reason2.is_empty():
				reason2 = "%d 人局启用 %s 时需要额外模块。" % [count, get_module_display_name(cur)]

			for req_mid_val in Array(module_ids_val):
				var req_mid := str(req_mid_val).strip_edges()
				if req_mid.is_empty():
					continue
				if req_mid.begins_with("base_"):
					continue
				if not _optional_module_ids.has(req_mid):
					continue
				if not out.has(req_mid):
					out[req_mid] = reason2
				if selected.has(req_mid):
					continue
				selected[req_mid] = true
				queue.append(req_mid)

	return out

