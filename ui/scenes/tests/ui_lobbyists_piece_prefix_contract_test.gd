class_name UiLobbyistsPiecePrefixContractTest
extends RefCounted

const _ROOT_DIR := "res://ui"
const _EXCLUDE_DIR := "res://ui/scenes/tests/"
const _PATTERNS := [
	"lobbyists_road_",
	"lobbyists_park_",
]

static func run() -> Result:
	var files: Array[String] = []
	var list_r := _list_text_files_recursive(_ROOT_DIR, files)
	if not list_r.ok:
		return list_r

	for path in files:
		if path.begins_with(_EXCLUDE_DIR):
			continue
		var read_r := _read_text(path)
		if not read_r.ok:
			return read_r
		var text: String = str(read_r.value)
		for pat in _PATTERNS:
			var idx := text.find(str(pat))
			if idx >= 0:
				var line_no := _find_line_number(text, idx)
				return Result.failure("UI 不应包含模块 piece 前缀分支字符串: %s:%d (%s)" % [path, line_no, str(pat)])

	return Result.success({
		"checked": files.size(),
	})

static func _list_text_files_recursive(root_dir: String, out: Array[String]) -> Result:
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
			var sub := _list_text_files_recursive(path, out)
			if not sub.ok:
				dir.list_dir_end()
				return sub
		else:
			var lower := entry.to_lower()
			if lower.ends_with(".gd") or lower.ends_with(".tscn"):
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

