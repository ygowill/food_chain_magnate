class_name MilestonePanelEffectTextContractTest
extends RefCounted

const _PATH := "res://ui/components/milestone_panel/milestone_panel.gd"
const _PATTERNS := [
	"rural_marketeers:",
	"new_milestones:",
	"ketchup_mechanism:",
	"lobbyists_grant_extra_map_tile",
]

static func run() -> Result:
	var read_r := _read_text(_PATH)
	if not read_r.ok:
		return read_r
	var text: String = str(read_r.value)

	for pat in _PATTERNS:
		var idx := text.find(str(pat))
		if idx >= 0:
			var line_no := _find_line_number(text, idx)
			return Result.failure("MilestonePanel 不应硬编码 optional 模块 effect_id/effect_type: %s:%d (%s)" % [_PATH, line_no, str(pat)])

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
