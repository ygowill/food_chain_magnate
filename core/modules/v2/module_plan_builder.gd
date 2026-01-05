# 模块系统 V2：启用模块闭包 + 冲突检测 + 确定性顺序（Fail Fast）
class_name ModulePlanBuilder
extends RefCounted

# 输入：
# - all_manifests: Dictionary(module_id -> ModuleManifest)
# - requested_module_ids: Array[String]
# 输出：
# - Array[String]（按依赖优先 + (priority,id) 稳定排序）
static func build_plan(all_manifests: Dictionary, requested_module_ids: Array[String]) -> Result:
	if not (all_manifests is Dictionary):
		return Result.failure("ModulePlanBuilder.build_plan: all_manifests 类型错误（期望 Dictionary）")
	if not (requested_module_ids is Array):
		return Result.failure("ModulePlanBuilder.build_plan: requested_module_ids 类型错误（期望 Array[String]）")

	# 空列表：允许（由上层决定是否仍需满足必需能力）
	if requested_module_ids.is_empty():
		return Result.success([])

	# 1) 去重 + 校验
	var requested_unique := {}
	for i in range(requested_module_ids.size()):
		var mid_val = requested_module_ids[i]
		if not (mid_val is String):
			return Result.failure("modules[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("modules[%d] 不能为空" % i)
		if requested_unique.has(mid):
			return Result.failure("重复的模块 id: %s" % mid)
		requested_unique[mid] = true

	# 2) 依赖闭包
	var wanted := {}
	var queue: Array[String] = []
	for mid in requested_unique.keys():
		queue.append(str(mid))
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if wanted.has(id):
			continue
		var manifest = all_manifests.get(id, null)
		if manifest == null:
			return Result.failure("未知的模块 id: %s" % id)
		wanted[id] = true

		var deps_val = manifest.dependencies
		if not (deps_val is Array):
			return Result.failure("module.json.dependencies 类型错误: %s" % id)
		for dep_val in deps_val:
			if not (dep_val is String):
				return Result.failure("module.json.dependencies 类型错误: %s -> %s" % [id, str(dep_val)])
			var dep: String = str(dep_val)
			if dep.is_empty():
				return Result.failure("module.json.dependencies 不能为空: %s" % id)
			queue.append(dep)

	# 3) 冲突检测（任一方声明 conflicts 即视为冲突）
	for id_val in wanted.keys():
		var id: String = str(id_val)
		var manifest = all_manifests.get(id, null)
		assert(manifest != null, "ModulePlanBuilder: 缺少 manifest: %s" % id)
		var conflicts_val = manifest.conflicts
		if not (conflicts_val is Array):
			return Result.failure("module.json.conflicts 类型错误: %s" % id)
		for other_val in conflicts_val:
			if not (other_val is String):
				return Result.failure("module.json.conflicts 类型错误: %s -> %s" % [id, str(other_val)])
			var other: String = str(other_val)
			if other.is_empty():
				return Result.failure("module.json.conflicts 不能为空: %s" % id)
			if wanted.has(other):
				return Result.failure("模块冲突: %s <-> %s" % [id, other])

	# 4) 拓扑排序（依赖优先；同层按 priority + id 稳定排序）
	var indegree := {}
	var outgoing := {}
	for id_val in wanted.keys():
		var id: String = str(id_val)
		indegree[id] = 0
		outgoing[id] = []

	for id_val in wanted.keys():
		var id: String = str(id_val)
		var manifest = all_manifests.get(id, null)
		assert(manifest != null, "ModulePlanBuilder: 缺少 manifest: %s" % id)
		for dep in manifest.dependencies:
			if not wanted.has(dep):
				return Result.failure("模块依赖缺失: %s -> %s" % [id, dep])
			outgoing[dep].append(id)
			indegree[id] = int(indegree.get(id, 0)) + 1

	var order: Array[String] = []
	var selected := {}
	while order.size() < wanted.size():
		var zeros: Array[String] = []
		for id_val in wanted.keys():
			var id: String = str(id_val)
			if selected.has(id):
				continue
			if int(indegree.get(id, 0)) == 0:
				zeros.append(id)
		if zeros.is_empty():
			return Result.failure("模块依赖存在环，无法启用: %s" % str(wanted.keys()))

		zeros.sort_custom(func(a: String, b: String) -> bool:
			var ma = all_manifests.get(a, null)
			var mb = all_manifests.get(b, null)
			var pa: int = int(ma.priority) if ma != null else 100
			var pb: int = int(mb.priority) if mb != null else 100
			if pa != pb:
				return pa < pb
			return a < b
		)

		var pick: String = zeros[0]
		selected[pick] = true
		order.append(pick)
		for nxt in outgoing.get(pick, []):
			indegree[nxt] = int(indegree.get(nxt, 0)) - 1

	return Result.success(order)

