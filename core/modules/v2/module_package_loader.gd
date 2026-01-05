# 模块系统 V2：加载 res://modules/<module_id>/module.json
class_name ModulePackageLoader
extends RefCounted

const DEFAULT_MODULES_DIR := "res://modules"
const ModuleManifestClass = preload("res://core/modules/v2/module_manifest.gd")

static func load_all(base_dir: String = DEFAULT_MODULES_DIR) -> Result:
	return load_all_from_dirs([base_dir])

static func load_all_from_dirs(base_dirs: Array) -> Result:
	if base_dirs == null or not (base_dirs is Array):
		return Result.failure("ModulePackageLoader.load_all_from_dirs: base_dirs 类型错误（期望 Array[String]）")
	if base_dirs.is_empty():
		return Result.failure("ModulePackageLoader.load_all_from_dirs: base_dirs 不能为空")

	var dirs: Array[String] = []
	var seen := {}
	for i in range(base_dirs.size()):
		var v = base_dirs[i]
		if not (v is String):
			return Result.failure("ModulePackageLoader.load_all_from_dirs: base_dirs[%d] 类型错误（期望 String）" % i)
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("ModulePackageLoader.load_all_from_dirs: base_dirs[%d] 不能为空" % i)
		if seen.has(s):
			continue
		seen[s] = true
		dirs.append(s)

	var out: Dictionary = {}  # id -> ModuleManifest
	for base_dir in dirs:
		var dir := DirAccess.open(base_dir)
		if dir == null:
			return Result.failure("无法读取目录: %s" % base_dir)

		var module_dirs: Array[String] = []
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if dir.current_is_dir():
				if not entry.begins_with("."):
					module_dirs.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()

		module_dirs.sort()

		for module_dir in module_dirs:
			var manifest_path := base_dir.path_join(module_dir).path_join("module.json")
			var manifest_read := ModuleManifestClass.load_from_file(manifest_path)
			if not manifest_read.ok:
				return Result.failure("无法加载模块包 manifest: %s (%s)" % [module_dir, manifest_read.error])
			var manifest = manifest_read.value
			if manifest == null:
				return Result.failure("模块包 manifest 解析失败: %s" % module_dir)
			if manifest.id != module_dir:
				return Result.failure("模块包目录名与 manifest.id 不一致: dir=%s id=%s" % [module_dir, manifest.id])
			if out.has(manifest.id):
				return Result.failure("重复的模块包 id: %s" % manifest.id)
			out[manifest.id] = manifest

	return Result.success(out)

static func resolve_module_root(base_dirs: Array, module_id: String) -> Result:
	if base_dirs == null or not (base_dirs is Array):
		return Result.failure("ModulePackageLoader.resolve_module_root: base_dirs 类型错误（期望 Array[String]）")
	if module_id.is_empty():
		return Result.failure("ModulePackageLoader.resolve_module_root: module_id 不能为空")

	for i in range(base_dirs.size()):
		var v = base_dirs[i]
		if not (v is String):
			continue
		var base_dir: String = str(v)
		if base_dir.is_empty():
			continue
		var root := base_dir.path_join(module_id)
		if DirAccess.open(root) != null:
			return Result.success(root)
	return Result.failure("模块包不存在: %s" % module_id)
