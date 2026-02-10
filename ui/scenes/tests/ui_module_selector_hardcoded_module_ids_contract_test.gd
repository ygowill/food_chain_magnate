class_name UiModuleSelectorHardcodedModuleIdsContractTest
extends RefCounted

const _MODULES_DIR := "res://modules"

const _PATHS := [
	"res://ui/components/module_selector/module_selector.gd",
	"res://ui/scenes/setup/game_setup.gd",
	"res://ui/components/room_config_editor/room_config_editor.gd",
]

static func run() -> Result:
	var mids_r := _list_optional_module_ids()
	if not mids_r.ok:
		return mids_r
	var mids: Array[String] = mids_r.value

	for path in _PATHS:
		var read_r := _read_text(str(path))
		if not read_r.ok:
			return read_r
		var text: String = str(read_r.value)

		for mid in mids:
			var idx := text.find(mid)
			if idx >= 0:
				var line_no := _find_line_number(text, idx)
				return Result.failure("核心 UI 不应硬编码 optional module_id: %s:%d (%s)" % [str(path), line_no, mid])

	return Result.success()

static func _list_optional_module_ids() -> Result:
	var dir := DirAccess.open(_MODULES_DIR)
	if dir == null:
		return Result.failure("无法读取目录: %s" % _MODULES_DIR)

	var out: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and not entry.begins_with("."):
			var mid := str(entry).strip_edges()
			if not mid.is_empty() and not mid.begins_with("base_"):
				out.append(mid)
		entry = dir.get_next()
	dir.list_dir_end()

	out.sort()
	return Result.success(out)

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
