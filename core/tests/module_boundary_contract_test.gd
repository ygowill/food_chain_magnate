# 模块边界契约测试（P1）
# 目标：
# - base_rules 不允许再引用旧 `res://core/rules/phase/**` 路径（避免规则实现回流到 core）
# - core（不含 core/tests 与 core/modules）不应直接引用 `res://modules/` 路径（避免 core 依赖具体模块资源/脚本）
class_name ModuleBoundaryContractTest
extends RefCounted

const _OLD_CORE_PHASE_PATH := "res://core/rules/phase/"
const _MODULES_PATH := "res://modules/"

static func run() -> Result:
	var r1 := _assert_no_pattern_in_gd_dir("res://modules/base_rules/rules", _OLD_CORE_PHASE_PATH)
	if not r1.ok:
		return r1

	var r2 := _assert_core_no_modules_path_refs()
	if not r2.ok:
		return r2

	return Result.success({
		"checks": 2,
	})

static func _assert_core_no_modules_path_refs() -> Result:
	var files: Array[String] = []
	var list_r := _list_gd_files_recursive("res://core", files)
	if not list_r.ok:
		return list_r

	for path in files:
		if path.begins_with("res://core/tests/"):
			continue
		if path.begins_with("res://core/modules/"):
			continue
		var read_r := _read_text(path)
		if not read_r.ok:
			return read_r
		var text: String = str(read_r.value)
		var idx := text.find(_MODULES_PATH)
		if idx >= 0:
			var line_no := _find_line_number(text, idx)
			return Result.failure("core 不应直接引用 %s: %s:%d" % [_MODULES_PATH, path, line_no])

	return Result.success()

static func _assert_no_pattern_in_gd_dir(root_dir: String, pattern: String) -> Result:
	var files: Array[String] = []
	var list_r := _list_gd_files_recursive(root_dir, files)
	if not list_r.ok:
		return list_r
	for path in files:
		var read_r := _read_text(path)
		if not read_r.ok:
			return read_r
		var text: String = str(read_r.value)
		var idx := text.find(pattern)
		if idx >= 0:
			var line_no := _find_line_number(text, idx)
			return Result.failure("检测到旧路径引用（需保持模块化边界）：%s:%d contains %s" % [path, line_no, pattern])
	return Result.success()

static func _list_gd_files_recursive(root_dir: String, out: Array[String]) -> Result:
	if root_dir.is_empty():
		return Result.failure("root_dir 不能为空")
	if out == null:
		return Result.failure("out 不能为空")

	var dir := DirAccess.open(root_dir)
	if dir == null:
		return Result.failure("无法打开目录: %s" % root_dir)

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path := root_dir.path_join(entry)
		if dir.current_is_dir():
			var sub := _list_gd_files_recursive(path, out)
			if not sub.ok:
				dir.list_dir_end()
				return sub
		else:
			if entry.ends_with(".gd"):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return Result.success()

static func _read_text(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法读取文件: %s" % path)
	var text := file.get_as_text()
	file.close()
	return Result.success(text)

static func _find_line_number(text: String, char_index: int) -> int:
	if char_index <= 0:
		return 1
	var n := 1
	for i in range(min(char_index, text.length())):
		if text[i] == "\n":
			n += 1
	return n
