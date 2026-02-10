class_name UiMapOverlayPrivateStateContractTest
extends RefCounted

const _FILES := [
	"res://ui/scenes/game/map_canvas_drawer_roads_pass.gd",
	"res://ui/overlays/distance_overlay.gd",
]

const _PATTERNS := [
	"\"pending_roads\"",
	"\"roadworks_markers\"",
	"\"segments_by_pos\"",
]

static func run() -> Result:
	for path in _FILES:
		var read_r := _read_text(str(path))
		if not read_r.ok:
			return read_r
		var text: String = str(read_r.value)
		for pat in _PATTERNS:
			var idx := text.find(str(pat))
			if idx >= 0:
				var line_no := _find_line_number(text, idx)
				return Result.failure("UI 不应解析模块私有 map overlay state: %s:%d (%s)" % [path, line_no, str(pat)])

	return Result.success({
		"checked": _FILES.size(),
	})

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

