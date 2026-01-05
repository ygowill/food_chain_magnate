# 模块目录 spec 解析工具（V2）
# - 支持用 ';' 分隔多个模块根目录
# - 负责去重/剔除空白，并保证结果非空（Fail Fast）
class_name ModuleDirSpec
extends RefCounted

static func parse_base_dirs(spec: String) -> Result:
	if spec.is_empty():
		return Result.failure("ModuleDirSpec: base_dir_spec 不能为空")

	var parts := spec.split(";", false)
	var out: Array[String] = []
	var seen := {}
	for i in range(parts.size()):
		var raw: String = str(parts[i])
		var s: String = raw.strip_edges()
		if s.is_empty():
			continue
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)

	if out.is_empty():
		return Result.failure("ModuleDirSpec: base_dir_spec 不能为空")
	return Result.success(out)

static func primary_base_dir(spec: String, fallback: String) -> String:
	var read := parse_base_dirs(spec)
	if read.ok:
		var base_dirs: Array = read.value
		if not base_dirs.is_empty():
			return str(base_dirs[0])
	return fallback

